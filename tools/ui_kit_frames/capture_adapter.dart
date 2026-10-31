// Constructor bridge only; rendering, animation and tokens are production code.
import 'package:flutter/material.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/chat/coach_delivery_transition.dart';
import 'package:smartfit/ui/chat/plan_focus_label.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

Widget buildCaptureBubble({
  required BuildContext context,
  Key? key,
  required coach.CoachSessionState state,
  required ExerciseLibrary library,
  required bool waiting,
  required bool visualComplete,
  required VoidCallback onCancel,
}) => CoachTaskBubble(
  key: key,
  task: state.task,
  sessionState: state,
  library: library,
  waiting: waiting,
  visualComplete: visualComplete,
  onCancel: onCancel,
);

Widget buildCaptureDelivery({
  required bool preparing,
  required bool successful,
  required Widget child,
}) => CoachDeliveryTransition(
  preparing: preparing,
  successful: successful,
  child: child,
);

Widget buildCaptureFocus({
  required String? title,
  required VoidCallback onClear,
}) => PlanFocusLabel(title: title, onClear: onClear, bottomGap: 8);

void beginCaptureExit(BuildContext context) =>
    TrainingRouteScope.maybeOf(context)!.beginExit();
