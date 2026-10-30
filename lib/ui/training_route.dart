import 'package:flutter/material.dart';

import '../diagnostics/frame_recorder.dart';

/// Only a still poster is composed during these transitions. PlayerPage mounts
/// the trainer after entry and removes its video surface as exit begins, so a
/// live decoder is never animated together with the unchanged underlying page.
class TrainingRoute<T> extends PageRouteBuilder<T> {
  TrainingRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    super.settings,
  }) : super(
         transitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : const Duration(milliseconds: 320),
         reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
             ? Duration.zero
             : const Duration(milliseconds: 260),
         pageBuilder: (context, _, _) => builder(context),
       );

  static const _fadeIn = Interval(0, .7, curve: Curves.easeOutCubic);
  double _reverseFrom = 1;
  double _exitOpacity = 1;
  double _exitOffset = 0;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final exiting = animation.status == AnimationStatus.reverse;
        final exitProgress = Curves.easeInCubic.transform(
          (_reverseFrom == 0 ? 1.0 : 1 - animation.value / _reverseFrom).clamp(
            0.0,
            1.0,
          ),
        );
        final offset = exiting
            ? _exitOffset + (.06 - _exitOffset) * exitProgress
            : .06 * (1 - Curves.easeOutCubic.transform(animation.value));
        final opacity = exiting
            ? _exitOpacity * (1 - exitProgress)
            : _fadeIn.transform(animation.value);
        return SlideTransition(
          position: AlwaysStoppedAnimation(Offset(0, offset)),
          child: FadeTransition(
            opacity: AlwaysStoppedAnimation(opacity),
            child: child,
          ),
        );
      },
    );
  }

  // Do not drive a Material/Cupertino route's secondary scale, slide or shade.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_recordTransition);
  }

  void _recordTransition(AnimationStatus status) {
    if (offstage) return; // Hero pre-layout temporarily reports completed.
    final recorder = FrameRecorder.instance;
    switch (status) {
      case AnimationStatus.forward:
        if (transitionDuration != Duration.zero) {
          recorder.beginScenario(FrameScenario.trainingRouteEntry);
        }
      case AnimationStatus.completed:
        recorder.endScenario(FrameScenario.trainingRouteEntry);
      case AnimationStatus.reverse:
        // Returning before entry finishes must start at the currently visible
        // poster position/alpha, without a jump to the full-entry fade curve.
        _reverseFrom = animation!.value;
        _exitOpacity = _fadeIn.transform(_reverseFrom);
        _exitOffset = .06 * (1 - Curves.easeOutCubic.transform(_reverseFrom));
        recorder.endScenario(FrameScenario.trainingRouteEntry);
        if (reverseTransitionDuration != Duration.zero) {
          recorder.beginScenario(FrameScenario.trainingRouteExit);
        }
      case AnimationStatus.dismissed:
        recorder.endScenario(FrameScenario.trainingRouteExit);
    }
  }

  @override
  void dispose() {
    animation!.removeStatusListener(_recordTransition);
    FrameRecorder.instance
      ..endScenario(FrameScenario.trainingRouteEntry)
      ..endScenario(FrameScenario.trainingRouteExit);
    super.dispose();
  }
}
