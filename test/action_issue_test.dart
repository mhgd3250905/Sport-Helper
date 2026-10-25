import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/action_issue.dart';
import 'package:smartfit/diagnostics/action_issue_export.dart';
import 'package:smartfit/diagnostics/action_issue_store.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  Completer<void>? gate;
  var failures = 0;
  var reads = 0;
  var writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    final pending = gate;
    gate = null;
    if (pending != null) await pending.future;
    if (failures > 0) {
      failures--;
      throw StateError('write failed');
    }
    values[key] = value;
  }
}

class _Exporter implements ActionIssueExporter {
  final pending = Completer<ActionIssueSavedFile>();
  int calls = 0;
  String? filename;
  String? contents;

  @override
  Future<ActionIssueSavedFile> saveToDownloads({
    required String filename,
    required String contents,
  }) {
    calls++;
    this.filename = filename;
    this.contents = contents;
    return pending.future;
  }
}

ActionIssueContext _capture() => ActionIssueContext(
  actionId: 'test-action-01',
  revision: 'fixture-r2',
  videoSeconds: 12.345,
  capturedAt: DateTime.utc(2026, 10, 25, 8, 9, 10),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = AndroidActionIssueExporter.channel;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'record round-trip preserves real video time, metadata and tag order',
    () {
      final issue = ActionIssue(
        id: 'test-issue',
        capture: _capture(),
        tags: [ActionIssueTag.naming, ActionIssueTag.pose, ActionIssueTag.pose],
        note: '  抬腿时\n脚部穿模  ',
      );
      final json = issue.toJson();
      expect(json['videoSeconds'], 12.345);
      expect(json['capturedAt'], '2026-10-25T08:09:10.000Z');
      expect(json['tags'], ['pose', 'naming']);
      expect(json['note'], '抬腿时 脚部穿模');
      expect(
        ActionIssue.fromJson(
          jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        ).toJson(),
        json,
      );
    },
  );

  test('unavailable position and revision stay null with explicit reasons', () {
    final capture = ActionIssueContext(
      actionId: 'test-action-01',
      revision: null,
      revisionUnavailableReason: 'manifest_has_no_revision',
      videoSeconds: null,
      videoPositionUnavailableReason:
          ActionIssueVideoUnavailableReason.notReady,
    );
    final json = capture.toJson();
    expect(json['revision'], isNull);
    expect(json['revisionUnavailableReason'], 'manifest_has_no_revision');
    expect(json['videoSeconds'], isNull);
    expect(json['videoPositionUnavailableReason'], 'not_ready');
    expect(
      () => ActionIssueContext(
        actionId: 'test-action-01',
        revision: 'fixture-r2',
        videoSeconds: null,
      ),
      throwsArgumentError,
    );
  });

  test(
    'records survive restart under a separate key from app settings',
    () async {
      final storage = _Storage()
        ..values['smartfit.state.v1'] = 'existing state';
      final store = LocalActionIssueStore(storage, enabled: true);
      final saved = await store.add(_capture(), note: '镜头切掉了手部');
      final restored = LocalActionIssueStore(storage, enabled: true);
      await restored.load();
      expect(restored.records.single.toJson(), saved.toJson());
      expect(storage.values['smartfit.state.v1'], 'existing state');
      expect(restored.records.single.tags, isEmpty);
      expect(() => restored.records.clear(), throwsUnsupportedError);
    },
  );

  test(
    'queued saves publish only durable records and retain both entries',
    () async {
      final gate = Completer<void>();
      final storage = _Storage()..gate = gate;
      final store = LocalActionIssueStore(storage, enabled: true);
      final first = store.add(_capture(), tags: [ActionIssueTag.pose]);
      final second = store.add(_capture(), tags: [ActionIssueTag.highlight]);
      await Future<void>.delayed(Duration.zero);
      expect(store.count, 0);
      expect(storage.writes, 1);
      gate.complete();
      final saved = await Future.wait([first, second]);
      expect(store.count, 2);
      expect(saved[0].id, isNot(saved[1].id));
      final restarted = LocalActionIssueStore(storage, enabled: true);
      await restarted.load();
      expect(restarted.count, 2);
    },
  );

  test(
    'write failure is visible and a retry cannot lose older records',
    () async {
      final storage = _Storage();
      final store = LocalActionIssueStore(storage, enabled: true);
      await store.add(_capture(), note: '已有标记');
      storage.failures = 1;
      await expectLater(store.add(_capture(), note: '新增标记'), throwsStateError);
      expect(store.count, 1);
      await store.add(_capture(), note: '新增标记');
      expect(store.records.map((issue) => issue.note), ['已有标记', '新增标记']);
    },
  );

  test(
    'disabled review never reads, writes or invokes native export',
    () async {
      final storage = _Storage();
      final store = LocalActionIssueStore(storage, enabled: false);
      final exporter = _Exporter();
      await store.load();
      await expectLater(store.add(_capture()), throwsStateError);
      await expectLater(
        ActionIssueExportService(
          store: store,
          exporter: exporter,
        ).saveToDownloads(),
        throwsStateError,
      );
      expect(storage.reads, 0);
      expect(storage.writes, 0);
      expect(exporter.calls, 0);
    },
  );

  test(
    'native protocol saves JSON directly and awaits actual publication',
    () async {
      final write = Completer<Map<String, Object?>>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'saveToDownloads');
        expect(call.arguments, {
          'filename': 'SmartFit-action-issues-test.json',
          'contents': '{"issues":[]}',
          'mimeType': 'application/json',
        });
        return write.future;
      });
      var saved = false;
      final result = const AndroidActionIssueExporter()
          .saveToDownloads(
            filename: 'SmartFit-action-issues-test.json',
            contents: '{"issues":[]}',
          )
          .then((value) {
            saved = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(saved, isFalse);
      write.complete({
        'uri': 'content://media/external/downloads/123',
        'displayName': 'SmartFit-action-issues-test.json',
      });
      expect(
        (await result).uri.toString(),
        'content://media/external/downloads/123',
      );
    },
  );

  test('invalid native result and write errors never report saved', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => <String, Object?>{},
    );
    await expectLater(
      const AndroidActionIssueExporter().saveToDownloads(
        filename: 'a.json',
        contents: '{}',
      ),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'write_failed');
    });
    await expectLater(
      const AndroidActionIssueExporter().saveToDownloads(
        filename: 'a.json',
        contents: '{}',
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test(
    'export snapshots all records once and keeps local data intact',
    () async {
      final store = LocalActionIssueStore(_Storage(), enabled: true);
      await store.add(
        _capture(),
        tags: [ActionIssueTag.framing],
        note: '手部被裁切',
      );
      final exporter = _Exporter();
      final service = ActionIssueExportService(
        store: store,
        exporter: exporter,
        clock: () => DateTime.utc(2026, 10, 25, 10, 11, 12),
      );
      final first = service.saveToDownloads();
      final repeated = service.saveToDownloads();
      expect(repeated, same(first));
      await Future<void>.delayed(Duration.zero);
      expect(exporter.calls, 1);
      expect(
        exporter.filename,
        'SmartFit-action-issues-20261025T101112000Z.json',
      );
      final report = jsonDecode(exporter.contents!) as Map<String, dynamic>;
      expect(report['schemaVersion'], 1);
      expect((report['issues'] as List).single, store.records.single.toJson());
      exporter.pending.complete(
        ActionIssueSavedFile(
          uri: Uri.parse('content://media/external/downloads/1'),
          displayName: exporter.filename!,
        ),
      );
      await first;
      expect(store.count, 1);
    },
  );
}
