import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import 'expand_route.dart';
import 'plan_card.dart';

/// The AI boundary accepts a gate result, then adapts it for the App's trainer.
class ValidatedPlanCard extends StatelessWidget {
  const ValidatedPlanCard({
    super.key,
    required this.validatedPlan,
    required this.library,
    required this.isSaved,
    required this.onStart,
    required this.onSave,
    required this.onOpen,
    this.landing = false,
    this.updatingSavedPlan = false,
    this.savedOverride,
    this.onSaveCopy,
  });

  final coach.ValidatedPlan validatedPlan;
  final ExerciseLibrary library;
  final bool Function(TrainingPlan) isSaved;
  final void Function(TrainingPlan, OriginRect) onStart;
  final ValueChanged<TrainingPlan> onSave;
  final ValueChanged<TrainingPlan> onOpen;
  final bool landing;
  final bool updatingSavedPlan;
  final bool? savedOverride;
  final ValueChanged<TrainingPlan>? onSaveCopy;

  @override
  Widget build(BuildContext context) {
    final plan = TrainingPlan.fromJson(validatedPlan.plan.toJson());
    return PlanCard(
      plan: plan,
      library: library,
      saved: savedOverride ?? isSaved(plan),
      landing: landing,
      saveLabel: updatingSavedPlan ? '更新到我的计划' : null,
      savedLabel: updatingSavedPlan ? '已更新' : null,
      onStart: (origin) => onStart(plan, origin),
      onSave: () => onSave(plan),
      onSaveCopy: onSaveCopy == null ? null : () => onSaveCopy!(plan),
      onOpen: () => onOpen(plan),
    );
  }
}
