import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart';

import 'support.dart';

void main() {
  final lib = loadLibrary();
  final catalog = loadCatalog();
  final gen = TemplatePlanGenerator(lib: lib, catalog: catalog);

  group('library', () {
    test('93 exercises with media files on disk', () {
      expect(lib.length, 93);
      for (final e in lib.all) {
        expect(File(e.media.video).existsSync(), isTrue, reason: e.media.video);
        expect(File(e.media.poster).existsSync(), isTrue, reason: e.media.poster);
        expect(e.cue, isNotEmpty);
        if (e.alternative != null) expect(lib.contains(e.alternative!), isTrue);
        if (e.dose.mode == DoseMode.reps) expect(e.repSeconds, greaterThan(0));
      }
    });

    test('every move is a drill pack with 1–3 cues and its own voice lines', () {
      final packs = loadPacksSync();
      expect(packs.exercises.map((p) => p.id).toSet(), lib.all.map((e) => e.id).toSet());
      for (final p in [packs.common, ...packs.exercises]) {
        for (final l in p.lines) {
          final ms = l.ms['zh'];
          expect(ms, isNotNull, reason: '${p.id}/${l.id}');
          expect(ms, greaterThan(0), reason: '${p.id}/${l.id}');
          expect(File(p.voiceAsset(l.id, 'zh')).existsSync(), isTrue,
              reason: '${p.id}/${l.id}');
        }
      }
      for (final p in packs.exercises) {
        final e = lib[p.id];
        expect(e.cues.length, inInclusiveRange(1, 3), reason: p.id);
        expect(p.linesWithRole('cue').length, e.cues.length, reason: p.id);
        for (final role in ['name', 'intro', 'rest', 'finish']) {
          expect(p.linesWithRole(role), hasLength(1), reason: '${p.id} $role');
        }
        expect(p.line('side_switch') != null, e.unilateral, reason: p.id);
        expect(e.media.playerId, p.id);
      }
      for (final n in List.generate(60, (i) => 'n.${i + 1}')) {
        expect(packs.common.line(n), isNotNull, reason: n);
      }
      expect(packs.common.chimes.keys, containsAll(['tick', 'start', 'end', 'finish', 'silence']));
    });

    test('templates only reference library ids with matching side flags', () {
      expect(catalog.templates.length, greaterThanOrEqualTo(10));
      for (final t in catalog.templates) {
        for (final i in t.blocks.expand((b) => b.items)) {
          expect(lib.contains(i.exerciseId), isTrue, reason: '${t.id} ${i.exerciseId}');
          expect(i.perSide, lib[i.exerciseId].unilateral, reason: '${t.id} ${i.exerciseId}');
        }
      }
    });
  });

  group('template generator', () {
    test('every template × level × minutes yields a valid plan', () async {
      for (final t in catalog.templates) {
        for (final level in [1, 2, 3]) {
          for (final minutes in [5, t.minutes, 30]) {
            final r = await gen.generate(ScenarioRequest(
              templateId: t.id,
              scene: t.scenes.first,
              equipment: t.equipment.map(Equipment.byName).toSet(),
              minutes: minutes,
              level: level,
            ));
            expect(r.issues, isEmpty, reason: '${t.id} L$level ${minutes}m ${r.issues}');
            expect(r.plan!.items, isNotEmpty);
          }
        }
      }
    });

    test('duration lands near the requested minutes for the default length', () async {
      for (final t in catalog.templates) {
        final r = await gen.generate(ScenarioRequest(
          templateId: t.id, scene: t.scenes.first,
          equipment: t.equipment.map(Equipment.byName).toSet(), minutes: t.minutes, level: 2));
        final s = SessionBuilder(lib).planSeconds(r.plan!) / 60;
        expect(s, inInclusiveRange(t.minutes * 0.6, t.minutes * 1.5), reason: '${t.id}: $s min');
      }
    });

    test('office plans never put the user on the floor', () async {
      final r = await gen.generate(const ScenarioRequest(scene: 'office', goal: 'fullbody', minutes: 10));
      expect(r.plan!.items.map((i) => lib[i.exerciseId]).where((e) => e.isFloor), isEmpty);
      expect(r.plan!.templateId, startsWith('office'));
    });

    test('no dumbbell → dumbbell template not picked; with dumbbell it is', () async {
      final a = await gen.generate(const ScenarioRequest(description: '想练哑铃全身力量 25 分钟'));
      expect(a.plan!.templateId, 'dumbbell-fullbody'); // matcher adds the dumbbell
      final b = await gen.generate(const ScenarioRequest(goal: 'strength', minutes: 25, description: '徒手'));
      expect(b.plan!.templateId, isNot('dumbbell-fullbody'));
      for (final i in b.plan!.items) {
        expect(lib[i.exerciseId].equipment, isNot(contains(Equipment.dumbbell)));
      }
    });

    test('protecting the knee swaps knee-heavy moves', () async {
      final r = await gen.generate(const ScenarioRequest(templateId: 'glutes-legs', avoid: {'膝'}, minutes: 18));
      for (final i in r.plan!.items) {
        expect(lib[i.exerciseId].cautions, isNot(contains('膝')), reason: i.exerciseId);
      }
      expect(r.plan!.notes.join(), contains('膝'));
    });

    test('beginners get the alternative of advanced moves', () async {
      final r = await gen.generate(const ScenarioRequest(templateId: 'glutes-legs', level: 1, minutes: 18));
      expect(r.plan!.exerciseIds, isNot(contains('h-bulgarian')));
      expect(r.plan!.exerciseIds, contains('h-squat'));
    });

    test('AI generator placeholder declines', () async {
      final r = await const AiPlanGenerator().generate(const ScenarioRequest());
      expect(r.plan, isNull);
    });
  });

  group('description matcher', () {
    const m = DescriptionMatcher();
    test('scene, minutes, gear, level, goal, cautions', () {
      final r = m.apply('新手，在办公室 15 分钟，膝盖疼，想放松肩颈', const ScenarioRequest());
      expect(r.scene, 'office');
      expect(r.minutes, 15);
      expect(r.level, 1);
      expect(r.avoid, contains('膝'));
      expect(r.goal, 'relax');
      final d = m.apply('家里有哑铃和弹力带，练臀腿半小时', const ScenarioRequest());
      expect(d.equipment, containsAll([Equipment.dumbbell, Equipment.band]));
      expect(d.minutes, 30);
      expect(d.goal, 'strength');
    });
    test('explicit goal wins over the description', () {
      final r = m.apply('睡前放松', const ScenarioRequest(goal: 'core'));
      expect(r.goal, 'core');
    });
  });

  group('validator', () {
    test('rejects unknown ids, bad doses and wrong side flags', () {
      const plan = TrainingPlan(
        id: 'x', source: 'ai', title: 't', summary: '', goal: 'core', scene: 'home',
        equipment: [], level: 1, targetMinutes: 10,
        blocks: [PlanBlock(id: 'b', name: 'b', type: BlockType.main, rounds: 1, restBetweenRoundsSeconds: 0, items: [
          PlanItem(exerciseId: 'made-up', mode: DoseMode.reps, sets: 3, reps: 10, perSide: false, restSeconds: 30),
          PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 9, reps: 99, perSide: true, restSeconds: 30),
        ])],
      );
      final issues = PlanValidator(lib).validate(plan);
      expect(issues.join('\n'), allOf(contains('made-up'), contains('组数'), contains('次数'), contains('perSide')));
    });
    test('plan JSON round-trips', () async {
      final r = await gen.generate(const ScenarioRequest(templateId: 'core', minutes: 12));
      final back = TrainingPlan.fromJson(r.plan!.toJson());
      expect(back.toJson(), r.plan!.toJson());
    });
  });

  group('session', () {
    TrainingPlan plan(List<PlanItem> items, {BlockType type = BlockType.main, int rounds = 1}) => TrainingPlan(
      id: 'p', source: 'template', title: 't', summary: '', goal: 'core', scene: 'home',
      equipment: const [], level: 1, targetMinutes: 5,
      blocks: [PlanBlock(id: 'b', name: '主训练', type: type, rounds: rounds, restBetweenRoundsSeconds: 40, items: items)],
    );

    test('sets × reps, per side, rests and transitions', () {
      final p = plan(const [
        PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 2, reps: 10, perSide: false, restSeconds: 30),
        PlanItem(exerciseId: 's-figure4', mode: DoseMode.time, sets: 1, workSeconds: 30, perSide: true, restSeconds: 10),
      ]);
      final ph = SessionBuilder(lib).phases(p);
      expect(ph.map((x) => x.kind).toList(), [
        PhaseKind.prep, PhaseKind.work, PhaseKind.rest, PhaseKind.work, PhaseKind.rest,
        PhaseKind.work, PhaseKind.switchSide, PhaseKind.work, PhaseKind.done,
      ]);
      expect(ph[1].seconds, 10 * lib['h-squat'].repSeconds!);
      expect(ph[1].reps, 10);
      expect(ph[2].set, 2);
      expect(ph[4].nextExerciseId, 's-figure4');
      expect(ph[5].side, Side.right);
      expect(ph[7].side, Side.left);
    });

    test('circuit rounds repeat items and rest between rounds', () {
      final p = plan(const [
        PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 1, reps: 8, perSide: false, restSeconds: 10),
        PlanItem(exerciseId: 'w-dead-bug', mode: DoseMode.reps, sets: 1, reps: 8, perSide: false, restSeconds: 10),
      ], type: BlockType.circuit, rounds: 3);
      final ph = SessionBuilder(lib).phases(p);
      expect(ph.where((x) => x.isWork).length, 6);
      final rr = ph.where((x) => x.kind == PhaseKind.roundRest).toList();
      expect(rr.length, 2);
      expect(rr.first.seconds, 40);
      expect(rr.first.round, 2);
    });

    test('absolute clock: a long gap lands in the right phase; skip/previous', () {
      final p = plan(const [
        PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 3, reps: 10, perSide: false, restSeconds: 30),
        PlanItem(exerciseId: 'w-dead-bug', mode: DoseMode.reps, sets: 2, reps: 10, perSide: false, restSeconds: 20),
      ]);
      final e = SessionEngine(SessionBuilder(lib).phases(p));
      e.update(10 + 0.1); // prep is 10 s
      expect(e.phase.kind, PhaseKind.work);
      expect(e.phase.set, 1);
      e.skip(11);
      expect(e.phase.kind, PhaseKind.rest);
      expect(e.phase.nextExerciseId, 'w-dead-bug');
      e.skip(12);
      expect(e.phase.isWork, isTrue);
      expect(e.phase.exerciseId, 'w-dead-bug');
      e.previous(13);
      expect(e.phase.exerciseId, 'h-squat');
      e.update(13 + 10000);
      expect(e.done, isTrue);
      expect(e.completedExercises, 2);
    });

    test('early end preserves progress in prep, work and transition', () {
      final phases = SessionBuilder(lib).phases(plan(const [
        PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 1, reps: 10, perSide: false, restSeconds: 30),
        PlanItem(exerciseId: 'w-dead-bug', mode: DoseMode.reps, sets: 1, reps: 10, perSide: false, restSeconds: 20),
      ]));
      final firstWorkEnd = phases[0].seconds + phases[1].seconds;
      for (final (time, completed) in [(0.0, 0), (11.0, 0), (firstWorkEnd, 1)]) {
        final engine = SessionEngine(phases)..finish(time);
        expect(engine.done, isTrue);
        expect(engine.endedEarly, isTrue);
        expect(engine.completedExercises, completed);
        engine.finish(time + 1);
        engine.update(time + 10000);
        expect(engine.completedExercises, completed);
      }
      final natural = SessionEngine(phases)..finish(10000);
      expect(natural.endedEarly, isFalse);
      expect(natural.completedExercises, 2);
    });
  });
}
