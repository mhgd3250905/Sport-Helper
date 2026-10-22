/// Plan generation. [PlanGenerator] is the seam the AI generator will plug
/// into later; the MVP ships [TemplatePlanGenerator] only (no model, no
/// network). Every generator's output goes through [PlanValidator].
library;

import 'dart:math' as math;

import 'exercise.dart';
import 'plan.dart';
import 'plan_validator.dart';
import 'scenario.dart';
import 'session.dart';
import 'template.dart';

class GenerationResult {
  const GenerationResult(this.plan, {this.issues = const []});
  final TrainingPlan? plan;
  final List<String> issues;
  bool get ok => plan != null && issues.isEmpty;
}

abstract interface class PlanGenerator {
  String get id;
  Future<GenerationResult> generate(ScenarioRequest request);
}

/// Placeholder for the model-backed generator (model to be chosen by the
/// user). It is not wired into the app; when it exists it must return a
/// TrainingPlan v1 that only references library ids, and the app falls
/// back to [TemplatePlanGenerator] whenever validation fails.
class AiPlanGenerator implements PlanGenerator {
  const AiPlanGenerator();
  @override
  String get id => 'ai';
  @override
  Future<GenerationResult> generate(ScenarioRequest request) async =>
      const GenerationResult(null, issues: ['AI 生成尚未接入']);
}

/// Picks the best template for a request, then adapts it: swaps moves the
/// user can't do (equipment, office floor, level, cautions), scales the
/// dose by level and stretches / shrinks rounds, sets and holds to the
/// requested minutes.
class TemplatePlanGenerator implements PlanGenerator {
  TemplatePlanGenerator({
    required this.lib,
    required this.catalog,
    this.matcher = const DescriptionMatcher(),
    this.preferredExerciseIds,
    this.onGenerated,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ExerciseLibrary lib;
  final TemplateCatalog catalog;
  final DescriptionMatcher matcher;

  /// Available local media while offline. Safety and equipment filters still
  /// take precedence; an empty set leaves the existing selection unchanged.
  final Set<String> Function()? preferredExerciseIds;
  final void Function(TrainingPlan)? onGenerated;
  final DateTime Function() _now;

  @override
  String get id => 'template';

  /// Score every template against the request (higher is better).
  List<(PlanTemplate, double)> rank(ScenarioRequest r) {
    final out = <(PlanTemplate, double)>[];
    for (final t in catalog.templates) {
      var s = 0.0;
      if (t.scenes.contains(r.scene)) {
        s += 40;
      } else {
        s -= 60;
      }
      if (r.goal != null) {
        if (t.goal == r.goal) {
          s += 50;
        } else if (_near(t.goal, r.goal!)) {
          s += 15;
        }
      }
      final need = t.equipment.map(Equipment.byName).toSet();
      if (!r.availableEquipment.containsAll(need)) {
        s -= 80;
      } else if (need.isNotEmpty) {
        s += 25; // the user ticked this gear: use it
      }
      final hits = t.keywords.where(r.description.contains).length;
      s += 12.0 * hits;
      s -= (t.minutes - r.minutes).abs() * 0.8;
      final preferred = preferredExerciseIds?.call() ?? const <String>{};
      final ids = [
        for (final b in t.blocks)
          for (final i in b.items) i.exerciseId,
      ];
      if (preferred.isNotEmpty && ids.isNotEmpty) {
        s += 20 * ids.where(preferred.contains).length / ids.length;
      }
      if (r.level < t.minLevel || r.level > t.maxLevel) s -= 10;
      out.add((t, s));
    }
    out.sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  static bool _near(String a, String b) {
    const groups = [
      {'relax', 'cooldown', 'mobility'},
      {'strength', 'fullbody', 'core'},
      {'warmup', 'fullbody', 'mobility'},
    ];
    return groups.any((g) => g.contains(a) && g.contains(b));
  }

  @override
  Future<GenerationResult> generate(ScenarioRequest request) async {
    final r = matcher.apply(request.description, request);
    final t =
        (r.templateId != null ? catalog.byId(r.templateId!) : null) ??
        rank(r).first.$1;
    final plan = fromTemplate(t, r);
    final issues = PlanValidator(lib).validate(plan, r);
    if (issues.isEmpty) onGenerated?.call(plan);
    return GenerationResult(issues.isEmpty ? plan : null, issues: issues);
  }

  TrainingPlan fromTemplate(PlanTemplate t, ScenarioRequest r) {
    final notes = <String>[];
    final blocks = <PlanBlock>[];
    for (final b in t.blocks) {
      final items = <PlanItem>[];
      for (final item in b.items) {
        final adapted = _adapt(item, r, notes, items);
        if (adapted != null) items.add(_dose(adapted, b.type, r.level));
      }
      if (items.isNotEmpty) blocks.add(b.copyWith(items: items));
    }
    var plan = TrainingPlan(
      id: 'plan-${_now().millisecondsSinceEpoch}',
      source: 'template',
      templateId: t.id,
      title: t.name,
      summary: t.summary,
      goal: t.goal,
      scene: r.scene,
      equipment: [
        for (final e in r.availableEquipment)
          if (e != Equipment.none) e.name,
      ],
      level: r.level,
      targetMinutes: r.minutes,
      blocks: blocks,
      avoid: r.avoid,
      safetyNotes: const [
        '动作过程中出现关节刺痛、麻木或头晕，请立即停止。',
        '本计划为通用健身建议，不能替代医生或康复治疗师的意见。',
      ],
    );
    plan = _fitDuration(plan, r.minutes, notes);
    return plan.copyWith(notes: notes);
  }

  /// Can the user do [e] in this scenario?
  String? blockerFor(Exercise e, ScenarioRequest r) {
    final have = r.availableEquipment;
    for (final q in e.equipment) {
      if (!have.contains(q)) return '没有${q.zh}';
    }
    if (r.scene == 'office' && e.isFloor) return '办公室不方便趴地';
    if (e.level > r.level + 1) return '难度偏高';
    final hit = e.cautions.where(r.avoid.contains);
    if (hit.isNotEmpty) return '保护${hit.first}';
    return null;
  }

  PlanItem? _adapt(
    PlanItem item,
    ScenarioRequest r,
    List<String> notes,
    List<PlanItem> sofar,
  ) {
    final e = lib.tryGet(item.exerciseId);
    if (e == null) return null;
    final why = blockerFor(e, r);
    final preferred = preferredExerciseIds?.call() ?? const <String>{};
    if (why == null && preferred.isNotEmpty && !preferred.contains(e.id)) {
      final local = _similar(e, r, sofar, onlyIds: preferred);
      if (local == null) return item;
      notes.add('离线优先使用已有示范：「${e.name}」换成「${local.name}」');
      return _itemForAlternative(item, e, local);
    }
    if (why == null) return item;
    // Walk the alternative chain, then any same-category move that fits.
    final tried = <String>{e.id};
    var alt = e.alternative == null ? null : lib.tryGet(e.alternative!);
    while (alt != null && tried.add(alt.id)) {
      if (blockerFor(alt, r) == null) break;
      alt = alt.alternative == null ? null : lib.tryGet(alt.alternative!);
    }
    if (alt != null && blockerFor(alt, r) != null) alt = null;
    alt ??= _similar(e, r, sofar);
    if (alt == null) {
      notes.add('去掉了「${e.name}」（$why）');
      return null;
    }
    notes.add('「${e.name}」换成「${alt.name}」（$why）');
    return _itemForAlternative(item, e, alt);
  }

  PlanItem _itemForAlternative(PlanItem item, Exercise e, Exercise alt) {
    final d = alt.dose;
    return PlanItem(
      exerciseId: alt.id,
      mode: d.mode,
      sets: item.sets,
      reps: d.mode == DoseMode.reps ? (item.reps ?? d.reps) : null,
      workSeconds: d.mode == DoseMode.time
          ? (item.workSeconds ?? d.seconds)
          : null,
      perSide: alt.unilateral,
      restSeconds: item.restSeconds,
      replacedFrom: e.id,
    );
  }

  Exercise? _similar(
    Exercise e,
    ScenarioRequest r,
    List<PlanItem> sofar, {
    Set<String>? onlyIds,
  }) {
    final used = {for (final i in sofar) i.exerciseId};
    final candidates = lib.all
        .where(
          (c) =>
              c.id != e.id &&
              (onlyIds == null || onlyIds.contains(c.id)) &&
              !used.contains(c.id) &&
              c.category == e.category &&
              c.scenes.contains(r.scene) &&
              blockerFor(c, r) == null,
        )
        .toList();
    if (candidates.isEmpty) return null;
    int overlap(Exercise c) => c.muscles.where(e.muscles.contains).length;
    candidates.sort((a, b) {
      final preferred = preferredExerciseIds?.call() ?? const <String>{};
      final ready = (preferred.contains(b.id) ? 1 : 0).compareTo(
        preferred.contains(a.id) ? 1 : 0,
      );
      if (ready != 0) return ready;
      final o = overlap(b).compareTo(overlap(a));
      return o != 0 ? o : a.level.compareTo(b.level);
    });
    return candidates.first;
  }

  /// Level scaling: 入门 fewer reps / shorter holds, 进阶 more.
  PlanItem _dose(PlanItem i, BlockType type, int level) {
    if (type == BlockType.warmup || type == BlockType.cooldown) return i;
    final f = switch (level) {
      1 => 0.8,
      3 => 1.25,
      _ => 1.0,
    };
    if (f == 1.0) return i;
    final sets = level == 3 && i.sets >= 2 ? i.sets + 1 : i.sets;
    return i.mode == DoseMode.reps
        ? i.copyWith(
            reps: math.max(5, ((i.reps ?? 10) * f).round()),
            sets: sets,
          )
        : i.copyWith(
            workSeconds: math.max(
              15,
              ((i.workSeconds ?? 30) * f / 5).round() * 5,
            ),
            sets: sets,
          );
  }

  double _seconds(TrainingPlan p) => SessionBuilder(lib).planSeconds(p);

  /// Re-fits an existing plan to [minutes] (rounds → sets → holds), the
  /// same way a fresh plan is fitted. Used by the chat's "再短一点 / 长一点".
  TrainingPlan refit(TrainingPlan plan, int minutes) {
    final notes = <String>[];
    final p = _fitDuration(plan, minutes, notes);
    return p.copyWith(notes: [...plan.notes, ...notes]);
  }

  /// A move that can stand in for [e] in this scenario and is not one of
  /// [exclude]: its alternative chain first, then the closest move of the
  /// same category (muscle overlap, then easier first).
  Exercise? replacementFor(Exercise e, ScenarioRequest r, Set<String> exclude) {
    final tried = <String>{e.id};
    var alt = e.alternative == null ? null : lib.tryGet(e.alternative!);
    while (alt != null && tried.add(alt.id)) {
      if (blockerFor(alt, r) == null && !exclude.contains(alt.id)) return alt;
      alt = alt.alternative == null ? null : lib.tryGet(alt.alternative!);
    }
    return _similar(e, r, [
      for (final id in exclude)
        PlanItem(
          exerciseId: id,
          mode: DoseMode.time,
          sets: 1,
          perSide: false,
          restSeconds: 0,
        ),
    ]);
  }

  /// Grow or shrink the plan toward [minutes]: circuit rounds first, then
  /// sets of main-block items, then hold lengths; within ±15 % or 6 steps.
  TrainingPlan _fitDuration(
    TrainingPlan plan,
    int minutes,
    List<String> notes,
  ) {
    final target = minutes * 60.0;
    var p = plan;
    final start = _seconds(p);
    for (var step = 0; step < 12; step++) {
      final now = _seconds(p);
      if ((now - target).abs() <= target * 0.15) break;
      final grow = now < target;
      final next = _nudge(p, grow);
      if (next == null) break;
      final after = _seconds(next);
      // Stop when the nudge overshoots further than where we are.
      if ((after - target).abs() >= (now - target).abs()) break;
      p = next;
    }
    final end = _seconds(p);
    if ((end - start).abs() > 60) {
      notes.add('按你选的 $minutes 分钟调整了组数/轮数（约 ${(end / 60).round()} 分钟）');
    }
    return p;
  }

  TrainingPlan? _nudge(TrainingPlan p, bool grow) {
    final blocks = [...p.blocks];
    // 1) circuit rounds
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type != BlockType.circuit) continue;
      final r = b.rounds + (grow ? 1 : -1);
      if (r >= 1 && r <= 5) {
        blocks[i] = b.copyWith(rounds: r);
        return p.copyWith(blocks: blocks);
      }
    }
    // 2) sets of main-block items
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.type != BlockType.main) continue;
      final items = [...b.items];
      var changed = false;
      for (var k = 0; k < items.length; k++) {
        final s = items[k].sets + (grow ? 1 : -1);
        if (s >= 1 && s <= 5) {
          items[k] = items[k].copyWith(sets: s);
          changed = true;
        }
      }
      if (changed) {
        blocks[i] = b.copyWith(items: items);
        return p.copyWith(blocks: blocks);
      }
    }
    // 3) hold lengths everywhere
    var changed = false;
    for (var i = 0; i < blocks.length; i++) {
      final items = [
        for (final it in blocks[i].items)
          if (it.mode == DoseMode.time)
            () {
              final s = (it.workSeconds ?? 30) + (grow ? 10 : -10);
              if (s < 15 || s > 90) return it;
              changed = true;
              return it.copyWith(workSeconds: s);
            }()
          else
            it,
      ];
      blocks[i] = blocks[i].copyWith(items: items);
    }
    return changed ? p.copyWith(blocks: blocks) : null;
  }
}
