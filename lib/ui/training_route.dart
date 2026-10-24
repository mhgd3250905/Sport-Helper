import 'package:flutter/material.dart';

/// The video stage opens at its final bounds, with the previous page offstage.
/// Fading or expanding the whole stage composites live media and the chat
/// together during the most expensive first frames. Ordinary pages retain
/// their themed slide transitions.
class TrainingRoute<T> extends PageRouteBuilder<T> {
  TrainingRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => builder(context),
      );
}
