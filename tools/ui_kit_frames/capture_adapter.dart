// Constructor bridge only; rendering, animation and tokens are production code.
import 'package:flutter/material.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' as sdk;

Widget buildCaptureBubble({
  required BuildContext context,
  Key? key,
  required coach.CoachSessionState state,
  required ExerciseLibrary library,
  required bool waiting,
  required bool visualComplete,
  required VoidCallback onCancel,
}) {
  final summary = coach.CoachTaskSummary.fromState(state);
  return sdk.CoachTaskBubble(
    key: key,
    title: summary.title,
    status: summary.status,
    phase: summary.phase,
    parameters: summary.parameters,
    picks: summary.picks.where(library.contains).toList(growable: false),
    complete: summary.complete,
    waiting: waiting,
    visualComplete: visualComplete,
    onCancel: onCancel,
    cutoutBuilder: smartfitTaskCutouts(library),
  );
}

Widget buildCaptureDelivery({
  required bool preparing,
  required bool successful,
  required Widget child,
}) => sdk.CoachDeliveryTransition(
  preparing: preparing,
  successful: successful,
  child: child,
);

Widget buildCaptureFocus({
  required String? title,
  required VoidCallback onClear,
}) => sdk.PlanFocusLabel(
  title: title,
  onClear: onClear,
  bottomGap: 8,
  iconBuilder: smartfitPlanFocusIcon,
  clearIconBuilder: smartfitPlanFocusClearIcon,
);

void beginCaptureExit(BuildContext context) =>
    TrainingRouteScope.maybeOf(context)!.beginExit();
