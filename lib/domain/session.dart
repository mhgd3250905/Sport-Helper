/// App plan/library adapters. Training phases and clocks belong to ugk_trainer.
library;

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/engine.dart' as trainer;

import 'exercise.dart';
import 'plan.dart';

export 'package:ugk_trainer/engine.dart'
    show PhaseKind, Side, SessionPhase, SessionEngine;

coach.TrainingPlan trainerPlan(TrainingPlan plan) =>
    const coach.PlanCodec().decode(plan.toJson());

Map<String, trainer.Rhythm> trainerRhythms(ExerciseLibrary library) => {
  for (final e in library.all)
    if (e.trainingRhythm case final rhythm?)
      e.id: rhythm
    else if (e.repSeconds case final double seconds when seconds > 0)
      e.id: trainer.Rhythm.fromRepSeconds(seconds),
};

/// Thin adapter for existing plan estimates; no app-owned engine.
class SessionBuilder {
  SessionBuilder(ExerciseLibrary library, {int prepSeconds = 10})
    : _builder = trainer.SessionBuilder(
        rhythms: trainerRhythms(library),
        known: library.contains,
        prepSeconds: prepSeconds,
      );

  final trainer.SessionBuilder _builder;
  List<trainer.SessionPhase> phases(TrainingPlan plan) =>
      _builder.phases(trainerPlan(plan));
  double planSeconds(TrainingPlan plan) =>
      _builder.planSeconds(trainerPlan(plan));
  int occurrenceCount(TrainingPlan plan) =>
      _builder.occurrenceCount(trainerPlan(plan));
}
