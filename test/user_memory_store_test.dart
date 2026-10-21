import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/user_memory_store.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('Storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('Storage unavailable');
    values[key] = value;
  }
}

final _remembered = [
  coach.MemoryEntry(
    coach.MemoryKind.level,
    '新手',
    at: DateTime.utc(2026, 10, 21),
  ),
  coach.MemoryEntry(
    coach.MemoryKind.equipment,
    '家里有哑铃',
    at: DateTime.utc(2026, 10, 21),
  ),
];

void main() {
  test(
    'memory entries round trip under a key separate from app state',
    () async {
      final storage = _Storage();
      final store = AppStore(storage);
      expect(await store.aiMemoryStore.load(), isEmpty);

      await store.aiMemoryStore.save(_remembered);
      await store.setAppearance('dark');
      expect(
        storage.values.keys,
        unorderedEquals([AppStore.key, LocalUserMemoryStore.key]),
      );
      expect(
        jsonDecode(storage.values[AppStore.key]!),
        isNot(contains('memory')),
      );

      final restarted = AppStore(storage);
      await restarted.load();
      expect(
        (await restarted.aiMemoryStore.load()).map((entry) => entry.toJson()),
        _remembered.map((entry) => entry.toJson()),
      );
      expect(restarted.appearance, 'dark');
    },
  );

  test(
    'memory defaults on; disabling survives restart and retains saved entries',
    () async {
      final storage = _Storage();
      final store = AppStore(storage);
      await store.load();
      expect(store.aiMemoryEnabled, isTrue);
      await store.aiMemoryStore.save(_remembered);
      await store.setAiMemoryEnabled(false);

      final restarted = AppStore(storage);
      await restarted.load();
      expect(restarted.aiMemoryEnabled, isFalse);
      expect(
        (await restarted.aiMemoryStore.load()).map((entry) => entry.text),
        ['新手', '家里有哑铃'],
      );
      await restarted.setAiMemoryEnabled(true);
      final enabled = AppStore(storage);
      await enabled.load();
      expect(enabled.aiMemoryEnabled, isTrue);
    },
  );

  test(
    'clearing entries leaves preference and existing app content intact',
    () async {
      final storage = _Storage();
      final store = AppStore(storage);
      await store.setAiMemoryEnabled(false);
      await store.setChatLog([
        {'id': 'old-chat', 'text': '对话仍保留'},
      ]);
      await store.aiMemoryStore.save(_remembered);
      await store.aiMemoryStore.save([]);

      final restarted = AppStore(storage);
      await restarted.load();
      expect(await restarted.aiMemoryStore.load(), isEmpty);
      expect(jsonDecode(storage.values[LocalUserMemoryStore.key]!), isEmpty);
      expect(restarted.aiMemoryEnabled, isFalse);
      expect(restarted.chatLog.single['text'], '对话仍保留');
    },
  );

  test('corrupt and malformed memory never becomes agent context', () async {
    final storage = _Storage();
    final memory = LocalUserMemoryStore(storage);
    for (final raw in ['invalid json', '{}', 'null']) {
      storage.values[LocalUserMemoryStore.key] = raw;
      expect(await memory.load(), isEmpty);
    }
    storage.values[LocalUserMemoryStore.key] = jsonEncode([
      null,
      'invalid',
      {'kind': 'unknown', 'text': 'skip'},
      {'kind': 'goal', 'text': '  '},
      _remembered
          .singleWhere((entry) => entry.kind == coach.MemoryKind.level)
          .toJson(),
    ]);
    expect((await memory.load()).single.text, '新手');
  });

  test(
    'I/O errors reach the caller and failed clears preserve existing entries',
    () async {
      final storage = _Storage();
      final memory = LocalUserMemoryStore(storage);
      await memory.save(_remembered);
      storage.failRead = true;
      await expectLater(memory.load(), throwsStateError);
      storage.failRead = false;
      storage.failWrite = true;
      await expectLater(memory.save([]), throwsStateError);
      expect((await memory.load()).map((entry) => entry.text), ['新手', '家里有哑铃']);
    },
  );

  test(
    'a failed setting save reports failure while stopping memory immediately',
    () async {
      final storage = _Storage()..failWrite = true;
      final store = AppStore(storage);
      await expectLater(store.setAiMemoryEnabled(false), throwsStateError);
      expect(store.aiMemoryEnabled, isFalse);
      storage.failWrite = false;
      await store.setAiMemoryEnabled(false);
      final restarted = AppStore(storage);
      await restarted.load();
      expect(restarted.aiMemoryEnabled, isFalse);
    },
  );
}
