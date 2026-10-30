import 'dart:async';

import 'package:flutter/material.dart';

import '../diagnostics/frame_recorder.dart';
import '../diagnostics/runtime_log.dart';
import '../diagnostics/performance_report.dart';
import '../diagnostics/training_transition_timings.dart';
import '../app/training_transition_activity.dart';
import '../domain/exercise.dart';
import 'theme/trainer_theme.dart';
import 'training_entry_placeholder.dart';
import 'training_poster_flight.dart';

part 'training_transition.dart';

/// A host-owned image. Entry freezes the tap position; return rechecks it.
class TrainingTransitionSource {
  const TrainingTransitionSource({
    required this.rect,
    required this.opacity,
    this.initialRect,
    this.repaintKey,
  });
  final Rect? Function() rect;
  final Rect? initialRect;
  final ValueNotifier<double> opacity;
  final GlobalKey? repaintKey;

  void show(double value) {
    if (repaintKey != null && repaintKey!.currentContext == null) return;
    opacity.value = value;
  }
}

/// Zero-time overlay route: the host animates a still image, never a video
/// texture. Its independent return layer survives the SDK's ordinary pop.
class TrainingRoute<T> extends PageRouteBuilder<T> {
  TrainingRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    this.source,
    super.settings,
  }) : _sourceRoute = ModalRoute.of(context),
       _theme = Theme.of(context).brightness.name,
       _reduced = MediaQuery.disableAnimationsOf(context),
       _releaseEntry = TrainingTransitionActivity.instance.hold(),
       _entryTiming = _beginTiming(context, TrainingTransitionKind.entry),
       super(
         opaque: false,
         transitionDuration: Duration.zero,
         reverseTransitionDuration: Duration.zero,
         pageBuilder: (context, _, _) => _TrainingTransitionHost(
           route: ModalRoute.of(context)! as TrainingRoute,
           builder: builder,
         ),
       );

  final TrainingTransitionSource? source;
  final ModalRoute<dynamic>? _sourceRoute;
  final String _theme;
  final bool _reduced;
  final VoidCallback _releaseEntry;
  final TrainingTransitionTimingToken? _entryTiming;
  TrainingTransitionTimingToken? _exitTiming;
  VoidCallback? _releaseExit;
  var _entryFinished = false;
  var _exitOutcome = 'completed';
  final _visual = Completer<void>();
  _TrainingTransitionHostState? _host;
  OverlayEntry? _returnEntry;
  bool _returning = false;
  bool _finishingVisual = false;
  LocalHistoryEntry? _returnHistory;

  /// Includes the post-pop shrink and the 120ms source-image cross-fade.
  Future<void> get visualCompleted => _visual.future;

  static TrainingTransitionTimingToken? _beginTiming(
    BuildContext context,
    TrainingTransitionKind kind,
  ) {
    final environment = PerformanceReportService.instance;
    TrainingTransitionTimings.instance.setEnvironment(
      renderer: environment.renderer,
      rendererBackend: environment.rendererBackend,
      rendererVerified: environment.rendererVerified,
    );
    return TrainingTransitionTimings.instance.begin(
      kind,
      theme: Theme.of(context).brightness.name,
      reducedMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  void _entryEnded() {
    if (_entryFinished) return;
    _entryFinished = true;
    TrainingTransitionTimings.instance.finish(_entryTiming);
    // Keep file verification and deferred model updates out of the 560ms
    // gate-release frame. This does not delay the gate, video or training.
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseEntry());
  }

  void _exitStarted() {
    _exitOutcome = 'completed';
    _releaseExit ??= TrainingTransitionActivity.instance.hold();
    _exitTiming = TrainingTransitionTimings.instance.begin(
      TrainingTransitionKind.exit,
      theme: _theme,
      reducedMotion: _reduced,
    );
  }

  void _exitFailed() {
    TrainingTransitionTimings.instance.finish(
      _exitTiming,
      outcome: 'save_failed',
    );
    _exitTiming = null;
    _releaseExit?.call();
    _releaseExit = null;
  }

  void _ensureReturnRecording() {
    // The SDK deliberately reports onExitStarted once until Replay. A durable
    // retry can therefore reach pop without a second callback. Preserve the
    // existing retry visuals while recording/freezing its actual return too.
    if (_exitTiming == null && _releaseExit == null) {
      _exitStarted();
      _exitTiming?.metadata['resumedAfterSaveFailure'] = true;
    }
  }

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  bool didPop(T? result) {
    _host?.prepareReturn();
    return super.didPop(result);
  }

  void _finishVisual() {
    if (_finishingVisual) return;
    _finishingVisual = true;
    final entry = _returnEntry;
    _returnEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    source?.show(1);
    _returnHistory?.remove();
    _returnHistory = null;
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteExit);
    if (!_entryFinished) {
      _entryFinished = true;
      TrainingTransitionTimings.instance.finish(
        _entryTiming,
        outcome: 'aborted',
      );
    }
    TrainingTransitionTimings.instance.finish(
      _exitTiming,
      outcome: _exitOutcome,
    );
    _releaseEntry();
    _releaseExit?.call();
    _releaseExit = null;
    if (!_visual.isCompleted) _visual.complete();
  }

  @override
  void dispose() {
    if (!_returning) _finishVisual();
    super.dispose();
  }
}
