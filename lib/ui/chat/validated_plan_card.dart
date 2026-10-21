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
  });

  final coach.ValidatedPlan validatedPlan;
  final ExerciseLibrary library;
  final bool Function(TrainingPlan) isSaved;
  final void Function(TrainingPlan, OriginRect) onStart;
  final ValueChanged<TrainingPlan> onSave;
  final ValueChanged<TrainingPlan> onOpen;
  final bool landing;

  @override
  Widget build(BuildContext context) {
    final plan = TrainingPlan.fromJson(validatedPlan.plan.toJson());
    return PlanCard(
      plan: plan,
      library: library,
      saved: isSaved(plan),
      landing: landing,
      onStart: (origin) => onStart(plan, origin),
      onSave: () => onSave(plan),
      onOpen: () => onOpen(plan),
    );
  }
}
