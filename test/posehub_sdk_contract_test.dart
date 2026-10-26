import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

const _pendingIds = {
  'h-bilateral-farmer-hold-native',
  'h-db-shrug',
  'h-floor-nordic-hand-reset',
  'h-kneeling-thread-needle',
  'h-pike-scapular-elevation',
  'h-towel-isometric-curl',
  'h-wall-palm-lift',
  'o-supported-ankle-eversion',
};

Map<String, Object?> _json(String text) =>
    jsonDecode(text) as Map<String, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late coach.PoseHubAppTestCatalog pack;
  late coach.Catalog ai;
  late Map<String, Object?> canonical;

  setUpAll(() async {
    // Use the App's real asset bundle, including the SDK's pinned checksum gate.
    pack = await PoseHubActionLibrary.load();
    ai = pack.toAiCatalog();
    canonical = _json(
      await rootBundle.loadString(
        '${PoseHubActionLibrary.assetRoot}catalog/catalog.json',
      ),
    );
  });

  test('real SDK bundle keeps 219 identities and exactly 211 AI actions', () {
    expect(pack.allActions, hasLength(219));
    expect(pack.allActions.map((action) => action.id).toSet(), hasLength(219));
    expect(pack.semanticCompleteActions, hasLength(211));
    expect(pack.pendingActions.map((action) => action.id).toSet(), _pendingIds);
    expect(ai.length, 211);
    expect(ai.problems, isEmpty);
    expect(ai.ids, pack.semanticCompleteActions.map((action) => action.id));

    final files = [
      for (final action in pack.allActions) ...action.files.values,
    ];
    expect(files, hasLength(657));
    expect(files.map((file) => file.path).toSet(), hasLength(657));
    for (final action in pack.pendingActions) {
      expect(ai.contains(action.id), isFalse, reason: action.id);
      expect(action.trainingStatusLabel, '训练说明待补');
    }
    // Semantic approval does not promote the original media review flags.
    expect(pack.raw['reviewed'], isFalse);
    expect(pack.raw['releaseEligible'], isFalse);
    for (final action in pack.allActions) {
      expect(action.raw['reviewed'], isFalse, reason: action.id);
      expect(action.raw['releaseEligible'], isFalse, reason: action.id);
      expect(action.rawTrainingSemantics['videoLoopIsTrainingDose'], isFalse);
    }
  });

  test(
    '142 canonical definitions and 69 authored doses survive projection',
    () {
      final original = (canonical['drills']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .toList();
      final originalIds = original.map((drill) => drill['id']).toSet();
      expect(original, hasLength(142));
      for (final source in original) {
        final id = source['id']! as String;
        expect(ai[id]!.raw, source, reason: '$id canonical definition');
      }

      final additions = pack.semanticCompleteActions
          .where((action) => !originalIds.contains(action.id))
          .toList();
      expect(additions, hasLength(69));
      for (final action in additions) {
        final drill = ai[action.id]!;
        expect(action.availableForTraining, isFalse, reason: action.id);
        expect(
          drill.defaultDose.toJson(),
          action.raw['defaultDose'],
          reason: '${action.id} must retain its authored dose',
        );
        expect(
          drill.doseRange.toJson(),
          action.raw['doseRange'],
          reason: '${action.id} must retain its authored range',
        );
        for (final field in action.raw.entries) {
          expect(
            drill.raw[field.key],
            field.value,
            reason: '${action.id}.${field.key} must retain source data',
          );
        }
      }
      // Different authored prescriptions catch a uniform fallback dose.
      expect(ai['h-slider-body-saw']!.defaultDose.toJson(), {
        'mode': 'reps',
        'sets': 1,
        'reps': 4,
        'restSeconds': 45,
      });
      expect(ai['g-cable-hip-abduction']!.defaultDose.toJson(), {
        'mode': 'reps',
        'sets': 3,
        'reps': 12,
        'restSeconds': 30,
      });
    },
  );

  test(
    'SmartFit profile whitelists 211 and admits none of the 8 pending IDs',
    () async {
      final profile = coach.CoachProfile.fromJson(
        _json(await rootBundle.loadString('assets/coach/smartfit.json')),
      );
      final whitelist = coach.CoachTools.whitelist(profile, ai);
      expect(whitelist, hasLength(211));
      expect(
        profile.scope(ai).map((drill) => drill.id).toSet(),
        ai.ids.toSet(),
      );
      for (final id in _pendingIds) {
        expect(whitelist, isNot(contains(id)), reason: id);
      }
    },
  );

  test(
    'missing doses stay unknown and unbound or altered semantics fail closed',
    () {
      final pending = pack.tryGet('h-towel-isometric-curl')!;
      final dose =
          pending.rawTrainingDefinition['defaultDose']! as Map<String, Object?>;
      expect(pending.rawTrainingDefinition['level'], isNull);
      expect(dose['mode'], 'time');
      for (final field in ['seconds', 'sets', 'restSeconds']) {
        expect(dose[field], isNull, reason: field);
      }
      expect(() => dose['seconds'] = 30, throwsUnsupportedError);
      expect(
        coach.PoseHubAppTestCatalog.fromJson(pack.raw).toAiCatalog,
        throwsStateError,
      );

      final altered = _json(jsonEncode(pack.raw));
      final action = (altered['actions']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((action) => action['id'] == 'g-cable-hip-abduction');
      (action['defaultDose']! as Map<String, Object?>)['restSeconds'] = null;
      expect(
        () => coach.PoseHubAppTestCatalog.fromJson(
          altered,
          semanticCatalog: canonical,
        ),
        throwsFormatException,
      );
    },
  );
}
