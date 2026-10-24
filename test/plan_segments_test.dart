import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/session.dart' as session;
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

TrainingPlan _plan({List<coach.PlanSegment>? segments}) => TrainingPlan(
  id: 'segmented-plan',
  source: 'template',
  title: '分段训练',
  summary: '逐段完成同一组',
  goal: 'fullbody',
  scene: 'home',
  equipment: const [],
  level: 1,
  targetMinutes: 5,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.reps,
          sets: 2,
          perSide: false,
          restSeconds: 15,
          segments:
              segments ??
              const [
                coach.PlanSegment(
                  id: 'squat',
                  exerciseId: 'h-squat',
                  label: '深蹲',
                  mode: coach.DoseMode.reps,
                  reps: 5,
                  holdSeconds: 2,
                ),
                coach.PlanSegment(
                  id: 'plank',
                  exerciseId: 'h-forearm-plank',
                  label: '支撑',
                  mode: coach.DoseMode.time,
                  workSeconds: 10,
                ),
              ],
        ),
      ],
    ),
  ],
);

void main() {
  test(
    'App persistence and trainer conversion preserve ordered SDK segments',
    () {
      final original = _plan();
      final restored = TrainingPlan.fromJson(original.toJson());
      final forwarded = session.trainerPlan(restored);
      expect(restored.toJson(), original.toJson());
      expect(restored.exerciseIds, {'h-squat', 'h-forearm-plank'});
      expect(forwarded.items.single.reps, isNull);
      expect(
        forwarded.items.single.segments.map((segment) => segment.toJson()),
        original.items.single.segments.map((segment) => segment.toJson()),
      );
      final changed = restored.items.single.copyWith(sets: 3);
      expect(changed.segments, same(restored.items.single.segments));
      expect(changed.doseText(), '3 组 × (深蹲 5 次 + 支撑 10 秒)');
      expect(
        PlanValidator(
          loadLibrary(),
        ).validate(restored, const ScenarioRequest()),
        isEmpty,
      );
    },
  );

  test('malformed stored segments are rejected instead of discarded', () {
    final invalid = _plan(
      segments: const [
        coach.PlanSegment(
          id: 'duplicate',
          exerciseId: 'h-squat',
          mode: coach.DoseMode.reps,
          reps: 5,
        ),
        coach.PlanSegment(
          id: 'duplicate',
          exerciseId: 'h-forearm-plank',
          mode: coach.DoseMode.time,
          workSeconds: 10,
        ),
      ],
    );
    expect(
      () => TrainingPlan.fromJson(invalid.toJson()),
      throwsFormatException,
    );
    expect(PlanValidator(loadLibrary()).validate(invalid), isNotEmpty);
  });

  test('segments obey App action, equipment, scene and dose gates', () {
    final validator = PlanValidator(loadLibrary());
    final unknown = _plan(
      segments: const [
        coach.PlanSegment(
          id: 'unknown',
          exerciseId: 'unreleased-action',
          mode: coach.DoseMode.reps,
          reps: 5,
        ),
      ],
    );
    expect(validator.validate(unknown).join(), contains('unreleased-action'));
    final band = _plan(
      segments: const [
        coach.PlanSegment(
          id: 'band',
          exerciseId: 'h-band-row',
          mode: coach.DoseMode.reps,
          reps: 5,
        ),
      ],
    );
    expect(
      validator.validate(band, const ScenarioRequest()).join(),
      contains('弹力带'),
    );
    expect(
      validator
          .validate(_plan(), const ScenarioRequest(scene: 'office'))
          .join(),
      contains('不适合办公室'),
    );
    final invalidDose = _plan(
      segments: const [
        coach.PlanSegment(
          id: 'short',
          exerciseId: 'h-forearm-plank',
          mode: coach.DoseMode.time,
          workSeconds: 1,
        ),
      ],
    );
    expect(validator.validate(invalidDose).join(), contains('时长 1 秒'));
  });
}
