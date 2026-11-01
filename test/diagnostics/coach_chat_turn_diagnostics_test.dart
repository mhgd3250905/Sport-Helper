import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/coach_chat_diagnostics.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../app_flow_test.dart' show MemoryStorage;
import '../support/chat_sdk_support.dart';
import '../support/coach_v2_fixtures.dart';

List<Map> _turns(RuntimeLog log) =>
    ((jsonDecode(log.exportJson()) as Map)['events'] as List)
        .cast<Map>()
        .where((event) => event['event'] == 'coach_chat.chat.turn.result')
        .toList();

class _OpenAiClient extends coach.OpenAiCompatibleClient {
  _OpenAiClient()
    : super(
        config: coach.LlmConfig.ugkWorker.copyWith(
          model: 'diagnostics-fixture',
          extraBody: const {'fixtureEncoder': true},
        ),
        auth: coach.ApiKeyAuth('UNIT_ONLY_GATEWAY_SECRET'),
      );

  final requests = <coach.LlmRequest>[];
  final cancellations = <coach.CancelToken?>[];
  final response = const coach.LlmResponse(content: 'Forwarded.');
  int closes = 0;

  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    requests.add(request);
    cancellations.add(cancel);
    return response;
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

void main() {
  late RuntimeLog previous;

  setUp(() {
    previous = RuntimeLog.instance;
    RuntimeLog.instance = RuntimeLog(enabled: true);
  });

  tearDown(() async {
    await RuntimeLog.instance.flush();
    RuntimeLog.instance = previous;
  });

  test('SDK turn byte diagnostics and errors survive restart', () async {
    final storage = MemoryStorage();
    final log = RuntimeLog(enabled: true, storage: storage);
    RuntimeLog.instance = log;
    final diagnostics = CoachChatDiagnostics();
    final details = <Map<String, Object?>>[
      {
        'turnId': 'success',
        'status': 'ok',
        'errorType': null,
        'contextRequests': [
          {
            'epoch': 3,
            'beforeBytes': 70123,
            'afterBytes': 24321,
            'softLimitBytes': 51200,
            'hardLimitBytes': 65536,
            'tailStateBytes': 4567,
            'completedTurnsFolded': 8,
            'receiptBodiesFolded': 2,
            'ledgerTurnsCompacted': 8,
            'restoredMessagesFolded': 10,
            'ledgerBytes': 1234,
            'seedBytes': 567,
            'folded': true,
            'measurement': 'caller-supplied',
            'fitsHardLimit': true,
          },
        ],
      },
      {
        'turnId': 'failure',
        'status': 'error',
        'errorType': 'AgentContextBudgetExceeded',
        'failureKind': 'context',
        'contextRequests': [
          {'beforeBytes': 90000, 'afterBytes': 70000, 'fitsHardLimit': false},
        ],
      },
      {
        'turnId': 'limit',
        'status': 'limitReached',
        'errorType': null,
        'failureKind': 'conversationLimit',
        'contextRequests': <Map<String, Object?>>[],
      },
    ];
    for (final detail in details) {
      diagnostics.observe('chat.turn.result', detail);
    }
    await log.flush();

    final restarted = RuntimeLog(enabled: true, storage: storage);
    await restarted.initialize();
    final turns = _turns(restarted);
    expect(turns.map((event) => event['data']), details);
    expect((turns.first['data'] as Map).containsKey('errorType'), isTrue);
    expect(turns.first['data']['errorType'], isNull);
    expect(turns[1]['fields'], {
      'status': 'error',
      'errorType': 'AgentContextBudgetExceeded',
      'kind': 'context',
    });
    expect(turns.last['fields'], {
      'status': 'limitReached',
      'kind': 'conversationLimit',
    });
    expect((turns.last['data'] as Map).containsKey('errorType'), isTrue);
    expect(turns.last['data']['errorType'], isNull);
  });

  test('turn persistence applies the existing secret sanitizer', () async {
    final storage = MemoryStorage();
    final log = RuntimeLog(
      enabled: true,
      storage: storage,
      secrets: const ['UNIT_ONLY_TURN_SECRET'],
    );
    RuntimeLog.instance = log;
    CoachChatDiagnostics().observe('chat.turn.result', <String, Object?>{
      'turnId': 'sanitized',
      'status': 'error',
      'errorType': 'AgentRequestFailed',
      'failureKind': 'authentication',
      'contextRequests': [
        {'beforeBytes': 12345, 'afterBytes': 12345, 'fitsHardLimit': true},
      ],
      'headers': {'Authorization': 'Bearer OTHER_PRIVATE_SECRET'},
      'diagnostic': 'UNIT_ONLY_TURN_SECRET',
    });
    await log.flush();

    final restarted = RuntimeLog(enabled: true, storage: storage);
    await restarted.initialize();
    for (final encoded in [
      log.exportJson(),
      restarted.exportJson(),
      storage.data[RuntimeLog.storageKey]!,
    ]) {
      expect(encoded, isNot(contains('UNIT_ONLY_TURN_SECRET')));
      expect(encoded, isNot(contains('OTHER_PRIVATE_SECRET')));
      expect(encoded, isNot(contains('Authorization')));
    }
    final detail = _turns(restarted).single['data'] as Map;
    expect(detail['failureKind'], 'authentication');
    expect((detail['contextRequests'] as List).single['afterBytes'], 12345);
    expect(detail['diagnostic'], '[REDACTED]');
  });

  test('each SDK turn logs the exact bytes from the observed client', () async {
    final fixture = await CoachV2Fixtures.load();
    final store = AppStore(MemoryStorage());
    await store.acceptSafety(blocked: false);
    final client = _OpenAiClient();
    final chat = fakeHostChat(sdkChatServices(store, fixture), client);
    addTearDown(() async {
      await chat.close();
      chat.dispose();
      store.dispose();
      client.close();
    });
    expect((await chat.start()).ok, isTrue);
    for (final input in ['hello', 'continue']) {
      expect((await chat.send(input))?.status, coach.TurnStatus.ok);
    }

    final turns = _turns(RuntimeLog.instance);
    expect(turns, hasLength(2));
    expect(client.requests, hasLength(2));
    expect(turns.map((event) => event['data']['turnId']).toSet(), hasLength(2));
    for (var index = 0; index < turns.length; index++) {
      final detail = turns[index]['data'] as Map;
      expect(detail['status'], 'ok');
      expect(detail.containsKey('errorType'), isTrue);
      expect(detail['errorType'], isNull);
      final request = (detail['contextRequests'] as List).single as Map;
      expect(request['beforeBytes'], isPositive);
      expect(request['afterBytes'], isPositive);
      expect(request['fitsHardLimit'], isTrue);
      expect(request['measurement'], 'caller-supplied');
      expect(
        request['afterBytes'],
        utf8
            .encode(jsonEncode(client.buildBody(client.requests[index])))
            .length,
      );
    }
  });

  test('observation preserves the concrete encoder and owned lease', () async {
    final inner = _OpenAiClient();
    addTearDown(() {
      if (inner.closes == 0) inner.close();
    });
    var releases = 0;
    void release() {
      releases++;
      inner.close();
    }

    final gateway = CoachChatDiagnostics().observeGateway(
      CoachGatewayBinding(
        create: () => CoachClientLease.owned(inner, release: release),
      ),
    );
    final lease = await gateway.create();
    expect(lease.client, isA<coach.OpenAiCompatibleClient>());
    final client = lease.client as coach.OpenAiCompatibleClient;
    const request = coach.LlmRequest(
      messages: [coach.LlmMessage.user('Encoded text.')],
      maxTokens: 321,
    );
    final cancel = coach.CancelToken();
    expect(client.config, same(inner.config));
    expect(client.auth, same(inner.auth));
    expect(client.buildBody(request), inner.buildBody(request));
    expect(client.buildBody(request)['fixtureEncoder'], isTrue);
    expect(
      await client.complete(request, cancel: cancel),
      same(inner.response),
    );
    expect(inner.requests.single, same(request));
    expect(inner.cancellations.single, same(cancel));
    expect(lease.release, same(release));
    await lease.release!();
    expect(releases, 1);
    expect(inner.closes, 1);
  });
}
