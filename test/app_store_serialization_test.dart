import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show SessionResult, TrainingFeeling;

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  final written = <Map<String, dynamic>>[];
  int attempts = 0;
  int failures = 0;
  Completer<void>? firstWriteStarted;
  Completer<void>? releaseFirstWrite;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    attempts++;
    if (attempts == 1) {
      firstWriteStarted?.complete();
      await releaseFirstWrite?.future;
    }
    if (failures > 0) {
      failures--;
      throw StateError('durable write rejected');
    }
    values[key] = value;
    written.add(jsonDecode(value) as Map<String, dynamic>);
  }
}

SessionResult _receipt({TrainingFeeling? feeling}) => SessionResult(
  sessionId: 'serialization-session',
  planId: 'serialization-plan',
  planTitle: '本次训练',
  startedAt: DateTime.utc(2026, 10, 30, 1),
  endedAt: DateTime.utc(2026, 10, 30, 1, 2),
  activeSeconds: 120,
  endedEarly: true,
  completedExercises: 1,
  totalExercises: 2,
  items: const [],
  feeling: feeling,
);

List<Map<String, dynamic>> _serializationEvents(RuntimeLog log) => [
  for (final event in (jsonDecode(log.exportJson()) as Map)['events'] as List)
    if ((event as Map)['event'] == 'state.serialization.started')
      Map<String, dynamic>.from(event),
];

void main() {
  test(
    'large Coach snapshot uses worker and round trips complete content',
    () async {
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog(enabled: true);
      RuntimeLog.instance = log;
      addTearDown(() => RuntimeLog.instance = previousLog);
      final storage = _Storage();
      final store = AppStore(storage);
      addTearDown(store.dispose);
      final largeSnapshot = jsonEncode({
        'sdk': 'opaque',
        'content': List.filled(18000, '动作“说明”\\\n').join(),
      });
      final display = [
        {
          'id': 'card',
          'plan': {
            'actions': [
              {'id': 'third', 'seconds': 30},
            ],
          },
        },
      ];
      await store.setConversation(
        [
          for (var i = 0; i < 65; i++) {'id': '$i', 'text': '计划条目 $i'},
        ],
        sessionJson: largeSnapshot,
        sdkMessages: display,
      );
      final written = storage.written.single;
      expect(written['coachSessionJson'], largeSnapshot);
      expect(written['coachDisplay'], display);
      expect(written['chat'], hasLength(AppStore.chatLogLimit));
      expect((written['chat'] as List).first['id'], '5');
      expect(
        _serializationEvents(log).single['fields'],
        containsPair('kind', 'compute'),
      );
      final reloaded = AppStore(storage);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.coachSessionJson, largeSnapshot);
      expect(reloaded.coachDisplayMessages, display);
      expect(reloaded.chatLog, written['chat']);
    },
  );

  test(
    'small snapshot stays below strict bound without a worker roundtrip',
    () async {
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog(enabled: true);
      RuntimeLog.instance = log;
      addTearDown(() => RuntimeLog.instance = previousLog);
      final storage = _Storage();
      final store = AppStore(storage);
      addTearDown(store.dispose);
      await store.setAppearance('light');
      expect(storage.written.single['appearance'], 'light');
      final fields = _serializationEvents(log).single['fields'] as Map;
      expect(fields['kind'], 'inline_small');
      expect(fields['bytes'], lessThan(16 * 1024));
      expect(
        utf8.encode(storage.values[AppStore.key]!).length,
        lessThanOrEqualTo(fields['bytes'] as int),
      );
    },
  );

  test(
    'nested chat and display snapshots detach before an encoder await',
    () async {
      final storage = _Storage();
      final encodingStarted = Completer<void>();
      final releaseEncoding = Completer<void>();
      final snapshots = <Map<String, Object?>>[];
      final store = AppStore(
        storage,
        stateEncoder: (snapshot) async {
          snapshots.add(snapshot);
          if (snapshots.length == 1) {
            encodingStarted.complete();
            await releaseEncoding.future;
          }
          return jsonEncode(snapshot);
        },
      );
      addTearDown(store.dispose);
      final nestedChat = <String, dynamic>{'seconds': 30};
      final nestedAction = <String, dynamic>{'id': 'old'};
      final first = store.setConversation(
        [
          {'id': 'chat', 'detail': nestedChat},
        ],
        sessionJson: 'snapshot-v1',
        sdkMessages: [
          {
            'id': 'sdk',
            'actions': [nestedAction],
          },
        ],
      );
      await encodingStarted.future;
      expect(
        () => snapshots.single['appearance'] = 'changed',
        throwsUnsupportedError,
      );
      final frozenChat = snapshots.single['chat'] as List;
      expect(() => frozenChat.add('bad'), throwsUnsupportedError);
      expect(
        () => (frozenChat.first as Map)['detail'] = 'bad',
        throwsUnsupportedError,
      );
      nestedChat['seconds'] = 5;
      nestedAction['id'] = 'new';
      store.coachSessionJson = 'snapshot-v2';
      final second = store.setAppearance('light');
      releaseEncoding.complete();
      await Future.wait([first, second]);
      expect(storage.written, hasLength(2));
      expect(storage.written.first['coachSessionJson'], 'snapshot-v1');
      expect(
        ((storage.written.first['chat'] as List).single['detail']
            as Map)['seconds'],
        30,
      );
      expect(
        (((storage.written.first['coachDisplay'] as List).single['actions']
                    as List)
                .single
            as Map)['id'],
        'old',
      );
      expect(storage.written.last['coachSessionJson'], 'snapshot-v2');
      expect(storage.written.last['appearance'], 'light');
      expect(
        ((storage.written.last['chat'] as List).single['detail']
            as Map)['seconds'],
        5,
      );
    },
  );

  test(
    'pending training write commits once then queued settings merge it',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final storage = _Storage()
        ..firstWriteStarted = started
        ..releaseFirstWrite = release;
      final store = AppStore(storage);
      addTearDown(store.dispose);
      final saving = store.saveSession(_receipt());
      await started.future;
      expect(store.history, isEmpty);
      expect(store.sessionResults, isEmpty);
      final settings = store.setAppearance('light');
      release.complete();
      await Future.wait([saving, settings]);
      expect(store.history.single.sessionId, 'serialization-session');
      expect(store.sessionResults, hasLength(1));
      expect(storage.written, hasLength(2));
      expect(storage.written.last['appearance'], 'light');
      expect(storage.written.last['sessions'], hasLength(1));
      final reloaded = AppStore(storage);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.appearance, 'light');
      expect(reloaded.history, hasLength(1));
      expect(reloaded.sessionResults.single.toJson(), _receipt().toJson());
    },
  );

  test(
    'failed durable write leaves no receipt and retry preserves chosen feeling',
    () async {
      final storage = _Storage()..failures = 1;
      final store = AppStore(storage);
      addTearDown(store.dispose);
      await expectLater(store.saveSession(_receipt()), throwsStateError);
      expect(store.history, isEmpty);
      expect(store.sessionResults, isEmpty);
      expect(storage.values, isEmpty);
      await store.saveSession(_receipt(feeling: TrainingFeeling.justRight));
      await store.saveSession(_receipt());
      expect(storage.attempts, 3);
      expect(store.history, hasLength(1));
      expect(store.sessionResults.single.feeling, TrainingFeeling.justRight);
      final reloaded = AppStore(storage);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.history.single.feeling, TrainingFeeling.justRight);
      expect(reloaded.sessionResults.single.feeling, TrainingFeeling.justRight);
    },
  );

  test(
    'encoder failure reaches training retry without poisoning later writes',
    () async {
      final storage = _Storage();
      var encodes = 0;
      final store = AppStore(
        storage,
        stateEncoder: (snapshot) async {
          if (++encodes == 1) throw StateError('worker unavailable');
          return jsonEncode(snapshot);
        },
      );
      addTearDown(store.dispose);
      await expectLater(store.saveSession(_receipt()), throwsStateError);
      expect(storage.attempts, 0);
      expect(store.sessionResults, isEmpty);
      await store.saveSession(_receipt());
      expect(storage.attempts, 1);
      expect(store.history, hasLength(1));
      expect(store.sessionResults, hasLength(1));
    },
  );
}
