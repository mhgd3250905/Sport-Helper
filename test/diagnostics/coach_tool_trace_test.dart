import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/coach_tool_trace.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../support/coach_v2_fixtures.dart';

List<Map<String, dynamic>> _events(RuntimeLog log, String event) => [
  for (final row in (jsonDecode(log.exportJson()) as Map)['events'] as List)
    if ((row as Map)['event'] == event) Map<String, dynamic>.from(row),
];

List<Map<String, dynamic>> _data(RuntimeLog log, String event) => [
  for (final row in _events(log, event))
    Map<String, dynamic>.from(row['data'] as Map),
];

coach.LlmToolCall _call(String id, String name, Map<String, Object?> args) =>
    coach.LlmToolCall(id: id, name: name, arguments: jsonEncode(args));

List<coach.LlmMessage> _receipt(coach.LlmToolCall call, Object result) => [
  coach.LlmMessage.assistant('', toolCalls: [call]),
  coach.LlmMessage.tool(call.id, jsonEncode(result)),
];

class _Client implements coach.LlmClient {
  _Client(this.inner, this.trace);
  final coach.LlmClient inner;
  final CoachToolTrace trace;
  int calls = 0;
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    trace.observeMessages(request.messages);
    final response = await inner.complete(request, cancel: cancel);
    trace.observeResponse(response, step: ++calls, attempt: calls);
    return response;
  }
}

void main() {
  test(
    'new SDK tool names and complete sourced parameters remain original',
    () {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      final fields = {
        'scene': {'value': 'home', 'source': 'derived', 'quote': '拉伸一下臀部'},
        'equipment': {'value': <String>[], 'source': 'default'},
        'minutes': {'value': 15, 'source': 'user', 'quote': '15 分钟'},
      };
      final call = _call('original-call', 'set_params', {'fields': fields});
      trace.observeResponse(
        coach.LlmResponse(
          content: 'DO_NOT_LOG_ASSISTANT_CONTENT',
          reasoning: 'DO_NOT_LOG_REASONING',
          toolCalls: [call],
        ),
        step: 4,
        attempt: 5,
      );
      final event = _events(log, 'ai.tool.requested').single;
      final data = _data(log, 'ai.tool.requested').single;
      expect(event['operation'], 'chat-test');
      expect((event['fields'] as Map)['kind'], 'set_params');
      expect(data['name'], 'set_params');
      expect(data['callId'], 'original-call');
      expect(data['argumentsRaw'], call.arguments);
      expect((data['arguments'] as Map)['fields'], fields);
      expect((data['parameters'] as List).first, {
        'name': 'scene',
        ...fields['scene']! as Map,
      });
      expect(
        _events(
          log,
          'ai.tool.requested',
        ).map((e) => (e['fields'] as Map)['kind']),
        isNot(contains('unknown')),
      );
      expect(log.exportJson(), isNot(contains('DO_NOT_LOG_')));
    },
  );

  test(
    'observed receipts preserve failure and skipped-after-error summaries',
    () {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      final first = _call('first', 'start_task', {'type': 'invalid'});
      final second = _call('second', 'set_params', {'fields': {}});
      trace.observeResponse(
        coach.LlmResponse(content: '', toolCalls: [first, second]),
      );
      final messages = [
        coach.LlmMessage.assistant('', toolCalls: [first, second]),
        const coach.LlmMessage.tool(
          'first',
          '{"ok":false,"code":"invalid_task_type","fix":"choose a task"}',
        ),
        const coach.LlmMessage.tool(
          'second',
          '{"ok":false,"code":"skipped_after_error"}',
        ),
      ];
      trace.observeMessages(messages);
      trace.observeMessages(messages);
      trace.finish(history: messages, status: 'error');
      final results = _data(log, 'ai.tool.result');
      expect(results, hasLength(2));
      expect(results.map((e) => e['receiptAvailable']), everyElement(isTrue));
      expect((results[0]['summary'] as Map)['code'], 'invalid_task_type');
      expect((results[1]['summary'] as Map)['code'], 'skipped_after_error');
    },
  );

  test(
    'reused call IDs and repeated protocol history do not cross-associate',
    () {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      final first = _call('reused', 'set_params', {
        'fields': {
          'minutes': {'value': 20},
        },
      });
      final second = _call('reused', 'set_params', {
        'fields': {
          'minutes': {'value': 10},
        },
      });
      final firstMessages = _receipt(first, {
        'ok': true,
        'params': {
          'minutes': {'value': 20, 'source': 'user', 'quote': '20分钟'},
        },
      });
      trace.observeResponse(coach.LlmResponse(content: '', toolCalls: [first]));
      trace.observeMessages(firstMessages);
      trace.observeResponse(
        coach.LlmResponse(content: '', toolCalls: [second]),
      );
      final all = [
        ...firstMessages,
        ..._receipt(second, {
          'ok': true,
          'params': {
            'minutes': {'value': 10, 'source': 'user', 'quote': '10分钟'},
          },
        }),
      ];
      trace.observeMessages(all);
      trace.observeMessages(all);
      trace.finish(history: all, status: 'ok');
      final results = _data(log, 'ai.tool.result');
      expect(results, hasLength(2));
      expect(results.map((r) => r['batch']), [1, 2]);
      expect((results[0]['summary'] as Map)['parameters'], [
        {'name': 'minutes', 'value': 20, 'source': 'user', 'quote': '20分钟'},
      ]);
      expect((results[1]['summary'] as Map)['parameters'], [
        {'name': 'minutes', 'value': 10, 'source': 'user', 'quote': '10分钟'},
      ]);
    },
  );

  test(
    'identical IDs and arguments from cloned complete history are separate calls',
    () {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      final first = _call('same', 'read', {'path': 'same.md'});
      final firstHistory = _receipt(
        _call('same', 'read', {'path': 'same.md'}),
        {'ok': true},
      );
      trace.observeResponse(coach.LlmResponse(content: '', toolCalls: [first]));
      trace.observeMessages(firstHistory);
      final second = _call('same', 'read', {'path': 'same.md'});
      trace.observeResponse(
        coach.LlmResponse(content: '', toolCalls: [second]),
      );
      final full = [
        ...firstHistory,
        ..._receipt(_call('same', 'read', {'path': 'same.md'}), {
          'ok': false,
          'code': 'second',
        }),
      ];
      trace.observeMessages(full);
      trace.finish(history: full, status: 'ok');
      final results = _data(log, 'ai.tool.result');
      expect(results, hasLength(2));
      expect((results[1]['summary'] as Map)['code'], 'second');
    },
  );

  test(
    'cancelled unobserved tools never acquire an invented successful receipt',
    () {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      trace.observeResponse(
        coach.LlmResponse(
          content: '',
          toolCalls: [
            _call('cancel', 'set_params', {'fields': {}}),
          ],
        ),
      );
      trace.finish(status: 'cancelled');
      trace.finish(status: 'ok');
      trace.observeResponse(
        coach.LlmResponse(content: '', toolCalls: [_call('late', 'read', {})]),
      );
      final result = _data(log, 'ai.tool.result').single;
      expect(result['receiptAvailable'], isFalse);
      expect(result['reason'], 'cancelled_without_observed_receipt');
      expect(result['summary'], {'turnStatus': 'cancelled'});
      expect(_data(log, 'ai.tool.requested'), hasLength(1));
    },
  );

  test('disabled diagnostic collector performs no protocol capture', () {
    final log = RuntimeLog(enabled: false);
    final trace = CoachToolTrace(log, operation: 'chat-test');
    final call = _call('disabled', 'set_params', {'fields': {}});
    trace.observeResponse(coach.LlmResponse(content: '', toolCalls: [call]));
    trace.observeMessages(_receipt(call, {'ok': true}));
    trace.finish(status: 'ok');
    expect(_events(log, 'ai.tool.requested'), isEmpty);
    expect(_events(log, 'ai.tool.result'), isEmpty);
  });

  group('actual SDK public protocol', () {
    late CoachV2Fixtures fixture;
    setUpAll(() async => fixture = await CoachV2Fixtures.load());

    test('failed and skipped SDK tools retain their actual receipts', () async {
      final log = RuntimeLog(enabled: true);
      final trace = CoachToolTrace(log, operation: 'chat-test');
      final client = _Client(
        coach.FakeLlmClient([
          CoachV2Fixtures.batch([
            _call('invalid', 'start_task', {'type': 'invalid'}),
            _call('skipped', 'set_params', {'fields': {}}),
          ]),
          CoachV2Fixtures.batch([
            _call('start', 'start_task', {'type': 'plan'}),
            _call('ask', 'ask_user', {
              'question': '在哪儿训练？',
              'mode': 'choice',
              'options': ['家里', '办公室'],
            }),
          ]),
        ], latency: Duration.zero),
        trace,
      );
      final agent = coach.CoachAgent(
        client: client,
        profile: fixture.profile,
        catalog: () => fixture.catalog,
      );
      addTearDown(agent.dispose);
      final result = await agent.send('安排训练');
      trace.finish(history: agent.history, result: result);
      expect(result.question, isNotNull);
      final results = _data(log, 'ai.tool.result');
      final failed = results.singleWhere((r) => r['callId'] == 'invalid');
      final skipped = results.singleWhere((r) => r['callId'] == 'skipped');
      expect(failed['receiptAvailable'], isTrue);
      expect((failed['summary'] as Map)['ok'], isFalse);
      expect((failed['summary'] as Map)['code'], 'invalid_task_type');
      expect(skipped['receiptAvailable'], isTrue);
      expect((skipped['summary'] as Map)['code'], 'skipped_after_error');
      expect(results, hasLength(4));
    });

    test(
      'plan intermediate receipts are observed; terminal card is turn-only evidence',
      () async {
        final log = RuntimeLog(enabled: true);
        final trace = CoachToolTrace(log, operation: 'chat-test');
        final client = _Client(
          coach.FakeLlmClient(fixture.planTurn(), latency: Duration.zero),
          trace,
        );
        final agent = coach.CoachAgent(
          client: client,
          profile: fixture.profile,
          catalog: () => fixture.catalog,
        );
        addTearDown(agent.dispose);
        final result = await agent.send('在家徒手10分钟拉伸');
        trace.finish(history: agent.history, result: result);
        expect(result.plan, isNotNull);
        final params = _data(
          log,
          'ai.tool.requested',
        ).singleWhere((r) => r['name'] == 'set_params');
        expect(
          params['parameters'],
          contains(
            equals({
              'name': 'scene',
              'value': 'home',
              'source': 'user',
              'quote': '在家',
            }),
          ),
        );
        final results = _data(log, 'ai.tool.result');
        expect(
          results.singleWhere(
            (r) => r['name'] == 'set_params',
          )['receiptAvailable'],
          isTrue,
        );
        final terminal = results.singleWhere((r) => r['name'] == 'show_plan');
        expect(terminal['source'], 'sdk_turn_result');
        expect(terminal['receiptAvailable'], isFalse);
        expect((terminal['summary'] as Map)['hasPlan'], isTrue);
        expect((terminal['summary'] as Map).containsKey('ok'), isFalse);
        expect(results, hasLength(_data(log, 'ai.tool.requested').length));
      },
    );

    test(
      'single terminal batch retains original arguments and clearly marks missing receipts',
      () async {
        final log = RuntimeLog(enabled: true);
        final trace = CoachToolTrace(log, operation: 'chat-test');
        final client = _Client(
          coach.FakeLlmClient(
            fixture.recommendationTurn(),
            latency: Duration.zero,
          ),
          trace,
        );
        final agent = coach.CoachAgent(
          client: client,
          profile: fixture.profile,
          catalog: () => fixture.catalog,
        );
        addTearDown(agent.dispose);
        final result = await agent.send('推荐拉伸动作');
        trace.finish(history: agent.history, result: result);
        expect(result.actions, isNotNull);
        final requests = _data(log, 'ai.tool.requested');
        final results = _data(log, 'ai.tool.result');
        expect(results, hasLength(requests.length));
        expect(
          results.map((r) => r['receiptAvailable']),
          everyElement(isFalse),
        );
        expect(
          requests.map((r) => r['name']),
          containsAll([
            'start_task',
            'set_params',
            'search_actions',
            'show_actions',
          ]),
        );
        expect(
          results.every((r) => !(r['summary'] as Map).containsKey('ok')),
          isTrue,
        );
      },
    );

    test(
      'ask_user terminal batch receipts are visible in SDK committed history',
      () async {
        final log = RuntimeLog(enabled: true);
        final trace = CoachToolTrace(log, operation: 'chat-test');
        final client = _Client(
          coach.FakeLlmClient([
            CoachV2Fixtures.batch([
              _call('start', 'start_task', {'type': 'plan'}),
              _call('ask', 'ask_user', {
                'question': '在哪儿训练？',
                'mode': 'choice',
                'options': ['家里', '办公室'],
              }),
            ]),
          ], latency: Duration.zero),
          trace,
        );
        final agent = coach.CoachAgent(
          client: client,
          profile: fixture.profile,
          catalog: () => fixture.catalog,
        );
        addTearDown(agent.dispose);
        final result = await agent.send('安排训练');
        trace.finish(history: agent.history, result: result);
        expect(result.question, isNotNull);
        final results = _data(log, 'ai.tool.result');
        expect(results, hasLength(2));
        expect(results.map((r) => r['source']), everyElement('history'));
        expect(results.map((r) => r['receiptAvailable']), everyElement(isTrue));
      },
    );
  });
}
