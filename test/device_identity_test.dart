import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  int writes = 0;
  bool failWrite = false;
  Completer<void>? writeGate;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    final gate = writeGate;
    if (gate != null) await gate.future;
    if (failWrite) throw StateError('Storage unavailable');
    values[key] = value;
  }
}

void main() {
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  test('generates and persists a UUID v4 under its own storage key', () async {
    final storage = _Storage();
    final id = await DeviceIdentity(storage).loadOrCreate();
    expect(id, matches(uuidV4));
    expect(storage.values, {DeviceIdentity.key: id});
    expect(storage.writes, 1);
  });

  test(
    'reuses the persisted identity after restart without another write',
    () async {
      final storage = _Storage();
      final first = await DeviceIdentity(storage).loadOrCreate();
      final restarted = DeviceIdentity(storage);
      expect(await restarted.loadOrCreate(), first);
      expect(await restarted.loadOrCreate(), first);
      expect(storage.writes, 1);
    },
  );

  test(
    'concurrent callers wait for one durable write and share one UUID',
    () async {
      final gate = Completer<void>();
      final storage = _Storage()..writeGate = gate;
      final identity = DeviceIdentity(storage);
      final pending = List.generate(10, (_) => identity.loadOrCreate());
      var returned = false;
      unawaited(pending.first.then((_) => returned = true));
      await Future<void>.delayed(Duration.zero);
      expect(storage.writes, 1);
      expect(returned, isFalse);
      expect(storage.values, isEmpty);
      gate.complete();
      final ids = await Future.wait(pending);
      expect(ids.toSet(), hasLength(1));
      expect(ids.first, matches(uuidV4));
      expect(storage.values[DeviceIdentity.key], ids.first);
      expect(storage.writes, 1);
    },
  );

  test(
    'a failed write throws and retry never reuses an unpersisted identity',
    () async {
      final storage = _Storage()..failWrite = true;
      final identity = DeviceIdentity(storage);
      await expectLater(identity.loadOrCreate(), throwsStateError);
      expect(storage.values, isEmpty);
      storage.failWrite = false;
      final saved = await identity.loadOrCreate();
      expect(saved, matches(uuidV4));
      expect(storage.values[DeviceIdentity.key], saved);
      expect(storage.writes, 2);
      expect(await identity.loadOrCreate(), saved);
      expect(storage.writes, 2);
    },
  );

  test('invalid stored content is replaced with a persisted UUID v4', () async {
    for (final invalid in [
      '',
      'device-123',
      '00000000-0000-0000-0000-000000000000',
      'ea2c6891-654f-431b-a1f4-11a9a3e03bea\n',
    ]) {
      final storage = _Storage()..values[DeviceIdentity.key] = invalid;
      final id = await DeviceIdentity(storage).loadOrCreate();
      expect(id, matches(uuidV4));
      expect(storage.values[DeviceIdentity.key], id);
      expect(storage.writes, 1);
    }
  });

  test(
    'proxy config uses only Bearer authentication with the approved model',
    () async {
      final client = const AiCoachConfig(
        token: ' fixture-app-key ',
      ).createClient(deviceId: 'ea2c6891-654f-431b-a1f4-11a9a3e03bea');
      addTearDown(client.close);
      expect(client.config.baseUrl, 'https://ai.uuugk.win/v1');
      expect(client.model, 'deepseek-flash');
      expect(client.config.maxRetries, 0);
      expect(client.config.timeout, const Duration(seconds: 120));
      expect(client.config.maxTokens, 6000);
      final headers = await client.auth.headers();
      expect(headers, {'Authorization': 'Bearer fixture-app-key'});
      expect(
        headers.keys.map((k) => k.toLowerCase()),
        isNot(anyOf(contains('x-app-key'), contains('x-device-id'))),
      );
    },
  );

  test(
    'explicit build configuration preserves defaults and SDK budgets',
    () async {
      const configured = AiCoachConfig(
        token: 'fixture-token',
        endpoint: 'https://fixture.invalid/v1',
        modelName: 'fixture-model',
        authMode: 'bearer',
      );
      final client = configured.createClient(deviceId: 'fixture-device');
      addTearDown(client.close);
      expect(client.config.baseUrl, 'https://fixture.invalid/v1');
      expect(client.config.model, 'fixture-model');
      expect(await client.auth.headers(), {
        'Authorization': 'Bearer fixture-token',
      });
      expect(client.config.maxRetries, 0);
      expect(client.config.timeout, const Duration(seconds: 120));
      expect(const AiCoachConfig().endpoint, AiCoachConfig.baseUrl);
      expect(const AiCoachConfig().modelName, AiCoachConfig.model);
    },
  );
}
