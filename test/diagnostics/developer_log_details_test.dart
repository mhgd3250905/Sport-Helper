import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartfit/app/build_info.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/diagnostics/session_snapshot_archive.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../app_flow_test.dart' show MemoryStorage;
import '../support/coach_v2_fixtures.dart';

class _Archive implements SessionSnapshotArchive {
  final contents = <String>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<String?> save(String value) async {
    contents.add(value);
    if (gate != null) await gate!.future;
    if (fail) throw StateError('private archive error');
    return 'coach-session-${contents.length}.json';
  }
}

List<Map> _events(RuntimeLog log) =>
    ((jsonDecode(log.exportJson()) as Map)['events'] as List).cast<Map>();

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  test(
    'developer fields preserve user text and sourced params across restart',
    () async {
      final storage = MemoryStorage();
      final log = RuntimeLog(enabled: true, storage: storage);
      const text = '  拉伸一下臀部\n保留原话。  ';
      log.recordDeveloper('chat.user', data: {'text': text});
      log.recordDeveloper(
        'ai.tool.requested',
        data: {
          'name': 'set_params',
          'arguments': {
            'fields': {
              'scene': {
                'value': 'home',
                'source': 'derived',
                'quote': '拉伸一下臀部',
              },
            },
          },
        },
      );
      await log.flush();
      final next = RuntimeLog(enabled: true, storage: storage);
      await next.initialize();
      expect(_events(next)[0]['data']['text'], text);
      expect(_events(next)[1]['data']['arguments']['fields']['scene'], {
        'value': 'home',
        'source': 'derived',
        'quote': '拉伸一下臀部',
      });
    },
  );

  test(
    'credentials and all header objects are removed, including raw JSON',
    () async {
      final storage = MemoryStorage();
      final log = RuntimeLog(
        enabled: true,
        storage: storage,
        secrets: ['UNIT_ONLY_API_SECRET'],
      );
      final raw = jsonEncode({
        'headers': {'Authorization': 'Bearer other-secret'},
        'requestHeaders': {'X-Device-Id': 'device-header'},
        'fields': {
          'scene': {'value': 'home', 'source': 'user', 'quote': '在家'},
        },
        'api_key': 'nested-secret',
        'token': 'another-secret',
      });
      log.recordDeveloper(
        'ai.tool.requested',
        data: {
          'name': 'set_params',
          'argumentsRaw': raw,
          'arguments': jsonDecode(raw),
          'userText':
              'test UNIT_ONLY_API_SECRET Authorization: Bearer hidden-token',
        },
      );
      await log.flush();
      final exported = log.exportJson();
      for (final forbidden in [
        'UNIT_ONLY_API_SECRET',
        'other-secret',
        'device-header',
        'nested-secret',
        'another-secret',
        'hidden-token',
        'Authorization',
        'requestHeaders',
      ]) {
        expect(exported, isNot(contains(forbidden)));
        expect(storage.data[RuntimeLog.storageKey], isNot(contains(forbidden)));
      }
      expect(
        _events(log).single['data']['arguments']['fields']['scene']['quote'],
        '在家',
      );
      final next = RuntimeLog(
        enabled: true,
        storage: storage,
        secrets: ['UNIT_ONLY_API_SECRET'],
      );
      await next.initialize();
      expect(next.exportJson(), isNot(contains('other-secret')));
    },
  );

  test(
    'disabled diagnostics neither collect payloads nor create archive files',
    () async {
      final archive = _Archive();
      final storage = MemoryStorage();
      final log = RuntimeLog(
        enabled: false,
        storage: storage,
        snapshotArchive: archive,
      );
      log.recordDeveloper('chat.user', data: {'text': 'private user message'});
      await log.archiveSession({'private': 'snapshot'});
      await log.flush();
      expect(_events(log), isEmpty);
      expect(storage.data, isEmpty);
      expect(archive.contents, isEmpty);
    },
  );

  test('overflowing JSON numbers never interrupt developer logging', () {
    final log = RuntimeLog(enabled: true);
    log.recordDeveloper('chat.user', data: {'text': '{"v":1e999}'});
    expect(_events(log).single['data']['text'], '{"v":null}');
  });

  test('nested JSON strings remove credential and header objects', () {
    final log = RuntimeLog(enabled: true);
    log.recordDeveloper(
      'ai.tool.requested',
      data: {
        'argumentsRaw': jsonEncode(
          jsonEncode({
            'headers': {'X-App-Key': 'foreign-fixture-secret'},
            'quote': '在家',
          }),
        ),
      },
    );
    expect(log.exportJson(), isNot(contains('foreign-fixture-secret')));
    expect(log.exportJson(), isNot(contains('X-App-Key')));
    final raw = _events(log).single['data']['argumentsRaw'] as String;
    expect(jsonDecode(jsonDecode(raw) as String), {'quote': '在家'});
  });

  test('text authorization removes Basic credentials completely', () {
    final log = RuntimeLog(enabled: true);
    log.recordDeveloper(
      'chat.user',
      data: {'text': 'Authorization: Basic Zml4dHVyZS1vbmx5'},
    );
    expect(log.exportJson(), isNot(contains('Zml4dHVyZS1vbmx5')));
    expect(log.exportJson(), isNot(contains('Authorization:')));
  });

  test('UTF-8 detailed events respect the existing byte and entry limits', () {
    final log = RuntimeLog(enabled: true, maxEntries: 6, maxBytes: 3500);
    for (var i = 0; i < 30; i++) {
      log.recordDeveloper('chat.user', data: {'text': '训练内容' * 30, 'index': i});
    }
    expect(_events(log).length, inInclusiveRange(1, 6));
    expect(utf8.encode(log.exportJson()).length, lessThanOrEqualTo(3500));
    expect(_events(log).last['data']['index'], 29);
  });

  test(
    'export header and startup metadata share actual installed build identity',
    () async {
      await AppBuildInfo.initialize(
        load: () async => PackageInfo(
          appName: 'SmartFit',
          packageName: 'fixture',
          version: '0.8.7',
          buildNumber: '2040',
        ),
      );
      final log = RuntimeLog(enabled: true);
      log.record(
        'app.start',
        fields: {
          'version': AppBuildInfo.version,
          'versionName': AppBuildInfo.versionName,
          'buildNumber': AppBuildInfo.buildNumber,
        },
      );
      final decoded = jsonDecode(log.exportJson()) as Map;
      expect(decoded['version'], '0.8.7+2040');
      expect(decoded['versionName'], '0.8.7');
      expect(decoded['buildNumber'], '2040');
      expect(_events(log).single['fields']['version'], decoded['version']);
      expect(
        _events(log).single['fields']['buildNumber'],
        decoded['buildNumber'],
      );
    },
  );

  Future<(ChatController, AiChatEngine, coach.FakeLlmClient)> setup(
    RuntimeLog log,
    List<Object> script,
  ) async {
    final previous = RuntimeLog.instance;
    RuntimeLog.instance = log;
    final storage = MemoryStorage();
    final store = AppStore(storage);
    await store.acceptSafety(blocked: false);
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final engine = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: client,
    );
    final chat = ChatController(
      engine: engine,
      store: store,
      replyDelay: Duration.zero,
    )..start();
    addTearDown(() async {
      chat.dispose();
      engine.dispose();
      await log.flush();
      RuntimeLog.instance = previous;
    });
    return (chat, engine, client);
  }

  test(
    'real SDK tools, accepted params and raw user input reach only logs',
    () async {
      final log = RuntimeLog(enabled: true, snapshotArchive: _Archive());
      final (chat, _, _) = await setup(log, fixture.planTurn());
      const input = '  在家徒手10分钟拉伸\n';
      await chat.send(input);
      await log.flush();
      final events = _events(log);
      expect(
        events.singleWhere((e) => e['event'] == 'chat.user')['data']['text'],
        input,
      );
      final calls = events
          .where((e) => e['event'] == 'ai.tool.requested')
          .toList();
      expect(calls.any((e) => e['data']['name'] == 'start_task'), isTrue);
      expect(calls.any((e) => e['fields']['kind'] == 'unknown'), isFalse);
      final set = calls.singleWhere((e) => e['data']['name'] == 'set_params');
      expect(
        (set['data']['parameters'] as List).cast<Map>().singleWhere(
          (p) => p['name'] == 'scene',
        ),
        {'name': 'scene', 'value': 'home', 'source': 'user', 'quote': '在家'},
      );
      final accepted = events.where(
        (e) =>
            e['event'] == 'ai.agent.event' &&
            e['data']['params'] is Map &&
            (e['data']['params'] as Map).containsKey('scene'),
      );
      expect(accepted, isNotEmpty);
      expect(accepted.last['data']['params']['scene']['value'], 'home');
      expect(events.any((e) => e['event'] == 'ai.tool.result'), isTrue);
      expect(
        chat.messages
            .where((m) => !m.isUser)
            .any(
              (m) =>
                  m.text.contains('argumentsRaw') ||
                  m.text.contains('set_params'),
            ),
        isFalse,
      );
    },
  );

  test(
    'new conversation durably archives before reset and queues new input',
    () async {
      final archive = _Archive();
      final log = RuntimeLog(enabled: true, snapshotArchive: archive);
      final (chat, engine, client) = await setup(log, [
        ...fixture.planTurn(),
        const coach.LlmResponse(content: '你好。'),
      ]);
      await chat.send('在家徒手10分钟拉伸');
      final before = engine.conversation.exportSession().toJson();
      final calls = client.requests.length;
      archive.gate = Completer<void>();
      final reset = chat.newConversation();
      expect(jsonDecode(archive.contents.single), before);
      final queued = chat.send('你好');
      await Future<void>.delayed(Duration.zero);
      expect(client.requests.length, calls);
      archive.gate!.complete();
      await reset;
      await queued;
      expect(client.requests.length, calls + 1);
      expect(engine.agent.sessionState.userTurns.map((t) => t.text), ['你好']);
      expect(
        jsonDecode(archive.contents.single)['sessionState']['plans'],
        isNotEmpty,
      );
    },
  );

  test(
    'archive failure is diagnostic only and does not block new conversation',
    () async {
      final archive = _Archive()..fail = true;
      final log = RuntimeLog(enabled: true, snapshotArchive: archive);
      final (chat, engine, _) = await setup(log, [
        const coach.LlmResponse(content: '你好。'),
      ]);
      await chat.send('你好');
      await chat.newConversation();
      expect(engine.agent.sessionState.userTurns, isEmpty);
      expect(
        _events(log).any((e) => e['event'] == 'chat.session_archive_failed'),
        isTrue,
      );
      expect(
        chat.messages.any((m) => m.text.contains('private archive error')),
        isFalse,
      );
    },
  );
}
