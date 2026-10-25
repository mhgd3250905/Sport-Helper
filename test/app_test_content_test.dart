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

Exercise _legacy() => const Exercise(
  id: 'complete',
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
    id: 'complete',
    video: 'assets/old.mp4',
    poster: 'assets/old.jpg',
    loopSeconds: 99,
    posterSeconds: 0,
    source: 'old',
  ),
);

void main() {
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
    'bundled catalog and semantic assets form the actual internal library',
    () async {
      final index =
          jsonDecode(await File(AppTestPackConfig.indexAsset).readAsString())
              as Map;
      final pack = (await AppTestPack.load(
        (path) => File(path).readAsString(),
        enabled: true,
      ))!;
      final catalog = await AppTestCatalog.load(
        deliveryCatalogJson: await File(
          index['catalogAsset'] as String,
        ).readAsString(),
        bundledMedia: pack.actions,
        readSemanticCatalog: (path) async {
          final asset = (index['semanticSources'] as Map?)?[path];
          return asset == null ? null : File(asset as String).readAsBytes();
        },
      );
      expect(catalog.semanticStatus, AppTestSemanticStatus.verified);
      final packs = await PackSet.load((path) => File(path).readAsString());
      final legacy = ExerciseLibrary.fromPacks(packs);
      final content = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: legacy,
      );
      expect(catalog.entries.length, pack.catalog.length);
      expect(content.library.length, catalog.trainingEligibleIds.length);
      expect(content.coachCatalog.length, content.library.length);
      for (final old in legacy.all) {
        expect(content.library.contains(old.id), isTrue, reason: old.id);
      }
      for (final pending in catalog.entries.values.where(
        (e) => !e.trainingEligible,
      )) {
        expect(content.library.contains(pending.id), isFalse);
        expect(content.coachCatalog[pending.id], isNull);
        if (pack.actions[pending.id] case final media?) {
          expect(pending.media, same(media));
        }
      }
      // ignore: avoid_print
      print(
        'Bundled ${catalog.entries.length} entries / ${content.library.length} complete / ${pack.actions.length} transparent media.',
      );
    },
  );

  test(
    'current complete definitions retain every historical pack ID',
    () async {
      final source = Directory(realPack!);
      final catalog = await AppTestCatalog.load(
        deliveryCatalogJson: await File(
          '${source.path}/catalog.json',
        ).readAsString(),
        readSemanticCatalog: (path) =>
            File('${source.path}/$path').readAsBytes(),
      );
      final packs = await PackSet.load((path) => File(path).readAsString());
      final legacy = ExerciseLibrary.fromPacks(packs);
      final result = AppTestContent.build(
        catalog: catalog,
        legacyLibrary: legacy,
      );
      expect(result.library.length, catalog.trainingEligibleIds.length);
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
