// English voice (2026-11-06): every shared line, the counts 1–60 and every
// exercise pack line has an English clip in the bundle, so the English voice
// no longer falls back to chimes; a custom 15 says 11…14 and 「Last one」.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/engine.dart';
import 'package:smartfit/voice/voice_asset_bundle.dart';

import 'support.dart';

void main() {
  final voices = loadVoices();
  final bundle = VoiceAssetBundle.fromJson(
    jsonDecode(File(VoiceAssetBundle.manifestAsset).readAsStringSync())
        as Map<String, dynamic>,
  );
  final common =
      (jsonDecode(File('assets/packs/_common/pack.json').readAsStringSync())
              as Map<String, dynamic>)['voice']
          as Map<String, dynamic>;

  test('bundle ships both voice languages', () {
    expect(bundle.languages, {'zh', 'en'});
    expect(voices.languages, containsAll(['zh', 'en']));
  });

  test('every shared line and the counts 1–60 have an English file', () {
    final ids = [
      for (final l in common['lines'] as List) (l as Map)['id'] as String,
    ];
    expect(ids, containsAll([for (var n = 1; n <= 60; n++) 'n.$n']));
    expect(ids, contains('p.last_rep'));
    for (final id in ids) {
      for (final lang in ['zh', 'en']) {
        final clip = bundle.clip(id, lang);
        expect(clip, isNotNull, reason: '$id/$lang');
        expect(File(clip!.asset).existsSync(), isTrue, reason: clip.asset);
        expect(clip.milliseconds, greaterThan(150), reason: '$id/$lang');
      }
      expect(voices.has(id, lang: 'en'), isTrue, reason: id);
    }
  });

  test('every exercise pack line has an English file', () {
    var n = 0;
    for (final entry in bundle.clips.entries) {
      if (!entry.key.contains('/')) continue;
      expect(entry.value.keys.toSet(), {'zh', 'en'}, reason: entry.key);
      expect(File(entry.value['en']!.asset).existsSync(), isTrue);
      n++;
    }
    expect(n, greaterThanOrEqualTo(611));
  });

  List<List<String>> countCues(String lang, {required bool rhythm}) {
    const item = coach.PlanItem(
      exerciseId: 'h-forward-lunge',
      mode: coach.DoseMode.reps,
      sets: 1,
      reps: 15,
      perSide: false,
      restSeconds: 20,
    );
    final plan = coach.TrainingPlan(
      id: 'p',
      source: 'template',
      title: 't',
      goal: 'core',
      scene: 'home',
      level: 1,
      targetMinutes: 5,
      blocks: const [
        coach.PlanBlock(
          id: 'b',
          name: '主训练',
          type: coach.BlockType.main,
          rounds: 1,
          restBetweenRoundsSeconds: 40,
          items: [item],
        ),
      ],
    );
    final work = SessionBuilder(
      rhythms: rhythm
          ? {
              item.exerciseId: Rhythm.fromJson({
                'kind': 'rep_updown',
                'leadSeconds': 1,
                'phases': [
                  {'id': 'go', 'seconds': 1.0},
                  {'id': 'back', 'seconds': 1.0},
                ],
              }),
            }
          : const {},
      prepSeconds: 0,
    ).phases(plan).firstWhere((p) => p.isWork);
    expect(work.reps, 15);
    return [
      for (final c in SessionScript(
        source: voices,
        lang: lang,
      ).cues(work, planSeconds: work.seconds))
        if (c.priority == CuePriority.count) c.clips,
    ];
  }

  for (final lang in ['en', 'zh']) {
    test('custom 15 in $lang: 11…14 counted, 15 is the last-one line', () {
      final cues = countCues(lang, rhythm: true);
      expect(cues, hasLength(15));
      final said = cues.expand((c) => c).where((k) => k.startsWith('n.'));
      expect(said, [for (var k = 1; k <= 14; k++) 'n.$k']);
      expect(cues.last, contains('p.last_rep'));
      expect(cues.expand((c) => c), isNot(contains('chime.tick')));
      for (final k in cues.expand((c) => c)) {
        if (!k.startsWith('chime.')) {
          expect(voices.has(k, lang: lang), isTrue, reason: '$k/$lang');
        }
      }
      if (lang == 'en') {
        expect(voices.line('p.last_rep', lang: 'en'), 'Last one.');
        expect(voices.asset('n.11', lang: 'en'), contains('/en/n.11.m4a'));
      }
    });
  }

  test('dose-paced 15 in English counts 11…15 with English clips', () {
    final said = countCues(
      'en',
      rhythm: false,
    ).expand((c) => c).where((k) => k.startsWith('n.')).toSet();
    for (var k = 11; k <= 15; k++) {
      expect(said, contains('n.$k'));
    }
  });
}
