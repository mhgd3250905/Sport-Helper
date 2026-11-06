import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/packs/drill_pack.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/engine.dart' as trainer;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

Map<String, Object?> _row(String id) => {
  'id': id,
  'nameZh': '测试动作',
  'equipment': ['mat', 'future-equipment'],
  'revision': '$id-r2',
  'category': 'mobility',
  'position': 'standing',
  'unilateral': true,
  'level': 1,
  'scenes': ['home'],
  'defaultDose': {
    'mode': 'reps',
    'sets': 1,
    'reps': 5,
    'restSeconds': 20,
    'holdSeconds': 4,
  },
  'cues': {
    'zh': ['保持稳定'],
  },
  'rhythm': {
    'durationSeconds': 8,
    'execution': {
      'kind': 'rep_hold',
      'leadSeconds': 1,
      'phases': [
        {'id': 'go', 'seconds': 0.5, 'cue': 'w.test_go'},
        {'id': 'hold', 'seconds': 2},
        {'id': 'back', 'seconds': 0.5},
      ],
    },
  },
};

const _alpha = AppTestAction(
  id: 'complete',
  revision: 'complete-r2',
  packedVideo: 'assets/complete.mp4',
  playbackPoster: 'assets/complete.first.webp',
  cover: 'assets/complete.cover.webp',
  thumbnail: 'assets/complete.thumb.webp',
  loopSeconds: 8,
);

Future<AppTestCatalog> _catalog({bool media = false}) => AppTestCatalog.load(
  deliveryCatalogJson: jsonEncode({
    'format': 'pose-hub-app-test-catalog@1',
    'id': 'synthetic',
    'actions': [
      _row('complete'),
      {..._row('pending'), 'defaultDose': null},
    ],
  }),
  bundledMedia: media ? {'complete': _alpha} : {},
);

Exercise _legacy({String id = 'complete'}) => Exercise(
  id: id,
  name: '旧名',
  muscles: [],
  unilateral: false,
  category: ExerciseCategory.mobility,
  equipment: [],
  position: 'standing',
  level: 1,
  scenes: ['home'],
  dose: Dose(mode: DoseMode.time, sets: 1, seconds: 20, restSeconds: 10),
  repSeconds: 99,
  cues: [],
  cautions: [],
  alternative: null,
  media: ExerciseMedia(
    id: id,
    video: 'assets/old.mp4',
    poster: 'assets/old.jpg',
    loopSeconds: 99,
    posterSeconds: 0,
    source: 'old',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'complete definitions retain unknown gear and real hold timing',
    () async {
      final content = AppTestContent.build(
        catalog: await _catalog(),
        legacyLibrary: ExerciseLibrary([_legacy()]),
      );
      expect(content.library.length, 1);
      expect(content.coachCatalog.ids, ['complete']);
      expect(content.catalog.entries['pending']!.trainingEligible, isFalse);
      final exercise = content.library['complete'];
      expect(exercise.effectiveEquipmentIds, ['mat', 'future-equipment']);
      expect(exercise.equipment, [Equipment.mat]);
      expect(content.unmappedEquipment, {
        'complete': ['future-equipment'],
      });
      expect(content.coachCatalog['complete']!.equipment, [
        'mat',
        'future-equipment',
      ]);
      expect(exercise.unilateral, isTrue);
      expect(exercise.dose.mode, DoseMode.reps);
      expect(
        exercise.repSeconds,
        5,
      ); // 0.5 + authored 4s hold + 0.5, not video 8s.
      expect(content.rhythms['complete']!.holdSeconds, 4);
      expect(exercise.trainingRhythm, same(content.rhythms['complete']));
      final sessionRhythm = trainerRhythms(content.library)['complete']!;
      expect(sessionRhythm.holdSeconds, 4);
      expect(sessionRhythm.phases.first.cues, ['w.test_go']);
      final generator = TemplatePlanGenerator(
        lib: content.library,
        catalog: TemplateCatalog([]),
      );
      expect(
        generator.blockerFor(exercise, const ScenarioRequest()),
        '没有future-equipment',
      );
      expect(content.rhythms['complete']!.phasesFor()[1].seconds, 4);
      final raw = (content.coachCatalog.raw['drills']! as List).first as Map;
      expect((raw['defaultDose'] as Map)['holdSeconds'], 4);
      expect(exercise.media.video, 'assets/old.mp4');
    },
  );

  test(
    'new alpha overlays opaque fallback without replacing timing semantics',
    () async {
      final content = AppTestContent.build(
        catalog: await _catalog(media: true),
        legacyLibrary: ExerciseLibrary([_legacy()]),
      );
      final exercise = content.library['complete'];
      expect(exercise.media.video, 'assets/old.mp4');
      expect(exercise.media.hasPackedAlpha, isTrue);
      expect(exercise.media.alphaPlaybackPoster, _alpha.playbackPoster);
      expect(exercise.media.revision, 'complete-r2');
      expect(exercise.media.loopSeconds, 8);
      expect(exercise.repSeconds, 5);
    },
  );

  test(
    'no legacy media still creates a complete training definition',
    () async {
      final content = AppTestContent.build(
        catalog: await _catalog(),
        legacyLibrary: ExerciseLibrary([]),
      );
      expect(content.library['complete'].media.videoAvailable, isFalse);
      expect(content.library['complete'].media.video, isEmpty);
      expect(content.coachCatalog.length, 1);
      expect(content.library.contains('pending'), isFalse);
    },
  );

  final realPack = Platform.environment['SMARTFIT_CATALOG_TEST_PACK'];
  test(
    'SDK projection drives the full execution library without old media fallback',
    () async {
      final sdk = await PoseHubActionLibrary.load();
      final catalog = AppTestCatalog.fromSdk(sdk);
      final ai = catalog.toCoachCatalog()!;
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([_legacy(id: sdk.allActions.first.id)]),
      );
      // r2-v1 ships every action ready: 249 complete definitions.
      expect(content.library.length, 249);
      expect(content.coachCatalog, isNot(same(ai)));
      expect(catalog.toCoachCatalog(), same(ai));
      expect(content.library.all.map((exercise) => exercise.id), ai.ids);
      expect(content.rhythms.keys, ai.ids);
      for (final exercise in content.library.all) {
        final source = ai[exercise.id]!;
        final rawDose = source.raw['defaultDose']! as Map;
        expect(exercise.dose.sets, rawDose['sets'], reason: exercise.id);
        expect(exercise.dose.reps, rawDose['reps'], reason: exercise.id);
        expect(
          exercise.dose.seconds,
          rawDose['seconds'] ?? rawDose['workSeconds'],
          reason: exercise.id,
        );
        expect(
          exercise.dose.restSeconds,
          rawDose['restSeconds'],
          reason: exercise.id,
        );
        expect(exercise.effectiveEquipmentIds, source.equipment);
        expect(exercise.trainingRhythm, same(content.rhythms[exercise.id]));
        final cover = 'posehub-r1/${Uri.encodeComponent(exercise.id)}/cover';
        final thumbnail =
            'posehub-r1/${Uri.encodeComponent(exercise.id)}/thumbnail';
        expect(exercise.media.videoAvailable, isTrue);
        expect(exercise.media.lightVideoAvailable, isTrue);
        expect(exercise.media.video, isEmpty);
        expect(exercise.media.poster, cover);
        expect(exercise.media.lightPoster, cover);
        expect(exercise.media.alphaCover, cover);
        expect(exercise.media.alphaThumbnail, thumbnail);
        expect(exercise.media.packedAlphaVideo, isNull);
        expect(exercise.media.playbackPoster, isNull);
        expect(exercise.media.alphaPlaybackPoster, isNull);
        expect(exercise.media.revision, catalog.entries[exercise.id]!.revision);
      }
      for (final pending in sdk.pendingActions) {
        expect(content.library.contains(pending.id), isFalse);
        expect(content.coachCatalog[pending.id], isNull);
        expect(content.rhythms.containsKey(pending.id), isFalse);
      }
    },
  );

  test(
    'unknown SDK execution stays self-paced while canonical rhythms retain holds',
    () async {
      // r2-v1 defines an execution for every action, so the unknown-execution
      // path runs on a copy of the real SDK catalogue in which one reps-dose
      // and one time-dose action have their execution cleared (as r1-v3 had).
      final sdk = await PoseHubActionLibrary.load();
      final edited = jsonDecode(jsonEncode(sdk.raw)) as Map<String, dynamic>;
      final cleared = <String>{};
      for (final mode in ['reps', 'time']) {
        final row = (edited['actions'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (row) =>
                  row['trainingDefinitionComplete'] == true &&
                  row['availableForTraining'] == true &&
                  (row['defaultDose'] as Map?)?['mode'] == mode,
            );
        (row['rhythm'] as Map<String, dynamic>)['execution'] = null;
        cleared.add(row['id'] as String);
      }
      final unknownSdk = coach.PoseHubAppTestCatalog.fromJson(edited);
      final unknownCatalog = AppTestCatalog.fromSdk(unknownSdk);
      final unknownContent = AppTestContent.build(
        catalog: unknownCatalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      // The SDK delivers the pack's execution as the definition's rhythm
      // (PR #18), so an unknown execution is read from the pack row itself.
      final unknown = unknownSdk.semanticCompleteActions
          .where(_unknownExecution)
          .toList();
      expect(unknown.map((action) => action.id).toSet(), cleared);
      final modes = <DoseMode>{};
      for (final action in unknown) {
        final exercise = unknownContent.library[action.id];
        final rhythm = unknownContent.rhythms[action.id]!;
        modes.add(exercise.dose.mode);
        expect(rhythm.phases, isEmpty, reason: action.id);
        expect(rhythm.counted, isFalse, reason: action.id);
        expect(exercise.repSeconds, isNull, reason: action.id);
        expect(
          exercise.media.loopSeconds,
          (action.raw['rhythm']! as Map)['durationSeconds'],
        );
        if (exercise.dose.mode == DoseMode.reps) {
          expect(rhythm, same(trainer.Rhythm.selfPacedReps));
          expect(rhythm.selfPaced, isTrue);
        } else {
          expect(rhythm, same(trainer.Rhythm.timedHold));
          expect(rhythm.selfPaced, isFalse);
        }
      }
      expect(modes, {DoseMode.reps, DoseMode.time});

      // The real r2-v1 SDK: no action is left without an execution, and every
      // canonical definition keeps the established helper and holdSeconds
      // rule; media duration never enters either code path.
      final catalog = AppTestCatalog.fromSdk(sdk);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      final oldRhythms = trainer.rhythmsFromCatalog(catalog.toCoachCatalog()!);
      expect(sdk.semanticCompleteActions.where(_unknownExecution), isEmpty);
      final canonical = sdk.semanticCompleteActions.where(
        (action) => action.availableForTraining,
      );
      expect(canonical, hasLength(249));
      for (final action in canonical) {
        final training = catalog.entries[action.id]!.training!;
        var expected = oldRhythms[action.id]!;
        if (training.holdSeconds case final hold? when expected.counted) {
          expected = expected.withHold(hold);
        }
        expect(
          content.rhythms[action.id]!.toJson(),
          expected.toJson(),
          reason: action.id,
        );
        // The pace is the pack's authored execution, not a dose default.
        var authored = trainer.Rhythm.fromJson(
          Map<String, dynamic>.from(
            (action.raw['rhythm']! as Map)['execution']! as Map,
          ),
        );
        if (training.holdSeconds case final hold? when authored.counted) {
          authored = authored.withHold(hold);
        }
        expect(
          content.rhythms[action.id]!.toJson(),
          authored.toJson(),
          reason: action.id,
        );
        expect(
          content.rhythms[action.id]!.source,
          trainer.RhythmSource.catalog,
          reason: action.id,
        );
      }
    },
  );

  test(
    'current complete definitions retain every historical pack ID',
    () async {
      final source = Directory(realPack!);
      final bytes = await File('${source.path}/catalog.json').readAsBytes();
      expect(
        coach.sha256Hex(bytes),
        PoseHubActionLibrary.catalogSha256,
        reason: 'The external smoke must use the current official SDK catalog.',
      );
      final sdk = coach.PoseHubAppTestCatalog.fromBytes(bytes);
      final catalog = AppTestCatalog.fromSdk(sdk);
      final packs = await PackSet.load((path) => File(path).readAsString());
      final legacy = ExerciseLibrary.fromPacks(packs);
      final result = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: legacy,
      );
      expect(result.library.length, catalog.trainingEligibleIds.length);
      expect(catalog.isSdkBound, isTrue);
      expect(result.coachCatalog.ids, sdk.toAiCatalog().ids);
      expect(result.coachCatalog.length, result.library.length);
      expect([
        for (final e in legacy.all)
          if (!result.library.contains(e.id)) e.id,
      ], isEmpty);
      for (final exercise in result.library.all) {
        final entry = catalog.entries[exercise.id]!;
        expect(exercise.effectiveEquipmentIds, entry.equipment);
        expect(result.coachCatalog[exercise.id]!.equipment, entry.equipment);
        expect(exercise.trainingRhythm, same(result.rhythms[exercise.id]));
      }
      // ignore: avoid_print
      print(
        'Mapped ${result.library.length} definitions; retained ${legacy.length} historical IDs; ${result.unmappedEquipment.length} rows preserve unfamiliar equipment.',
      );
    },
    skip: realPack == null
        ? 'Set SMARTFIT_CATALOG_TEST_PACK for the current delivery.'
        : false,
  );
}

bool _unknownExecution(coach.PoseHubPackAction action) {
  final rhythm = action.raw['rhythm'];
  return rhythm is Map &&
      rhythm.containsKey('execution') &&
      rhythm['execution'] == null;
}
