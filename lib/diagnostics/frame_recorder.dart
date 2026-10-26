import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' show FramePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
  pageEntry,
  bottomBarSwitch,
  trainingPlayback,
}

/// Bounded raw engine timings. No per-frame encoding, I/O or UI notification.
/// Exact engine frame numbers retain labels across delayed timing batches.
class FrameRecorder with WidgetsBindingObserver {
  FrameRecorder({
    required this.enabled,
    this.maxPages = 32,
    this.maxLabelTransitions = 128,
    this.maxConditionGroupsPerCase = 16,
    this.maxRawFrames = 60000,
    this.maxFramesPerCase = 12000,
    DateTime Function()? clock,
    int Function()? currentFrameNumber,
    int Function()? monotonicMicros,
  }) : assert(maxPages > 0),
       assert(maxLabelTransitions >= 2),
       assert(maxRawFrames > 0),
       assert(maxFramesPerCase > 0),
       assert(maxConditionGroupsPerCase > 0),
       _clock = clock ?? DateTime.now,
       _monotonicMicros = monotonicMicros ?? (() => Timeline.now),
       _currentFrameNumber =
           currentFrameNumber ??
           (() => SchedulerBinding
               .instance
               .platformDispatcher
               .frameData
               .frameNumber) {
    _startedAt = _clock().toUtc();
    _total = _FrameStats(maxRawFrames);
    _otherPages = _FrameStats(maxRawFrames);
  }
  static const buildEnabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal';
  static FrameRecorder instance = FrameRecorder(enabled: buildEnabled);
  static const material = 'solid';
  static const acceptanceScenarios = [
    FrameScenario.planCardScroll,
    FrameScenario.longChatScroll,
    FrameScenario.pageEntry,
    FrameScenario.bottomBarSwitch,
    FrameScenario.trainingPlayback,
  ];
  static int minimumSampleMicros(FrameScenario scenario) => switch (scenario) {
    FrameScenario.pageEntry => 3000000,
    FrameScenario.bottomBarSwitch => 10000000,
    FrameScenario.trainingPlayback => 20000000,
    _ => 30000000,
  };
  final bool enabled;
  final int maxPages,
      maxLabelTransitions,
      maxConditionGroupsPerCase,
      maxRawFrames,
      maxFramesPerCase;
  final DateTime Function() _clock;
  final int Function() _monotonicMicros, _currentFrameNumber;
  final _labels = <_FrameLabel>[];
  final _pages = <String, _FrameStats>{};
  final _scenarios = <FrameScenario, _FrameStats>{};
  final _metadata = <String, Object?>{};
  final _cases = <String, _CaseStats>{};
  final _firstPageEntries = <String, _PageEntry>{};
  late _FrameStats _total, _otherPages;
  _CaseStats? _activeCase;
  _ArmedCase? _armedCase;
  Timer? _caseTimer;
  _RenderConditions _conditions = const _RenderConditions();
  String _page = 'unknown';
  FrameScenario? _scenario;
  double _refreshRateHz = 60;
  bool _hasExplicitRefreshRate = false,
      _running = false,
      _attached = false,
      _observing = false;
  int? _scheduledBoundary, _sessionStartFrameNumber;
  int _receivedFrames = 0, _unattributedFrames = 0, _beforeSessionFrames = 0;
  int _inactiveFrames = 0,
      _invalidFrames = 0,
      _invalidPageLabels = 0,
      _evictedLabels = 0;
  int _unavailableFrameKeyBoundaries = 0,
      _conditionChangesDuringCapture = 0,
      _invalidCaseRequests = 0;
  late DateTime _startedAt;

  bool get isRunning => _running;
  bool get isCollecting => _attached;
  String get currentPage => _page;
  FrameScenario? get currentScenario => _scenario;
  String? get currentCaseId => _activeCase?.id;

  void start() {
    if (!enabled || _running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
    if (_isResumed) _attach();
  }

  void stop() {
    if (!enabled || !_running) return;
    _caseTimer?.cancel();
    _armedCase = null;
    _markInactive();
    _running = false;
    _detach();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  bool get _isResumed =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
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

  /// A new round rejects delayed timings from before reset. Device metadata,
  /// current page/scenario and the actual display rate remain available.
  void reset() {
    if (!enabled) return;
    _caseTimer?.cancel();
    _armedCase = null;
    _total = _FrameStats(maxRawFrames);
    _otherPages = _FrameStats(maxRawFrames);
    _pages.clear();
    _scenarios.clear();
    for (final item in _cases.values) {
      item.retire();
    }
    _cases.clear();
    _firstPageEntries.clear();
    _activeCase = null;
    _labels.clear();
    _sessionStartFrameNumber = null;
    _receivedFrames = _unattributedFrames = _beforeSessionFrames = 0;
    _inactiveFrames = _invalidFrames = _invalidPageLabels = _evictedLabels = 0;
    _unavailableFrameKeyBoundaries = _conditionChangesDuringCapture =
        _invalidCaseRequests = 0;
    _startedAt = _clock().toUtc();
    if (_attached) _scheduleBoundary();
  }

  void setPage(String stableId) {
    if (!enabled) return;
    if (!_pageId.hasMatch(stableId)) {
      _invalidPageLabels++;
      stableId = 'unknown';
    }
    if (_page == stableId) return;
    _page = stableId;
    _tryStartArmed();
    _scheduleBoundary();
  }

  void beginScenario(FrameScenario scenario) {
    if (!enabled || _scenario == scenario) return;
    _scenario = scenario;
    _scheduleBoundary();
  }

  void endScenario([FrameScenario? scenario]) {
    if (!enabled ||
        _scenario == null ||
        (scenario != null && _scenario != scenario)) {
      return;
    }
    _scenario = null;
    _scheduleBoundary();
  }

  bool beginCase({
    required String theme,
    required FrameScenario scenario,
    String fixtureId = 'real_page',
    int messageCount = 0,
  }) {
    if (!enabled) return false;
    if (!const {'light', 'dark'}.contains(theme) ||
        !acceptanceScenarios.contains(scenario) ||
        !_pageId.hasMatch(fixtureId) ||
        messageCount < 0 ||
        messageCount > 10000) {
      _invalidCaseRequests++;
      return false;
    }
    if (_activeCase != null) endCase(completed: false);
    final id = '${theme}__${scenario.name}';
    _cases[id]?.retire();
    final item = _CaseStats(
      id: id,
      theme: theme,
      scenario: scenario,
      fixtureId: fixtureId,
      messageCount: messageCount,
      maxFrames: maxFramesPerCase,
      maxGroups: maxConditionGroupsPerCase,
      startedUs: _monotonicMicros(),
    );
    _cases[id] = item;
    _activeCase = item;
    _scenario = scenario;
    _scheduleBoundary();
    return true;
  }

  void endCase({bool completed = true}) {
    _caseTimer?.cancel();
    _caseTimer = null;
    if (!enabled || _activeCase == null) return;
    _activeCase!.completed = completed;
    _activeCase!.endedUs = _monotonicMicros();
    _activeCase = null;
    _scenario = null;
    _scheduleBoundary();
  }

  /// Arms a real-page workload. Navigation remains the actual App navigation;
  /// entry starts before the target route builds, not on a substitute fixture.
  bool armCase({required String theme, required FrameScenario scenario}) {
    if (!enabled ||
        !const {'light', 'dark'}.contains(theme) ||
        !acceptanceScenarios.contains(scenario) ||
        _activeCase != null) {
      return false;
    }
    final target = switch (scenario) {
      FrameScenario.pageEntry => 'action_library',
      FrameScenario.bottomBarSwitch => 'chat',
      FrameScenario.trainingPlayback => 'training',
      _ => null,
    };
    if (target == null) return false;
    _armedCase = _ArmedCase(theme, scenario, target);
    start();
    if (scenario != FrameScenario.pageEntry) _tryStartArmed();
    return true;
  }

  void cancelArmedCase() {
    _armedCase = null;
  }

  void _tryStartArmed() {
    final armed = _armedCase;
    if (armed == null || armed.target != _page) return;
    _armedCase = null;
    if (!beginCase(theme: armed.theme, scenario: armed.scenario)) return;
    final id = currentCaseId;
    final seconds = switch (armed.scenario) {
      FrameScenario.pageEntry => 3,
      FrameScenario.bottomBarSwitch => 20,
      _ => 22,
    };
    _caseTimer = Timer(Duration(seconds: seconds), () {
      if (currentCaseId == id) endCase();
    });
  }

  void invalidateCase(String id, {String reason = 'invalidated'}) {
    final item = _cases[id];
    if (!enabled || item == null) return;
    item.completed = false;
    item.invalidationReason = _pageId.hasMatch(reason) ? reason : 'invalidated';
  }

  void setRenderConditions({
    required bool starfield,
    required String renderer,
    String rendererBackend = 'unknown',
    bool rendererVerified = false,
    String theme = 'unknown',
    double? viewportWidth,
    double? viewportHeight,
    double? devicePixelRatio,
    double? textScale,
  }) {
    if (!enabled) return;
    final next = _RenderConditions(
      starfield: starfield,
      renderer: const {'impeller', 'skia'}.contains(renderer.toLowerCase())
          ? renderer.toLowerCase()
          : 'unknown',
      rendererBackend: _conditionId(rendererBackend),
      rendererVerified: rendererVerified,
      theme: const {'light', 'dark'}.contains(theme) ? theme : 'unknown',
      viewportWidth: _positive(viewportWidth),
      viewportHeight: _positive(viewportHeight),
      devicePixelRatio: _positive(devicePixelRatio),
      textScale: _positive(textScale),
    );
    if (next.key == _conditions.key) return;
    if (_running && _conditions.starfield != null) {
      _conditionChangesDuringCapture++;
    }
    _conditions = next;
    _scheduleBoundary();
  }

  static String _conditionId(String value) =>
      _pageId.hasMatch(value.toLowerCase()) ? value.toLowerCase() : 'unknown';
  static double? _positive(double? value) =>
      value != null && value.isFinite && value > 0 && value <= 100000
      ? value
      : null;
  void setRefreshRateHz(double hz) {
    if (!enabled || !hz.isFinite || hz < 10 || hz > 1000) return;
    final changed = _refreshRateHz != hz || !_hasExplicitRefreshRate;
    if (_running && _hasExplicitRefreshRate && changed) {
      _conditionChangesDuringCapture++;
    }
    _hasExplicitRefreshRate = true;
    _refreshRateHz = hz;
    if (changed) _scheduleBoundary();
  }

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
        _metadata[entry.key] = value;
      }
    }
  }

  void _scheduleBoundary() {
    if (!_attached || _scheduledBoundary != null) return;
    _scheduledBoundary = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduledBoundary = null;
      if (!_attached) return;
      final number = _currentFrameNumber();
      if (number < 0) {
        _unavailableFrameKeyBoundaries++;
        _labels.clear();
        return;
      }
      _sessionStartFrameNumber ??= number;
      _addLabel(
        _FrameLabel(
          number,
          _page,
          _scenario,
          _refreshRateHz,
          _hasExplicitRefreshRate,
          active: true,
          conditions: _conditions,
          measurement: _activeCase,
          firstPageEntry:
              _firstPageEntries[_page] ??
              (_firstPageEntries.length < maxPages
                  ? (_firstPageEntries[_page] = _PageEntry(maxRawFrames))
                  : null),
        ),
      );
    });
  }

  void _markInactive() {
    if (!_attached || _sessionStartFrameNumber == null) return;
    _activeCase?.lifecycleInterrupted = true;
    _addLabel(
      _FrameLabel(
        _currentFrameNumber() + 1,
        _page,
        _scenario,
        _refreshRateHz,
        _hasExplicitRefreshRate,
        active: false,
        conditions: _conditions,
        measurement: _activeCase,
        firstPageEntry: _firstPageEntries[_page],
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

  _FrameLabel? _labelAt(int number) {
    var low = 0, high = _labels.length - 1;
    _FrameLabel? result;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final label = _labels[middle];
      if (label.startFrameNumber <= number) {
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
      if (timing.frameNumber < 0) {
        _unattributedFrames++;
        continue;
      }
      if (_sessionStartFrameNumber != null &&
          timing.frameNumber < _sessionStartFrameNumber!) {
        _beforeSessionFrames++;
        continue;
      }
      final label = _labelAt(timing.frameNumber);
      if (label == null) {
        _unattributedFrames++;
        continue;
      }
      if (!label.active) {
        _inactiveFrames++;
        continue;
      }
      final buildUs = timing.buildDuration.inMicroseconds,
          rasterUs = timing.rasterDuration.inMicroseconds;
      if (buildUs < 0 || rasterUs < 0) {
        _invalidFrames++;
        continue;
      }
      final frame = _RawFrame(timing, label, buildUs, rasterUs);
      _total.add(frame);
      (_pages[label.page] ??
              (_pages.length < maxPages
                  ? (_pages[label.page] = _FrameStats(maxRawFrames))
                  : _otherPages))
          .add(frame);
      label.firstPageEntry?.add(frame);
      if (label.scenario != null && !_excludedPages.contains(label.page)) {
        (_scenarios[label.scenario!] ??= _FrameStats(maxRawFrames)).add(frame);
        label.measurement?.add(frame);
      } else if (label.measurement case final item?) {
        item.excludedPageFrames++;
      }
    }
  }

  /// Lightweight VM automation status: no percentile sorts or raw JSON maps.
  Map<String, Object?>? caseSnapshot(String id) => _cases[id]?.snapshot();

  Map<String, Object?>? caseReport(String id) {
    final value = caseSnapshot(id);
    return value == null
        ? null
        : {
            'schema': 3,
            'app': 'smartfit',
            'reportType': 'solid_frame_performance',
            'material': material,
            'metadata': Map<String, Object?>.of(_metadata),
            'cases': {id: value},
          };
  }

  Map<String, Object?> status() => {
    'material': material,
    'enabled': enabled,
    'running': _running,
    'currentPage': _page,
    'currentScenario': _scenario?.name,
    'currentCaseId': currentCaseId,
    'currentTheme': _conditions.theme,
    'currentRefreshRateHz': _refreshRateHz,
    'armedCaseId': _armedCase == null
        ? null
        : '${_armedCase!.theme}__${_armedCase!.scenario.name}',
    'armedTargetPage': _armedCase?.target,
    'caseIds': _cases.keys.toList(),
  };
  Map<String, Object?> snapshot() {
    final indices = Map<_RawFrame, int>.identity();
    for (var index = 0; index < _total.frames.length; index++) {
      indices[_total.frames[index]] = index;
    }
    return {
      'schema': 3,
      'reportType': 'solid_frame_performance',
      'app': 'smartfit',
      'material': material,
      'startedAt': _startedAt.toIso8601String(),
      'exportedAt': _clock().toUtc().toIso8601String(),
      ...status(),
      'collecting': _attached,
      'currentRenderConditions': _conditions.snapshot(
        _refreshRateHz,
        _hasExplicitRefreshRate,
      ),
      'metadata': Map<String, Object?>.of(_metadata),
      'definitions': {
        'durations':
            'Original engine FrameTiming integer microseconds; UI and Raster are separate threads.',
        'percentiles':
            'Exact nearest-rank from retained original integer samples. Null after raw retention overflow.',
        'rawFrameSource':
            'FrameTiming with engine frameNumber and every FramePhase timestamp.',
        'rawFrameStorage':
            'One rawFrames table. Case rawFrameIndices reference it without duplicating timings.',
        'overBudgetFrames':
            'duration >1000000/actual refreshRateHz per thread; not measured display drops.',
        'p99Acceptance':
            'At 120Hz Raster P99 <8330us, strictly below 8.33ms; count >8330us separately.',
        'warmup':
            'First two seconds are separate; pageEntry acceptance uses all frames.',
        'limits':
            'No display-present FPS, hardware GPU completion or screen dropped-frame rate is inferred.',
      },
      'receivedFrameCount': _receivedFrames,
      'recordedFrameCount': _total.count,
      'unattributedFrameCount': _unattributedFrames,
      'beforeSessionFrameCount': _beforeSessionFrames,
      'inactiveFrameCount': _inactiveFrames,
      'invalidFrameCount': _invalidFrames,
      'invalidPageLabelCount': _invalidPageLabels,
      'evictedLabelTransitionCount': _evictedLabels,
      'unavailableFrameKeyBoundaryCount': _unavailableFrameKeyBoundaries,
      'conditionChangesDuringCapture': _conditionChangesDuringCapture,
      'invalidCaseRequestCount': _invalidCaseRequests,
      'limits': {
        'maxPages': maxPages,
        'maxLabelTransitions': maxLabelTransitions,
        'maxRawFrames': maxRawFrames,
        'maxFramesPerCase': maxFramesPerCase,
        'maxCases': 10,
      },
      'total': _total.snapshot(),
      'otherPages': _otherPages.snapshot(),
      'pages': {
        for (final entry in _pages.entries) entry.key: entry.value.snapshot(),
      },
      'scenarios': {
        for (final entry in _scenarios.entries)
          entry.key.name: entry.value.snapshot(),
      },
      'pageEntries': {
        for (final entry in _firstPageEntries.entries)
          entry.key: entry.value.snapshot(),
      },
      'cases': {
        for (final entry in _cases.entries)
          entry.key: entry.value.snapshot(rawIndices: indices),
      },
      'rawFramesTruncated': _total.overflow > 0,
      'rawFrames': [for (final frame in _total.frames) frame.snapshot()],
    };
  }

  static final _pageId = RegExp(r'^[a-z][a-z0-9_.]{0,63}$');
  static final _unsafeMetadata = RegExp(r'[\x00-\x1f\\/@]');
  static const _excludedPages = {
    'settings',
    'performance_settings',
    'performance_lab',
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
    'material',
    'deviceApiLevel',
    'metadataStatus',
    'contentActionCount',
    'chatMessageCount',
    'theme',
    'appBaseCommit',
    'sourceFingerprint',
  };
}

class _ArmedCase {
  const _ArmedCase(this.theme, this.scenario, this.target);
  final String theme, target;
  final FrameScenario scenario;
}

class _FrameLabel {
  _FrameLabel(
    this.startFrameNumber,
    this.page,
    this.scenario,
    this.hz,
    this.rateVerified, {
    required this.active,
    required this.conditions,
    required this.measurement,
    required this.firstPageEntry,
  });
  final int startFrameNumber;
  final String page;
  final FrameScenario? scenario;
  final double hz;
  final bool rateVerified, active;
  final _RenderConditions conditions;
  final _CaseStats? measurement;
  final _PageEntry? firstPageEntry;
  String get conditionKey => '${conditions.key}|$hz|$rateVerified';
}

class _RenderConditions {
  const _RenderConditions({
    this.starfield,
    this.renderer = 'unknown',
    this.rendererBackend = 'unknown',
    this.rendererVerified = false,
    this.theme = 'unknown',
    this.viewportWidth,
    this.viewportHeight,
    this.devicePixelRatio,
    this.textScale,
  });
  final bool? starfield;
  final String renderer, rendererBackend, theme;
  final bool rendererVerified;
  final double? viewportWidth, viewportHeight, devicePixelRatio, textScale;
  String get key =>
      '$starfield|$renderer|$rendererBackend|$rendererVerified|$theme|$viewportWidth|$viewportHeight|$devicePixelRatio|$textScale';
  Map<String, Object?> snapshot(double hz, bool rateVerified) => {
    'material': 'solid',
    'starfield': starfield,
    'renderer': renderer,
    'rendererBackend': rendererBackend,
    'rendererVerified': rendererVerified,
    'theme': theme,
    'viewportWidth': viewportWidth,
    'viewportHeight': viewportHeight,
    'devicePixelRatio': devicePixelRatio,
    'textScale': textScale,
    'refreshRateHz': hz,
    'refreshRateVerified': rateVerified,
    'frameBudgetMs': 1000 / hz,
    'frameBudgetUs': 1000000 / hz,
  };
}

class _RawFrame {
  _RawFrame(this.timing, this.label, this.buildUs, this.rasterUs);
  final FrameTiming timing;
  final _FrameLabel label;
  final int buildUs, rasterUs;
  int get vsyncUs => timing.timestampInMicroseconds(FramePhase.vsyncStart);
  Map<String, Object?> snapshot() => {
    'frameNumber': timing.frameNumber,
    'vsyncStartUs': vsyncUs,
    'buildUs': buildUs,
    'rasterUs': rasterUs,
    'page': label.page,
    'scenario': label.scenario?.name,
    'caseId': label.measurement?.id,
    'refreshRateHz': label.hz,
    'phasesUs': {
      for (final phase in FramePhase.values)
        phase.name: timing.timestampInMicroseconds(phase),
    },
  };
}

class _FrameStats {
  _FrameStats(this.limit);
  final int limit;
  final frames = <_RawFrame>[];
  int count = 0, overflow = 0, overEither = 0;
  void add(_RawFrame frame) {
    count++;
    if (math.max(frame.buildUs, frame.rasterUs) > 1000000 / frame.label.hz) {
      overEither++;
    }
    if (frames.length < limit) {
      frames.add(frame);
    } else {
      overflow++;
    }
  }

  Map<String, Object?> snapshot() => {
    'frameCount': count,
    'rawFrameCount': frames.length,
    'rawSampleOverflowFrameCount': overflow,
    'percentilesExact': overflow == 0,
    'uiBuild': _distribution(frames, false, overflow),
    'raster': _distribution(frames, true, overflow),
    'eitherThreadOverBudgetFrames': overEither,
    'refreshRatesHz': frames.map((frame) => frame.label.hz).toSet().toList()
      ..sort(),
  };
}

Map<String, Object?> _distribution(
  List<_RawFrame> frames,
  bool raster,
  int overflow,
) {
  final values = [
    for (final frame in frames) raster ? frame.rasterUs : frame.buildUs,
  ]..sort();
  int? rank(int p) => values.isEmpty || overflow > 0
      ? null
      : values[((p * values.length + 99) ~/ 100) - 1];
  final overLiteral = values.where((value) => value > 8330).length;
  return {
    'count': values.length,
    'p50Us': rank(50),
    'p90Us': rank(90),
    'p99Us': rank(99),
    'averageMs': values.isEmpty || overflow > 0
        ? null
        : values.reduce((a, b) => a + b) / values.length / 1000,
    'p90Ms': rank(90) == null ? null : rank(90)! / 1000,
    'p99Ms': rank(99) == null ? null : rank(99)! / 1000,
    'worstMs': values.isEmpty || overflow > 0 ? null : values.last / 1000,
    'maxUs': values.isEmpty || overflow > 0 ? null : values.last,
    'over8_33msCount': overflow > 0 ? null : overLiteral,
    'over8_33msRatio': values.isEmpty || overflow > 0
        ? null
        : overLiteral / values.length,
    'overExact120HzPeriodCount': overflow > 0
        ? null
        : values.where((value) => value * 120 > 1000000).length,
    'overBudgetFrames': overflow > 0
        ? null
        : frames
              .where(
                (f) => (raster ? f.rasterUs : f.buildUs) > 1000000 / f.label.hz,
              )
              .length,
    'overBudgetRatio': values.isEmpty || overflow > 0
        ? null
        : frames
                  .where(
                    (f) =>
                        (raster ? f.rasterUs : f.buildUs) >
                        1000000 / f.label.hz,
                  )
                  .length /
              values.length,
    'rawSampleOverflowFrameCount': overflow,
  };
}

class _PageEntry {
  _PageEntry(int limit) : stats = _FrameStats(limit);
  final _FrameStats stats;
  int? firstUs;
  int outOfOrder = 0;
  void add(_RawFrame frame) {
    firstUs ??= frame.vsyncUs;
    if (frame.vsyncUs < firstUs!) {
      outOfOrder++;
      return;
    }
    if (frame.vsyncUs - firstUs! < 2000000) stats.add(frame);
  }

  Map<String, Object?> snapshot() => {
    'firstVsyncStartUs': firstUs,
    'first2Seconds': stats.snapshot(),
    'earlierOutOfOrderFrameCount': outOfOrder,
  };
}

class _CaseStats {
  _CaseStats({
    required this.id,
    required this.theme,
    required this.scenario,
    required this.fixtureId,
    required this.messageCount,
    required this.maxFrames,
    required this.maxGroups,
    required this.startedUs,
  });
  final String id, theme, fixtureId;
  final FrameScenario scenario;
  final int messageCount, maxFrames, maxGroups, startedUs;
  final frames = <_RawFrame>[];
  final _conditions = <String, _FrameLabel>{};
  final _pages = <String>{};
  bool completed = false,
      lifecycleInterrupted = false,
      _retired = false,
      outOfOrder = false;
  String? invalidationReason;
  int? endedUs, _lastUs;
  int overflow = 0, conditionOverflow = 0, excludedPageFrames = 0;
  void retire() {
    _retired = true;
    frames.clear();
    _conditions.clear();
    _pages.clear();
  }

  void add(_RawFrame frame) {
    if (_retired) return;
    if (_lastUs != null && frame.vsyncUs < _lastUs!) outOfOrder = true;
    _lastUs = math.max(_lastUs ?? frame.vsyncUs, frame.vsyncUs);
    _pages.add(frame.label.page);
    if (frames.length < maxFrames) {
      frames.add(frame);
    } else {
      overflow++;
    }
    if (_conditions.containsKey(frame.label.conditionKey) ||
        _conditions.length < maxGroups) {
      _conditions[frame.label.conditionKey] = frame.label;
    } else {
      conditionOverflow++;
    }
  }

  Map<String, Object?> snapshot({Map<_RawFrame, int>? rawIndices}) {
    final sorted = List<_RawFrame>.of(frames)
      ..sort((a, b) => a.vsyncUs.compareTo(b.vsyncUs));
    final first = sorted.firstOrNull?.vsyncUs,
        last = sorted.lastOrNull?.vsyncUs;
    Map<String, Object?> stats(List<_RawFrame> samples) {
      final value = _FrameStats(maxFrames);
      for (final sample in samples) {
        value.add(sample);
      }
      return value.snapshot();
    }

    final warmup = first == null
        ? <_RawFrame>[]
        : sorted.where((f) => f.vsyncUs - first < 2000000).toList();
    final steady = first == null
        ? <_RawFrame>[]
        : sorted.where((f) => f.vsyncUs - first >= 2000000).toList();
    final issues = <String>[
      if (!completed || endedUs == null) 'incomplete',
      ?invalidationReason,
      if (frames.isEmpty) 'no_frames',
      if (overflow > 0) 'raw_frame_limit_reached',
      if (rawIndices != null &&
          sorted.any((frame) => !rawIndices.containsKey(frame)))
        'raw_export_table_incomplete',
      if (conditionOverflow > 0) 'condition_group_limit_reached',
      if (_conditions.length != 1) 'mixed_or_missing_render_conditions',
      if (lifecycleInterrupted) 'lifecycle_interrupted',
      if (outOfOrder) 'out_of_order_vsync_timestamps',
      if (endedUs != null &&
          endedUs! - startedUs < FrameRecorder.minimumSampleMicros(scenario))
        'sample_duration_too_short',
      if (scenario != FrameScenario.pageEntry &&
          scenario != FrameScenario.bottomBarSwitch &&
          _pages.length > 1)
        'multiple_pages',
      if (scenario == FrameScenario.longChatScroll && messageCount < 60)
        'long_chat_has_fewer_than_60_messages',
      if (scenario == FrameScenario.pageEntry &&
          !_pages.contains('action_library'))
        'entry_target_not_observed',
      if (scenario == FrameScenario.bottomBarSwitch &&
          !(_pages.contains('chat') && _pages.contains('action_library')))
        'real_bottom_bar_flow_not_observed',
      if (scenario == FrameScenario.trainingPlayback &&
          !_pages.contains('training'))
        'training_page_not_observed',
      if (frames.map((f) => f.timing.frameNumber).toSet().length !=
          frames.length)
        'duplicate_frame_numbers',
      if ((scenario == FrameScenario.planCardScroll ||
              scenario == FrameScenario.longChatScroll) &&
          steady.isEmpty)
        'no_steady_state_frames',
    ];
    for (final label in _conditions.values) {
      final c = label.conditions;
      if (!label.rateVerified) issues.add('refresh_rate_unverified');
      if (!c.rendererVerified || c.renderer == 'unknown') {
        issues.add('renderer_unverified');
      }
      if (c.rendererBackend == 'unknown' || c.rendererBackend == 'unverified') {
        issues.add('renderer_backend_unverified');
      }
      if (c.theme != theme) issues.add('theme_mismatch');
      if ([
        c.viewportWidth,
        c.viewportHeight,
        c.devicePixelRatio,
        c.textScale,
      ].contains(null)) {
        issues.add('viewport_unverified');
      }
      if (c.starfield == null) issues.add('starfield_unverified');
    }
    final acceptanceFrames = scenario == FrameScenario.pageEntry
        ? sorted
        : steady;
    final acceptance = stats(acceptanceFrames),
        raster = acceptance['raster'] as Map;
    final hz = _conditions.values.firstOrNull?.hz;
    const budget = 8330;
    final p99 = raster['p99Us'];
    return {
      'id': id,
      'material': 'solid',
      'theme': theme,
      'scenario': scenario.name,
      'fixtureId': fixtureId,
      'messageCount': messageCount,
      'completed': completed,
      'startedMonotonicUs': startedUs,
      'endedMonotonicUs': endedUs,
      'sampleDurationUs': endedUs == null ? null : endedUs! - startedUs,
      'firstVsyncStartUs': first,
      'lastVsyncStartUs': last,
      'observedDurationSeconds': first == null || last == null
          ? null
          : (last - first) / 1000000,
      'pages': _pages.toList(),
      'comparisonReady': issues.isEmpty,
      'comparisonIssues': issues.toSet().toList(),
      'rawFrameCount': frames.length,
      'rawFrameOverflowCount': overflow,
      'excludedDiagnosticPageFrames': excludedPageFrames,
      'allFrames': stats(sorted),
      'warmupFirst2Seconds': stats(warmup),
      'steadyState': stats(steady),
      'acceptanceWindow': scenario == FrameScenario.pageEntry
          ? 'allFrames'
          : 'steadyState',
      'acceptanceBudgetUs': budget,
      'actualFrameBudgetUs': hz == null ? null : 1000000 / hz,
      'is120HzDeviceSample': hz != null && (hz - 120).abs() < .25,
      'rasterP99Pass': issues.isEmpty && p99 is int && p99 < budget,
      'conditions': [
        for (final label in _conditions.values)
          label.conditions.snapshot(label.hz, label.rateVerified),
      ],
      if (rawIndices == null)
        'rawFrames': [for (final frame in sorted) frame.snapshot()]
      else
        'rawFrameIndices': [for (final frame in sorted) rawIndices[frame]],
    };
  }
}
