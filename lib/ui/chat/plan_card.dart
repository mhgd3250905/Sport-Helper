import 'package:flutter/material.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../alpha_artwork.dart';
import '../theme/ui_polish_tokens.dart';
import 'coach_ui_adapter.dart';

/// App adapter: domain snapshots and navigation; card rendering lives in SDK.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.library,
    required this.saved,
    required this.onStart,
    required this.onSave,
    required this.onOpen,
    this.landing = false,
    this.saveLabel,
    this.savedLabel,
    this.onSaveCopy,
  });
  final TrainingPlan plan;
  final ExerciseLibrary library;
  final bool saved, landing;
  final VoidCallback onStart;
  final VoidCallback onSave, onOpen;
  final String? saveLabel, savedLabel;
  final VoidCallback? onSaveCopy;
  static const exerciseHeight = CoachPlanCard.exerciseHeight;
  static const setHeight = CoachPlanCard.setHeight;
  @override
  Widget build(BuildContext context) {
    final alphaCards = SfAlphaCards.enabledOf(context);
    final hero = plan.items.firstOrNull?.exerciseId;
    final alphaHero = SfAlphaCards.hasCover(
      hero == null ? null : library.tryGet(hero),
      enabled: alphaCards,
    );
    return SfAlphaCardScope(
      active: alphaHero,
      child: ClipRRect(
        key: ValueKey('plan-clip-${plan.id}'),
        borderRadius: BorderRadius.circular(SfCardTokens.radius),
        child: withSmartfitPlanSaveUi(
          context,
          CoachPlanCard(
            cutoutTopInset: alphaHero ? 0 : null,
            // This batch's opaque card surface starts at its own top edge.
            surfaceTopInset: 0,
            plan: toCoachRoutine(plan, library),
            library: CoachExerciseLibrary([
              for (final id in plan.exerciseIds)
                if (library.tryGet(id) case final e?)
                  toCoachExercise(e, alphaCards: alphaCards),
            ]),
            saved: saved,
            landing: landing,
            onStart: (_) => onStart(),
            onSave: onSave,
            onOpen: onOpen,
          ),
          planId: plan.id,
          saveLabel: saveLabel,
          savedLabel: savedLabel,
          onSaveCopy: onSaveCopy,
        ),
      ),
    );
  }
}
