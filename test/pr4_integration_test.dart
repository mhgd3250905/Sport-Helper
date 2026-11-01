import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

class _BlockedStorage implements LocalStateStorage {
  final values = <String, String>{};
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (writes++ == 0) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    values[key] = value;
  }
}

SessionResult _completedWorkout() => SessionResult(
  sessionId: 'flat-integration-workout',
  planId: 'core-plan',
  planTitle: '核心训练',
  startedAt: DateTime.utc(2026, 10, 21, 1),
  endedAt: DateTime.utc(2026, 10, 21, 1, 2),
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

void main() {
  for (final settingsFirst in [true, false]) {
    test('${settingsFirst ? 'settings' : 'trainer'} write in flight preserves '
        'trainer result, memory setting and appearance changes', () async {
      final storage = _BlockedStorage();
      final store = AppStore(storage);
      addTearDown(store.dispose);
      int notifications = 0;
      store.addListener(() => notifications++);
      final result = _completedWorkout();
      final first = settingsFirst
          ? store.setAppearance('light')
          : store.saveSession(result);
      await storage.firstStarted.future;
      expect(notifications, settingsFirst ? 1 : 0);
      expect(store.sessionResults, isEmpty);
      final second = settingsFirst
          ? store.saveSession(result)
          : store.setAppearance('light');
      final memory = store.setAiMemoryEnabled(false);
      final settledAppearance = store.setAppearance('dark');
      expect(notifications, 3);

      storage.releaseFirst.complete();
      await Future.wait([first, second, memory, settledAppearance]);
      expect(notifications, 4);
      final restored = AppStore(storage);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.appearance, 'dark');
      expect(restored.aiMemoryEnabled, isFalse);
      expect(restored.sessionResults.single.toJson(), result.toJson());
      expect(restored.history.single.sessionId, result.sessionId);
      expect(restored.history.single.completed, 1);
    });
  }
}
