import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/domain/session.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// A queued provider response may arrive after cancellation.
class _LateClient implements coach.LlmClient {
  final started = Completer<void>();
  final late = Completer<coach.LlmResponse>();
  final requests = <coach.LlmRequest>[];
  coach.CancelToken? token;
  @override
  String get model => 'late-test-model';
  @override
  coach.Pricing? get pricing => null;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) {
    requests.add(request);
    token = cancel;
    if (requests.length == 1) {
      started.complete();
      return late.future;
    }
    return Future.value(const coach.LlmResponse(content: '新的回复'));
  }
}

/// Exercises the SDK OpenAI tool-call wire parser and HTTP cancellation.
class _Gateway {
  _Gateway(this.server);
  final HttpServer server;
  final bodies = <Map<String, dynamic>>[];
  final sockets = <Socket>[];
  final requestStarted = Completer<void>();
  final aborted = Completer<void>();

  static Future<_Gateway> start(
    List<coach.LlmResponse> responses, {
    bool hold = false,
    int status = HttpStatus.ok,
  }) async {
    final gateway = _Gateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen((request) async {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      gateway.bodies.add(body);
      if (!gateway.requestStarted.isCompleted) {
        gateway.requestStarted.complete();
      }
      if (status != HttpStatus.ok) {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {'message': 'test quota exceeded'},
          }),
        );
        await request.response.close();
        return;
      }
      if (hold) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        gateway.sockets.add(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!gateway.aborted.isCompleted) gateway.aborted.complete();
          },
          onError: (Object _) {
            if (!gateway.aborted.isCompleted) gateway.aborted.complete();
          },
        );
        return;
      }
      final response = responses[gateway.bodies.length - 1];
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'loopback-test',
          'choices': [
            {
              'message': {
                'content': response.content,
                if (response.toolCalls.isNotEmpty)
                  'tool_calls': [
                    for (final call in response.toolCalls) call.toJson(),
                  ],
                'reasoning_content': '仅供模型内部推理，不能显示',
              },
              'finish_reason': response.toolCalls.isEmpty
                  ? 'stop'
                  : 'tool_calls',
            },
          ],
          'usage': {'prompt_tokens': 100, 'completion_tokens': 20},
        }),
      );
      await request.response.close();
    });
    return gateway;
  }

  coach.OpenAiCompatibleClient client() => coach.OpenAiCompatibleClient(
    config: coach.LlmConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'loopback-test',
      timeout: const Duration(seconds: 2),
      maxRetries: 0,
    ),
  );

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close(force: true);
  }
}

void main() {
  final library = loadLibrary();
  final packs = loadPacksSync();
  final catalog = const coach.DrillPackAdapter().build(
    version: 'smartfit-test-assets',
    packs: {for (final pack in packs.exercises) pack.id: pack.json},
  );
  late coach.CoachProfile profile;

  setUpAll(() {
    profile = coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    );
  });

  RuleChatEngine local() => RuleChatEngine(
    lib: library,
    templates: TemplatePlanGenerator(lib: library, catalog: loadCatalog()),
  );

  AiChatEngine engine(
    coach.LlmClient client, {
    Duration? deadline,
    coach.UserMemoryStore? memoryStore,
    bool enableUserMemory = true,
  }) {
    final result = AiChatEngine(
      local: local(),
      catalog: catalog,
      profile: profile,
      client: client,
      turnTimeout: deadline ?? const Duration(seconds: 1230),
      memoryStore: memoryStore,
      enableUserMemory: enableUserMemory,
    );
    addTearDown(result.dispose);
    return result;
  }

  TrainingPlan plan({
    String id = 'model-plan-one',
    List<String> ids = const ['h-calf-raise'],
    String scene = 'home',
    int minutes = 10,
    int level = 1,
    Set<String> avoid = const {},
  }) => TrainingPlan(
    id: id,
    source: 'ai',
    title: 'AI 徒手训练',
    summary: '按已确认条件编排。',
    goal: 'fullbody',
    scene: scene,
    equipment: const [],
    level: level,
    targetMinutes: minutes,
    avoid: avoid,
    blocks: [
      PlanBlock(
        id: 'main',
        name: '主训练',
        type: BlockType.main,
        rounds: 1,
        restBetweenRoundsSeconds: 0,
        items: [
          for (final id in ids)
            PlanItem(
              exerciseId: id,
              mode: library.tryGet(id)?.dose.mode ?? DoseMode.reps,
              sets: 1,
              reps: library.tryGet(id)?.dose.mode == DoseMode.time ? null : 10,
              workSeconds: library.tryGet(id)?.dose.mode == DoseMode.time
                  ? 30
                  : null,
              perSide: library.tryGet(id)?.unilateral ?? false,
              restSeconds: 10,
            ),
        ],
      ),
    ],
  );

  coach.LlmResponse tool(
    String name,
    Map<String, Object?> arguments, {
    String text = '按你的条件排好了。',
  }) => coach.LlmResponse(
    content: text,
    toolCalls: [
      coach.LlmToolCall(
        id: 'call-test',
        name: name,
        arguments: jsonEncode(arguments),
      ),
    ],
  );

  coach.LlmResponse planResponse({TrainingPlan? value, String? text}) => tool(
    coach.CoachTools.showPlan,
    (value ?? plan()).toJson(),
    text: text ?? '按你的条件排好了。',
  );

  coach.LlmResponse actionsResponse({
    List<String> ids = const ['h-calf-raise'],
    String text = '先看看这些动作的做法。',
  }) => tool(coach.CoachTools.showActions, {
    'items': [
      for (final id in ids) {'actionId': id, 'note': '保持自然呼吸。'},
    ],
  }, text: text);

  String texts(ChatReply reply) => reply.messages.map((m) => m.text).join('\n');
  TrainingPlan? replyPlan(ChatReply reply) =>
      reply.messages.map((m) => m.plan).whereType<TrainingPlan>().firstOrNull;
  String requestText(coach.LlmRequest request) =>
      request.messages.map((m) => jsonEncode(m.toJson())).join('\n');

  void expectLocalPreserved(ChatReply actual, ChatReply expected) {
    expect(actual.state.pending.toString(), expected.state.pending.toString());
    expect(actual.state.asked, expected.state.asked);
    expect(actual.state.safetyBlocked, expected.state.safetyBlocked);
    expect(actual.suggestions, expected.suggestions);
    expect(actual.action, expected.action);
    for (final message in expected.messages) {
      expect(texts(actual), contains(message.text));
      expect(
        actual.messages.expand((m) => m.options).map((o) => o.toJson()),
        containsAll(message.options.map((o) => o.toJson())),
      );
    }
  }

  test(
    'plain SDK text reaches bubbles without inventing cards or App commands',
    () async {
      final client = coach.FakeLlmClient([
        '动作慢一点，保持自然呼吸。',
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('训练时怎么呼吸更舒服？', const ChatState());
      expect(texts(reply), '动作慢一点，保持自然呼吸。');
      expect(reply.aiTurn, isTrue);
      expect(replyPlan(reply), isNull);
      expect(reply.messages.every((m) => m.actions == null), isTrue);
      expect(reply.action, isNull);
      expect(ai.lastResult?.status, coach.TurnStatus.ok);
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      expect(ai.session.turnCount, 1);
    },
  );

  test('wire show_actions and show_plan accept only SDK gate values', () async {
    final gateway = await _Gateway.start([actionsResponse(), planResponse()]);
    addTearDown(gateway.close);
    final ai = engine(gateway.client());
    final first = await ai.reply('给我看提踵动作', const ChatState());
    final actions = first.messages.map((m) => m.actions).nonNulls.single;
    expect(actions, isA<coach.ValidatedActions>());
    expect(identical(actions, ai.lastResult!.actions), isTrue);
    expect(actions.items.single.id, 'h-calf-raise');
    expect(actions.items.single.note, '保持自然呼吸。');
    expect(replyPlan(first), isNull);

    final second = await ai.reply('在家 10 分钟练全身，徒手', first.state);
    final selected = replyPlan(second)!;
    expect(ai.lastResult!.plan, isA<coach.ValidatedPlan>());
    expect(selected.exerciseIds, ai.lastResult!.plan!.plan.exerciseIds);
    expect(selected.source, 'ai');
    expect(
      PlanValidator(library).validate(selected, second.state.request),
      isEmpty,
    );
    expect(texts(first) + texts(second), isNot(contains('仅供模型内部推理')));
    expect(texts(second), isNot(contains('"tool_calls"')));
    expect(gateway.bodies, hasLength(2));
    for (final body in gateway.bodies) {
      expect(body['tool_choice'], 'auto');
      expect(body.containsKey('response_format'), isFalse);
      expect(
        (body['tools'] as List).map((t) => (t as Map)['function']['name']),
        containsAll(['show_actions', 'show_plan']),
      );
    }
    final history = gateway.bodies.last['messages'] as List;
    expect(history.where((m) => m['role'] == 'tool'), isNotEmpty);
    final shown =
        history.where((m) => m['role'] == 'tool').single['content'] as String;
    expect(jsonDecode(shown), {'ok': true, 'shown': true});

    final phases = SessionBuilder(library).phases(selected);
    final session = SessionEngine(phases);
    session.update(phases.fold<double>(0, (n, p) => n + p.seconds) + 1);
    expect(session.done, isTrue);
    expect(session.completedExercises, selected.items.length);
    final storage = _Storage();
    await AppStore(storage).savePlan(selected);
    final reloaded = AppStore(storage);
    await reloaded.load();
    expect(reloaded.savedPlans.single.plan.toJson(), selected.toJson());
  });

  test(
    'wire agent reads skills, checks a plan and delivers one typed card with per-step usage',
    () async {
      const hidden = 'INTERMEDIATE-SKILL-NOTES-MUST-NOT-RENDER';
      final gateway = await _Gateway.start([
        tool('read', {'path': 'action-library/SKILL.md'}, text: hidden),
        tool('check_plan', plan().toJson(), text: hidden),
        planResponse(text: '按条件排好了，可以开始。'),
        const coach.LlmResponse(content: '下一轮正常回复。'),
      ]);
      addTearDown(gateway.close);
      final ai = engine(gateway.client());
      final events = <coach.AgentEvent>[];
      final subscription = ai.agent.events.listen(events.add);
      addTearDown(subscription.cancel);

      final reply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      final result = ai.lastResult!;
      expect(result.status, coach.TurnStatus.ok);
      expect(result.plan, isA<coach.ValidatedPlan>());
      expect(result.steps, 3);
      expect(result.reads, ['action-library/SKILL.md']);
      expect(result.submissions, 1);
      expect(result.resubmits, 0);
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      expect(result.records.map((r) => r.outcome), [
        coach.CallOutcome.toolStep,
        coach.CallOutcome.toolStep,
        coach.CallOutcome.passed,
      ]);
      expect(result.records.map((r) => r.turnOutcome).toSet(), {
        coach.TurnOutcome.model,
      });
      expect(result.usage.promptTokens, 300);
      expect(result.usage.completionTokens, 60);
      expect(
        ai.usage.records.map((r) => r.id),
        result.records.map((r) => r.id),
      );
      expect(
        result.records.every((r) => r.promptVersion.startsWith('agent-v1-')),
        isTrue,
      );
      expect(reply.messages, hasLength(1));
      expect(texts(reply), '按条件排好了，可以开始。');
      expect(texts(reply), isNot(contains(hidden)));
      expect(replyPlan(reply)!.exerciseIds, {'h-calf-raise'});
      expect(events.map((e) => e.kind), [
        coach.AgentEventKind.thinking,
        coach.AgentEventKind.reading,
        coach.AgentEventKind.thinking,
        coach.AgentEventKind.checking,
        coach.AgentEventKind.thinking,
        coach.AgentEventKind.done,
      ]);
      expect(events.last.status, coach.TurnStatus.ok);
      expect(events.map((e) => e.turnId).toSet(), {result.turnId});

      final secondRequest = gateway.bodies[1];
      expect(
        (secondRequest['messages'] as List).last['content'],
        contains('action-library'),
      );
      final checkResult =
          jsonDecode(
                (gateway.bodies[2]['messages'] as List).last['content']
                    as String,
              )
              as Map;
      expect(checkResult['ok'], isTrue);
      expect(checkResult['estimatedMinutes'], isA<num>());
      expect(checkResult['targetMinutes'], 10);
      expect(
        (gateway.bodies.first['tools'] as List).map(
          (t) => (t as Map)['function']['name'],
        ),
        containsAll(['read', 'ls', 'check_plan', 'show_actions', 'show_plan']),
      );

      final history = jsonEncode(
        ai.agent.history.map((m) => m.toJson()).toList(),
      );
      expect(history, contains('show_plan'));
      expect(history, isNot(contains(hidden)));
      expect(history, isNot(contains('action-library/SKILL.md')));
      expect(history, isNot(contains('check_plan')));
      await ai.reply('下一轮的问题', reply.state);
      final nextPrompt = jsonEncode(gateway.bodies.last['messages']);
      expect(nextPrompt, contains('按条件排好了，可以开始'));
      expect(nextPrompt, isNot(contains(hidden)));
      expect(gateway.bodies, hasLength(4));
    },
  );

  test(
    'check_plan errors are private tool feedback and do not count as a rejected delivery',
    () async {
      final invalid = plan(ids: ['unknown-drill']);
      final client = coach.FakeLlmClient([
        tool('check_plan', invalid.toJson(), text: 'CHECK-FAILED-PRIVATE'),
        tool('read', {'path': 'action-library/index/scene/home.md'}),
        tool('check_plan', plan().toJson()),
        planResponse(),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      expect(ai.lastResult!.status, coach.TurnStatus.ok);
      expect(ai.lastResult!.steps, 4);
      expect(ai.lastResult!.submissions, 1);
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      final feedback =
          jsonDecode(client.requests[1].messages.last.content) as Map;
      expect(feedback['ok'], isFalse);
      expect(jsonEncode(feedback['errors']), contains('unknown_exercise'));
      expect(replyPlan(reply)!.exerciseIds, {'h-calf-raise'});
      expect(texts(reply), isNot(contains('CHECK-FAILED-PRIVATE')));
      expect(texts(reply), isNot(contains('unknown-drill')));
    },
  );

  test('default ten-step limit returns a labelled local fallback', () async {
    final client = coach.FakeLlmClient([
      for (var i = 0; i < 10; i++)
        tool('read', {'path': 'action-library/SKILL.md'}, text: 'STEP-PRIVATE'),
    ], latency: Duration.zero);
    final ai = engine(client);
    final reply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
    expect(ai.agent.maxSteps, 10);
    expect(client.requests, hasLength(10));
    expect(ai.lastResult!.steps, 10);
    expect(ai.lastResult!.error, isA<coach.AgentStepLimitExceeded>());
    expect(ai.lastOutcome, coach.TurnOutcome.fallback);
    expect(ai.lastResult!.records, hasLength(10));
    expect(texts(reply), contains('预设方案'));
    expect(texts(reply), isNot(contains('STEP-PRIVATE')));
    expect(replyPlan(reply), isNotNull);
  });

  test('default turn deadline covers all ten HTTP step budgets', () {
    final ai = AiChatEngine(
      local: local(),
      catalog: catalog,
      profile: profile,
      client: coach.FakeLlmClient([], latency: Duration.zero),
    );
    addTearDown(ai.dispose);
    expect(ai.agent.maxSteps, 10);
    expect(ai.turnTimeout, greaterThan(const Duration(seconds: 1200)));
  });

  test(
    'enabled memory commits after a successful turn and enters the next plan request',
    () async {
      final memory = coach.InMemoryUserMemoryStore();
      final client = coach.FakeLlmClient([
        tool('remember', {'kind': 'level', 'text': '用户是新手'}),
        tool('remember', {'kind': 'equipment', 'text': '家里有哑铃'}),
        '记下了：新手，家里有哑铃。',
        planResponse(),
      ], latency: Duration.zero);
      final ai = engine(client, memoryStore: memory);
      final remembered = await ai.reply('我是新手，家里有哑铃', const ChatState());
      await Future<void>.delayed(Duration.zero);
      expect(texts(remembered), contains('记下了'));
      expect(memory.entries.map((m) => m.kind), [
        coach.MemoryKind.level,
        coach.MemoryKind.equipment,
      ]);
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      expect(ai.lastResult!.steps, 3);
      final planned = await ai.reply('在家 10 分钟练全身', remembered.state);
      expect(replyPlan(planned), isNotNull);
      final system = client.requests.last.messages.first.content;
      expect(system, contains('用户是新手'));
      expect(system, contains('家里有哑铃'));
      expect(
        client.requests.last.tools.map((t) => t.name),
        containsAll(['remember', 'forget']),
      );
      final history = jsonEncode(
        ai.agent.history.map((m) => m.toJson()).toList(),
      );
      expect(history, isNot(contains('"name":"remember"')));
    },
  );

  test(
    'memory disabled from startup omits stored facts, skills and memory tools',
    () async {
      const privateFact = 'STORED-ONLY-MEMORY-SENTINEL';
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(
          coach.MemoryKind.preference,
          privateFact,
          at: DateTime.utc(2026),
        ),
      ]);
      final client = coach.FakeLlmClient([
        tool('remember', {'kind': 'goal', 'text': '不应被保存的目标'}),
        '好的，按本次条件来。',
      ], latency: Duration.zero);
      final ai = engine(client, memoryStore: memory, enableUserMemory: false);
      final reply = await ai.reply('给我一点训练建议', const ChatState());
      expect(texts(reply), '好的，按本次条件来。');
      for (final request in client.requests) {
        expect(requestText(request), isNot(contains(privateFact)));
        expect(
          request.messages.first.content,
          isNot(contains('user-memory/SKILL.md')),
        );
        expect(
          request.tools.map((t) => t.name),
          isNot(anyOf(contains('remember'), contains('forget'))),
        );
      }
      expect(client.requests.last.messages.last.content, contains('没有工具'));
      await Future<void>.delayed(Duration.zero);
      expect(memory.entries.map((m) => m.text), [privateFact]);
    },
  );

  test(
    'clearMemory removes durable facts and the next system summary',
    () async {
      const privateFact = 'CLEAR-MEMORY-SENTINEL';
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(
          coach.MemoryKind.preference,
          privateFact,
          at: DateTime.utc(2026),
        ),
      ]);
      final client = coach.FakeLlmClient([
        '先聊一下。',
        '已经清除了。',
      ], latency: Duration.zero);
      final ai = engine(client, memoryStore: memory);
      await ai.reply('先聊训练', const ChatState());
      expect(
        client.requests.first.messages.first.content,
        contains(privateFact),
      );
      await ai.clearMemory();
      expect(memory.entries, isEmpty);
      await ai.reply('再聊训练', const ChatState());
      expect(
        client.requests.last.messages.first.content,
        isNot(contains(privateFact)),
      );
      expect(await ai.agent.memory(), isEmpty);
    },
  );

  test(
    'runtime memory toggle keeps the conversation and suppresses stored facts in subsequent requests',
    () async {
      const privateFact = 'RUNTIME-STORED-ONLY-MEMORY-SENTINEL';
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(
          coach.MemoryKind.preference,
          privateFact,
          at: DateTime.utc(2026),
        ),
      ]);
      final client = coach.FakeLlmClient([
        '请告诉我本次训练条件。',
        planResponse(),
        planResponse(),
        '欢迎继续训练。',
      ], latency: Duration.zero);
      final ai = engine(client, memoryStore: memory);
      await ai.reply('聊一聊训练', const ChatState());
      expect(ai.enableUserMemory, isTrue);
      expect(
        client.requests.first.messages.first.content,
        contains(privateFact),
      );

      ai.enableUserMemory = false;
      expect(ai.enableUserMemory, isFalse);
      expect(ai.agent.history, isNotEmpty);
      await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      expect(requestText(client.requests[1]), contains('请告诉我本次训练条件'));
      expect(requestText(client.requests[1]), isNot(contains(privateFact)));
      expect(
        client.requests[1].tools.map((t) => t.name),
        isNot(anyOf(contains('remember'), contains('forget'))),
      );

      ai.reset();
      await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      expect(requestText(client.requests[2]), isNot(contains(privateFact)));
      expect(requestText(client.requests[2]), isNot(contains('请告诉我本次训练条件')));
      expect(memory.entries.map((e) => e.text), [privateFact]);

      ai.enableUserMemory = true;
      ai.reset();
      await ai.reply('聊一聊训练', const ChatState());
      expect(
        client.requests.last.messages.first.content,
        contains(privateFact),
      );
      expect(
        client.requests.last.tools.map((t) => t.name),
        containsAll(['remember', 'forget']),
      );
    },
  );

  test(
    'cancelling a multistep turn suppresses late output, events and staged memory writes',
    () async {
      final memory = coach.InMemoryUserMemoryStore();
      final started = Completer<void>();
      final late = Completer<Object>();
      final client = coach.FakeLlmClient([
        tool('remember', {'kind': 'equipment', 'text': '家里有哑铃'}),
        (coach.LlmRequest _) {
          started.complete();
          return late.future;
        },
        '新轮正常回复。',
      ], latency: Duration.zero);
      final ai = engine(client, memoryStore: memory);
      final events = <coach.AgentEvent>[];
      final subscription = ai.agent.events.listen(events.add);
      addTearDown(subscription.cancel);
      final pending = ai.reply('记下我家里有哑铃', const ChatState());
      await started.future;
      expect(memory.entries, isEmpty);
      ai.cancelPending();
      final reply = await pending.timeout(const Duration(seconds: 1));
      final eventCount = events.length;
      expect(reply.messages, isEmpty);
      expect(ai.agent.turnCount, 0);
      expect(ai.agent.history, isEmpty);
      expect(ai.lastOutcome, coach.TurnOutcome.cancelled);
      expect(memory.entries, isEmpty);
      late.complete('迟到的记忆确认不得保存');
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(eventCount));
      expect(events.where((e) => e.kind == coach.AgentEventKind.done), isEmpty);
      expect(memory.entries, isEmpty);
      final next = await ai.reply('再来一轮', const ChatState());
      expect(texts(next), '新轮正常回复。');
      expect(requestText(client.requests.last), isNot(contains('迟到的记忆确认')));
      expect(
        client.requests.last.messages.first.content,
        isNot(contains('家里有哑铃')),
      );
    },
  );

  test(
    'natural action-demo requests reach show_actions while the explicit library command stays local',
    () async {
      final client = coach.FakeLlmClient([
        actionsResponse(),
        actionsResponse(),
        actionsResponse(),
      ], latency: Duration.zero);
      final ai = engine(client);
      for (final input in ['看看动作', '有哪些拉伸动作', '动作示范']) {
        final reply = await ai.reply(input, const ChatState());
        expect(reply.action, isNull);
        expect(
          reply.messages.map((m) => m.actions).nonNulls.single,
          isA<coach.ValidatedActions>(),
        );
      }
      expect(client.requests, hasLength(3));
      final library = await ai.reply('看看动作库', const ChatState());
      expect(library.action, '@library');
      expect(client.requests, hasLength(3));
    },
  );

  test(
    'all gate errors return as tool feedback before a valid resubmission',
    () async {
      final invalid = plan(ids: ['unknown-drill', 'h-db-row', 'h-squat']);
      final client = coach.FakeLlmClient([
        planResponse(value: invalid, text: '不合格原始文字不可显示'),
        planResponse(),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家 10 分钟练全身，徒手，保护膝', const ChatState());
      expect(ai.lastOutcome, coach.TurnOutcome.rewritten);
      expect(ai.lastResult!.resubmits, 1);
      expect(client.requests, hasLength(2));
      final feedback = client.requests.last.messages.last;
      expect(feedback.role, coach.LlmRole.tool);
      final errors = (jsonDecode(feedback.content) as Map)['errors'] as List;
      expect(
        errors.map((e) => e['code']),
        containsAll(['unknown_exercise', 'equipment', 'avoid']),
      );
      for (final error in errors.cast<Map>()) {
        expect(
          error.keys,
          containsAll(['path', 'code', 'expected', 'actual', 'fix']),
        );
      }
      expect(feedback.content, contains('unknown-drill'));
      expect(feedback.content, contains('h-db-row'));
      expect(feedback.content, contains('h-squat'));
      expect(replyPlan(reply)!.exerciseIds, {'h-calf-raise'});
      expect(replyPlan(reply)!.avoid, contains('膝'));
      expect(texts(reply), isNot(contains('不合格原始文字')));
    },
  );

  test(
    'three rejected wire submissions use the labelled local fallback without raw output',
    () async {
      final invalid = actionsResponse(
        ids: ['unknown-drill'],
        text: 'SECRET-REJECTED-TEXT',
      );
      final gateway = await _Gateway.start([invalid, invalid, invalid]);
      addTearDown(gateway.close);
      final ai = engine(gateway.client());
      final reply = await ai.reply('在家练全身', const ChatState());
      expect(gateway.bodies, hasLength(3));
      expect(ai.lastResult!.status, coach.TurnStatus.fallback);
      expect(ai.lastResult!.submissions, 3);
      expect(ai.lastFallbackReason, coach.FallbackReason.invalidOutput);
      expect(texts(reply), contains('预设方案'));
      expect(texts(reply), isNot(contains('SECRET-REJECTED-TEXT')));
      expect(texts(reply), isNot(contains('unknown-drill')));
      expect(reply.messages.every((m) => m.actions == null), isTrue);
      expectLocalPreserved(
        reply,
        await local().reply('在家练全身', const ChatState()),
      );
      expect(reply.state.pending, isNotNull);
      expect(reply.messages.expand((m) => m.options), isNotEmpty);
      expect(
        jsonEncode(ai.session.history.map((m) => m.toJson()).toList()),
        isNot(contains('SECRET-REJECTED-TEXT')),
      );
    },
  );

  test(
    'prompt canary in tool parameters falls back immediately without exposing it',
    () async {
      final response = tool(coach.CoachTools.showActions, {
        'items': [
          {'actionId': 'h-calf-raise', 'note': coach.defaultPromptCanary},
        ],
      }, text: '这句和整轮一起丢弃');
      final client = coach.FakeLlmClient([response], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家练全身', const ChatState());
      expect(client.requests, hasLength(1));
      expect(ai.lastResult!.leaked, isTrue);
      expect(texts(reply), contains('预设方案'));
      expect(texts(reply), isNot(contains(coach.defaultPromptCanary)));
      expect(texts(reply), isNot(contains('这句和整轮一起丢弃')));
      expect(reply.messages.every((m) => m.actions == null), isTrue);
    },
  );

  test(
    'offline and request timeout each fall back once without model rewrites',
    () async {
      for (final pair in [
        (coach.LlmErrorKind.network, coach.FallbackReason.offline),
        (coach.LlmErrorKind.timeout, coach.FallbackReason.timeout),
      ]) {
        final client = coach.FakeLlmClient([
          coach.LlmException(pair.$1, 'test-unavailable'),
        ], latency: Duration.zero);
        final ai = engine(client);
        final reply = await ai.reply('在家练全身', const ChatState());
        expect(client.requests, hasLength(1));
        expect(ai.lastFallbackReason, pair.$2);
        expect(texts(reply), contains('预设方案'));
        expectLocalPreserved(
          reply,
          await local().reply('在家练全身', const ChatState()),
        );
      }
    },
  );

  test(
    'fallback plan itself is admitted by the SDK before App mapping',
    () async {
      final client = coach.FakeLlmClient([
        const coach.LlmException(coach.LlmErrorKind.network, 'offline'),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家 10 分钟练全身，徒手，保护膝', const ChatState());
      final selected = replyPlan(reply)!;
      expect(ai.lastResult!.status, coach.TurnStatus.fallback);
      expect(ai.lastResult!.plan, isA<coach.ValidatedPlan>());
      expect(selected.exerciseIds, ai.lastResult!.plan!.plan.exerciseIds);
      expect(selected.avoid, contains('膝'));
      expect(
        PlanValidator(library).validate(selected, reply.state.request),
        isEmpty,
      );
      expect(texts(reply), contains('预设方案'));
    },
  );

  test(
    'App commands, recalled plans, workout records and safety stay local',
    () async {
      final client = coach.FakeLlmClient([], latency: Duration.zero);
      final ai = engine(client);
      final savedPlan = plan();
      final state = ChatState(
        lastPlan: savedPlan,
        saved: [
          SavedPlan(
            id: 'saved-one',
            name: '我的训练',
            plan: savedPlan,
            savedAt: DateTime(2026, 10, 20),
          ),
        ],
        history: [
          WorkoutLog(
            title: '昨天训练',
            at: DateTime(2026, 10, 19),
            minutes: 10,
            completed: 1,
            total: 1,
          ),
        ],
      );
      for (final input in [
        '看看动作库',
        '@saved:saved-one',
        '我的计划',
        '上次练了什么',
        '上次那个',
        '换浅色',
        '胸口疼',
      ]) {
        expectLocalPreserved(
          await ai.reply(input, state),
          await local().reply(input, state),
        );
        expect(client.requests, isEmpty, reason: 'App-owned input: $input');
      }
      final blocked = state.copyWith(safetyBlocked: true);
      expectLocalPreserved(
        await ai.reply('在家 10 分钟练全身，徒手', blocked),
        await local().reply('在家 10 分钟练全身，徒手', blocked),
      );
      expect(ai.session.history, isEmpty);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'persistent SDK history carries tool turns and explicit CoachContext',
    () async {
      final client = coach.FakeLlmClient([
        '请告诉我这次有几分钟。',
        planResponse(value: plan(level: 2)),
        planResponse(value: plan(minutes: 7, level: 2)),
      ], latency: Duration.zero);
      final ai = engine(client);
      final first = await ai.reply('在家练全身，偶尔练，徒手，保护膝', const ChatState());
      final second = await ai.reply('10 分钟', first.state);
      final secondPrompt = client.requests[1].messages.last.content;
      expect(secondPrompt, contains('水平 2'));
      expect(secondPrompt, contains('时长 10 分钟'));
      expect(secondPrompt, contains('要保护 膝'));
      expect(second.state.coachContext!.level, 2);
      expect(second.state.coachContext!.minutes, 10);
      expect(second.state.coachContext!.avoid, contains('膝'));
      final third = await ai.reply('再短一点', second.state);
      expect(replyPlan(third)!.targetMinutes, 7);
      expect(ai.session.turnCount, 3);
      expect(client.requests, hasLength(3));
      expect(requestText(client.requests[2]), contains('请告诉我这次有几分钟'));
      final oldTool = client.requests[2].messages
          .where((m) => m.role == coach.LlmRole.assistant)
          .expand((m) => m.toolCalls)
          .single;
      expect(oldTool.name, 'show_plan');
      expect(oldTool.arguments, contains('h-calf-raise'));
      expect(
        client.requests[2].messages.any(
          (m) =>
              m.role == coach.LlmRole.tool &&
              m.content.contains('"shown":true'),
        ),
        isTrue,
      );
    },
  );

  test(
    'level and duration conflicts are resubmitted rather than repaired',
    () async {
      final client = coach.FakeLlmClient([
        planResponse(value: plan(level: 1, minutes: 20)),
        planResponse(value: plan(level: 3, minutes: 10)),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('进阶，在家 10 分钟练全身，徒手', const ChatState());
      expect(ai.lastResult!.resubmits, 1);
      final feedback = client.requests.last.messages.last.content;
      final errors = (jsonDecode(feedback) as Map)['errors'] as List;
      expect(
        errors
            .where((e) => e['code'] == 'context_conflict')
            .map((e) => e['path']),
        containsAll(['level', 'targetMinutes']),
      );
      expect(replyPlan(reply)!.level, 3);
      expect(replyPlan(reply)!.targetMinutes, 10);
    },
  );

  test(
    'duplicate send is busy and does not cancel the active turn or call the model',
    () async {
      final client = _LateClient();
      final ai = engine(client);
      final first = ai.reply('请解释训练节奏', const ChatState());
      await client.started.future;
      final busy = await ai.reply('重复发送', const ChatState());
      expect(ai.lastResult!.status, coach.TurnStatus.busy);
      expect(busy.messages, isEmpty);
      expect(client.requests, hasLength(1));
      expect(client.token!.isCancelled, isFalse);
      client.late.complete(const coach.LlmResponse(content: '第一轮正常完成'));
      expect(texts(await first), '第一轮正常完成');
      expect(ai.session.turnCount, 1);
    },
  );

  test(
    'cancelPending returns promptly and late plans never reach history or rendering',
    () async {
      final client = _LateClient();
      final ai = engine(client);
      final pending = ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      await client.started.future;
      ai.cancelPending();
      final cancelled = await pending.timeout(const Duration(seconds: 1));
      expect(client.token?.isCancelled, isTrue);
      expect(cancelled.messages, isEmpty);
      expect(ai.lastOutcome, coach.TurnOutcome.cancelled);
      expect(ai.session.turnCount, 0);
      expect(ai.session.history, isEmpty);
      client.late.complete(planResponse(text: '晚到取消训练，不应进入任何历史'));
      await Future<void>.delayed(Duration.zero);
      final next = await ai.reply('有什么建议？', cancelled.state);
      expect(replyPlan(next), isNull);
      expect(requestText(client.requests.last), isNot(contains('晚到取消训练')));
      expect(texts(next), '新的回复');
      expect(ai.session.turnCount, 1);
    },
  );

  test(
    'reset clears the SDK conversation and invalidates a pending old turn',
    () async {
      final client = _LateClient();
      final ai = engine(client);
      final pending = ai.reply('旧会话问题', const ChatState());
      await client.started.future;
      ai.reset();
      final cancelled = await pending.timeout(const Duration(seconds: 1));
      expect(cancelled.messages, isEmpty);
      expect(ai.session.history, isEmpty);
      expect(ai.session.turnCount, 0);
      client.late.complete(planResponse(text: '旧会话迟到计划'));
      final next = await ai.reply('新会话问题', const ChatState());
      expect(texts(next), '新的回复');
      expect(requestText(client.requests.last), isNot(contains('旧会话问题')));
      expect(requestText(client.requests.last), isNot(contains('旧会话迟到计划')));
    },
  );

  test('reset clears completed tool turns before a new conversation', () async {
    final client = coach.FakeLlmClient([
      actionsResponse(),
      '全新会话',
    ], latency: Duration.zero);
    final ai = engine(client);
    await ai.reply('旧动作问题', const ChatState());
    expect(ai.session.history, isNotEmpty);
    ai.reset();
    expect(ai.session.history, isEmpty);
    expect(ai.session.turnCount, 0);
    await ai.reply('新问题', const ChatState());
    expect(requestText(client.requests.last), isNot(contains('旧动作问题')));
    expect(client.requests.last.messages, hasLength(2));
  });

  test(
    'total deadline aborts actual HTTP and supplies a labelled template',
    () async {
      final gateway = await _Gateway.start([], hold: true);
      addTearDown(gateway.close);
      final ai = engine(
        gateway.client(),
        deadline: const Duration(milliseconds: 40),
      );
      final reply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      await gateway.aborted.future.timeout(const Duration(seconds: 2));
      expect(ai.lastFallbackReason, coach.FallbackReason.timeout);
      expect(texts(reply), contains('预设方案'));
      expect(replyPlan(reply), isNotNull);
      expect(gateway.bodies, hasLength(1));
    },
  );

  test(
    'offline fallback retains scene and protections from earlier text-only turns',
    () async {
      final client = coach.FakeLlmClient([
        '记住了：办公室、徒手，避开膝部负担。',
        const coach.LlmException(coach.LlmErrorKind.network, 'test offline'),
      ], latency: Duration.zero);
      final ai = engine(client);
      final confirmed = await ai.reply('办公室，徒手，保护膝', const ChatState());
      final fallback = await ai.reply('10 分钟全身', confirmed.state);
      final selected = replyPlan(fallback)!;
      expect(selected.scene, 'office');
      expect(selected.avoid, contains('膝'));
      expect(fallback.state.coachContext!.equipment, isEmpty);
      expect(
        fallback.state.request!.equipment,
        isNot(anyOf(contains(Equipment.band), contains(Equipment.dumbbell))),
      );
      expect(
        PlanValidator(library).validate(selected, fallback.state.request),
        isEmpty,
      );
      expect(ai.lastResult!.plan, isA<coach.ValidatedPlan>());
      for (final item in selected.items) {
        final exercise = library[item.exerciseId];
        expect(exercise.isFloor, isFalse, reason: exercise.id);
        expect(exercise.cautions, isNot(contains('膝')), reason: exercise.id);
      }
    },
  );

  test(
    'adopting an office saved plan retains protections in the following CoachContext',
    () async {
      final office = plan(
        id: 'office-saved',
        ids: ['o-stand-sidebend'],
        scene: 'office',
        avoid: {'肩'},
      );
      for (final input in ['@saved:office', '上次那个']) {
        final client = coach.FakeLlmClient([
          '按办公室条件继续调整。',
        ], latency: Duration.zero);
        final ai = engine(client);
        final previous = ChatState(
          plan: plan(),
          request: requestForPlan(plan()),
          coachContext: const Slots(
            scene: 'home',
            equipment: {},
            avoid: {'膝'},
            minutes: 10,
          ),
          lastPlan: office,
          saved: [
            SavedPlan(
              id: 'office',
              name: '工位训练',
              plan: office,
              savedAt: DateTime(2026, 10, 20),
            ),
          ],
        );
        final adopted = await ai.reply(input, previous);
        expect(client.requests, isEmpty);
        expect(adopted.state.plan!.scene, 'office');
        final edited = await ai.reply('再短一点', adopted.state);
        expect(edited.state.coachContext!.scene, 'office');
        expect(edited.state.coachContext!.avoid, containsAll(['肩', '膝']));
        expect(
          client.requests.single.messages.last.content,
          contains('办公室（office）'),
        );
        expect(client.requests.single.messages.last.content, contains('肩'));
        expect(client.requests.single.messages.last.content, contains('膝'));
      }
    },
  );

  test(
    'controller keeps records and safety answers out of persistent SDK prompts',
    () async {
      final client = coach.FakeLlmClient([
        'AI 轮次一：保持稳定节奏。',
        'AI 轮次二：再逐步增加强度。',
      ], latency: Duration.zero);
      final ai = engine(client);
      final store = AppStore(_Storage());
      store.history.add(
        HistoryEntry(
          title: '仅留本机的敏感训练记录',
          at: DateTime(2026, 10, 20),
          minutes: 10,
          completed: 1,
          total: 1,
        ),
      );
      final controller = ChatController(
        engine: ai,
        store: store,
        replyDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.start();
      var question = controller.messages.lastWhere((m) => m.options.isNotEmpty);
      await controller.choose(
        question,
        question.options.indexWhere((o) => o.value == '@safety:ack'),
      );
      while (controller.inSafetyCheck) {
        question = controller.messages.lastWhere((m) => m.options.isNotEmpty);
        await controller.choose(
          question,
          question.options.indexWhere((o) => o.value == '@safety:no'),
        );
      }
      final safetyMessages = List<ChatMessage>.of(controller.messages);
      await controller.send('上次练了什么');
      expect(controller.messages.last.text, contains('仅留本机的敏感训练记录'));
      await controller.send('请解释训练节奏');
      await controller.send('再讲得具体一点');
      expect(client.requests, hasLength(2));
      final prompt = requestText(client.requests.last);
      expect(prompt, contains('AI 轮次一：保持稳定节奏。'));
      expect(prompt, contains('请解释训练节奏'));
      expect(prompt, isNot(contains('上次练了什么')));
      expect(prompt, isNot(contains('仅留本机的敏感训练记录')));
      expect(prompt, isNot(contains('我已了解')));
      expect(safetyMessages.every((m) => !m.aiVisible), isTrue);
      expect(controller.messages.last.aiVisible, isTrue);
      expect(
        ChatMessage.fromJson(controller.messages.last.toJson()).aiVisible,
        isTrue,
      );
    },
  );

  test(
    '100 and 120 minute inputs clamp to 60 as whole numbers before the SDK gate',
    () async {
      final client = coach.FakeLlmClient([
        planResponse(value: plan(minutes: 60)),
        planResponse(value: plan(minutes: 60)),
      ], latency: Duration.zero);
      final ai = engine(client);
      for (final minutes in [100, 120]) {
        final reply = await ai.reply('在家 $minutes 分钟练全身，徒手', const ChatState());
        expect(ai.lastResult!.status, coach.TurnStatus.ok);
        expect(reply.state.coachContext!.minutes, 60);
        expect(replyPlan(reply)!.targetMinutes, 60);
      }
      expect(client.requests, hasLength(2));
    },
  );

  test(
    'HTTP 429 asks to try later and retains the labelled local fallback',
    () async {
      final gateway = await _Gateway.start(
        [],
        status: HttpStatus.tooManyRequests,
      );
      addTearDown(gateway.close);
      final ai = engine(gateway.client());
      final reply = await ai.reply('在家练全身', const ChatState());
      expect(gateway.bodies, hasLength(1));
      expect(ai.lastFallbackReason, coach.FallbackReason.rateLimited);
      expect(texts(reply), contains('稍后再试'));
      expect(texts(reply), contains('预设方案'));
      expectLocalPreserved(
        reply,
        await local().reply('在家练全身', const ChatState()),
      );
    },
  );

  test(
    'restart restores the latest office conditions over an older home card',
    () async {
      final oldPlan = plan(avoid: {'腰'});
      final at = DateTime(2026, 10, 20);
      final messages = [
        ChatMessage(
          id: 'old-user',
          role: ChatRole.user,
          at: at,
          text: '在家 10 分钟练全身，徒手，保护腰',
          aiVisible: true,
        ),
        ChatMessage(
          id: 'old-plan',
          role: ChatRole.assistant,
          at: at,
          text: '居家计划。',
          plan: oldPlan,
          request: requestForPlan(oldPlan),
          aiVisible: true,
        ),
        ChatMessage(
          id: 'new-user',
          role: ChatRole.user,
          at: at,
          text: '现在改在办公室，徒手，保护膝',
          aiVisible: true,
        ),
        ChatMessage(
          id: 'new-question',
          role: ChatRole.assistant,
          at: at,
          text: '这次有几分钟？',
          aiVisible: true,
        ),
      ];
      final storage = _Storage();
      final initial = AppStore(storage);
      await initial.acceptSafety(blocked: false);
      await initial.setChatLog(messages.map((m) => m.toJson()).toList());
      final store = AppStore(storage);
      await store.load();
      final client = coach.FakeLlmClient([
        planResponse(
          value: plan(ids: ['o-stand-sidebend'], scene: 'office'),
        ),
      ], latency: Duration.zero);
      final ai = engine(client);
      final controller = ChatController(
        engine: ai,
        store: store,
        replyDelay: Duration.zero,
        clock: () => at,
      );
      addTearDown(controller.dispose);
      controller.start();
      expect(controller.currentPlan!.scene, 'home');
      await controller.send('10 分钟全身');
      expect(ai.lastResult!.status, coach.TurnStatus.ok);
      expect(controller.currentPlan!.scene, 'office');
      expect(controller.currentPlan!.avoid, containsAll(['腰', '膝']));
      expect(
        client.requests.single.messages.last.content,
        contains('办公室（office）'),
      );
    },
  );

  test(
    'offline shortening revalidates old cards against new protection and scene',
    () async {
      final base = plan(ids: ['h-squat', 'h-forearm-plank'], minutes: 20);
      final old = TrainingPlan.fromJson({
        ...base.toJson(),
        'blocks': [
          {
            ...base.blocks.single.toJson(),
            'items': [
              {
                ...base.blocks.single.items.first.toJson(),
                'sets': 6,
                'reps': 30,
                'restSeconds': 30,
              },
              {
                ...base.blocks.single.items.last.toJson(),
                'sets': 3,
                'workSeconds': 120,
                'restSeconds': 30,
              },
            ],
          },
        ],
      });
      expect(SessionBuilder(library).planSeconds(old), greaterThan(600));
      for (final scenario in [
        ('再短一点，保护膝', 'home', const {'膝'}),
        ('再短一点，改在办公室，徒手', 'office', const <String>{}),
      ]) {
        final client = coach.FakeLlmClient([
          const coach.LlmException(coach.LlmErrorKind.network, 'offline'),
        ], latency: Duration.zero);
        final ai = engine(client);
        final reply = await ai.reply(
          scenario.$1,
          ChatState(
            plan: old,
            request: requestForPlan(old),
            coachContext: const Slots(
              scene: 'home',
              minutes: 20,
              equipment: {},
            ),
          ),
        );
        expect(ai.lastFallbackReason, coach.FallbackReason.offline);
        expect(texts(reply), contains('预设方案'));
        final merged = requestForPlan(old).copyWith(
          scene: scenario.$2,
          avoid: scenario.$3,
          equipment: {},
          minutes: 14,
        );
        for (final message in reply.messages.where((m) => m.plan != null)) {
          expect(message.validatedPlan, isA<coach.ValidatedPlan>());
          expect(message.plan!.scene, scenario.$2);
          expect(message.plan!.avoid, containsAll(scenario.$3));
          expect(
            PlanValidator(library).validate(message.plan!, merged),
            isEmpty,
          );
        }
        expect(client.requests, hasLength(1));
      }
    },
  );

  test(
    'distinct accepted plans with a reused model id save independently',
    () async {
      final client = coach.FakeLlmClient([
        planResponse(value: plan(id: 'model-reused-id')),
        planResponse(
          value: plan(id: 'model-reused-id', ids: ['h-squat']),
        ),
      ], latency: Duration.zero);
      final ai = engine(client);
      final firstReply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      final secondReply = await ai.reply('换一套', firstReply.state);
      final first = replyPlan(firstReply)!;
      final second = replyPlan(secondReply)!;
      expect(first.id, isNot('model-reused-id'));
      expect(second.id, isNot('model-reused-id'));
      expect(first.id, isNot(second.id));
      expect(first.exerciseIds, {'h-calf-raise'});
      expect(second.exerciseIds, {'h-squat'});
      final storage = _Storage();
      final store = AppStore(storage);
      await store.savePlan(first);
      await store.savePlan(second);
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(reloaded.savedPlans, hasLength(2));
      expect(reloaded.savedPlans.map((p) => p.plan.id).toSet(), {
        first.id,
        second.id,
      });
    },
  );
}
