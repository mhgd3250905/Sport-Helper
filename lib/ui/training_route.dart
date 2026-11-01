import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show
        TrainerSlideRoute,
        TrainerSlideRouteControl,
        TrainerSlideRouteScope,
        TrainerTheme;

import '../app/training_transition_activity.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_report.dart';
import '../diagnostics/training_transition_timings.dart';
import 'theme/trainer_theme.dart';

/// Host diagnostics for the SDK-owned route shared by every training entry.
/// Animation, gates, media retirement and failed-save recovery stay in the SDK.
class TrainingRoute<T> extends TrainerSlideRoute<T> {
  TrainingRoute({
    required super.context,
    required super.builder,
    TrainerTheme? trainerTheme,
    this.sourceEntry = 'plan',
    super.settings,
  }) : _theme = (trainerTheme ?? SmartFitTrainerTheme.of(context)).isDark
           ? 'dark'
           : 'light',
       _releaseEntry = TrainingTransitionActivity.instance.hold(),
       super(trainerTheme: trainerTheme ?? SmartFitTrainerTheme.of(context)) {
    final environment = PerformanceReportService.instance;
    TrainingTransitionTimings.instance.setEnvironment(
      renderer: environment.renderer,
      rendererBackend: environment.rendererBackend,
      rendererVerified: environment.rendererVerified,
    );
    _entryTiming = _beginTiming(TrainingTransitionKind.entry);
    FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteEntry);
    control.addListener(_sdkStateChanged);
  }

  final String sourceEntry;
  final String _theme;
  final VoidCallback _releaseEntry;
  TrainingTransitionTimingToken? _entryTiming, _exitTiming;
  VoidCallback? _releaseExit;
  bool _entryEnded = false,
      _exitActive = false,
      _wasExiting = false,
      _disposed = false;

  TrainingTransitionTimingToken? _beginTiming(TrainingTransitionKind kind) =>
      TrainingTransitionTimings.instance.begin(
        kind,
        theme: _theme,
        reducedMotion: reducedMotion,
        sourceEntry: sourceEntry,
      );

  void _sdkStateChanged() {
    if (_disposed) return;
    final startingExit = control.exiting && !_wasExiting;
    _wasExiting = control.exiting;
    if (control.entered && !_entryEnded) {
      _entryEnded = true;
      TrainingTransitionTimings.instance.finish(_entryTiming);
      FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
      _releaseEntry();
    }
    if (control.saveFailed) {
      _endExitTiming(outcome: 'save_failed');
    } else if (startingExit) {
      // A retry can start while mediaRetired is already true. The next SDK
      // retirement notification closes this new timing window after its slide.
      _exitActive = true;
      _releaseExit = TrainingTransitionActivity.instance.hold();
      _exitTiming = _beginTiming(TrainingTransitionKind.exit);
      FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteExit);
    } else if (control.exiting && control.mediaRetired) {
      _endExitTiming();
    }
  }

  void _endExitTiming({String outcome = 'completed'}) {
    if (!_exitActive) return;
    _exitActive = false;
    TrainingTransitionTimings.instance.finish(_exitTiming, outcome: outcome);
    _exitTiming = null;
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteExit);
    _releaseExit?.call();
    _releaseExit = null;
  }

  @override
  void dispose() {
    _disposed = true;
    control.removeListener(_sdkStateChanged);
    if (!_entryEnded) {
      TrainingTransitionTimings.instance.finish(
        _entryTiming,
        outcome: 'aborted',
      );
      FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
    }
    _endExitTiming(outcome: control.entered ? 'completed' : 'aborted');
    _releaseEntry();
    super.dispose();
  }
}

/// Existing host pages use the SDK's public control and inherited scope directly.
typedef TrainingRouteControl = TrainerSlideRouteControl;
typedef TrainingRouteScope = TrainerSlideRouteScope;
