import 'exercise.dart';
import 'plan.dart';
import 'scenario.dart';

/// Checks a TrainingPlan v1 against the library and the request. The same
/// rules apply to template plans and (later) AI plans: only library ids,
/// gear the user has, sane doses, side flags matching the move, warm-up
/// before cool-down.
class PlanValidator {
  const PlanValidator(this.lib);
  final ExerciseLibrary lib;

  List<String> validate(TrainingPlan plan, [ScenarioRequest? r]) {
    final issues = <String>[];
    final avoid = {...plan.avoid, ...?r?.avoid};
    if (plan.schemaVersion != 1) issues.add('schemaVersion 必须为 1');
    if (plan.blocks.isEmpty) issues.add('计划没有任何训练块');
    var sawCooldown = false;
    for (final b in plan.blocks) {
      if (b.items.isEmpty) issues.add('训练块「${b.name}」为空');
      if (b.rounds < 1 || b.rounds > 6) issues.add('「${b.name}」轮数 ${b.rounds} 超出 1–6');
      if (b.type == BlockType.cooldown) sawCooldown = true;
      if (b.type == BlockType.warmup && sawCooldown) {
        issues.add('热身块不能排在放松块之后');
      }
      for (final i in b.items) {
        final e = lib.tryGet(i.exerciseId);
        if (e == null) {
          issues.add('未知动作 ID：${i.exerciseId}');
          continue;
        }
        if (i.sets < 1 || i.sets > 6) issues.add('${e.name}：组数 ${i.sets} 超出 1–6');
        if (i.mode == DoseMode.reps) {
          final reps = i.reps;
          if (reps == null || reps < 1 || reps > 30) {
            issues.add('${e.name}：次数 $reps 超出 1–30');
          }
        } else {
          final s = i.workSeconds;
          if (s == null || s < 10 || s > 120) {
            issues.add('${e.name}：时长 $s 秒超出 10–120');
          }
        }
        if (i.restSeconds < 0 || i.restSeconds > 180) {
          issues.add('${e.name}：休息 ${i.restSeconds} 秒超出 0–180');
        }
        if (i.perSide != e.unilateral) {
          issues.add('${e.name}：perSide 应为 ${e.unilateral}');
        }
        for (final c in e.cautions) {
          if (avoid.contains(c)) issues.add('${e.name} 会加重$c部负担');
        }
        if (r != null) {
          for (final q in e.equipment) {
            if (!r.availableEquipment.contains(q)) {
              issues.add('${e.name} 需要${q.zh}');
            }
          }
          if (r.scene == 'office' && e.isFloor) {
            issues.add('${e.name} 需要趴/躺在地上，不适合办公室');
          }
        }
      }
    }
    return issues;
  }
}
