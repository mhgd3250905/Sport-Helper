import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Fixed identifiers only: never pass a chat message, exercise name or path.
enum FrameScenario {
  actionListScroll,
  filterSwitch,
  actionDetail,
  longChatScroll,
  planCardScroll,
  planExpand,
  trainingActionSwitch,
  mediaDownloadScroll,
  mediaVerifyScroll,
}

/// Internal-build frame diagnostics with bounded, in-memory aggregation.
///
/// No per-frame I/O, JSON encoding, notifications or widget rebuilds occur.
/// Labels become effective at the next scheduler frame. Engine frame numbers
/// match each timing to its label without confusing the scheduler's presentation
/// timestamp with build/vsync start, or assigning a delayed batch to today's page.
class FrameRecorder with WidgetsBindingObserver {
  FrameRecorder({
    required this.enabled,
    this.maxPages = 32,
    this.maxLabelTransitions = 128,
    this.maxConditionGroupsPerCase = 16,
    DateTime Function()? clock,
    int Function()? currentFrameNumber,
  }) : assert(maxPages > 0),
       assert(maxLabelTransitions >= 2),
       assert(maxConditionGroupsPerCase > 0),
       _clock = clock ?? DateTime.now,
       _currentFrameNumber =
           currentFrameNumber ??
           (() => SchedulerBinding
               .instance
               .platformDispatcher
               .frameData
               .frameNumber) {
    _startedAt = _clock().toUtc();
  }

  static const buildEnabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal';
  static FrameRecorder instance = FrameRecorder(enabled: buildEnabled);

  final bool enabled;
  final int maxPages;
  final int maxLabelTransitions;
  final int maxConditionGroupsPerCase;
  final DateTime Function() _clock;
  // Injectable because the test platform dispatcher cannot set engine FrameData.
  final int Function() _currentFrameNumber;
  final _labels = <_FrameLabel>[];
  final _pages = <String, _FrameStats>{};
  final _scenarios = <FrameScenario, _FrameStats>{};
  final _scenarioConditions = <FrameScenario, _ScenarioConditions>{};
  final _metadata = <String, Object?>{};
  final _cases = <String, _CaseStats>{};
  final _firstPageEntries = <String, _PageEntry>{};
  _CaseStats? _activeCase;
  _RenderConditions _conditions = const _RenderConditions();
  _FrameStats _total = _FrameStats();
  _FrameStats _otherPages = _FrameStats();
  String _page = 'unknown';
  FrameScenario? _scenario;
  double _refreshRateHz = 60;
  bool _hasExplicitRefreshRate = false;
  bool _running = false;
  bool _attached = false;
  bool _observing = false;
  int? _scheduledBoundary;
  int? _sessionStartFrameNumber;
  int _receivedFrames = 0;
  int _unattributedFrames = 0;
  int _beforeSessionFrames = 0;
  int _inactiveFrames = 0;
  int _invalidFrames = 0;
  int _invalidPageLabels = 0;
  int _evictedLabels = 0;
  int _unavailableFrameKeyBoundaries = 0;
  int _conditionChangesDuringCapture = 0;
  int _invalidCaseRequests = 0;
  late DateTime _startedAt;

  bool get isRunning => _running;
  bool get isCollecting => _attached;
  String get currentPage => _page;
  FrameScenario? get currentScenario => _scenario;
  String? get currentCaseId => _activeCase?.id;
  String? get currentCaseVariant => _activeCase?.variant;

  /// Calling start repeatedly registers exactly one timings callback/observer.
  void start() {
    if (!enabled || _running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    if (_isResumed) _attach();
  }

  void stop() {
    if (!enabled || !_running) return;
    _markInactive();
    _running = false;
    _detach();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  bool get _isResumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_running) return;
    if (state == AppLifecycleState.resumed) {
      _attach();
    } else {
      _markInactive();
      _detach();
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _scheduleBoundary();
  }

  void _detach() {
    if (_scheduledBoundary case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
      _scheduledBoundary = null;
    }
    if (!_attached) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _attached = false;
  }

  /// Starts a new measurement round and rejects delayed pre-reset timings.
  /// Current page/scenario, display rate and safe device metadata are retained.
  void reset() {
    if (!enabled) return;
    _total = _FrameStats();
    _otherPages = _FrameStats();
    _pages.clear();
    _scenarios.clear();
    _scenarioConditions.clear();
    _cases.clear();
    _firstPageEntries.clear();
    _activeCase = null;
    _labels.clear();
    _sessionStartFrameNumber = null;
    _receivedFrames = 0;
    _unattributedFrames = 0;
    _beforeSessionFrames = 0;
    _inactiveFrames = 0;
    _invalidFrames = 0;
    _invalidPageLabels = 0;
    _evictedLabels = 0;
    _unavailableFrameKeyBoundaries = 0;
    _conditionChangesDuringCapture = 0;
    _invalidCaseRequests = 0;
    _startedAt = _clock().toUtc();
    if (_attached) _scheduleBoundary();
  }

  /// [stableId] is a source-code constant, e.g. `action_library`.
  void setPage(String stableId) {
    if (!enabled) return;
    if (!_pageId.hasMatch(stableId)) {
      _invalidPageLabels++;
      stableId = 'unknown';
    }
    if (_page == stableId) return;
    _page = stableId;
    _scheduleBoundary();
  }

  void beginScenario(FrameScenario scenario) {
    if (!enabled || _scenario == scenario) return;
    _scenario = scenario;
    _scheduleBoundary();
  }

  /// Supplying the previous scenario cannot accidentally end a newer one.
  void endScenario([FrameScenario? scenario]) {
    if (!enabled || _scenario == null) return;
    if (scenario != null && _scenario != scenario) return;
    _scenario = null;
    _scheduleBoundary();
  }

  /// Starts one of the eight fixed comparison cells. Resampling replaces only
  /// that cell; old frame labels retain the old object, never the replacement.
  bool beginCase({
    required String variant,
    required FrameScenario scenario,
    required String fixtureId,
    required int messageCount,
  }) {
    if (!enabled) return false;
    if (!_variants.contains(variant) ||
        !_comparisonScenarios.contains(scenario) ||
        !_pageId.hasMatch(fixtureId) ||
        messageCount < 0 ||
        messageCount > 10000) {
      _invalidCaseRequests++;
      return false;
    }
    // Starting another cell without explicitly ending this one leaves the old
    // cell incomplete, even if timings for it are reported by a later batch.
    _activeCase?.completed = false;
    final id = '${variant}__${scenario.name}';
    _cases[id]?.retire();
    final measurement = _CaseStats(
      id: id,
      variant: variant,
      scenario: scenario,
      fixtureId: fixtureId,
      messageCount: messageCount,
      maxConditionGroups: maxConditionGroupsPerCase,
    );
    _cases[id] = measurement;
    _activeCase = measurement;
    _scenario = scenario;
    _scheduleBoundary();
    return true;
  }

  void endCase({bool completed = true}) {
    if (!enabled || _activeCase == null) return;
    _activeCase!.completed = completed;
    _activeCase = null;
    _scenario = null;
    _scheduleBoundary();
  }

  /// Invalidates a completed cell if delivery of its final engine timings is
  /// interrupted. Existing frame labels and aggregates remain available, so a
  /// delayed tail still belongs to its original cell without reopening a case.
  void invalidateCase(
    String id, {
    String reason = 'interrupted_tail_delivery',
  }) {
    if (!enabled) return;
    final measurement = _cases[id];
    if (measurement == null) return;
    measurement.completed = false;
    measurement.invalidationReason = _pageId.hasMatch(reason)
        ? reason
        : 'invalidated';
  }

  /// Actual render state, provided by the live adaptive scope/engine probe.
  /// Unknown state stays explicit; metadata never substitutes for this state.
  /// The immutable value is captured with the next engine frame boundary.
  void setRenderConditions({
    required bool glassEnabled,
    required bool starfield,
    required String glassQuality,
    required String glassPhase,
    required bool glassFrost,
    required String renderer,
    String rendererBackend = 'unknown',
    required double adaptiveTargetFrameMs,
    String theme = 'unknown',
    double? viewportWidth,
    double? viewportHeight,
    double? devicePixelRatio,
    double? textScale,
  }) {
    if (!enabled) return;
    final next = _RenderConditions(
      glassEnabled: glassEnabled,
      starfield: starfield,
      glassQuality: _conditionId(glassQuality),
      glassPhase: _conditionId(glassPhase),
      glassFrost: glassFrost,
      renderer: switch (renderer.toLowerCase()) {
        'impeller' => 'Impeller',
        'skia' => 'Skia',
        _ => 'unknown',
      },
      rendererBackend: _conditionId(rendererBackend),
      theme: _conditionId(theme),
      viewportWidth: _positiveDimension(viewportWidth),
      viewportHeight: _positiveDimension(viewportHeight),
      devicePixelRatio: _positiveDimension(devicePixelRatio),
      textScale: _positiveDimension(textScale),
      adaptiveTargetFrameMs:
          adaptiveTargetFrameMs.isFinite &&
              adaptiveTargetFrameMs > 0 &&
              adaptiveTargetFrameMs <= 100
          ? adaptiveTargetFrameMs
          : null,
    );
    if (next == _conditions) return;
    if (_running && _conditions.isSupplied) {
      _conditionChangesDuringCapture++;
    }
    _conditions = next;
    _scheduleBoundary();
  }

  static String _conditionId(String value) =>
      _pageId.hasMatch(value.toLowerCase()) &&
          value.toLowerCase() != 'adaptive_initial'
      ? value.toLowerCase()
      : 'unknown';

  static double? _positiveDimension(double? value) =>
      value != null && value.isFinite && value > 0 && value <= 100000
      ? value
      : null;

  /// Defaults to an explicitly reported 60 Hz assumption until set by the app.
  void setRefreshRateHz(double hz) {
    if (!enabled || !hz.isFinite || hz < 10 || hz > 1000) return;
    final changed = _refreshRateHz != hz;
    if (_running && _hasExplicitRefreshRate && changed) {
      _conditionChangesDuringCapture++;
    }
    _hasExplicitRefreshRate = true;
    if (!changed) return;
    _refreshRateHz = hz;
    _scheduleBoundary();
  }

  /// Accepts a small device/app allowlist; no user content or device IDs.
  void setMetadata(Map<String, Object?> metadata) {
    if (!enabled) return;
    for (final entry in metadata.entries) {
      if (!_metadataKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool ||
          value is int ||
          (value is double && value.isFinite) ||
          (value is String &&
              value.length <= 128 &&
              !_unsafeMetadata.hasMatch(value))) {
        if (_running &&
            _conditionKeys.contains(entry.key) &&
            _metadata.containsKey(entry.key) &&
            _metadata[entry.key] != value) {
          _conditionChangesDuringCapture++;
        }
        _metadata[entry.key] = value;
      }
    }
  }

  void _scheduleBoundary() {
    if (!_attached || _scheduledBoundary != null) return;
    _scheduledBoundary = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduledBoundary = null;
      if (!_attached) return;
      final frameNumber = _currentFrameNumber();
      if (frameNumber < 0) {
        // Scheduler timestamps can be future presentation targets, so they
        // cannot safely replace the exact engine key when it is unavailable.
        _unavailableFrameKeyBoundaries++;
        _labels.clear();
        return;
      }
      _sessionStartFrameNumber ??= frameNumber;
      _addLabel(
        _FrameLabel(
          frameNumber,
          _page,
          _scenario,
          _refreshRateHz,
          conditions: _conditions,
          measurement: _activeCase,
          firstPageEntry:
              _firstPageEntries[_page] ??
              (_firstPageEntries.length < maxPages
                  ? (_firstPageEntries[_page] = _PageEntry())
                  : null),
          active: true,
        ),
      );
    });
  }

  void _markInactive() {
    if (!_attached || _sessionStartFrameNumber == null) return;
    _activeCase?.lifecycleInterrupted = true;
    // The last begun frame remains eligible. Subsequent frames until resume
    // are explicitly excluded, even if the engine reports them in a late batch.
    _addLabel(
      _FrameLabel(
        _currentFrameNumber() + 1,
        _page,
        _scenario,
        _refreshRateHz,
        conditions: _conditions,
        measurement: _activeCase,
        firstPageEntry: _firstPageEntries[_page],
        active: false,
      ),
    );
  }

  void _addLabel(_FrameLabel label) {
    if (_labels.isNotEmpty &&
        _labels.last.startFrameNumber == label.startFrameNumber) {
      _labels[_labels.length - 1] = label;
    } else {
      _labels.add(label);
    }
    if (_labels.length > maxLabelTransitions) {
      _labels.removeAt(0);
      _evictedLabels++;
    }
  }

  _FrameLabel? _labelAt(int frameNumber) {
    var low = 0;
    var high = _labels.length - 1;
    _FrameLabel? result;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final label = _labels[middle];
      if (label.startFrameNumber <= frameNumber) {
        result = label;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_attached) return;
    for (final timing in timings) {
      _receivedFrames++;
      final frameNumber = timing.frameNumber;
      if (frameNumber < 0) {
        _unattributedFrames++;
        continue;
      }
      final sessionStart = _sessionStartFrameNumber;
      if (sessionStart != null && frameNumber < sessionStart) {
        _beforeSessionFrames++;
        continue;
      }
      final label = _labelAt(frameNumber);
      if (label == null) {
        _unattributedFrames++;
        continue;
      }
      if (!label.active) {
        _inactiveFrames++;
        continue;
      }
      final buildUs = timing.buildDuration.inMicroseconds;
      final rasterUs = timing.rasterDuration.inMicroseconds;
      if (buildUs < 0 || rasterUs < 0) {
        _invalidFrames++;
        continue;
      }
      _total.add(buildUs, rasterUs, label.refreshRateHz);
      final vsyncUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final entry = label.firstPageEntry;
      entry?.add(buildUs, rasterUs, label.refreshRateHz, vsyncUs);
      final pageStats =
          _pages[label.page] ??
          (_pages.length < maxPages
              ? (_pages[label.page] = _FrameStats())
              : _otherPages);
      pageStats.add(buildUs, rasterUs, label.refreshRateHz);
      final scenario = label.scenario;
      if (scenario != null && !_scenarioExcludedPages.contains(label.page)) {
        (_scenarios[scenario] ??= _FrameStats()).add(
          buildUs,
          rasterUs,
          label.refreshRateHz,
        );
        (_scenarioConditions[scenario] ??= _ScenarioConditions(
          maxConditionGroupsPerCase,
        )).add(buildUs, rasterUs, label);
        label.measurement?.add(
          buildUs,
          rasterUs,
          label,
          vsyncUs,
          firstPageEntry: entry?.contains(vsyncUs) ?? false,
          pageEntryKnown: entry != null,
        );
      } else {
        if (label.measurement case final measurement?) {
          measurement.excludedPageFrames++;
        }
      }
    }
  }

  /// Snapshot/JSON encoding/file creation belong on the explicit export path.
  Map<String, Object?> snapshot() => {
    'schema': 2,
    'reportType': 'frame_performance',
    'app': 'smartfit',
    'startedAt': _startedAt.toIso8601String(),
    'exportedAt': _clock().toUtc().toIso8601String(),
    'enabled': enabled,
    'running': _running,
    'collecting': _attached,
    'currentPage': _page,
    'currentScenario': _scenario?.name,
    'currentRefreshRateHz': _refreshRateHz,
    'currentCaseId': currentCaseId,
    'currentRenderConditions': _conditions.snapshot(_refreshRateHz),
    'metadata': Map<String, Object?>.of(_metadata),
    'definitions': {
      'durations':
          'milliseconds; UI is FrameTiming.buildDuration; '
          'raster is FrameTiming.rasterDuration',
      'coverage':
          'Flutter engine frame timings only; embedded WebView compositor and '
          'video frames are not measured; no screen-present FPS or actual '
          'display-present dropped-frame measurement is provided',
      'overBudgetFrames':
          'duration > 1000 / refreshRateHz, separately per '
          'thread; union counts a frame once when either thread exceeds budget',
      'estimatedMissedVsyncs':
          'sum(max(0, ceil(max(buildUs, rasterUs) / '
          '(1000000 / refreshRateHz)) - 1)); throughput estimate, '
          'not measured display-present drops',
      'percentiles':
          'nearest rank, logarithmic histogram upper bound capped '
          'at observed maximum; error <= 6.25% of duration or 1 microsecond; '
          'averages and worst frames are exact',
      'attribution':
          'labels start on next scheduler frame; PlatformDispatcher.frameData.'
          'frameNumber matches FrameTiming.frameNumber; delayed batches use '
          'retained frame-key history, not callback time or presentation timestamps',
      'unattributed':
          'frames without retained label history are counted and '
          'excluded from duration/budget statistics rather than guessed',
      'lifecycle':
          'only resumed state is collected; engine batches pending '
          'at stop/pause may not be delivered; pre-reset frames are excluded',
      'refreshRate':
          'per-frame label rate; initial 60 Hz is an assumption '
          'until the app supplies a display rate',
      'scenarios':
          'one explicit scenario at a time; frames outside a scenario '
          'remain in totals and page statistics; settings and '
          'performance_settings pages are excluded from scenario statistics',
      'conditionChangesDuringCapture':
          'number of changes to previously supplied theme, appearance, '
          'starfield, glassQuality or refresh-rate values while running; '
          'initial values and device metadata readiness do not count; '
          'reset clears the count and retains current conditions',
      'comparisonWindows':
          'warmupFirst2Seconds is [first case FrameTiming.vsyncStart, +2 s); '
          'steadyState begins at +2 s; firstPageEntryFirst2Seconds independently '
          'covers the first observed entry of each page in this round, and may '
          'overlap warmup or steady state; spikes do not prove shader compilation',
      'comparisonEligibility':
          'completed; >=30 s observed case vsync span; steady frames present; '
          'one actual render condition and one refresh rate; verified renderer; '
          'variant matches actual switches; long chat >=60 messages; no '
          'condition overflow or out-of-order case timestamps',
    },
    'retention': {
      'maxPages': maxPages,
      'maxScenarios': FrameScenario.values.length,
      'histogramBucketsPerThread': _DurationStats.bucketCount,
      'maxLabelTransitions': maxLabelTransitions,
      'maxCases': 8,
      'maxConditionGroupsPerCase': maxConditionGroupsPerCase,
      'retainedFirstPageEntries': _firstPageEntries.length,
      'retainedLabelTransitions': _labels.length,
      'evictedLabelTransitions': _evictedLabels,
      'pageOverflow': 'additional page identifiers aggregate in otherPages',
      'perFrameSamplesStored': 0,
    },
    'receivedFrameCount': _receivedFrames,
    'recordedFrameCount': _total.count,
    'unattributedFrameCount': _unattributedFrames,
    'ignoredBeforeSessionFrameCount': _beforeSessionFrames,
    'ignoredInactiveFrameCount': _inactiveFrames,
    'invalidTimingFrameCount': _invalidFrames,
    'invalidPageLabelCount': _invalidPageLabels,
    'unavailableFrameKeyBoundaryCount': _unavailableFrameKeyBoundaries,
    'conditionChangesDuringCapture': _conditionChangesDuringCapture,
    'invalidCaseRequestCount': _invalidCaseRequests,
    'total': _total.snapshot(),
    'pages': {
      for (final entry in _pages.entries) entry.key: entry.value.snapshot(),
    },
    'otherPages': _otherPages.snapshot(),
    'scenarios': {
      for (final entry in _scenarios.entries)
        entry.key.name: entry.value.snapshot(),
    },
    'cases': {
      for (final entry in _cases.entries) entry.key: entry.value.snapshot(),
    },
    'scenarioConditions': {
      for (final entry in _scenarioConditions.entries)
        entry.key.name: entry.value.snapshot(),
    },
    'pageEntries': {
      for (final entry in _firstPageEntries.entries)
        entry.key: entry.value.snapshot(),
    },
  };

  static final _pageId = RegExp(r'^[a-z][a-z0-9_.]{0,47}$');
  static final _unsafeMetadata = RegExp(r'[\x00-\x1f\\/@]');
  static const _scenarioExcludedPages = {
    'settings',
    'performance_settings',
    'performance_lab',
  };
  static const _comparisonScenarios = {
    FrameScenario.longChatScroll,
    FrameScenario.planCardScroll,
  };
  static const _variants = {
    'glass_on_stars_on',
    'glass_on_stars_off',
    'glass_off_stars_on',
    'glass_off_stars_off',
  };
  static const _conditionKeys = {
    'theme',
    'appearance',
    'starfield',
    'glassQuality',
  };
  static const _metadataKeys = {
    'appVersion',
    'appBuild',
    'flavor',
    'buildMode',
    'platform',
    'deviceModel',
    'deviceManufacturer',
    'systemVersion',
    'refreshRateSource',
    'renderer',
    'rendererBackend',
    'rendererSource',
    'rendererVerified',
    'isEmulator',
    'sdkRef',
    'appSource',
    'appBuildNumber',
    'measurementKind',
    'appearance',
    'starfield',
    'glassQuality',
    'deviceApiLevel',
    'metadataStatus',
    'contentActionCount',
    'chatMessageCount',
    'theme',
    'appBaseCommit',
  };
}

class _FrameLabel {
  _FrameLabel(
    this.startFrameNumber,
    this.page,
    this.scenario,
    this.refreshRateHz, {
    required this.active,
    required this.conditions,
    required this.measurement,
    required this.firstPageEntry,
  }) : conditionKey = '${conditions.key}|$refreshRateHz';

  final int startFrameNumber;
  final String page;
  final FrameScenario? scenario;
  final double refreshRateHz;
  final bool active;
  final _RenderConditions conditions;
  final _CaseStats? measurement;
  final _PageEntry? firstPageEntry;
  final String conditionKey;
}

class _RenderConditions {
  const _RenderConditions({
    this.glassEnabled,
    this.starfield,
    this.glassQuality = 'unknown',
    this.glassPhase = 'unknown',
    this.glassFrost,
    this.renderer = 'unknown',
    this.rendererBackend = 'unknown',
    this.adaptiveTargetFrameMs,
    this.theme = 'unknown',
    this.viewportWidth,
    this.viewportHeight,
    this.devicePixelRatio,
    this.textScale,
  });

  final bool? glassEnabled;
  final bool? starfield;
  final String glassQuality;
  final String glassPhase;
  final bool? glassFrost;
  final String renderer;
  final String rendererBackend;
  final double? adaptiveTargetFrameMs;
  final String theme;
  final double? viewportWidth;
  final double? viewportHeight;
  final double? devicePixelRatio;
  final double? textScale;

  bool get isSupplied => glassEnabled != null;
  String get key =>
      '$glassEnabled|$starfield|$glassQuality|$glassPhase|$glassFrost|'
      '$renderer|$rendererBackend|$adaptiveTargetFrameMs|$theme|$viewportWidth|'
      '$viewportHeight|$devicePixelRatio|$textScale';

  Map<String, Object?> snapshot(double hz) => {
    'glassEnabled': glassEnabled,
    'starfield': starfield,
    'glassQuality': glassQuality,
    'glassPhase': glassPhase,
    'glassFrost': glassFrost,
    'renderer': renderer,
    'rendererBackend': rendererBackend,
    'refreshRateHz': hz,
    'frameBudgetMs': 1000 / hz,
    'adaptiveTargetFrameMs': adaptiveTargetFrameMs,
    'theme': theme,
    'viewportWidth': viewportWidth,
    'viewportHeight': viewportHeight,
    'devicePixelRatio': devicePixelRatio,
    'textScale': textScale,
  };

  @override
  bool operator ==(Object other) =>
      other is _RenderConditions &&
      glassEnabled == other.glassEnabled &&
      starfield == other.starfield &&
      glassQuality == other.glassQuality &&
      glassPhase == other.glassPhase &&
      glassFrost == other.glassFrost &&
      renderer == other.renderer &&
      rendererBackend == other.rendererBackend &&
      adaptiveTargetFrameMs == other.adaptiveTargetFrameMs &&
      theme == other.theme &&
      viewportWidth == other.viewportWidth &&
      viewportHeight == other.viewportHeight &&
      devicePixelRatio == other.devicePixelRatio &&
      textScale == other.textScale;

  @override
  int get hashCode => Object.hash(
    glassEnabled,
    starfield,
    glassQuality,
    glassPhase,
    glassFrost,
    renderer,
    rendererBackend,
    adaptiveTargetFrameMs,
    theme,
    viewportWidth,
    viewportHeight,
    devicePixelRatio,
    textScale,
  );
}

class _PageEntry {
  int? firstVsyncUs;
  final _stats = _FrameStats();
  int _framesBeforeFirstObservation = 0;

  void add(int buildUs, int rasterUs, double hz, int vsyncUs) {
    firstVsyncUs ??= vsyncUs;
    if (vsyncUs < firstVsyncUs!) _framesBeforeFirstObservation++;
    if (contains(vsyncUs)) _stats.add(buildUs, rasterUs, hz);
  }

  bool contains(int vsyncUs) {
    final start = firstVsyncUs;
    return start != null && vsyncUs >= start && vsyncUs - start < 2000000;
  }

  Map<String, Object?> snapshot() => {
    'firstVsyncStartUs': firstVsyncUs,
    'first2Seconds': _stats.snapshot(),
    'earlierOutOfOrderFrameCount': _framesBeforeFirstObservation,
  };
}

class _WindowStats {
  final allFrames = _FrameStats();
  final warmup = _FrameStats();
  final steady = _FrameStats();
  final firstPageEntry = _FrameStats();

  void add(
    int buildUs,
    int rasterUs,
    double hz, {
    required bool isWarmup,
    required bool isSteady,
    required bool isFirstPageEntry,
  }) {
    allFrames.add(buildUs, rasterUs, hz);
    if (isWarmup) warmup.add(buildUs, rasterUs, hz);
    if (isSteady) steady.add(buildUs, rasterUs, hz);
    if (isFirstPageEntry) firstPageEntry.add(buildUs, rasterUs, hz);
  }

  Map<String, Object?> snapshot() => {
    'allFrames': allFrames.snapshot(),
    'warmupFirst2Seconds': warmup.snapshot(),
    'steadyState': steady.snapshot(),
    'firstPageEntryFirst2Seconds': firstPageEntry.snapshot(),
  };
}

class _ConditionStats {
  _ConditionStats(this.conditions, this.refreshRateHz);

  final _RenderConditions conditions;
  final double refreshRateHz;
  final windows = _WindowStats();

  Map<String, Object?> snapshot() => {
    'condition': conditions.snapshot(refreshRateHz),
    ...windows.snapshot(),
  };
}

class _ScenarioConditions {
  _ScenarioConditions(this.maxGroups);

  final int maxGroups;
  final _groups = <String, (_RenderConditions, double, _FrameStats)>{};
  int _overflowFrames = 0;

  void add(int buildUs, int rasterUs, _FrameLabel label) {
    var group = _groups[label.conditionKey];
    if (group == null) {
      if (_groups.length >= maxGroups) {
        _overflowFrames++;
        return;
      }
      group = (label.conditions, label.refreshRateHz, _FrameStats());
      _groups[label.conditionKey] = group;
    }
    group.$3.add(buildUs, rasterUs, label.refreshRateHz);
  }

  Map<String, Object?> snapshot() => {
    'groups': [
      for (final group in _groups.values)
        {
          'condition': group.$1.snapshot(group.$2),
          'frames': group.$3.snapshot(),
        },
    ],
    'overflowFrameCount': _overflowFrames,
  };
}

class _CaseStats {
  _CaseStats({
    required this.id,
    required this.variant,
    required this.scenario,
    required this.fixtureId,
    required this.messageCount,
    required this.maxConditionGroups,
  });

  final String id;
  final String variant;
  final FrameScenario scenario;
  final String fixtureId;
  final int messageCount;
  final int maxConditionGroups;
  _WindowStats? _windows = _WindowStats();
  _WindowStats get windows => _windows!;
  final groups = <String, _ConditionStats>{};
  final _pages = <String>{};
  bool completed = false;
  String? invalidationReason;
  bool lifecycleInterrupted = false;
  int excludedPageFrames = 0;
  bool _retired = false;
  int? _firstVsyncUs;
  int? _lastVsyncUs;
  int _overflowConditionFrames = 0;
  bool _outOfOrderTimings = false;
  bool _unknownPageEntry = false;
  bool _scenarioMismatch = false;

  /// Old frame labels can outlive a resampled matrix cell. Retain only the
  /// small identity object and discard its histograms immediately.
  void retire() {
    _retired = true;
    _windows = null;
    groups.clear();
    _pages.clear();
  }

  void add(
    int buildUs,
    int rasterUs,
    _FrameLabel label,
    int vsyncUs, {
    required bool firstPageEntry,
    required bool pageEntryKnown,
  }) {
    if (_retired) return;
    if (label.scenario != scenario) {
      _scenarioMismatch = true;
      return;
    }
    _firstVsyncUs ??= vsyncUs;
    if (_lastVsyncUs != null && vsyncUs < _lastVsyncUs!) {
      _outOfOrderTimings = true;
    }
    _lastVsyncUs = math.max(_lastVsyncUs ?? vsyncUs, vsyncUs);
    if (_pages.length < 2) _pages.add(label.page);
    if (!pageEntryKnown) _unknownPageEntry = true;
    final elapsed = vsyncUs - _firstVsyncUs!;
    final isWarmup = elapsed >= 0 && elapsed < 2000000;
    final isSteady = elapsed >= 2000000;
    windows.add(
      buildUs,
      rasterUs,
      label.refreshRateHz,
      isWarmup: isWarmup,
      isSteady: isSteady,
      isFirstPageEntry: firstPageEntry,
    );
    final _ConditionStats group;
    if (groups[label.conditionKey] case final existing?) {
      group = existing;
    } else if (groups.length < maxConditionGroups) {
      group = _ConditionStats(label.conditions, label.refreshRateHz);
      groups[label.conditionKey] = group;
    } else {
      _overflowConditionFrames++;
      return;
    }
    group.windows.add(
      buildUs,
      rasterUs,
      label.refreshRateHz,
      isWarmup: isWarmup,
      isSteady: isSteady,
      isFirstPageEntry: firstPageEntry,
    );
  }

  double get _durationSeconds =>
      _firstVsyncUs == null ? 0 : (_lastVsyncUs! - _firstVsyncUs!) / 1000000;

  List<String> get _comparisonIssues {
    final issues = <String>[];
    if (!completed) issues.add('incomplete');
    if (invalidationReason case final reason?) {
      issues.add('case_invalidated');
      issues.add(reason);
    }
    if (windows.allFrames.count == 0) issues.add('no_frames');
    if (_durationSeconds < 30) issues.add('observed_span_less_than_30_seconds');
    if (windows.steady.count == 0) issues.add('no_steady_state_frames');
    if (groups.length > 1) issues.add('mixed_render_conditions');
    if (_overflowConditionFrames > 0) issues.add('condition_groups_overflow');
    if (_outOfOrderTimings) issues.add('out_of_order_vsync_timestamps');
    if (_unknownPageEntry) issues.add('page_entry_history_unavailable');
    if (_pages.length > 1) issues.add('multiple_pages');
    if (_scenarioMismatch) issues.add('scenario_changed_during_case');
    if (lifecycleInterrupted) issues.add('lifecycle_interrupted');
    if (excludedPageFrames > 0) issues.add('excluded_page_frames_during_case');
    if (scenario == FrameScenario.longChatScroll && messageCount < 60) {
      issues.add('long_chat_has_fewer_than_60_messages');
    }
    if (groups.values.any((group) => group.conditions.renderer == 'unknown')) {
      issues.add('renderer_unknown');
    }
    if (groups.values.any((group) {
      final condition = group.conditions;
      return !condition.isSupplied ||
          condition.starfield == null ||
          condition.glassQuality == 'unknown' ||
          condition.glassPhase == 'unknown' ||
          condition.glassFrost == null ||
          condition.adaptiveTargetFrameMs == null ||
          condition.theme == 'unknown' ||
          condition.viewportWidth == null ||
          condition.viewportHeight == null ||
          condition.devicePixelRatio == null ||
          condition.textScale == null;
    })) {
      issues.add('actual_render_condition_unknown');
    }
    if (groups.values.any((group) {
      final budget = group.conditions.adaptiveTargetFrameMs;
      return budget != null &&
          (budget - 1000 / group.refreshRateHz).abs() > .05;
    })) {
      issues.add('adaptive_budget_does_not_match_refresh_rate');
    }
    final expectsGlass = variant.startsWith('glass_on_');
    final expectsStars = variant.endsWith('_stars_on');
    if (groups.values.any((group) {
      final condition = group.conditions;
      return condition.glassEnabled != expectsGlass ||
          condition.starfield != expectsStars;
    })) {
      issues.add('variant_switches_do_not_match_actual_conditions');
    }
    return issues;
  }

  Map<String, Object?> snapshot() {
    final issues = _comparisonIssues;
    return {
      'id': id,
      'variant': variant,
      'scenario': scenario.name,
      'fixtureId': fixtureId,
      'messageCount': messageCount,
      'completed': completed,
      'invalidationReason': invalidationReason,
      'observedDurationSeconds': _durationSeconds,
      'firstVsyncStartUs': _firstVsyncUs,
      'lastVsyncStartUs': _lastVsyncUs,
      'pages': _pages.toList(),
      'comparisonReady': issues.isEmpty,
      'comparisonIssues': issues,
      'overflowConditionFrameCount': _overflowConditionFrames,
      ...windows.snapshot(),
      'conditions': [for (final group in groups.values) group.snapshot()],
    };
  }
}

class _FrameStats {
  final _build = _DurationStats();
  final _raster = _DurationStats();
  final _refreshRates = <double>{};
  int count = 0;
  int _overBudget = 0;
  int _estimatedMissedVsyncs = 0;
  bool _refreshRatesTruncated = false;

  void add(int buildUs, int rasterUs, double hz) {
    count++;
    final budget = Duration.microsecondsPerSecond / hz;
    _build.add(buildUs, budget);
    _raster.add(rasterUs, budget);
    final longest = math.max(buildUs, rasterUs);
    if (longest > budget) _overBudget++;
    _estimatedMissedVsyncs += math.max(0, (longest / budget).ceil() - 1);
    if (_refreshRates.length < 16 || _refreshRates.contains(hz)) {
      _refreshRates.add(hz);
    } else {
      _refreshRatesTruncated = true;
    }
  }

  Map<String, Object?> snapshot() => {
    'frameCount': count,
    'uiBuild': _build.snapshot(),
    'raster': _raster.snapshot(),
    'eitherThreadOverBudgetFrames': _overBudget,
    'estimatedMissedVsyncs': _estimatedMissedVsyncs,
    'refreshRatesHz': _refreshRates.toList()..sort(),
    'refreshRatesTruncated': _refreshRatesTruncated,
  };
}

class _DurationStats {
  // 16 sub-buckets per power of two cover all positive signed 64-bit µs.
  static const bucketCount = 1024;
  final _histogram = Uint64List(bucketCount);
  int _count = 0;
  int _sumUs = 0;
  int _worstUs = 0;
  int _overBudget = 0;

  void add(int microseconds, double budget) {
    _count++;
    _sumUs += microseconds;
    _worstUs = math.max(_worstUs, microseconds);
    if (microseconds > budget) _overBudget++;
    final exponent = microseconds.bitLength - 1;
    final index = microseconds < 16
        ? microseconds
        : (exponent - 3) * 16 + (microseconds >> (exponent - 4)) - 16;
    _histogram[index]++;
  }

  double? _percentile(double fraction) {
    if (_count == 0) return null;
    final rank = (_count * fraction).ceil();
    var cumulative = 0;
    for (var index = 0; index < bucketCount; index++) {
      cumulative += _histogram[index];
      if (cumulative < rank) continue;
      final upperUs = index < 16
          ? index
          : ((17 + index % 16) << (index ~/ 16 - 1)) - 1;
      return math.min(upperUs, _worstUs) / 1000;
    }
    return _worstUs / 1000;
  }

  Map<String, Object?> snapshot() => {
    'averageMs': _count == 0 ? null : _sumUs / _count / 1000,
    'p90Ms': _percentile(.90),
    'p99Ms': _percentile(.99),
    'worstMs': _count == 0 ? null : _worstUs / 1000,
    'overBudgetFrames': _overBudget,
    'overBudgetRatio': _count == 0 ? null : _overBudget / _count,
  };
}
