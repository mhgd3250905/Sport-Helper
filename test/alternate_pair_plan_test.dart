import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/session.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

// SDK r2-v2 (PR #18): 23 alternating actions count one left + one right as
// one rep. SF plans them as 每侧 N 次 and plays N pairs in one pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '23 alternating pairs: 每侧 N 次, one pass per set, plan = played time',
    () async {
      final sdk = await PoseHubActionLibrary.load();
      final content = AppTestContent.build(
        catalog: AppTestCatalog.fromSdk(sdk),
        legacyLibrary: ExerciseLibrary(const []),
      );
      final pairs = [
        for (final e in content.library.all)
          if (e.trainingRhythm?.alternatePair ?? false) e,
      ];
      expect(pairs.map((e) => e.id), hasLength(23));
      expect(
        pairs.map((e) => e.id),
        containsAll([
          'h-mountain-climber',
          'w-dead-bug',
          'h-russian-twist',
          'n-chair-wiper',
        ]),
      );
      const estimate = coach.PlanDuration();
      for (final e in pairs) {
        final rhythm = e.trainingRhythm!;
        final reps = e.dose.reps!;
        final sets = e.dose.sets;
        expect(e.unilateral, isTrue, reason: e.id);
        expect(e.dose.mode, DoseMode.reps, reason: e.id);
        // Played: one work phase per set holding every pair (right + left).
        final item = PlanItem(
          exerciseId: e.id,
          mode: DoseMode.reps,
          sets: sets,
          reps: reps,
          perSide: e.unilateral,
          restSeconds: e.dose.restSeconds,
        );
        expect(item.doseText(), contains('每侧 $reps 次'), reason: e.id);
        final plan = TrainingPlan(
          id: 'p',
          source: 'template',
          title: 't',
          summary: '',
          goal: 'core',
          scene: 'home',
          equipment: const [],
          level: 1,
          targetMinutes: 5,
          blocks: [
            PlanBlock(
              id: 'b',
              name: '主训练',
              type: BlockType.main,
              rounds: 1,
              restBetweenRoundsSeconds: 40,
              items: [item],
            ),
          ],
        );
        final phases = SessionBuilder(content.library).phases(plan);
        expect(
          phases.where((p) => p.kind == PhaseKind.switchSide),
          isEmpty,
          reason: e.id,
        );
        final work = phases.where((p) => p.isWork).toList();
        expect(work, hasLength(sets), reason: e.id);
        for (final p in work) {
          expect(p.reps, reps, reason: e.id);
          expect(p.side, isNull, reason: e.id);
          expect(p.rhythm?.alternatePair, isTrue, reason: e.id);
        }
        final pairSet = reps * rhythm.cycleFor();
        // Planned: 每侧 N 次 × 2 sides × per-side cost = the pairs actually played.
        expect(item.workFor(e) * 2, closeTo(pairSet, 1e-6), reason: e.id);
        final drill = content.coachCatalog[e.id]!;
        expect(
          estimate.repSeconds(drill) * 2 * reps,
          closeTo(pairSet, 1e-6),
          reason: e.id,
        );
        // ignore: avoid_print
        print(
          '${e.id} sets=$sets reps=$reps pair=${rhythm.cycleFor().toStringAsFixed(2)}s '
          'set=${pairSet.toStringAsFixed(1)}s first=${rhythm.pairFirstSide}',
        );
      }
    },
  );
}
