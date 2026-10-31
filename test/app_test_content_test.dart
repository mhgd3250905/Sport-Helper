import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/packs/drill_pack.dart';
import 'package:smartfit/ui/plan_presentation.dart';
import 'package:smartfit/ui/theme.dart' show minutesZh;
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

Future<AppTestCatalog> _catalog({
  bool media = false,
  List<Map<String, Object?>>? rows,
}) => AppTestCatalog.load(
  deliveryCatalogJson: jsonEncode({
    'format': 'pose-hub-app-test-catalog@1',
    'id': 'synthetic',
    'actions':
        rows ??
        [
          _row('complete'),
          {..._row('pending'), 'defaultDose': null},
        ],
  }),
  bundledMedia: media ? {'complete': _alpha} : {},
);

Future<AppTestCatalog> _semanticCatalog(Map<String, Object?> row) {
  final bytes = utf8.encode(
    jsonEncode({
      'format': coach.catalogFormat,
      'formatVersion': coach.supportedCatalogFormatVersion,
      'version': '1.0.0',
      'drills': [
        {
          ...row,
          'name': {'zh': row['nameZh']},
          'rhythm': (row['rhythm']! as Map)['execution'],
        },
      ],
    }),
  );
  return AppTestCatalog.load(
    deliveryCatalogJson: jsonEncode({
      'format': 'pose-hub-app-test-catalog@1',
      'id': 'semantic-source',
      'semanticCatalog': {
        'path': 'semantic.json',
        'version': '1.0.0',
        'bytes': bytes.length,
        'sha256': coach.sha256Hex(bytes),
      },
      'actions': [
        {
          for (final key in ['id', 'nameZh', 'equipment', 'revision'])
            key: row[key],
          if (row['files'] != null) 'files': row['files'],
        },
      ],
    }),
    readSemanticCatalog: (_) async => bytes,
  );
}

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
      expect(content.library.length, 211);
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
    'planning updates the first valid video cycle and keeps execution',
    () async {
      final row = {
        ..._row('complete'),
        'assets': {
          'video': {
            'status': 'ok',
            'sources': [
              {'path': 'invalid-without-app.mp4', 'repSeconds': 99},
              {
                'app': 'pose-hub',
                'path': 'media/complete-r2/complete.mp4',
                'sha256': 'source-hash',
                'repSeconds': 8,
              },
              {'app': 'other', 'path': 'other.mp4', 'repSeconds': 20},
            ],
          },
        },
      };
      final catalog = await _semanticCatalog(row);
      final source = catalog.toCoachCatalog()!;
      final original = jsonEncode(source.raw);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      final drill = content.coachCatalog['complete']!;
      expect(const coach.PlanDuration().repSeconds(drill), 5);
      expect(drill.assets.videos.first.path, 'media/complete-r2/complete.mp4');
      expect(drill.assets.videos.first.sha256, 'source-hash');
      expect(drill.assets.videos.last.repSeconds, 20);
      expect(jsonEncode(source.raw), original);
      expect(const coach.PlanDuration().repSeconds(source['complete']!), 8);
      final rhythm = content.rhythms['complete']!;
      expect(rhythm.lead, 1);
      expect(rhythm.cycleFor(), 5);
      expect(rhythm.phases.first.cues, ['w.test_go']);
      expect(rhythm.phases.map((p) => p.id), ['go', 'hold', 'back']);

      final plan = TrainingPlan(
        id: 'cadence-contract',
        source: 'test',
        title: '节奏对账',
        summary: '',
        goal: 'mixed',
        scene: 'home',
        equipment: const [],
        level: 1,
        targetMinutes: 5,
        blocks: const [
          PlanBlock(
            id: 'main',
            name: '主训练',
            type: BlockType.main,
            rounds: 2,
            restBetweenRoundsSeconds: 15,
            items: [
              PlanItem(
                exerciseId: 'complete',
                mode: DoseMode.reps,
                sets: 2,
                reps: 5,
                perSide: true,
                restSeconds: 20,
              ),
            ],
          ),
        ],
      );
      final builder = SessionBuilder(content.library);
      expect(builder.totalSeconds(plan), 293);
      expect(builder.planSeconds(plan), 283);
      expect(
        const coach.PlanDuration().estimateSeconds(
          trainerPlan(plan),
          content.coachCatalog,
        ),
        285,
      ); // Eight one-off leads, not eight seconds spread across every rep.
      expect(planDurationLabel(plan, content.library), minutesZh(293));
      final phases = builder.phases(plan);
      final engine = SessionEngine(phases)..update(293);
      expect(engine.done, isTrue);
      expect(engine.endedEarly, isFalse);
    },
  );

  test(
    'planning adds only the declared real media source and skips missing media',
    () async {
      final row = {
        ..._row('complete'),
        'files': {
          'video': {'path': 'media/complete-r2/complete.mp4', 'bytes': 12},
        },
      };
      final catalog = await _catalog(rows: [row]);
      final original = jsonEncode(catalog.entries['complete']!.raw);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      final source = content.coachCatalog['complete']!.assets.videos.single;
      expect(source.app, 'pose-hub');
      expect(source.path, 'media/complete-r2/complete.mp4');
      expect(source.repSeconds, 5);
      expect(source.bytes, 12);
      expect(jsonEncode(catalog.entries['complete']!.raw), original);

      final missingCatalog = await _catalog();
      final missing = AppTestContent.build(
        catalog: missingCatalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      expect(missing.coachCatalog.raw, missingCatalog.toCoachCatalog()!.raw);
      expect(missing.coachCatalog['complete']!.assets.videos, isEmpty);
    },
  );

  test(
    'unknown SDK execution stays self-paced while canonical rhythms retain holds',
    () async {
      final sdk = await PoseHubActionLibrary.load();
      final catalog = AppTestCatalog.fromSdk(sdk);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      final oldRhythms = trainer.rhythmsFromCatalog(catalog.toCoachCatalog()!);
      final unknown = sdk.semanticCompleteActions.where((action) {
        final rhythm = catalog.entries[action.id]!.training!.rhythm;
        return rhythm != null &&
            rhythm.containsKey('execution') &&
            rhythm['execution'] == null;
      }).toList();
      expect(unknown, hasLength(69));
      for (final action in unknown) {
        final exercise = content.library[action.id];
        final rhythm = content.rhythms[action.id]!;
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
      // The original canonical definitions keep the established helper and
      // holdSeconds rule; media duration never enters either code path.
      final canonical = sdk.semanticCompleteActions.where(
        (action) => action.availableForTraining,
      );
      expect(canonical, hasLength(142));
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
      }
    },
  );

  test(
    'captured five-minute v3 keeps its dose and accounts for fixed lead',
    () async {
      final bytes = File(
        'test/fixtures/smartfit-five-minute-v3.json',
      ).readAsBytesSync();
      expect(
        coach.sha256Hex(bytes),
        '67d833cd2fdbdb9559cf13428f2ca27bfccfc1b7d6e4ec927c333fc8ccbeb994',
      );
      final raw = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final plan = TrainingPlan.fromJson(raw);
      final pack = await rootBundle.load(
        '${PoseHubActionLibrary.assetRoot}catalog.json',
      );
      final sdk = coach.PoseHubAppTestCatalog.fromBytes(
        pack.buffer.asUint8List(pack.offsetInBytes, pack.lengthInBytes),
      ); // Exact projection used by the historical capture, before enrichment.
      final catalog = AppTestCatalog.fromSdk(sdk);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: ExerciseLibrary([]),
      );
      const duration = coach.PlanDuration();
      expect(
        duration.estimateSeconds(trainerPlan(plan), catalog.toCoachCatalog()!),
        313,
      );
      expect(
        duration.estimateSeconds(trainerPlan(plan), content.coachCatalog),
        344,
      );
      final builder = SessionBuilder(content.library);
      expect(builder.totalSeconds(plan), 345);
      expect(builder.planSeconds(plan), 335);
      expect(
        SessionBuilder(content.library, prepSeconds: 0).totalSeconds(plan),
        335,
      );
      expect(content.rhythms['h-squat']!.lead, 1);
      expect(content.rhythms['h-squat']!.cycleFor(), 4);
      expect(content.rhythms['h-wall-angel']!.cycleFor(), 4);
      expect(content.rhythms['h-reverse-crunch']!.cycleFor(), 4);
      expect(content.rhythms['w-dead-bug']!.cycleFor(), 3);
      expect(planDurationLabel(plan, content.library), minutesZh(345));
      expect(
        SessionEngine(builder.phases(plan))..update(345),
        isA<SessionEngine>().having((engine) => engine.done, 'done', isTrue),
      );
      // The historical dose still exceeds 5 min +10%; new plans must be fitted
      // against the aligned catalogue rather than rewriting this source record.
      expect(
        builder.totalSeconds(plan),
        greaterThan(plan.targetMinutes * 60 * 1.1),
      );
      expect(plan.toJson(), raw);
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
