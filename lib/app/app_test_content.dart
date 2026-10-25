import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/engine.dart' as trainer;

import '../domain/exercise.dart';
import 'app_test_catalog.dart';

typedef AppTestEquipmentResolver = Equipment? Function(String id);

/// App adapters for complete definitions only. Browse-only pending actions stay
/// in [AppTestCatalog.entries]; no default prescription is invented for those rows.
class AppTestContent {
  AppTestContent._({
    required this.catalog,
    required this.library,
    required this.coachCatalog,
    required this.rhythms,
    required this.unmappedEquipment,
  });

  final AppTestCatalog catalog;
  final ExerciseLibrary library;
  final coach.Catalog coachCatalog;
  final Map<String, trainer.Rhythm> rhythms;

  /// Diagnostic only: raw equipment stays on Exercise and in the coach catalog.
  /// These IDs are never treated as bodyweight and do not exclude a definition.
  final Map<String, List<String>> unmappedEquipment;

  factory AppTestContent.build({
    required AppTestCatalog catalog,
    required ExerciseLibrary legacyLibrary,
    AppTestEquipmentResolver resolveEquipment = _knownEquipment,
  }) {
    final coachCatalog =
        catalog.toCoachCatalog() ??
        coach.Catalog.fromJson({
          'format': coach.catalogFormat,
          'formatVersion': coach.supportedCatalogFormatVersion,
          'version': catalog.semanticSource?.version ?? '0.0.0',
          'drills': <Object?>[],
        });
    final rhythms = trainer.rhythmsFromCatalog(coachCatalog);
    final exercises = <Exercise>[];
    final unknown = <String, List<String>>{};
    for (final entry in catalog.entries.values) {
      final training = entry.training;
      if (training == null) continue;
      final drill = training.drill;
      final equipment = <Equipment>[];
      final unmapped = <String>[];
      for (final id in entry.equipment) {
        final known = resolveEquipment(id);
        if (known == null) {
          unmapped.add(id);
        } else if (!equipment.contains(known)) {
          equipment.add(known);
        }
      }
      if (unmapped.isNotEmpty) unknown[entry.id] = List.unmodifiable(unmapped);
      var rhythm = rhythms[entry.id]!;
      if (training.holdSeconds case final hold? when rhythm.counted) {
        rhythm = rhythm.withHold(hold);
        rhythms[entry.id] = rhythm;
      }
      final fallback =
          legacyLibrary.tryGet(entry.id)?.media ??
          ExerciseMedia(
            id: entry.id,
            video: '',
            poster: '',
            loopSeconds: entry.media?.loopSeconds ?? 0,
            posterSeconds: 0,
            source: 'Pose-Hub App test (unreviewed)',
            videoAvailable: false,
            revision: entry.revision,
            appTestOnly: true,
          );
      final rawDose = training.defaultDose;
      exercises.add(
        Exercise(
          id: entry.id,
          name: entry.nameZh,
          muscles: drill.muscles.isNotEmpty
              ? drill.muscles
              : drill.muscleGroups,
          unilateral: drill.unilateral,
          category: ExerciseCategory.byName(drill.category),
          equipment: List.unmodifiable(equipment),
          equipmentIds: entry.equipment,
          trainingRhythm: rhythm,
          position: drill.position,
          level: drill.level,
          scenes: drill.scenes,
          dose: Dose(
            mode: drill.defaultDose.mode == coach.DoseMode.reps
                ? DoseMode.reps
                : DoseMode.time,
            sets: rawDose['sets']! as int,
            reps: rawDose['reps'] as int?,
            seconds: (rawDose['seconds'] ?? rawDose['workSeconds']) as int?,
            restSeconds: rawDose['restSeconds']! as int,
          ),
          repSeconds:
              drill.defaultDose.mode == coach.DoseMode.reps && rhythm.counted
              ? rhythm.cycleFor()
              : null,
          cues: drill.cues['zh'] ?? const [],
          cautions: drill.cautions,
          alternative: drill.alternative,
          media: entry.media?.applyTo(fallback) ?? fallback,
        ),
      );
    }
    return AppTestContent._(
      catalog: catalog,
      library: ExerciseLibrary(exercises),
      coachCatalog: coachCatalog,
      rhythms: Map.unmodifiable(rhythms),
      unmappedEquipment: Map.unmodifiable(unknown),
    );
  }
}

Equipment? _knownEquipment(String id) {
  for (final value in Equipment.values) {
    if (value.name == id) return value;
  }
  return null;
}
