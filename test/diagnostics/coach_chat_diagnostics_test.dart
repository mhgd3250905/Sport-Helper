import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/coach_chat_diagnostics.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';

import '../app_flow_test.dart' show MemoryStorage;

const _restoreEvent = 'coach_chat.chat.restore.recovered';

Map<String, Object?> _fields(String encoded, String name) {
  final events = (jsonDecode(encoded) as Map)['events'] as List;
  final event = events.cast<Map>().singleWhere((row) => row['event'] == name);
  return Map<String, Object?>.from(event['fields'] as Map);
}

RuntimeLog _log(MemoryStorage storage, {List<String> secrets = const []}) =>
    RuntimeLog(
      enabled: true,
      storage: storage,
      secrets: secrets,
      encode: (request) async => encodeRuntimeLogSnapshot(request),
    );

Future<List<String>> _roundTrip(RuntimeLog log, MemoryStorage storage) async {
  final immediate = log.exportJson();
  await log.flush();
  final persisted = storage.data[RuntimeLog.storageKey]!;
  final restarted = _log(storage);
  await restarted.initialize();
  return [immediate, persisted, restarted.exportJson()];
}

void main() {
  late RuntimeLog previous;

  setUp(() => previous = RuntimeLog.instance);
  tearDown(() async {
    try {
      await RuntimeLog.instance.flush();
    } finally {
      RuntimeLog.instance = previous;
    }
  });

  test(
    'restore observer fields survive export, flush and log reload',
    () async {
      final storage = MemoryStorage();
      final log = _log(storage);
      RuntimeLog.instance = log;
      const expected = <String, Object?>{
        'stage': 'messages[2].plan.decode',
        'errorType': 'PlanDecodeError<messages[2]>',
        'message': 'messages[2] 计划恢复失败: blocks[0].items 缺少字段 / 使用旧档',
        'status': 'recovered with fallback',
        'reason': 'messages[2] rejected / schema 缺失',
      };

      CoachChatDiagnostics().observe('chat.restore.recovered', {
        ...expected,
        'arbitrary': 'UNRELATED_DETAIL_SENTINEL',
        'headers': {'Authorization': 'Bearer UNIT_PRIVATE_HEADER_SENTINEL'},
        'nested': {'messages': 'NOT_OBSERVER_FIELDS'},
      });
      final turnDetail = <String, Object?>{
        ...expected,
        'turnId': 'restore-roundtrip',
        'failureKind': 'restore',
        'contextRequests': [
          {'beforeBytes': 12345, 'afterBytes': 12345},
        ],
      };
      CoachChatDiagnostics().observe('chat.turn.result', turnDetail);

      for (final encoded in await _roundTrip(log, storage)) {
        expect(_fields(encoded, _restoreEvent), expected);
        expect(encoded, isNot(contains('UNRELATED_DETAIL_SENTINEL')));
        expect(encoded, isNot(contains('UNIT_PRIVATE_HEADER_SENTINEL')));
        expect(encoded, isNot(contains('Authorization')));
        expect(encoded, isNot(contains('NOT_OBSERVER_FIELDS')));
        final events = ((jsonDecode(encoded) as Map)['events'] as List)
            .cast<Map>();
        final event = events.singleWhere(
          (row) => row['event'] == _restoreEvent,
        );
        expect(event.containsKey('data'), isFalse);
        expect(_fields(encoded, 'coach_chat.chat.turn.result'), {
          ...expected,
          'kind': 'restore',
        });
        expect(
          events.singleWhere(
            (row) => row['event'] == 'coach_chat.chat.turn.result',
          )['data'],
          turnDetail,
        );
      }
    },
  );

  test(
    'only restore message is capped at 300 characters without token filtering',
    () async {
      final storage = MemoryStorage();
      final log = _log(storage);
      RuntimeLog.instance = log;
      const prefix = 'messages[2] 计划恢复失败: ';
      final padded =
          '$prefix${List.filled(298 - prefix.runes.length, '字').join()}';
      final kept = '$padded🧭中';
      final message = '$kept 后续内容不应保存';
      final expected = <String, Object?>{
        'stage': 'messages[2] / display restore',
        'errorType': 'FormatException<TrainingPlan>',
        'message': kept,
        'status': 'recovered / 历史显示',
        'reason': 'missing plan fields: messages[2]',
      };
      expect(message.runes.length, greaterThan(300));

      CoachChatDiagnostics().observe('chat.restore.recovered', {
        ...expected,
        'message': message,
      });

      for (final encoded in await _roundTrip(log, storage)) {
        final fields = _fields(encoded, _restoreEvent);
        expect(fields, expected);
        expect((fields['message'] as String).runes.length, 300);
        expect(fields['message'], endsWith('🧭中'));
      }
    },
  );

  test(
    'observer strings retain existing redaction and other events stay bounded',
    () async {
      const secret = 'UNIT_RESTORE_PRIVATE_VALUE';
      final storage = MemoryStorage();
      final log = _log(storage, secrets: [secret]);
      RuntimeLog.instance = log;
      CoachChatDiagnostics().observe('chat.restore.recovered', {
        'stage': 'messages[2] $secret',
        'errorType': 'Restore<$secret>',
        'message': 'messages[2] 中文 error $secret; Bearer UNIT_BEARER_VALUE',
        'status': 'recovered $secret',
        'reason': 'fallback $secret',
        'apiKey': 'UNIT_UNKNOWN_KEY_VALUE',
      });
      log.record(
        'storage.restore',
        fields: {
          'stage': 'messages[2]',
          'message': 'unrestricted ordinary event text',
          'status': 'recovered with spaces',
          'reason': 'messages[2] 缺失',
          'errorType': 'Restore<Map>',
          'count': 3,
        },
      );

      for (final encoded in await _roundTrip(log, storage)) {
        final fields = _fields(encoded, _restoreEvent);
        expect(fields, {
          'stage': 'messages[2] [REDACTED]',
          'errorType': 'Restore<[REDACTED]>',
          'message': 'messages[2] 中文 error [REDACTED]; Bearer [REDACTED]',
          'status': 'recovered [REDACTED]',
          'reason': 'fallback [REDACTED]',
        });
        expect(_fields(encoded, 'storage.restore'), {'count': 3});
        expect(encoded, isNot(contains(secret)));
        expect(encoded, isNot(contains('UNIT_BEARER_VALUE')));
        expect(encoded, isNot(contains('UNIT_UNKNOWN_KEY_VALUE')));
      }
    },
  );

  test(
    'redaction precedes the 300-character boundary in fields and turn data',
    () async {
      const secret = 'BOUNDARY_PRIVATE_MESSAGE_SECRET';
      final storage = MemoryStorage();
      final log = _log(storage, secrets: [secret]);
      RuntimeLog.instance = log;
      final prefix = List.filled(290, '文').join();
      final expected = '$prefix[REDACTED]';
      final detail = <String, Object?>{
        'stage': 'messages[2]',
        'errorType': 'FormatException',
        'message': '$prefix$secret trailing text',
        'status': 'recovered',
        'reason': 'display_only',
      };
      final diagnostics = CoachChatDiagnostics();
      diagnostics.observe('chat.restore.recovered', detail);
      diagnostics.observe('chat.turn.result', detail);

      for (final encoded in await _roundTrip(log, storage)) {
        expect(encoded, isNot(contains(secret)));
        expect(encoded, isNot(contains('BOUNDARY_P')));
        for (final event in [_restoreEvent, 'coach_chat.chat.turn.result']) {
          final message = _fields(encoded, event)['message'] as String;
          expect(message, expected);
          expect(message, endsWith('[REDACTED]'));
          expect(message.runes.length, lessThanOrEqualTo(300));
        }
        final turn = ((jsonDecode(encoded) as Map)['events'] as List)
            .cast<Map>()
            .singleWhere(
              (row) => row['event'] == 'coach_chat.chat.turn.result',
            );
        final message = (turn['data'] as Map)['message'] as String;
        expect(message, expected);
        expect(message, endsWith('[REDACTED]'));
        expect(message.runes.length, lessThanOrEqualTo(300));
      }
    },
  );
}
