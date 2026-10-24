import 'exercise.dart';
import 'plan.dart';

/// A user-selected action uses its published drill dose, without a model call.
TrainingPlan singleExercisePlan(Exercise exercise) {
  final dose = exercise.dose;
  final item = PlanItem(
    exerciseId: exercise.id,
    mode: dose.mode,
    sets: dose.sets,
    reps: dose.reps,
    workSeconds: dose.seconds,
    perSide: exercise.unilateral,
    restSeconds: dose.restSeconds,
  );
  final seconds =
      item.workFor(exercise) * dose.sets * (exercise.unilateral ? 2 : 1) +
      dose.restSeconds * (dose.sets - 1);
  return TrainingPlan(
    id: 'selected-${exercise.id}-${DateTime.now().microsecondsSinceEpoch}',
    source: 'template',
    title: exercise.name,
    summary: exercise.cue,
    goal: exercise.category == ExerciseCategory.stretch ? 'relax' : 'fullbody',
    scene: exercise.scenes.firstOrNull ?? 'home',
    equipment: exercise.equipment.map((e) => e.name).toList(),
    level: exercise.level,
    targetMinutes: (seconds / 60).ceil().clamp(1, 120),
    blocks: [
      PlanBlock(
        id: 'selected',
        name: '动作跟练',
        type: BlockType.main,
        rounds: 1,
        restBetweenRoundsSeconds: 0,
        items: [item],
      ),
    ],
  );
}
