import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show ItemResult, ItemStatus, SessionResult;

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  var writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
    writes++;
  }
}

TrainingPlan _plan({
  String id = 'versioned-plan',
  String title = '原计划',
  int workSeconds = 30,
}) => TrainingPlan(
  id: id,
  source: 'ai',
  title: title,
  summary: '原始计划内容。',
  goal: 'mixed',
  scene: 'home',
  equipment: const ['chair', 'mat'],
  level: 1,
  targetMinutes: 9,
  avoid: const {'knee', 'wrist'},
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        for (final id in ['h-squat', 'h-crunch'])
          PlanItem(
            exerciseId: id,
            mode: DoseMode.time,
            sets: 2,
            workSeconds: workSeconds,
            perSide: false,
            restSeconds: 12,
          ),
      ],
    ),
  ],
);

SessionResult _workout() => SessionResult(
  sessionId: 'original-workout',
  planId: 'versioned-plan',
  planTitle: '训练时的旧名称',
  startedAt: DateTime.utc(2026, 10, 29, 1),
  endedAt: DateTime.utc(2026, 10, 29, 1, 2),
  activeSeconds: 120,
  endedEarly: false,
  completedExercises: 1,
  totalExercises: 1,
  items: const [
    ItemResult(
      exerciseId: 'h-squat',
      blockIndex: 0,
      itemInBlock: 0,
      plannedSets: 2,
      completedSets: 2,
      activeSeconds: 120,
      status: ItemStatus.completed,
    ),
  ],
);

void main() {
  late _Storage storage;
  late AppStore store;

  setUp(() {
    storage = _Storage();
    store = AppStore(storage);
    addTearDown(store.dispose);
  });

  test(
    'old saved records migrate with no SDK version and keep their data',
    () async {
      final original = SavedPlan(
        id: 'old-saved-record',
        name: '用户改过的名称',
        plan: _plan(),
        savedAt: DateTime.utc(2026, 10, 28),
        lastUsedAt: DateTime.utc(2026, 10, 29),
      );
      final legacy = original.toJson()..remove('sdkVersion');
      storage.values[AppStore.key] = jsonEncode({
        'savedPlans': [legacy],
      });

      await store.load();
      final restored = store.savedPlans.single;
      expect(restored.sdkVersion, isNull);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.plan.toJson(), original.plan.toJson());
      expect(restored.savedAt, original.savedAt);
      expect(restored.lastUsedAt, original.lastUsedAt);
    },
  );

  test('SDK version survives JSON, rename and last-used updates', () async {
    final saved = await store.savePlan(_plan(), sdkVersion: 3);
    await store.renamePlan(saved.id, '午休训练');
    final usedAt = DateTime.utc(2026, 10, 29, 2);
    await store.touchPlan(saved.id, now: usedAt);
    final current = store.savedPlans.single;
    expect(current.sdkVersion, 3);
    expect(current.name, '午休训练');
    expect(current.lastUsedAt, usedAt);
    final restored = SavedPlan.fromJson(
      current.toJson().cast<String, dynamic>(),
    );
    expect(restored.toJson(), current.toJson());

    final reloaded = AppStore(storage);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.savedPlans.single.toJson(), current.toJson());
  });

  test(
    'unchanged content and version reuse the record without another write',
    () async {
      final saved = await store.savePlan(_plan(), sdkVersion: 1);
      final writes = storage.writes;
      var notifications = 0;
      store.addListener(() => notifications++);
      final unchanged = await store.savePlan(_plan(), sdkVersion: 1);
      expect(unchanged, same(saved));
      expect(store.savedPlans, [saved]);
      expect(storage.writes, writes);
      expect(notifications, 0);
    },
  );

  test(
    'a content update replaces the snapshot but preserves saved identity and workouts',
    () async {
      final original = _plan();
      final savedAt = DateTime.utc(2026, 10, 28);
      final saved = await store.savePlan(
        original,
        name: '每天午休',
        now: savedAt,
        sdkVersion: 1,
      );
      final usedAt = DateTime.utc(2026, 10, 29, 2);
      await store.touchPlan(saved.id, now: usedAt);
      await store.rememberPlan(original);
      await store.saveSession(_workout());
      final history = [for (final row in store.history) row.toJson()];
      final sessions = [
        for (final result in store.sessionResults) result.toJson(),
      ];
      final newer = _plan(title: '模型更新后的名称', workSeconds: 45);

      final updated = await store.savePlan(
        newer,
        name: '不应覆盖用户命名',
        now: DateTime.utc(2026, 10, 30),
        sdkVersion: 2,
      );
      expect(updated, isNot(same(saved)));
      expect(store.savedPlans, hasLength(1));
      expect(updated.id, saved.id);
      expect(updated.name, '每天午休');
      expect(updated.savedAt, savedAt);
      expect(updated.lastUsedAt, usedAt);
      expect(updated.plan.toJson(), newer.toJson());
      expect(updated.sdkVersion, 2);
      expect(store.lastPlan!.toJson(), original.toJson());
      expect([for (final row in store.history) row.toJson()], history);
      expect([
        for (final result in store.sessionResults) result.toJson(),
      ], sessions);

      final reloaded = AppStore(storage);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.savedPlans.single.toJson(), updated.toJson());
      expect([for (final row in reloaded.history) row.toJson()], history);
      expect([
        for (final result in reloaded.sessionResults) result.toJson(),
      ], sessions);
    },
  );

  test(
    'content changes update even when the SDK version did not change',
    () async {
      final saved = await store.savePlan(_plan(), sdkVersion: 1);
      final newer = _plan(workSeconds: 45);
      final updated = await store.savePlan(newer, sdkVersion: 1);
      expect(updated.id, saved.id);
      expect(updated.plan.items.first.workSeconds, 45);
      expect(updated.sdkVersion, 1);
      expect(store.savedForSnapshot(newer, sdkVersion: 1), same(updated));
      expect(store.savedForSnapshot(_plan(), sdkVersion: 1), isNull);
    },
  );

  test(
    'version-only updates are saved and an explicitly unknown version is null',
    () async {
      final plan = _plan();
      final saved = await store.savePlan(plan, sdkVersion: 1);
      final updated = await store.savePlan(plan, sdkVersion: 2);
      expect(updated.id, saved.id);
      expect(updated.sdkVersion, 2);
      expect(updated, isNot(same(saved)));
      expect(store.savedForSnapshot(plan, sdkVersion: 1), isNull);
      expect(store.savedForSnapshot(plan, sdkVersion: 2), same(updated));

      final unversioned = await store.updateSavedPlan(saved.id, plan);
      expect(unversioned!.sdkVersion, isNull);
      expect(unversioned.toJson().containsKey('sdkVersion'), isFalse);
      expect(store.savedForSnapshot(plan), same(unversioned));
    },
  );

  test(
    'explicit replacement targets its saved record when SDK plan identity changes',
    () async {
      final saved = await store.savePlan(
        _plan(),
        name: '保留这个名称',
        sdkVersion: 1,
      );
      final sibling = await store.savePlan(_plan(id: 'unrelated-plan'));
      final imported = _plan(id: 'imported-plan-id', workSeconds: 50);
      final updated = await store.updateSavedPlan(
        saved.id,
        imported,
        sdkVersion: 4,
      );
      expect(updated!.id, saved.id);
      expect(updated.name, saved.name);
      expect(updated.savedAt, saved.savedAt);
      expect(updated.plan.id, imported.id);
      expect(updated.sdkVersion, 4);
      expect(store.savedPlans, hasLength(2));
      expect(store.savedPlans.first, same(sibling));
      expect(store.savedFor(imported), same(updated));
      expect(store.savedFor(_plan()), isNull);
    },
  );

  test(
    'a deleted replacement target returns null without reviving it',
    () async {
      final saved = await store.savePlan(_plan(), sdkVersion: 1);
      await store.deletePlan(saved.id);
      final writes = storage.writes;
      final result = await store.updateSavedPlan(
        saved.id,
        _plan(),
        sdkVersion: 2,
      );
      expect(result, isNull);
      expect(store.savedPlans, isEmpty);
      expect(storage.writes, writes);
    },
  );

  test(
    'save as new preserves the original and creates unique same-plan records',
    () async {
      final at = DateTime.utc(2026, 10, 29, 2);
      final original = await store.savePlan(
        _plan(),
        name: '午休练习',
        now: at,
        sdkVersion: 1,
      );
      final newer = _plan(workSeconds: 45);
      final copy = await store.savePlan(
        newer,
        now: at,
        sdkVersion: 2,
        forceNew: true,
      );
      final again = await store.savePlan(
        newer,
        name: original.name,
        now: at,
        sdkVersion: 2,
        forceNew: true,
      );
      expect(copy.name, '午休练习 新版');
      expect(again.name, '午休练习 新版 2');
      expect({original.id, copy.id, again.id}, hasLength(3));
      expect(store.savedPlans, [again, copy, original]);
      expect(original.plan.items.first.workSeconds, 30);
      expect(original.sdkVersion, 1);
      expect(copy.plan.toJson(), newer.toJson());
      expect(copy.sdkVersion, 2);
      expect(copy.savedAt, at);
      expect(copy.lastUsedAt, isNull);
      expect(store.savedForSnapshot(_plan(), sdkVersion: 1), same(original));
      expect(store.savedForSnapshot(newer, sdkVersion: 2), same(again));
      expect(
        store.savedForSnapshot(newer, sdkVersion: 2, savedId: copy.id),
        same(copy),
      );
      expect(
        store.savedForSnapshot(newer, sdkVersion: 2, savedId: original.id),
        isNull,
      );
    },
  );

  test(
    'snapshot equality ignores equipment order but preserves action order and dose',
    () async {
      final original = _plan();
      final saved = await store.savePlan(original, sdkVersion: 1);
      final reorderedSets = TrainingPlan.fromJson({
        ...original.toJson(),
        'equipment': original.equipment.reversed.toList(),
        'avoid': original.avoid.toList().reversed.toList(),
      });
      expect(await store.savePlan(reorderedSets, sdkVersion: 1), same(saved));
      final reorderedActions = original.copyWith(
        blocks: [
          original.blocks.single.copyWith(
            items: original.blocks.single.items.reversed.toList(),
          ),
        ],
      );
      expect(store.savedFor(reorderedActions), same(saved));
      expect(store.savedForSnapshot(reorderedActions, sdkVersion: 1), isNull);
      final updated = await store.savePlan(reorderedActions, sdkVersion: 1);
      expect(updated.id, saved.id);
      expect(updated.plan.items.first.exerciseId, 'h-crunch');
      expect(updated.plan.items.last.exerciseId, 'h-squat');
      expect(store.savedForSnapshot(original, sdkVersion: 1), isNull);
    },
  );
}
