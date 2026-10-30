import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../app/build_info.dart';
import 'training_transition_timings_storage.dart';

enum TrainingTransitionKind { entry, exit }

/// A timestamp window, not the phase active when a delayed batch is delivered.
class TrainingTransitionTimingToken {
  TrainingTransitionTimingToken._({
    required this.id,
    required this.kind,
    required this.startUs,
    required this.firstFrameNumber,
    required this.metadata,
  });
  final String id;
  final TrainingTransitionKind kind;
  final int startUs;
  final int? firstFrameNumber;
  final Map<String, Object?> metadata;
  final frames = <Map<String, int>>[];
  final _frameKeys = <String>{};
  final _ready = Completer<void>();
  Completer<void>? _publishDone;
  int? endUs;
  int? lastFrameNumber;
  String outcome = 'completed';
  bool truncated = false, publishing = false, published = false;
  int revision = 0, publishedRevision = -1;
  Timer? timer;
}

/// Internal builds collect engine timings with no per-frame encoding, I/O or
/// notifications. Closed windows remain eligible for delayed engine batches.
/// Stats and JSON encoding run in compute, after the visual transition ends.
class TrainingTransitionTimings extends ChangeNotifier
    with WidgetsBindingObserver {
  TrainingTransitionTimings({
    required this.enabled,
    TrainingTransitionTimingsStorage? storage,
    DateTime Function()? clock,
    int Function()? monotonicMicros,
    int Function()? currentFrameNumber,
    bool Function()? currentFrameInProgress,
    this.settleDelay = const Duration(milliseconds: 1200),
    this.attachScheduler = true,
    Future<Map<String, Object?>> Function(Map<String, Object?>)? summarize,
    Future<String> Function(Map<String, Object?>)? encode,
  }) : _storage = storage ?? createTrainingTransitionTimingsStorage(),
       _clock = clock ?? DateTime.now,
       _monotonicMicros = monotonicMicros ?? (() => Timeline.now),
       _currentFrameNumber =
           currentFrameNumber ??
           (() => SchedulerBinding
               .instance
               .platformDispatcher
               .frameData
               .frameNumber),
       _currentFrameInProgress =
           currentFrameInProgress ??
           (() => const {
             SchedulerPhase.transientCallbacks,
             SchedulerPhase.midFrameMicrotasks,
             SchedulerPhase.persistentCallbacks,
           }.contains(SchedulerBinding.instance.schedulerPhase)),
       _summarize =
           summarize ?? ((data) => compute(summarizeTransitionTimings, data)),
       _encode = encode ?? ((data) => compute(_encodeReport, data)) {
    processId = _clock().toUtc().microsecondsSinceEpoch.toRadixString(36);
  }

  static const buildEnabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal';
  static TrainingTransitionTimings instance = TrainingTransitionTimings(
    enabled: buildEnabled,
  );
  static const retainedResults = 10;
  static const maximumFramesPerTransition = 600;
  final bool enabled, attachScheduler;
  final Duration settleDelay;
  final TrainingTransitionTimingsStorage _storage;
  final DateTime Function() _clock;
  final int Function() _monotonicMicros;
  final int Function() _currentFrameNumber;
  final bool Function() _currentFrameInProgress;
  final Future<Map<String, Object?>> Function(Map<String, Object?>) _summarize;
  final Future<String> Function(Map<String, Object?>) _encode;
  late final String processId;
  final _windows = <TrainingTransitionTimingToken>[];
  final _results = <Map<String, Object?>>[];
  final _runs = <TrainingTransitionKind, int>{};
  final _environment = <String, Object?>{
    'renderer': 'unverified',
    'rendererBackend': 'unverified',
    'rendererVerified': false,
  };
  Future<void>? _initializing;
  Future<void>? _writes;
  TrainingTransitionTimingToken? _active;
  int _sequence = 0;
  bool _attached = false, _disposed = false, persistenceFailed = false;

  List<Map<String, Object?>> get results =>
      List.unmodifiable(_results.map(Map<String, Object?>.unmodifiable));
  int get pendingResultCount => _windows
      .where(
        (window) =>
            window.endUs != null &&
            (!window._ready.isCompleted ||
                window.publishing ||
                window.revision != window.publishedRevision),
      )
      .length;
  bool get hasPendingResults => pendingResultCount > 0;

  /// Call during app startup, not on the first animation frame.
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!enabled || _disposed) return;
    _attach();
    try {
      final stored = await _storage.read();
      if (stored != null) {
        final loaded = await compute(_decodeResults, stored);
        if (_disposed) return;
        final existing = _results.map((row) => row['id']).toSet();
        _results.addAll(loaded.where((row) => !existing.contains(row['id'])));
        _sortAndBound();
      }
    } on Object {
      persistenceFailed = true;
    }
    if (!_disposed) notifyListeners();
  }

  /// Copy only verified renderer/device facts from PerformanceReportService.
  /// Requested Android backend flags alone must never set rendererVerified.
  void setEnvironment({
    required String renderer,
    required String rendererBackend,
    required bool rendererVerified,
  }) {
    if (!enabled) return;
    final verified =
        rendererVerified && const {'impeller', 'skia'}.contains(renderer);
    // The engine backend is fixed for this process. A temporary failed native
    // query cannot erase an already-observed startup announcement.
    if (!verified && _environment['rendererVerified'] == true) return;
    _environment
      ..['renderer'] = verified ? renderer : 'unverified'
      ..['rendererBackend'] = verified ? rendererBackend : 'unverified'
      ..['rendererVerified'] = verified;
    if (verified) {
      for (final window in _windows) {
        if (window.metadata['rendererVerified'] != true) {
          window.metadata.addAll({
            ..._environment,
            'rendererVerifiedAfterSampleStarted': true,
          });
        }
      }
      var changed = false;
      for (final result in _results) {
        if (result['processId'] == processId &&
            result['rendererVerified'] != true) {
          result.addAll({
            ..._environment,
            'rendererVerifiedAfterSampleStarted': true,
          });
          changed = true;
        }
      }
      if (changed) _persist();
    }
  }

  void _attach() {
    if (_attached || !attachScheduler || !enabled || _disposed) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(acceptTimings);
    WidgetsBinding.instance.addObserver(this);
  }

  /// [sourceEntry] is a stable route identifier, never plan/user content.
  TrainingTransitionTimingToken? begin(
    TrainingTransitionKind kind, {
    String theme = 'unknown',
    bool reducedMotion = false,
    String? sourceEntry,
  }) {
    // main initializes real collection before runApp. Merely constructing a
    // widget in a test/preview must not arm batch-tail timers or synthesize data.
    if (!enabled || _disposed || _initializing == null) return null;
    _attach();
    if (_active case final old?) finish(old, outcome: 'interrupted');
    final run = (_runs[kind] ?? 0) + 1;
    _runs[kind] = run;
    final time = _clock().toUtc();
    final number = _currentFrameNumber();
    final window = TrainingTransitionTimingToken._(
      id: '$processId-${kind.name}-$run',
      kind: kind,
      startUs: _monotonicMicros(),
      firstFrameNumber: number < 0
          ? null
          : number + (_currentFrameInProgress() ? 0 : 1),
      metadata: {
        'processId': processId,
        'processSequence': ++_sequence,
        'kind': kind.name,
        'runInProcess': run,
        'firstAfterProcessStart': run == 1,
        'transitionStyle': 'horizontal_slide',
        'sourceEntry': ?sourceEntry,
        'startedAtUtc': time.toIso8601String(),
        'theme': const {'light', 'dark'}.contains(theme) ? theme : 'unknown',
        'reducedMotion': reducedMotion,
        'appVersion': AppBuildInfo.version,
        'source': const String.fromEnvironment(
          'SMARTFIT_BUILD_SOURCE',
          defaultValue: 'working_tree',
        ),
        'sdk': AppBuildInfo.sdkRef,
        'buildMode': kProfileMode
            ? 'profile'
            : (kReleaseMode ? 'release' : 'debug'),
        ..._environment,
      },
    );
    _windows.add(window);
    _active = window;
    while (_windows.length > retainedResults) {
      final removed = _windows.removeAt(0);
      removed.timer?.cancel();
      if (!removed._ready.isCompleted) removed._ready.complete();
    }
    return window;
  }

  /// Does not wait for storage or delay the transition. The engine may report
  /// this range up to a second later; publication waits for that normal tail.
  void finish(
    TrainingTransitionTimingToken? token, {
    String outcome = 'completed',
  }) {
    if (!enabled || _disposed || token == null || token.endUs != null) return;
    token.endUs = _monotonicMicros();
    final number = _currentFrameNumber();
    token.lastFrameNumber = number < 0 ? null : number;
    token.outcome =
        const {
          'completed',
          'interrupted',
          'aborted',
          'save_failed',
        }.contains(outcome)
        ? outcome
        : 'interrupted';
    if (identical(_active, token)) _active = null;
    token.timer = Timer(settleDelay, () => unawaited(_publish(token)));
  }

  @visibleForTesting
  void acceptTimings(List<FrameTiming> timings) {
    if (!enabled || _disposed) return;
    for (final timing in timings) {
      final start = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      if (start < 0 || build < 0 || raster < 0) continue;
      for (final window in _windows.reversed) {
        // Beginning during build must include that current engine frame even
        // though its vsync timestamp predates this call's Timeline.now.
        final exact =
            timing.frameNumber >= 0 && window.firstFrameNumber != null;
        final belongs = exact
            ? timing.frameNumber >= window.firstFrameNumber! &&
                  (window.lastFrameNumber == null ||
                      timing.frameNumber <= window.lastFrameNumber!)
            : start >= window.startUs &&
                  (window.endUs == null || start < window.endUs!);
        if (!belongs) continue;
        final key = '${timing.frameNumber}:$start';
        if (window._frameKeys.contains(key)) break;
        if (window.frames.length >= maximumFramesPerTransition) {
          if (!window.truncated) {
            window.truncated = true;
            window.revision++;
            _scheduleCorrection(window);
          }
          break;
        }
        window._frameKeys.add(key);
        window.frames.add({
          'frameNumber': timing.frameNumber,
          'vsyncStartUs': start,
          'buildUs': build,
          'rasterUs': raster,
          'totalSpanUs': timing.totalSpan.inMicroseconds,
        });
        window.revision++;
        _scheduleCorrection(window);
        break;
      }
    }
  }

  void _scheduleCorrection(TrainingTransitionTimingToken window) {
    if (!window.published || window.publishing) return;
    window.timer?.cancel();
    window.timer = Timer(
      const Duration(milliseconds: 100),
      () => unawaited(_publish(window)),
    );
  }

  Future<void> _publish(TrainingTransitionTimingToken window) async {
    if (_disposed || !_windows.contains(window) || window.endUs == null) {
      return;
    }
    if (window.publishing) {
      await window._publishDone?.future;
      return;
    }
    if (window.published && window.revision == window.publishedRevision) return;
    window.timer?.cancel();
    window.publishing = true;
    window._publishDone = Completer<void>();
    final revision = window.revision;
    try {
      final result = await _summarize({
        ...window.metadata,
        'id': window.id,
        'startUs': window.startUs,
        'endUs': window.endUs,
        'firstFrameNumber': window.firstFrameNumber,
        'lastFrameNumber': window.lastFrameNumber,
        'outcome': window.outcome,
        'truncated': window.truncated,
        'frames': List<Map<String, int>>.of(window.frames),
      });
      if (_disposed || !_windows.contains(window)) return;
      if (window.metadata['rendererVerified'] == true) {
        for (final key in const [
          'renderer',
          'rendererBackend',
          'rendererVerified',
          'rendererVerifiedAfterSampleStarted',
        ]) {
          if (window.metadata.containsKey(key)) {
            result[key] = window.metadata[key];
          }
        }
      }
      _results.removeWhere((row) => row['id'] == window.id);
      _results.add(result);
      _sortAndBound();
      window.published = true;
      window.publishedRevision = revision;
      _persist();
      notifyListeners();
    } on Object {
      persistenceFailed = true;
      if (!_disposed) notifyListeners();
    } finally {
      window.publishing = false;
      if (!window._ready.isCompleted) window._ready.complete();
      if (window._publishDone?.isCompleted == false) {
        window._publishDone!.complete();
      }
      if (!_disposed && revision != window.revision) {
        _scheduleCorrection(window);
      }
    }
  }

  void _sortAndBound() {
    _results.sort((a, b) {
      final aCurrent = a['processId'] == processId;
      final bCurrent = b['processId'] == processId;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      if (aCurrent && bCurrent) {
        return ((b['processSequence'] as int?) ?? 0).compareTo(
          (a['processSequence'] as int?) ?? 0,
        );
      }
      final time = '${b['startedAtUtc']}'.compareTo('${a['startedAtUtc']}');
      if (time != 0) return time;
      return ((b['processSequence'] as int?) ?? 0).compareTo(
        (a['processSequence'] as int?) ?? 0,
      );
    });
    if (_results.length > retainedResults) {
      _results.removeRange(retainedResults, _results.length);
    }
  }

  Map<String, Object?> get report => {
    'schema': 'smartfit-training-transition-timings@1',
    'recordedAtUtc': _clock().toUtc().toIso8601String(),
    'currentProcessId': processId,
    'enabled': enabled,
    'retainedLimit': retainedResults,
    'budgetMs': 16,
    'overBudgetDefinition':
        'buildUs > 16000 OR rasterUs > 16000; not total pipeline latency',
    'percentileDefinition': 'nearest rank: sorted[ceil(0.90*n)-1]',
    'sampleAttribution':
        'inclusive engine frameNumber boundaries; monotonic vsync interval fallback; late batches retained',
    'hasActiveTransition': _active != null,
    'persistenceFailed': persistenceFailed,
    'results': List<Map<String, Object?>>.of(_results),
  };

  void _persist() {
    final previous = _writes;
    _writes = previous == null
        ? _writeReport()
        : previous.then((_) => _writeReport());
  }

  Future<void> _writeReport() async {
    if (_disposed) return;
    try {
      final encoded = await _encode(report);
      await _storage.write(encoded);
      persistenceFailed = false;
    } on Object {
      persistenceFailed = true;
    }
    if (!_disposed) notifyListeners();
  }

  /// Copy waits only for closed samples' delayed timing delivery, not an active
  /// workout. It never clears previous runs or restarts collection.
  Future<String> exportJson() async {
    if (!enabled) throw StateError('Internal transition diagnostics disabled');
    await initialize();
    await Future.wait(
      _windows
          .where((window) => window.endUs != null)
          .map((window) => window._ready.future),
    );
    // Flush already-received late frames even inside a correction's 100ms
    // debounce. Timing delivery after the normal tail cannot stale a copy.
    for (final window in _windows.where((window) => window.endUs != null)) {
      if (window.publishing) await window._publishDone?.future;
      if (window.revision != window.publishedRevision) await _publish(window);
    }
    await _writes;
    return _encode(report);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      finish(_active, outcome: 'interrupted');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_attached) {
      SchedulerBinding.instance.removeTimingsCallback(acceptTimings);
      WidgetsBinding.instance.removeObserver(this);
    }
    for (final window in _windows) {
      window.timer?.cancel();
      if (!window._ready.isCompleted) window._ready.complete();
    }
    super.dispose();
  }
}

/// Pure worker: no Widget/engine/platform state crosses the isolate boundary.
@visibleForTesting
Map<String, Object?> summarizeTransitionTimings(Map<String, Object?> sample) {
  final frames = (sample['frames'] as List).cast<Map<String, int>>();
  final builds = frames.map((row) => row['buildUs']!).toList()..sort();
  final rasters = frames.map((row) => row['rasterUs']!).toList()..sort();
  double? percentile(List<int> values) =>
      values.isEmpty ? null : values[(values.length * .9).ceil() - 1] / 1000;
  double? maximum(List<int> values) =>
      values.isEmpty ? null : values.last / 1000;
  final over = frames
      .where((row) => row['buildUs']! > 16000 || row['rasterUs']! > 16000)
      .length;
  final complete =
      frames.isNotEmpty &&
      sample['outcome'] == 'completed' &&
      sample['truncated'] != true;
  return {
    ...sample,
    'frameCount': frames.length,
    'buildMaxMs': maximum(builds),
    'buildP90Ms': percentile(builds),
    'rasterMaxMs': maximum(rasters),
    'rasterP90Ms': percentile(rasters),
    'buildOver16ms': builds.where((value) => value > 16000).length,
    'rasterOver16ms': rasters.where((value) => value > 16000).length,
    'over16msFrames': over,
    'hasMeasuredFrames': frames.isNotEmpty,
    'sampleComplete': complete,
  };
}

String _encodeReport(Map<String, Object?> data) =>
    const JsonEncoder.withIndent('  ').convert(data);

List<Map<String, Object?>> _decodeResults(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map ||
      decoded['schema'] != 'smartfit-training-transition-timings@1' ||
      decoded['results'] is! List) {
    return [];
  }
  return (decoded['results'] as List)
      .whereType<Map>()
      .where(
        (row) =>
            row['id'] is String &&
            row['startedAtUtc'] is String &&
            const {'entry', 'exit'}.contains(row['kind']) &&
            row['frameCount'] is int &&
            (row['frames'] is List &&
                (row['frames'] as List).length <=
                    TrainingTransitionTimings.maximumFramesPerTransition),
      )
      .take(TrainingTransitionTimings.retainedResults)
      .map(
        (row) => Map<String, Object?>.from(row)
          // Older persisted reports used an obsolete performance target. Keep
          // their measured frames, but do not retain a superseded verdict.
          ..remove('warmAcceptanceRun')
          ..remove('eligibleForWarmTarget')
          ..remove('meetsNumericTarget'),
      )
      .toList();
}
