import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test(
    'media timing stage and terminal fields survive restart and export',
    () async {
      final storage = _Storage();
      final log = RuntimeLog(enabled: true, storage: storage);
      final fields = <String, Object?>{
        'taskId': 'media.1',
        'entryId': 'training.1',
        'entry': 'guide_preview',
        'actionId': 's-figure4',
        'kind': 'video',
        'bytes': 211565,
        'receivedBytes': 211565,
        'phase': 'ready',
        'stage': 'verified',
        'elapsedMs': 140,
        'sinceEntryMs': 160,
        'queueDepth': 2,
        'activeSlots': 2,
        'baseIndex': 1,
        'retry': 0,
        'retries': 0,
        'result': 'ready',
        'source': 'network',
        'code': null,
        'queueMs': 20,
        'ttfbMs': 30,
        'downloadMs': 80,
        'verifyMs': 10,
        'enqueuedAt': '2026-11-07T10:00:00.000Z',
        'acquiredAt': '2026-11-07T10:00:00.020Z',
        'requestStartedAt': '2026-11-07T10:00:00.021Z',
        'firstByteAt': '2026-11-07T10:00:00.051Z',
        'downloadCompletedAt': '2026-11-07T10:00:00.131Z',
        'verifiedAt': '2026-11-07T10:00:00.141Z',
        'completedAt': '2026-11-07T10:00:00.160Z',
      };
      log.record(
        'media.timing',
        fields: {
          ...fields,
          'url': 'https://media.invalid/video?signature=PRIVATE',
          'headers': {'Authorization': 'PRIVATE'},
          'message': 'PRIVATE',
        },
      );
      await log.flush();
      final restored = RuntimeLog(enabled: true, storage: storage);
      await restored.initialize();
      final json = restored.exportJson();
      final event = (jsonDecode(json)['events'] as List).single;
      expect(event['fields'], fields);
      expect(json, isNot(contains('PRIVATE')));
      expect(json, isNot(contains('signature')));
    },
  );

  test(
    'timing timestamps are scoped and never accept arbitrary URL strings',
    () {
      final log = RuntimeLog(enabled: true);
      log.record(
        'media.timing.first_byte',
        fields: {
          'taskId': 'video.1',
          'firstByteAt': 'https://host/?token=PRIVATE',
          'entry': 'https://host/?token=PRIVATE',
          'sinceEntryMs': 50,
        },
      );
      log.record(
        'unrelated.event',
        fields: {
          'taskId': 'video.1',
          'sinceEntryMs': 50,
          'entry': 'guide_preview',
        },
      );
      final events = jsonDecode(log.exportJson())['events'] as List;
      expect(events[0]['fields'], {'taskId': 'video.1', 'sinceEntryMs': 50});
      expect(events[1]['fields'], isEmpty);
    },
  );
}
