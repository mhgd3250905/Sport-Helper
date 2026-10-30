import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/training_transition_activity.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';

class _Storage implements LocalStateStorage {
  final values = <String>[];
  bool fail = false;

  @override
  Future<String?> read(String key) async => values.lastOrNull;

  @override
  Future<void> write(String key, String value) async {
    // Automatic flush resumes while tester.pump is guarded, outside its zone.
    // Keep the assertion without invoking expect's unrelated async-scope guard.
    expectSync(key, RuntimeLog.storageKey);
    if (fail) throw StateError('private storage error');
    values.add(value);
  }
}

List<dynamic> _events(String encoded) => jsonDecode(encoded)['events'] as List;

Map<String, Object?> _encodeInDifferentIsolate(Map<String, Object?> request) =>
    {
      'encoded': encodeRuntimeLogSnapshot(request),
      'isolateName': Isolate.current.debugName,
    };

void main() {
  testWidgets('automatic bursts encode once after the caller yields', (
    tester,
  ) async {
    final storage = _Storage();
    var encodes = 0;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) async {
        encodes++;
        return encodeRuntimeLogSnapshot(request);
      },
    );
    for (var i = 0; i < 50; i++) {
      log.record('ai.progress', fields: {'step': i});
    }
    log.recordDeveloper('chat.user', data: {'text': 'training plan'});
    log.protectSecret('UNIT_UNUSED_SECRET');
    expect(encodes, 0);
    expect(storage.values, isEmpty);
    await tester.pump();
    expect(encodes, 1);
    expect(
      storage.values,
      hasLength(1),
      reason: jsonEncode(
        _events(log.exportJson())
            .where(
              (event) => event['event'] == 'diagnostics.storage_write_failed',
            )
            .map((event) => event['fields'])
            .toList(),
      ),
    );
    expect(_events(storage.values.single), hasLength(51));
    expect(_events(storage.values.single)[49]['fields']['step'], 49);
  });

  testWidgets('a pending encoder never blocks painting or log collection', (
    tester,
  ) async {
    final pending = Completer<String>();
    final storage = _Storage();
    Map<String, Object?>? captured;
    var encodes = 0;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) {
        if (++encodes == 1) {
          captured = request;
          return pending.future;
        }
        return Future.value(encodeRuntimeLogSnapshot(request));
      },
    );
    log.record('training.finished');
    await tester.pump();
    expect(encodes, 1);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('frame remains responsive'),
      ),
    );
    log.record('training.result.saved');
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('frame remains responsive'), findsOneWidget);
    expect(log.entryCount, 2);
    expect(storage.values, isEmpty);
    pending.complete(encodeRuntimeLogSnapshot(captured!));
    await tester.pump();
    expect(storage.values, hasLength(2));
    expect(_events(storage.values.last).map((e) => e['event']), [
      'training.finished',
      'training.result.saved',
    ]);
  });

  testWidgets('automatic writes wait for the transition without a timer', (
    tester,
  ) async {
    final release = TrainingTransitionActivity.instance.hold();
    addTearDown(release);
    final storage = _Storage();
    var encodes = 0;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) async {
        encodes++;
        return encodeRuntimeLogSnapshot(request);
      },
    );
    log.record('voice.speech.stop_requested');
    await tester.pump(const Duration(seconds: 2));
    expect(encodes, 0);
    expect(storage.values, isEmpty);
    release();
    await tester.pump();
    expect(encodes, 1);
    expect(storage.values, hasLength(1));
  });

  testWidgets('explicit flush bypasses an automatic transition wait', (
    tester,
  ) async {
    final release = TrainingTransitionActivity.instance.hold();
    addTearDown(release);
    final storage = _Storage();
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) async => encodeRuntimeLogSnapshot(request),
    );
    log.record('training.result.saved');
    await tester.pump();
    var completed = false;
    unawaited(log.flush().then((_) => completed = true));
    await tester.pump();
    expect(completed, isTrue);
    expect(TrainingTransitionActivity.instance.active, isTrue);
    expect(storage.values, hasLength(1));
    release();
    await tester.pump();
    expect(storage.values, hasLength(1));
  });

  testWidgets('new credentials discard an already-encoded stale snapshot', (
    tester,
  ) async {
    const secret = 'UNIT_NEW_CREDENTIAL';
    final pending = Completer<String>();
    final storage = _Storage();
    var encodes = 0;
    String? obsolete;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) {
        final encoded = encodeRuntimeLogSnapshot(request);
        if (++encodes == 1) {
          obsolete = encoded;
          return pending.future;
        }
        return Future.value(encoded);
      },
    );
    log.recordDeveloper('chat.user', data: {'text': 'value $secret'});
    await tester.pump();
    expect(obsolete, contains(secret));
    log.protectSecret(secret);
    log.record('training.result.saved');
    pending.complete(obsolete!);
    await tester.pump();
    expect(encodes, 2);
    expect(storage.values, hasLength(1));
    expect(storage.values.single, isNot(contains(secret)));
    expect(storage.values.single, contains('[REDACTED]'));
    expect(_events(storage.values.single), hasLength(2));
  });

  testWidgets('encoder errors retain events and allow explicit retry', (
    tester,
  ) async {
    final storage = _Storage();
    var fail = true;
    var encodes = 0;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) async {
        encodes++;
        if (fail) throw StateError('UNIT_PRIVATE_ENCODER_ERROR');
        return encodeRuntimeLogSnapshot(request);
      },
    );
    log.record('training.finished');
    await tester.pump();
    expect(encodes, 1);
    expect(log.persistenceFailed, isTrue);
    expect(storage.values, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(encodes, 1, reason: 'Failure logging must not create a retry loop.');
    fail = false;
    unawaited(log.flush());
    await tester.pump();
    expect(log.persistenceFailed, isFalse);
    expect(storage.values, hasLength(1));
    expect(_events(storage.values.single).map((e) => e['event']), [
      'training.finished',
      'diagnostics.storage_write_failed',
    ]);
    expect(
      storage.values.single,
      isNot(contains('UNIT_PRIVATE_ENCODER_ERROR')),
    );
  });

  testWidgets('a completion callback tail is persisted without a third event', (
    tester,
  ) async {
    final pending = Completer<String>();
    final storage = _Storage();
    Map<String, Object?>? captured;
    var encodes = 0;
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      encode: (request) {
        if (++encodes == 1) {
          captured = request;
          return pending.future;
        }
        return Future.value(encodeRuntimeLogSnapshot(request));
      },
    );
    log.record('training.finished');
    final writing = log.flush();
    // Register before the automatic task awaits writing: this callback runs
    // after _writing clears but before that task's finally clears its flag.
    unawaited(writing.then((_) => log.record('training.result.saved')));
    await tester.pump();
    expect(encodes, 1);
    expect(storage.values, isEmpty);
    pending.complete(encodeRuntimeLogSnapshot(captured!));
    await tester.pump();
    expect(encodes, 2);
    expect(storage.values, hasLength(2));
    expect(_events(storage.values.last).map((e) => e['event']), [
      'training.finished',
      'training.result.saved',
    ]);
    expect(log.persistenceFailed, isFalse);
  });

  test(
    'the encoder payload crosses a real isolate with redaction intact',
    () async {
      final storage = _Storage();
      const secret = 'UNIT_ISOLATE_CREDENTIAL';
      final log = RuntimeLog(
        enabled: true,
        storage: storage,
        secrets: [secret],
        encode: (request) async {
          final result = await compute(
            _encodeInDifferentIsolate,
            request,
            debugLabel: 'runtime-log-sendability-test',
          );
          expect(result['isolateName'], 'runtime-log-sendability-test');
          return result['encoded']! as String;
        },
      );
      log.recordDeveloper(
        'chat.user',
        data: {
          'text': 'private $secret',
          'authorization': 'Bearer UNIT_OTHER_SECRET',
        },
      );
      await log.flush();
      expect(storage.values.single, isNot(contains(secret)));
      expect(storage.values.single, isNot(contains('UNIT_OTHER_SECRET')));
      expect(jsonDecode(storage.values.single)['schema'], 1);
    },
  );

  test(
    'the default background encoder persists without capturing storage',
    () async {
      final storage = _Storage();
      final log = RuntimeLog(enabled: true, storage: storage);
      log.record('app.start');
      await log.flush();
      expect(storage.values, hasLength(1));
      expect(_events(storage.values.single).single['event'], 'app.start');
    },
  );
}
