import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

Map<String, Object?> _definition(String id) => {
  'id': id,
  'name': {'zh': '测试动作 $id'},
  'category': 'mobility',
  'equipment': ['unfamiliar-grip'],
  'position': 'standing',
  'unilateral': true,
  'level': 1,
  'scenes': ['home'],
  'defaultDose': {
    'mode': 'reps',
    'sets': 1,
    'reps': 3,
    'holdSeconds': 10,
    'restSeconds': 15,
  },
  'cues': {
    'zh': ['测试提示'],
  },
  'rhythm': {
    'kind': 'rep_hold',
    'leadSeconds': 1,
    'phases': [
      {'id': 'hold', 'seconds': 10},
    ],
    'authoredField': 'preserved',
  },
  'review': {'status': 'doubt'},
};

Map<String, Object?> _semantic({bool completed = false}) => {
  'format': 'pose-hub-catalog',
  'formatVersion': 1,
  'version': completed ? '0.3.1' : '0.3.0',
  'taxonomy': {
    'positions': {
      'standing': {'zh': '站姿'},
    },
  },
  'drills': [
    _definition('future-action'),
    {
      ..._definition('h-adductor-rock'),
      // Authored new-catalog value; the App's older time-based pack is not read.
      'defaultDose': {'mode': 'reps', 'sets': 1, 'reps': 5, 'restSeconds': 15},
    },
    if (completed) _definition('pending-action'),
  ],
};

List<int> _bytes(Map<String, Object?> json) => utf8.encode(jsonEncode(json));

Map<String, Object?> _delivery(Map<String, Object?> semantic) {
  final bytes = _bytes(semantic);
  return {
    'format': 'pose-hub-app-test-catalog@1',
    'id': 'synthetic-review-pack',
    'reviewed': false,
    'releaseEligible': false,
    'semanticCatalog': {
      'path': 'catalog/catalog.json',
      'version': semantic['version'],
      'bytes': bytes.length,
      'sha256': coach.sha256Hex(bytes),
    },
    'actions': [
      for (final id in ['future-action', 'h-adductor-rock', 'pending-action'])
        <String, Object?>{
          'id': id,
          'nameZh': '测试动作 $id',
          'equipment': ['unfamiliar-grip'],
          'muscleGroups': ['test-group'],
          'revision': '$id-r1',
          'reviewed': false,
          'releaseEligible': false,
          'availableForApp': id == 'pending-action',
          'family': id == 'pending-action' ? 'h-adductor-rock' : id,
          'files': {
            'video': {'path': 'media/$id.rgb-alpha.mp4'},
          },
        },
    ],
  };
}

const _pendingMedia = AppTestAction(
  id: 'pending-action',
  revision: 'pending-action-r1',
  packedVideo: 'assets/app_test_pack/synthetic/pending.rgb-alpha.mp4',
  playbackPoster: 'assets/app_test_pack/synthetic/pending.first.webp',
  cover: 'assets/app_test_pack/synthetic/pending.cover.webp',
  thumbnail: 'assets/app_test_pack/synthetic/pending.thumb.webp',
  loopSeconds: 8,
);

Future<AppTestCatalog> _load(Map<String, Object?> semantic) =>
    AppTestCatalog.load(
      deliveryCatalogJson: jsonEncode(_delivery(semantic)),
      readSemanticCatalog: (_) async => _bytes(semantic),
      bundledMedia: const {'pending-action': _pendingMedia},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'SDK binding preserves the exact AI projection and source objects',
    () async {
      final sdk = await PoseHubActionLibrary.load();
      final result = AppTestCatalog.fromSdk(sdk);
      final ai = result.toCoachCatalog()!;
      expect(result.toCoachCatalog(), same(ai));
      expect(result.isSdkBound, isTrue);
      expect(result.semanticStatus, AppTestSemanticStatus.verified);
      expect(result.semanticSource!.sha256, sdk.semanticCatalogFile.sha256);
      expect(result.entries.keys, sdk.allActions.map((action) => action.id));
      expect(result.trainingEligibleIds, ai.ids);
      expect(ai.ids, sdk.toAiCatalog().ids);

      for (final action in sdk.allActions) {
        final entry = result.entries[action.id]!;
        expect(entry.raw, same(action.raw), reason: action.id);
        expect(entry.mediaFiles, same(action.raw['files']), reason: action.id);
        expect(entry.media, isNull, reason: action.id);
        expect(entry.trainingEligible, action.trainingDefinitionComplete);
        if (entry.training case final training?) {
          expect(training.drill, same(ai[action.id]));
          expect(training.raw, same(ai[action.id]!.raw));
          expect(training.defaultDose, same(ai[action.id]!.raw['defaultDose']));
        } else {
          expect(
            entry.trainingProblems,
            action.rawTrainingSemantics['missingRequiredFields'],
          );
        }
      }
      final pending = result.entries['h-towel-isometric-curl']!;
      expect(pending.raw['level'], isNull);
      expect((pending.raw['defaultDose']! as Map)['seconds'], isNull);
      expect(() => pending.raw['level'] = 1, throwsUnsupportedError);
    },
  );

  test(
    'inline catalog completion admits an ID without legacy source changes',
    () async {
      final source = _semantic();
      final delivery = _delivery(source);
      final rows = delivery['actions']! as List;
      final pending = rows.last as Map<String, Object?>;
      final authored = _definition('pending-action');
      pending.addAll({...authored}..remove('name'));
      pending['rhythm'] = {
        'durationSeconds': 8,
        'videoLoopIsTrainingDose': false,
        'execution': authored['rhythm'],
      };
      final updated = await AppTestCatalog.load(
        deliveryCatalogJson: jsonEncode(delivery),
        readSemanticCatalog: (_) async => _bytes(source),
      );
      final training = updated.entries['pending-action']!.training!;
      expect(training.holdSeconds, 10);
      expect(training.rhythm!['kind'], 'rep_hold');
      expect(training.rhythm!.containsKey('durationSeconds'), isFalse);
      expect(updated.trainingEligibleIds.length, 3);
      final withoutSource = await AppTestCatalog.load(
        deliveryCatalogJson: jsonEncode(delivery),
      );
      expect(withoutSource.trainingEligibleIds, ['pending-action']);
      expect(withoutSource.toCoachCatalog()!.length, 1);
    },
  );

  test(
    'partial inline updates stay pending instead of restoring an old dose',
    () async {
      final source = _semantic();
      final delivery = _delivery(source);
      final row = (delivery['actions']! as List).first as Map<String, Object?>;
      row.addAll({'category': 'mobility', 'defaultDose': null});
      row['trainingDefinitionComplete'] = true; // Never an admission shortcut.
      final result = await AppTestCatalog.load(
        deliveryCatalogJson: jsonEncode(delivery),
        readSemanticCatalog: (_) async => _bytes(source),
      );
      expect(result.entries['future-action']!.trainingEligible, isFalse);
      expect(
        result.entries['future-action']!.trainingProblems,
        contains('defaultDose.mode'),
      );
    },
  );

  final realPack = Platform.environment['SMARTFIT_CATALOG_TEST_PACK'];
  test(
    'external current delivery matches declared training completeness',
    () async {
      final root = Directory(realPack!);
      final bytes = await File('${root.path}/catalog.json').readAsBytes();
      expect(
        coach.sha256Hex(bytes),
        PoseHubActionLibrary.catalogSha256,
        reason: 'The external smoke must use the current official SDK catalog.',
      );
      // Current packs are self-contained. Do not send them through the legacy
      // fixture decoder or require an independently installed canonical file.
      final sdk = coach.PoseHubAppTestCatalog.fromBytes(bytes);
      final result = AppTestCatalog.fromSdk(sdk);
      final rows = sdk.allActions;
      expect(result.entries.length, rows.length);
      expect(result.entries.keys, rows.map((action) => action.id));
      final declared = sdk.semanticCompleteActions
          .map((action) => action.id)
          .toList();
      expect(
        result.trainingEligibleIds,
        unorderedEquals(declared),
        reason: {
          for (final entry in result.entries.values)
            if (declared.contains(entry.id) && !entry.trainingEligible)
              entry.id: entry.trainingProblems,
        }.toString(),
      );
      expect(result.semanticStatus, AppTestSemanticStatus.verified);
      expect(result.isSdkBound, isTrue);
      expect(result.toCoachCatalog()!.length, declared.length);
      expect(result.toCoachCatalog()!.ids, sdk.toAiCatalog().ids);
      // ignore: avoid_print
      print(
        'Current delivery: ${rows.length} library rows; ${declared.length} AI-ready; ${rows.length - declared.length} pending.',
      );
    },
    skip: realPack == null
        ? 'Set SMARTFIT_CATALOG_TEST_PACK for the current delivery.'
        : false,
  );

  test(
    'verified source admits complete new IDs and preserves real raw semantics',
    () async {
      final catalog = await _load(_semantic());
      expect(catalog.semanticStatus, AppTestSemanticStatus.verified);
      expect(catalog.entries.length, 3);
      expect(catalog.trainingEligibleIds, ['future-action', 'h-adductor-rock']);
      final future = catalog.entries['future-action']!;
      expect(future.equipment, ['unfamiliar-grip']);
      expect(future.training!.drill.equipment, ['unfamiliar-grip']);
      expect(future.training!.holdSeconds, 10);
      expect(future.training!.rhythm!['authoredField'], 'preserved');
      expect(future.raw['reviewed'], isFalse);
      final coachCatalog = catalog.toCoachCatalog()!;
      expect(coachCatalog.length, 2);
      final raw = (coachCatalog.raw['drills']! as List).first as Map;
      expect((raw['defaultDose'] as Map)['holdSeconds'], 10);
      expect((raw['rhythm'] as Map)['leadSeconds'], 1);
      expect(
        catalog.entries['h-adductor-rock']!.training!.drill.defaultDose.mode,
        coach.DoseMode.reps,
      );
      expect(
        catalog.entries['h-adductor-rock']!.training!.defaultDose['reps'],
        5,
      );
    },
  );

  test(
    'incomplete rows keep media and metadata without guessed family prescriptions',
    () async {
      final catalog = await _load(_semantic());
      final pending = catalog.entries['pending-action']!;
      expect(pending.training, isNull);
      expect(pending.trainingProblems, ['semantic_definition_missing']);
      expect(pending.nameZh, '测试动作 pending-action');
      expect(pending.revision, 'pending-action-r1');
      expect(pending.equipment, ['unfamiliar-grip']);
      expect(pending.media, same(_pendingMedia));
      expect(pending.mediaPlayable, isTrue);
      expect(
        (pending.mediaFiles['video'] as Map)['path'],
        'media/pending-action.rgb-alpha.mp4',
      );
    },
  );

  test(
    'absent semantic bytes keep every row pending and allow an explicit source loader',
    () async {
      final source = _semantic();
      final delivery = jsonEncode(_delivery(source));
      final missing = await AppTestCatalog.load(
        deliveryCatalogJson: delivery,
        bundledMedia: const {'pending-action': _pendingMedia},
      );
      expect(missing.semanticStatus, AppTestSemanticStatus.missing);
      expect(missing.entries.length, 3);
      expect(missing.trainingEligibleIds, isEmpty);
      expect(missing.entries['pending-action']!.mediaPlayable, isTrue);
      expect(missing.toCoachCatalog(), isNull);
      final paths = <String>[];
      final verified = await AppTestCatalog.load(
        deliveryCatalogJson: delivery,
        readSemanticCatalog: (path) async {
          paths.add(path);
          return _bytes(source);
        },
      );
      expect(paths, ['catalog/catalog.json']);
      expect(verified.semanticSource!.sha256, coach.sha256Hex(_bytes(source)));
      expect(verified.trainingEligibleIds.length, 2);
    },
  );

  test(
    'hash, size and version mismatches retain browse rows but reject definitions',
    () async {
      final source = _semantic();
      for (final change in ['sha256', 'bytes', 'version']) {
        final delivery = _delivery(source);
        final descriptor = delivery['semanticCatalog']! as Map<String, Object?>;
        descriptor[change] = switch (change) {
          'sha256' => '0' * 64,
          'bytes' => _bytes(source).length + 1,
          _ => '0.3.9',
        };
        final result = await AppTestCatalog.load(
          deliveryCatalogJson: jsonEncode(delivery),
          readSemanticCatalog: (_) async => _bytes(source),
        );
        expect(
          result.semanticStatus,
          AppTestSemanticStatus.rejected,
          reason: change,
        );
        expect(result.trainingEligibleIds, isEmpty);
        expect(result.entries.length, 3);
      }
    },
  );

  test(
    'invalid supplied definitions do not receive SDK fallback field values',
    () async {
      for (final field in ['unilateral', 'scenes', 'cues', 'defaultDose']) {
        final source = _semantic();
        final drill = (source['drills']! as List).first as Map<String, Object?>;
        drill[field] = switch (field) {
          'unilateral' => 'true',
          'scenes' => <String>[],
          'cues' => {'zh': <String>[]},
          _ => {'mode': 'reps', 'sets': 1, 'reps': 3}, // No invented 20s rest.
        };
        final catalog = await _load(source);
        expect(
          catalog.entries['future-action']!.training,
          isNull,
          reason: field,
        );
        expect(catalog.entries['future-action']!.trainingProblems, isNotEmpty);
        expect(catalog.entries['h-adductor-rock']!.trainingEligible, isTrue);
      }
    },
  );

  test(
    'a later complete catalog automatically admits the previously pending ID',
    () async {
      final initial = await _load(_semantic());
      final updated = await _load(_semantic(completed: true));
      expect(initial.entries['pending-action']!.trainingEligible, isFalse);
      expect(updated.entries['pending-action']!.trainingEligible, isTrue);
      expect(updated.trainingEligibleIds.length, 3);
      expect(updated.toCoachCatalog()!.version, '0.3.1');
    },
  );

  test(
    'manifest reference is supported and source paths cannot guess another root',
    () async {
      final source = _semantic();
      final delivery = _delivery(source);
      final descriptor = delivery.remove('semanticCatalog');
      final result = await AppTestCatalog.load(
        deliveryCatalogJson: jsonEncode(delivery),
        manifestJson: jsonEncode({'semanticCatalog': descriptor}),
        readSemanticCatalog: (_) async => _bytes(source),
      );
      expect(result.semanticStatus, AppTestSemanticStatus.verified);
      final invalid = _delivery(source);
      (invalid['semanticCatalog']! as Map)['path'] = '../catalog.json';
      var called = false;
      final rejected = await AppTestCatalog.load(
        deliveryCatalogJson: jsonEncode(invalid),
        readSemanticCatalog: (_) async {
          called = true;
          return _bytes(source);
        },
      );
      expect(rejected.semanticStatus, AppTestSemanticStatus.rejected);
      expect(called, isFalse);
    },
  );
}
