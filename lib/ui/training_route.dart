import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show TrainerTheme;

import '../app/training_transition_activity.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_report.dart';
import '../diagnostics/training_transition_timings.dart';
import 'theme/trainer_theme.dart';

/// One opaque horizontal route. The full SDK page exists from its first frame;
/// only its translation changes. startGate keeps native playback and training
/// work out of the slide, rather than hiding or delaying the SDK controls.
class TrainingRoute<T> extends PageRouteBuilder<T> {
  TrainingRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    this.trainerTheme,
    this.sourceEntry = 'plan',
    super.settings,
  }) : reducedMotion = MediaQuery.disableAnimationsOf(context),
       _theme = trainerTheme == null
           ? Theme.of(context).brightness.name
           : (trainerTheme.isDark ? 'dark' : 'light'),
       _releaseEntry = TrainingTransitionActivity.instance.hold(),
       super(
         opaque: true,
         allowSnapshotting: false,
         transitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : const Duration(milliseconds: 300),
         reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : const Duration(milliseconds: 280),
         pageBuilder: (context, _, _) => _TrainingRoutePage(
           route: ModalRoute.of(context)! as TrainingRoute,
           builder: builder,
         ),
         transitionsBuilder: (context, animation, _, child) => Stack(
           fit: StackFit.expand,
           children: [
             // Unlike ModalRoute's barrier this stays interactive while the
             // controller is reversed/dismissed and a durable save is pending.
             const AbsorbPointer(
               key: ValueKey('training-navigation-lock'),
               child: SizedBox.expand(),
             ),
             SlideTransition(
               key: const ValueKey('training-slide'),
               position: (ModalRoute.of(context)! as TrainingRoute)._position,
               child: child,
             ),
           ],
         ),
       ) {
    final environment = PerformanceReportService.instance;
    TrainingTransitionTimings.instance.setEnvironment(
      renderer: environment.renderer,
      rendererBackend: environment.rendererBackend,
      rendererVerified: environment.rendererVerified,
    );
    _entryTiming = _beginTiming(TrainingTransitionKind.entry);
    FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteEntry);
  }

  final String sourceEntry;
  final TrainerTheme? trainerTheme;
  final bool reducedMotion;
  final String _theme;
  final VoidCallback _releaseEntry;
  late final control = TrainingRouteControl._(this);
  TrainingTransitionTimingToken? _entryTiming, _exitTiming;
  VoidCallback? _releaseExit;
  Future<void>? _exitFuture;
  bool _entryEnded = false, _disposed = false, _aborted = false;
  int _exitCycle = 0;
  late final CurvedAnimation _curve;
  late final Animation<Offset> _position;

  TrainingTransitionTimingToken? _beginTiming(TrainingTransitionKind kind) =>
      TrainingTransitionTimings.instance.begin(
        kind,
        theme: _theme,
        reducedMotion: reducedMotion,
        sourceEntry: sourceEntry,
      );

  @override
  void install() {
    super.install();
    _curve = CurvedAnimation(
      parent: animation!,
      curve: Curves.easeOutCubic,
      // The tween runs 1 -> 0 on reverse; flip the curve so physical rightward
      // displacement is easeInCubic(elapsed), rather than its complement.
      reverseCurve: Curves.easeInCubic.flipped,
    );
    _position = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(_curve);
    controller!.addStatusListener(_statusChanged);
  }

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  RoutePopDisposition get popDisposition {
    // Leaving before the gate opens must never start or save a session.
    if (!control.entered) return RoutePopDisposition.pop;
    return super.popDisposition;
  }

  void _statusChanged(AnimationStatus status) {
    if (_disposed) return;
    if (status == AnimationStatus.completed && !control.exiting) {
      // Also used for a zero-duration route: paint the complete poster and
      // chrome once before releasing the SDK gate, never a blank video frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || _aborted || control.exiting) return;
        if (controller!.status != AnimationStatus.completed) return;
        if (!_entryEnded) {
          _entryEnded = true;
          TrainingTransitionTimings.instance.finish(_entryTiming);
          FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
          _releaseEntry();
        }
        control._entered();
      });
    }
  }

  void _beginExit() {
    if (_disposed || control.exiting) return;
    _exitCycle++;
    final cycle = _exitCycle;
    control._exiting();
    _releaseExit = TrainingTransitionActivity.instance.hold();
    _exitTiming = _beginTiming(TrainingTransitionKind.exit);
    FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteExit);
    // A route is explicitly allowed to be active with its controller dismissed
    // (the framework's interactive-pop lifecycle). Do not pop or dispose the SDK
    // before its durable save/receipt is complete.
    _exitFuture = () async {
      try {
        await controller!.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
      if (_disposed || cycle != _exitCycle) return;
      control._retireMedia();
      _endExitTiming();
    }();
  }

  void _endExitTiming({String outcome = 'completed'}) {
    TrainingTransitionTimings.instance.finish(_exitTiming, outcome: outcome);
    _exitTiming = null;
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteExit);
    _releaseExit?.call();
    _releaseExit = null;
  }

  Future<void> _beforeExitPop() async {
    _beginExit();
    await _exitFuture;
  }

  void _saveFailed() {
    if (_disposed || !control.exiting) return;
    _exitCycle++;
    _endExitTiming(outcome: 'save_failed');
    _exitFuture = null;
    control._failed();
    // Let the SDK finish replacing its retained early-exit frame with its
    // public retry view before sliding that complete view back into sight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && control.saveFailed && isActive) {
        controller!.forward();
        // A very fast failed save can reverse then forward at value=1 without
        // a value tick. Refresh ModalRoute's cached pointer/focus state too.
        changedInternalState();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void abortEntrance() {
    if (_disposed || control.entered || _aborted) return;
    _aborted = true;
    if (isCurrent) navigator?.pop();
    controller?.value = 0;
  }

  @override
  bool didPop(T? result) {
    if (!control.entered) {
      _aborted = true;
    } else if (!control.exiting) {
      _beginExit();
    }
    return super.didPop(result);
  }

  @override
  void dispose() {
    _disposed = true;
    controller?.removeStatusListener(_statusChanged);
    if (!_entryEnded) {
      TrainingTransitionTimings.instance.finish(
        _entryTiming,
        outcome: 'aborted',
      );
      FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
    }
    _endExitTiming(outcome: _aborted ? 'aborted' : 'completed');
    _releaseEntry();
    control.dispose();
    _curve.dispose();
    super.dispose();
  }
}

/// Public host state only; the SDK owns clocks, confirmation, records and pop.
class TrainingRouteControl extends ChangeNotifier {
  TrainingRouteControl._(this._route);
  final TrainingRoute<dynamic> _route;
  final _gate = Completer<void>();
  bool entered = false,
      exiting = false,
      mediaRetired = false,
      saveFailed = false;
  Future<void> get startGate => _gate.future;
  bool get canPlay => entered && !mediaRetired;

  void beginExit() => _route._beginExit();
  Future<void> beforeExitPop() => _route._beforeExitPop();
  void exitSaveFailed() => _route._saveFailed();

  void replay() {
    exiting = false;
    mediaRetired = false;
    saveFailed = false;
    notifyListeners();
  }

  void _entered() {
    if (entered) return;
    entered = true;
    if (!_gate.isCompleted) _gate.complete();
    notifyListeners();
  }

  void _exiting() {
    exiting = true;
    saveFailed = false;
    notifyListeners();
  }

  void _retireMedia() {
    mediaRetired = true;
    notifyListeners();
  }

  void _failed() {
    exiting = false;
    mediaRetired = true;
    saveFailed = true;
    notifyListeners();
  }
}

class TrainingRouteScope extends InheritedNotifier<TrainingRouteControl> {
  const TrainingRouteScope({
    super.key,
    required TrainingRouteControl control,
    required super.child,
  }) : super(notifier: control);
  static TrainingRouteControl? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TrainingRouteScope>()
      ?.notifier;
}

class _TrainingRoutePage extends StatefulWidget {
  const _TrainingRoutePage({required this.route, required this.builder});
  final TrainingRoute<dynamic> route;
  final WidgetBuilder builder;
  @override
  State<_TrainingRoutePage> createState() => _TrainingRoutePageState();
}

class _TrainingRoutePageState extends State<_TrainingRoutePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !widget.route.control.entered) {
      widget.route.abortEntrance();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.route.trainerTheme ?? SmartFitTrainerTheme.of(context);
    final dark = theme.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.mediaStage,
        systemNavigationBarColor: theme.mediaStage,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        key: const ValueKey('training-route-background'),
        color: theme.mediaStage,
        child: TrainingRouteScope(
          control: widget.route.control,
          child: ListenableBuilder(
            listenable: widget.route.control,
            child: Builder(builder: widget.builder),
            builder: (_, child) => IgnorePointer(
              ignoring:
                  !widget.route.control.entered || widget.route.control.exiting,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
