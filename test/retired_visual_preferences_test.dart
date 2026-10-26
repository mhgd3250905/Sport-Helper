import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

const _oldKey = 'glassQuality';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  int writes = 0;
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (fail) throw StateError('fixture storage unavailable');
    values[key] = value;
  }
}

Map<String, Object?> _state() {
  const plan = TrainingPlan(
    id: 'kept-plan',
    source: 'template',
    title: '原有计划',
    summary: '',
    goal: 'mobility',
    scene: 'home',
    equipment: [],
    level: 1,
    targetMinutes: 2,
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
            mode: DoseMode.time,
            sets: 1,
            workSeconds: 30,
            perSide: false,
            restSeconds: 0,
          ),
        ],
      ),
    ],
  );
  final at = DateTime.utc(2026, 10, 25, 8);
  final session = SessionResult(
    sessionId: 'kept-session',
    planId: plan.id,
    planTitle: plan.title,
    startedAt: at,
    endedAt: at.add(const Duration(minutes: 2)),
    activeSeconds: 120,
    endedEarly: false,
    completedExercises: 1,
    totalExercises: 1,
    items: const [
      ItemResult(
        exerciseId: 'h-squat',
        blockIndex: 0,
        itemInBlock: 0,
        plannedSets: 1,
        completedSets: 1,
        activeSeconds: 120,
        status: ItemStatus.completed,
      ),
    ],
  );
  return {
    _oldKey: 'premium',
    'safetyAccepted': true,
    'safetyBlocked': false,
    'appearance': 'light',
    'starfield': false,
    'aiMemoryEnabled': false,
    'mediaWifiOnly': false,
    'lastPlan': plan.toJson(),
    'savedPlans': [
      SavedPlan(
        id: 'saved',
        name: plan.title,
        plan: plan,
        savedAt: at,
      ).toJson(),
    ],
    'sessions': [session.toJson()],
    'history': [
      for (var i = 0; i < 37; i++)
        HistoryEntry(
          title: '记录$i',
          at: at,
          minutes: 2,
          completed: 1,
          total: 1,
        ).toJson(),
    ],
    'chat': [
      for (var i = 0; i < 73; i++)
        {'id': 'm$i', 'role': 'user', 'text': '原有消息$i'},
    ],
    'futurePreference': {
      'preserve': [1, 2, 3],
    },
  };
}

void main() {
  test(
    'one-time cleanup preserves the complete original map and other storage',
    () async {
      final storage = _Storage();
      final original = _state();
      storage.values[AppStore.key] = jsonEncode(original);
      storage.values['fixture-device'] = 'device-unchanged';
      storage.values['fixture-memory'] = 'memory-unchanged';
      storage.values['fixture-action-issues'] = 'issues-unchanged';
      final expected = Map<String, Object?>.from(original)..remove(_oldKey);
      final store = AppStore(storage);
      await store.load();
      expect(jsonDecode(storage.values[AppStore.key]!), expected);
      expect(store.history, hasLength(37));
      expect(store.chatLog, hasLength(73));
      expect(store.savedPlans.single.plan.id, 'kept-plan');
      expect(store.sessionResults.single.sessionId, 'kept-session');
      expect(store.safetyAccepted, isTrue);
      expect(store.appearance, 'light');
      expect(store.aiMemoryEnabled, isFalse);
      expect(store.mediaWifiOnly, isFalse);
      expect(storage.values['fixture-device'], 'device-unchanged');
      expect(storage.values['fixture-memory'], 'memory-unchanged');
      expect(storage.values['fixture-action-issues'], 'issues-unchanged');
      expect(storage.writes, 1);
      await AppStore(storage).load();
      expect(storage.writes, 1);
    },
  );

  test(
    'failed cleanup still loads user state and retries on the next launch',
    () async {
      final storage = _Storage()..fail = true;
      final raw = jsonEncode(_state());
      storage.values[AppStore.key] = raw;
      final store = AppStore(storage);
      await store.load();
      expect(store.safetyAccepted, isTrue);
      expect(store.savedPlans, hasLength(1));
      expect(store.sessionResults, hasLength(1));
      expect(storage.values[AppStore.key], raw);
      storage.fail = false;
      await AppStore(storage).load();
      expect(
        jsonDecode(storage.values[AppStore.key]!),
        Map<String, Object?>.from(_state())..remove(_oldKey),
      );
    },
  );

  test('already migrated state performs no cleanup write', () async {
    final storage = _Storage();
    storage.values[AppStore.key] = jsonEncode(_state()..remove(_oldKey));
    await AppStore(storage).load();
    expect(storage.writes, 0);
  });
}
