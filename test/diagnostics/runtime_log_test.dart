import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';

class _Storage implements LocalStateStorage {
  String? value;
  bool fail = false;
  int writes = 0;
  Completer<void>? gate;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async {
    writes++;
    await gate?.future;
    if (fail) throw StateError('private exception with auth secret');
    this.value = value;
  }
}

List<dynamic> _events(RuntimeLog log) =>
    (jsonDecode(log.exportJson()) as Map)['events'] as List;

void main() {
  test(
    'production default is off and disabled log never accesses storage',
    () async {
      expect(RuntimeLog.buildEnabled, isFalse);
      final storage = _Storage()..fail = true;
      final log = RuntimeLog(enabled: false, storage: storage);
      await log.initialize();
      log.record('app.start');
      await log.flush();
      expect(storage.writes, 0);
      expect(log.entryCount, 0);
    },
  );

  test(
    'persist, restart and export retain safe correlated metadata only',
    () async {
      final storage = _Storage();
      final log = RuntimeLog(enabled: true, storage: storage);
      final operation = log.newOperation('chat');
      log.record(
        'ai.request_error',
        operation: operation,
        fields: {
          'httpStatus': 401,
          'reason': 'auth',
          'elapsedMs': 20,
          'inputChars': 83,
          'token': 'PRIVATE_KEY',
          'deviceId': 'private-device-uuid',
          'prompt': 'private health message',
          'reasoning': 'private reasoning',
          'errorType': 'raw error with PRIVATE_KEY',
          'model': {'nested': 'PRIVATE_KEY'},
          'source': 'http://host/private?key=PRIVATE_KEY',
      'code': 'https://privatehost',
      'kind': '/private/path',
        },
      );
      await log.flush();
      final restarted = RuntimeLog(enabled: true, storage: storage);
      await restarted.initialize();
      final events = _events(restarted);
      expect(events.single['operation'], operation);
      expect(events.single['fields'], {
        'httpStatus': 401,
        'reason': 'auth',
        'elapsedMs': 20,
        'inputChars': 83,
      });
      expect(restarted.exportJson(), isNot(contains('PRIVATE_KEY')));
      expect(restarted.exportJson(), isNot(contains('private')));
    },
  );

  test('rotation caps entry count and actual UTF-8 export size', () async {
    final log = RuntimeLog(enabled: true, maxEntries: 6, maxBytes: 3000);
    for (var i = 0; i < 100; i++) {
      log.record('training.heartbeat', fields: {'completed': i});
    }
    expect(log.entryCount, lessThanOrEqualTo(6));
    expect(log.entryCount, greaterThan(0));
    expect(utf8.encode(log.exportJson()).length, lessThanOrEqualTo(3000));
    expect(_events(log).last['fields']['completed'], 99);
  });

  test('entries older than seven days are dropped at restart', () async {
    var now = DateTime.utc(2026, 10, 1);
    final storage = _Storage();
    final log = RuntimeLog(enabled: true, storage: storage, clock: () => now);
    log.record('app.start');
    await log.flush();
    now = now.add(const Duration(days: 8));
    final next = RuntimeLog(enabled: true, storage: storage, clock: () => now);
    await next.initialize();
    expect(next.entryCount, 0);
  });

  test('writes serialize, coalesce bursts and keep newest event', () async {
    final storage = _Storage()..gate = Completer<void>();
    final log = RuntimeLog(enabled: true, storage: storage);
    log.record('app.start');
    for (var i = 0; i < 50; i++) {
      log.record('ai.progress', fields: {'step': i});
    }
    expect(storage.writes, 1);
    storage.gate!.complete();
    await log.flush();
    expect(storage.writes, 2);
    expect(
      (jsonDecode(storage.value!)['events'] as List).last['fields']['step'],
      49,
    );
  });

  test(
    'disk failure never escapes and export keeps unsaved events for retry',
    () async {
      final storage = _Storage()..fail = true;
      final log = RuntimeLog(enabled: true, storage: storage);
      log.record('app.start');
      await log.flush();
      expect(log.persistenceFailed, isTrue);
      expect(_events(log).length, 1);
      storage.fail = false;
      await log.flush();
      expect(log.persistenceFailed, isFalse);
      expect(storage.value, isNotNull);
      expect(log.exportJson(), isNot(contains('private exception')));
    },
  );

  test(
    'corrupt existing data does not block boot or later persistence',
    () async {
      final storage = _Storage()..value = '{broken';
      final log = RuntimeLog(enabled: true, storage: storage);
      await log.initialize();
      expect(log.persistenceFailed, isTrue);
      log.record('app.start');
      await log.flush();
      expect(log.persistenceFailed, isFalse);
      expect(jsonDecode(storage.value!)['schema'], 1);
    },
  );
}
