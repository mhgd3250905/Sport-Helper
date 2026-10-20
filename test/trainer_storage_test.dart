import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  var failures = 0;
  Completer<void>? nextWriteGate;
  Completer<void>? writeStarted;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final gate = nextWriteGate;
    nextWriteGate = null;
    writeStarted?.complete();
    writeStarted = null;
    if (gate != null) await gate.future;
    if (failures > 0) {
      failures--;
      throw StateError('Storage write failed');
    }
    values[key] = value;
  }
}

SessionResult _result({String id = 'session-one', int completed = 1}) =>
    SessionResult(
      sessionId: id,
      planId: 'core-plan',
      planTitle: '核心训练',
      startedAt: DateTime.utc(2026, 10, 20, 1),
      endedAt: DateTime.utc(2026, 10, 20, 1, 3),
      activeSeconds: 121,
      endedEarly: completed < 2,
      completedExercises: completed,
      totalExercises: 2,
      items: [
        ItemResult(
          exerciseId: 'h-squat',
          blockIndex: 0,
          itemInBlock: 0,
          plannedSets: 2,
          completedSets: completed,
          activeSeconds: 100,
          status: completed == 2 ? ItemStatus.completed : ItemStatus.partial,
          replacedFrom: 'h-crunch',
        ),
      ],
      discomfort: const [
        DiscomfortEvent(
          at: 21,
          exerciseId: 'h-crunch',
          action: DiscomfortAction.substitute,
          substituteId: 'h-squat',
          note: '换动作',
        ),
      ],
    );

void main() {
  test('legacy history survives loading and saving trainer results', () async {
    final storage = _Storage();
    storage.values[AppStore.key] = jsonEncode({
      'safetyAccepted': true,
      'appearance': 'light',
      'history': [
        {
          'title': '以前的训练',
          'at': '2026-10-19T12:00:00.000',
          'minutes': 5,
          'completed': 3,
          'total': 4,
        },
      ],
    });
    final store = AppStore(storage);
    await store.load();
    expect(store.history.single.sessionId, isNull);
    expect(store.sessionResults, isEmpty);

    await store.saveSession(_result());
    final restored = AppStore(storage);
    await restored.load();
    expect(restored.safetyAccepted, isTrue);
    expect(restored.appearance, 'light');
    expect(restored.history.map((h) => h.title), ['核心训练', '以前的训练']);
    expect(restored.history.last.sessionId, isNull);
    expect(restored.history.first.minutes, 2);
    expect(restored.history.first.completed, 1);
    expect(restored.history.first.at, _result().endedAt);
    expect(restored.sessionResults.single.toJson(), _result().toJson());
  });

  test(
    'same session upserts history and the complete result across reloads',
    () async {
      final storage = _Storage();
      final store = AppStore(storage);
      await store.saveSession(_result());
      await store.saveSession(_result(completed: 2));
      final restored = AppStore(storage);
      await restored.load();
      await restored.saveSession(_result(completed: 2));

      expect(restored.history, hasLength(1));
      expect(restored.history.single.completed, 2);
      expect(restored.sessionResults, hasLength(1));
      expect(
        restored.sessionResults.single.toJson(),
        _result(completed: 2).toJson(),
      );
      final persisted = AppStore(storage);
      await persisted.load();
      expect(persisted.history, hasLength(1));
      expect(persisted.sessionResults.single.full, isTrue);
    },
  );

  test(
    'failed storage leaves memory unchanged and SDK retry saves one result',
    () async {
      final storage = _Storage()..failures = 1;
      final store = AppStore(storage);
      var notifications = 0;
      store.addListener(() => notifications++);
      final saver = ResultSaver(store.saveSession);
      final result = _result();

      expect(await saver(result), isFalse);
      expect(saver.lastError, isA<StateError>());
      expect(store.history, isEmpty);
      expect(store.sessionResults, isEmpty);
      expect(storage.values, isEmpty);
      expect(notifications, 0);

      expect(await saver(result), isTrue);
      expect(await saver(result), isTrue);
      expect(store.history, hasLength(1));
      expect(store.sessionResults, hasLength(1));
      expect(notifications, 1);
      final restored = AppStore(storage);
      await restored.load();
      expect(restored.sessionResults.single.sessionId, result.sessionId);
    },
  );

  test(
    'concurrent completion and settings writes preserve all results',
    () async {
      final storage = _Storage();
      final gate = Completer<void>();
      final started = Completer<void>();
      storage
        ..nextWriteGate = gate
        ..writeStarted = started;
      final store = AppStore(storage);
      final first = store.saveSession(_result());
      await started.future;
      expect(store.history, isEmpty);
      expect(store.sessionResults, isEmpty);
      final second = store.saveSession(_result(id: 'session-two'));
      final duplicate = store.saveSession(_result(completed: 2));
      final settings = store.setAppearance('light');
      gate.complete();
      await Future.wait([first, second, duplicate, settings]);

      final restored = AppStore(storage);
      await restored.load();
      expect(restored.appearance, 'light');
      expect(restored.history.map((h) => h.sessionId), [
        'session-one',
        'session-two',
      ]);
      expect(restored.history.first.completed, 2);
      expect(restored.sessionResults, hasLength(2));
    },
  );

  test(
    'a failed queued save does not prevent another session or retry',
    () async {
      final storage = _Storage()..failures = 1;
      final store = AppStore(storage);
      final failed = expectLater(
        store.saveSession(_result()),
        throwsStateError,
      );
      final next = store.saveSession(_result(id: 'session-two'));
      await Future.wait([failed, next]);
      expect(store.sessionResults.single.sessionId, 'session-two');
      await store.saveSession(_result());
      final restored = AppStore(storage);
      await restored.load();
      expect(restored.sessionResults, hasLength(2));
      expect(restored.history, hasLength(2));
    },
  );

  test('full results outlive the thirty-entry history display limit', () async {
    final storage = _Storage();
    final store = AppStore(storage);
    for (var i = 0; i < 32; i++) {
      await store.saveSession(_result(id: 'session-$i'));
    }
    final restored = AppStore(storage);
    await restored.load();
    expect(restored.history, hasLength(30));
    expect(restored.sessionResults, hasLength(32));
    expect(restored.sessionResults.first.sessionId, 'session-0');
    expect(restored.sessionResults.last.discomfort.single.note, '换动作');
  });
}
