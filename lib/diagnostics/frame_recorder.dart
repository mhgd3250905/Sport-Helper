import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Fixed identifiers only: never pass a chat message, exercise name or path.
enum FrameScenario {
  actionListScroll,
  filterSwitch,
  actionDetail,
  longChatScroll,
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
    DateTime Function()? clock,
    int Function()? currentFrameNumber,
  }) : assert(maxPages > 0),
       assert(maxLabelTransitions >= 2),
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
  final DateTime Function() _clock;
  // Injectable because the test platform dispatcher cannot set engine FrameData.
  final int Function() _currentFrameNumber;
  final _labels = <_FrameLabel>[];
  final _pages = <String, _FrameStats>{};
  final _scenarios = <FrameScenario, _FrameStats>{};
  final _metadata = <String, Object?>{};
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
  late DateTime _startedAt;

  bool get isRunning => _running;
  bool get isCollecting => _attached;
  String get currentPage => _page;
  FrameScenario? get currentScenario => _scenario;

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
          active: true,
        ),
      );
    });
  }

  void _markInactive() {
    if (!_attached || _sessionStartFrameNumber == null) return;
    // The last begun frame remains eligible. Subsequent frames until resume
    // are explicitly excluded, even if the engine reports them in a late batch.
    _addLabel(
      _FrameLabel(
        _currentFrameNumber() + 1,
        _page,
        _scenario,
        _refreshRateHz,
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
      }
    }
  }

  /// Snapshot/JSON encoding/file creation belong on the explicit export path.
  Map<String, Object?> snapshot() => {
    'schema': 1,
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
    },
    'retention': {
      'maxPages': maxPages,
      'maxScenarios': FrameScenario.values.length,
      'histogramBucketsPerThread': _DurationStats.bucketCount,
      'maxLabelTransitions': maxLabelTransitions,
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
    'total': _total.snapshot(),
    'pages': {
      for (final entry in _pages.entries) entry.key: entry.value.snapshot(),
    },
    'otherPages': _otherPages.snapshot(),
    'scenarios': {
      for (final entry in _scenarios.entries)
        entry.key.name: entry.value.snapshot(),
    },
  };

  static final _pageId = RegExp(r'^[a-z][a-z0-9_.]{0,47}$');
  static final _unsafeMetadata = RegExp(r'[\x00-\x1f\\/@]');
  static const _scenarioExcludedPages = {'settings', 'performance_settings'};
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
  const _FrameLabel(
    this.startFrameNumber,
    this.page,
    this.scenario,
    this.refreshRateHz, {
    required this.active,
  });

  final int startFrameNumber;
  final String page;
  final FrameScenario? scenario;
  final double refreshRateHz;
  final bool active;
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
  };
}
