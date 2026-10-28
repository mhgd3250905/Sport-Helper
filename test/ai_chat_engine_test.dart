import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support/coach_v2_fixtures.dart';

class _LateClient implements coach.LlmClient {
  final started = Completer<void>();
  final late = Completer<coach.LlmResponse>();
  final requests = <coach.LlmRequest>[];
  coach.CancelToken? token;
  @override
  String get model => 'late-test';
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

class _FailingMemory extends coach.InMemoryUserMemoryStore {
  @override
  Future<void> save(List<coach.MemoryEntry> entries) async =>
      throw StateError('private-disk-error');
}

String _text(ChatReply reply) => reply.messages.map((m) => m.text).join('\n');
String _wire(coach.LlmRequest request) =>
    jsonEncode(request.messages.map((m) => m.toJson()).toList());

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
  });
  AiChatEngine engine(
    coach.LlmClient client, {
    Duration deadline = const Duration(seconds: 390),
    coach.UserMemoryStore? memoryStore,
    bool enableUserMemory = false,
  }) {
    final value = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: client,
      turnTimeout: deadline,
      memoryStore: memoryStore,
      enableUserMemory: enableUserMemory,
    );
    addTearDown(value.dispose);
    return value;
  }

  group('SDK owns text and task decisions', () {
    for (final input in ['帮我安排一组训练', '我的计划', '换浅色', '看看动作库', '@library']) {
      test(
        'free text "$input" reaches SDK without App intent routing',
        () async {
          final client = coach.FakeLlmClient(['SDK回答'], latency: Duration.zero);
          final ai = engine(client);
          final reply = await ai.reply(input, const ChatState());
          expect(_text(reply), 'SDK回答');
          expect(reply.action, isNull);
          expect(client.requests, hasLength(1));
          expect(ai.agent.sessionState.userTurns.single.text, input);
          expect(
            ai.conversation.state.messages.where((m) => m.isUser).single.text,
            input,
          );
        },
      );
    }
    test(
      'explicit App command bypasses model without interpreting prose',
      () async {
        final client = coach.FakeLlmClient([], latency: Duration.zero);
        final reply = await engine(
          client,
        ).replyAppCommand('@library', const ChatState());
        expect(reply.action, '@library');
        expect(client.requests, isEmpty);
      },
    );
    test(
      'stale App plan/request/history never become host parameters',
      () async {
        const old = TrainingPlan(
          id: 'old-private-card',
          source: 'ai',
          title: '旧方案私有标记',
          summary: '',
          goal: 'core',
          scene: 'gym',
          equipment: ['dumbbell'],
          level: 3,
          targetMinutes: 45,
          blocks: [],
        );
        final state = ChatState(
          plan: old,
          request: requestForPlan(old),
          recentMessages: [
            ChatMessage(
              id: 'old-user',
              role: ChatRole.user,
              at: DateTime(2026),
              text: 'OLD-PRIVATE-GYM-CONTEXT',
              aiVisible: true,
            ),
          ],
        );
        final client = coach.FakeLlmClient([
          '请说说本次需求。',
        ], latency: Duration.zero);
        final ai = engine(client);
        await ai.reply('现在想活动一下', state);
        expect(ai.agent.sessionState.params, isEmpty);
        expect(ai.agent.sessionState.hostValues, isEmpty);
        expect(ai.agent.sessionState.userTurns.map((m) => m.text), ['现在想活动一下']);
        expect(
          _wire(client.requests.single),
          isNot(contains('OLD-PRIVATE-GYM-CONTEXT')),
        );
        expect(_wire(client.requests.single), isNot(contains('旧方案私有标记')));
      },
    );
    test('plain JSON or prose never creates an admitted App plan', () async {
      final client = coach.FakeLlmClient([
        '{"title":"model prose","targetMinutes":10,"blocks":[]}',
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('描述这个例子', const ChatState());
      expect(
        reply.messages.every((m) => m.plan == null && m.validatedPlan == null),
        isTrue,
      );
      expect(ai.agent.sessionState.plans, isEmpty);
    });
    test('SDK ask_user is answerable only after send has completed', () async {
      final client = coach.FakeLlmClient([
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('question', 'ask_user', {
            'question': '想重点练哪里？',
            'mode': 'choice',
            'options': ['核心', '下肢'],
          }),
        ]),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('帮我练一下', const ChatState());
      expect(reply.messages.single.question?.options, ['核心', '下肢']);
      expect(reply.messages.single.plan, isNull);
      expect(
        ai.conversation.canAnswer(reply.messages.single.conversationMessageId!),
        isTrue,
      );
      expect(
        client.requests,
        hasLength(1),
        reason: 'The fake model chose to ask; no App preflight question.',
      );
    });
  });

  group('v2 typed cards and ledger', () {
    test(
      'batched plan tools produce exact SDK plan identity and payload',
      () async {
        final client = coach.FakeLlmClient(
          fixture.planTurn(),
          latency: Duration.zero,
        );
        final ai = engine(client);
        final events = <coach.AgentEvent>[];
        final sub = ai.events.listen(events.add);
        addTearDown(sub.cancel);
        final reply = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
        expect(
          ai.lastResult?.plan,
          isNotNull,
          reason: '${ai.lastResult?.issues} ${ai.lastResult?.error}',
        );
        final card = reply.messages.single;
        expect(identical(card.validatedPlan, ai.lastResult!.plan), isTrue);
        expect(card.plan!.id, ai.lastResult!.plan!.plan.id);
        expect(card.plan!.toJson(), ai.lastResult!.plan!.plan.toJson());
        expect(card.plan!.targetMinutes, 10);
        expect(client.requests, hasLength(2));
        expect(ai.agent.sessionState.params['minutes']!.source, 'user');
        expect(ai.agent.sessionState.params['equipment']!.value, isEmpty);
        expect(
          events
              .where(
                (e) =>
                    e.kind == coach.AgentEventKind.node &&
                    e.node?.status == 'done',
              )
              .map((e) => e.node!.id),
          [
            'understand',
            'parameters',
            'actions',
            'planning',
            'review',
            'output',
          ],
        );
      },
    );
    test('SDK recommendation is typed actions and never a text plan', () async {
      final client = coach.FakeLlmClient(
        fixture.recommendationTurn(),
        latency: Duration.zero,
      );
      final ai = engine(client);
      final reply = await ai.reply('推荐几个拉伸动作', const ChatState());
      expect(
        reply.messages.single.actions,
        isNotNull,
        reason: '${ai.lastResult?.issues} ${ai.lastResult?.error}',
      );
      expect(
        reply.messages.single.actions!.items.map((a) => a.id),
        CoachV2Fixtures.stretching,
      );
      expect(reply.messages.single.plan, isNull);
      expect(ai.agent.sessionState.task!.type, 'recommend');
      expect(ai.agent.sessionState.task!.nodes.last.status, 'done');
      expect(client.requests, hasLength(1));
    });
    test('recommendation becomes a plan through SDK default reuse', () async {
      final client = coach.FakeLlmClient([
        ...fixture.recommendationTurn(),
        ...fixture.planTurn(prefix: 'from-recommend', goalQuote: null),
      ], latency: Duration.zero);
      final ai = engine(client);
      final first = await ai.reply('推荐几个拉伸动作', const ChatState());
      expect(first.messages.single.actions, isNotNull);
      final reply = await ai.reply('在家徒手10分钟，把这些排成计划', first.state);
      expect(
        reply.messages.single.validatedPlan,
        isNotNull,
        reason: '${ai.lastResult?.issues}',
      );
      expect(ai.agent.sessionState.task!.reused, isTrue);
      expect(reply.messages.single.question, isNull);
    });
    test(
      'same-plan edit preserves SDK identity and advances version',
      () async {
        final client = coach.FakeLlmClient([
          ...fixture.planTurn(),
          ...fixture.planTurn(
            prefix: 'edited',
            reuse: true,
            sceneQuote: null,
            equipmentQuote: null,
            goalQuote: null,
            minutes: 7,
            minutesQuote: '7分钟',
            operation: 'edit',
            operationQuote: '缩短',
          ),
        ], latency: Duration.zero);
        final ai = engine(client);
        final first = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
        final previous = first.messages.single.plan!;
        final next = await ai.reply('缩短到7分钟', first.state);
        expect(
          next.messages.single.plan,
          isNotNull,
          reason: '${ai.lastResult?.issues}',
        );
        expect(next.messages.single.plan!.id, previous.id);
        expect(next.messages.single.plan!.targetMinutes, 7);
        expect(
          ai.agent.sessionState.plans[previous.id]!.map((v) => v.version),
          [1, 2],
        );
        expect(next.messages.single.question, isNull);
      },
    );
    for (final phrase in ['换一套', '换个别的', '再来一套']) {
      test(
        '"$phrase" keeps SDK conditions and changes at least half main actions',
        () async {
          final client = coach.FakeLlmClient([
            ...fixture.planTurn(),
            ...fixture.planTurn(
              prefix: 'replacement',
              reuse: true,
              sceneQuote: null,
              equipmentQuote: null,
              goalQuote: null,
              minutes: null,
              operation: 'replace_all',
              operationQuote: phrase,
              ids: CoachV2Fixtures.alternativeStretching,
            ),
          ], latency: Duration.zero);
          final ai = engine(client);
          final first = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
          final next = await ai.reply(phrase, first.state);
          final plan = next.messages.single.plan;
          expect(
            plan,
            isNotNull,
            reason: '${ai.lastResult?.issues} ${ai.lastResult?.error}',
          );
          expect(plan!.id, first.messages.single.plan!.id);
          expect(plan.targetMinutes, 10);
          expect(next.messages.single.question, isNull);
          final oldIds = first.messages.single.plan!.items
              .map((m) => m.exerciseId)
              .toSet();
          final ids = plan.items.map((m) => m.exerciseId).toSet();
          expect(
            ids.difference(oldIds).length / ids.length,
            greaterThanOrEqualTo(.5),
            reason:
                'old=$oldIds new=$ids; ledger=${jsonEncode(ai.agent.sessionState.toJson())}',
          );
        },
      );
    }
    test('unsearched recommendation cannot become an App card', () async {
      final client = coach.FakeLlmClient([
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('start', 'start_task', {'type': 'recommend'}),
          CoachV2Fixtures.call('params', 'set_params', {
            'fields': {
              'goal': CoachV2Fixtures.sourced(['purpose.stretch'], '拉伸'),
            },
          }),
          CoachV2Fixtures.call('invalid', 'show_actions', {
            'ids': ['fabricated-action'],
            'note': '慢慢来。',
          }),
        ]),
        '暂时无法提供这个动作。',
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('推荐拉伸动作', const ChatState());
      expect(
        reply.messages.every(
          (m) => m.actions == null && m.validatedPlan == null,
        ),
        isTrue,
      );
      expect(ai.agent.sessionState.lastDeliveredPlanId, isNull);
    });
  });

  group('lifecycle and failures', () {
    test(
      'upstream error makes only a failure bubble without a preset',
      () async {
        final client = coach.FakeLlmClient([
          const coach.LlmException(
            coach.LlmErrorKind.http,
            'PRIVATE-UPSTREAM-ERROR',
            statusCode: 401,
          ),
        ], latency: Duration.zero);
        final ai = engine(client);
        final reply = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
        expect(reply.messages.single.isPlanningFailure, isTrue);
        expect(reply.messages.single.plan, isNull);
        expect(reply.messages.single.actions, isNull);
        expect(_text(reply), isNot(contains('PRIVATE-UPSTREAM-ERROR')));
        expect(_text(reply), isNot(contains('预设方案')));
        expect(ai.lastOutcome, coach.TurnOutcome.error);
        expect(client.requests, hasLength(1));
      },
    );
    test('cancel defeats late custom transport and next turn works', () async {
      final client = _LateClient();
      final ai = engine(client);
      final pending = ai.reply('第一条', const ChatState());
      await client.started.future;
      ai.cancelPending();
      final cancelled = await pending;
      expect(cancelled.messages, isEmpty);
      expect(cancelled.inputAccepted, isFalse);
      expect(client.token!.isCancelled, isTrue);
      client.late.complete(
        const coach.LlmResponse(content: 'LATE-PRIVATE-ANSWER'),
      );
      await Future<void>.delayed(Duration.zero);
      final next = await ai.reply('第二条', const ChatState());
      expect(_text(next), '新的回复');
      expect(
        ai.conversation.state.messages.map((m) => m.text).join(),
        isNot(contains('LATE-PRIVATE-ANSWER')),
      );
    });
    test(
      'reset clears ledger and completed history using the same Agent',
      () async {
        final client = coach.FakeLlmClient([
          '第一条回答',
          '第二条回答',
        ], latency: Duration.zero);
        final ai = engine(client);
        await ai.reply('PREVIOUS-PRIVATE-TURN', const ChatState());
        final original = ai.agent;
        ai.reset();
        expect(identical(ai.agent, original), isTrue);
        expect(ai.agent.sessionState.userTurns, isEmpty);
        await ai.reply('新的对话', const ChatState());
        expect(
          _wire(client.requests.last),
          isNot(contains('PREVIOUS-PRIVATE-TURN')),
        );
        expect(
          ai.conversation.state.messages
              .where((m) => m.isUser)
              .map((m) => m.text),
          ['新的对话'],
        );
      },
    );
    test(
      'dispose ignores late completion and refuses subsequent sends',
      () async {
        final client = _LateClient();
        final ai = engine(client);
        final pending = ai.reply('等待中的请求', const ChatState());
        await client.started.future;
        ai.dispose();
        client.late.complete(
          const coach.LlmResponse(content: 'late after disposal'),
        );
        expect((await pending).messages, isEmpty);
        expect((await ai.reply('不要再发送', const ChatState())).messages, isEmpty);
        expect(client.requests, hasLength(1));
      },
    );
    test('duplicate send during a request is not accepted or sent', () async {
      final client = _LateClient();
      final ai = engine(client);
      final first = ai.reply('原始消息', const ChatState());
      await client.started.future;
      final duplicate = await ai.reply('重复消息', const ChatState());
      expect(duplicate.inputAccepted, isFalse);
      expect(client.requests, hasLength(1));
      ai.cancelPending();
      await first;
      client.late.complete(const coach.LlmResponse(content: 'ignored'));
    });
    test(
      'overlong SDK input is rejected without consuming a model call',
      () async {
        final client = coach.FakeLlmClient(['有效回复'], latency: Duration.zero);
        final ai = engine(client);
        final long = await ai.reply(
          '长' * (ai.agent.maxInputChars + 1),
          const ChatState(),
        );
        expect(long.inputAccepted, isFalse);
        expect(client.requests, isEmpty);
        expect(_text(await ai.reply('正常提问', const ChatState())), '有效回复');
      },
    );
    test(
      'outer deadline cancels ignored transport without a stale reply',
      () async {
        final client = _LateClient();
        final ai = engine(client, deadline: const Duration(milliseconds: 25));
        final pending = ai.reply('等待', const ChatState());
        await client.started.future;
        final result = await pending;
        expect(result.messages.single.isPlanningFailure, isTrue);
        expect(result.messages.single.plan, isNull);
        client.late.complete(
          const coach.LlmResponse(content: 'late private answer'),
        );
      },
    );
  });

  group('SDK defaults and memory', () {
    test(
      'SDK retry timeout and context thresholds are not overridden',
      () async {
        final ai = engine(coach.FakeLlmClient([]));
        expect(ai.agent.maxSteps, 100);
        expect(ai.agent.maxRequestRetries, 4);
        expect(ai.agent.requestTimeout, const Duration(seconds: 60));
        expect(ai.agent.turnTimeout, const Duration(seconds: 360));
        expect(ai.agent.contextBudgetTokens, 60000);
        expect(ai.agent.keepRecentSteps, 3);
        expect(ai.agent.contextBudgetConfig.toJson(), {
          'softOffBytes': 40960,
          'softOnBytes': 51200,
          'hardBytes': 65536,
        });
        expect(ai.agent.extraRules, isEmpty);
        expect(ai.agent.fallback, isNull);
        expect(ai.turnTimeout, const Duration(seconds: 390));
        final transport = const AiCoachConfig(
          token: 'test-key',
        ).createClient(deviceId: 'test-device');
        addTearDown(transport.close);
        expect(transport.config.maxRetries, 0);
        expect(
          transport.config.timeout,
          greaterThanOrEqualTo(coach.LlmConfig.ugkWorker.timeout),
        );
        expect(transport.config.baseUrl, 'https://ai.uuugk.win/v1');
        expect(transport.config.model, 'deepseek-flash');
        expect(transport.auth, isA<coach.ApiKeyAuth>());
        expect(await transport.auth.headers(), {
          'Authorization': 'Bearer test-key',
        });
      },
    );
    test('disabled memory omits stored habits and memory tools', () async {
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(
          coach.MemoryKind.preference,
          'PRIVATE-MEMORY-SENTINEL',
          at: DateTime(2026),
        ),
      ]);
      final client = coach.FakeLlmClient(['正常回答'], latency: Duration.zero);
      await engine(
        client,
        memoryStore: memory,
      ).reply('训练呼吸怎么做', const ChatState());
      expect(
        _wire(client.requests.single),
        isNot(contains('PRIVATE-MEMORY-SENTINEL')),
      );
      expect(
        client.requests.single.tools.map((t) => t.name),
        isNot(contains('remember')),
      );
      expect(memory.entries.single.text, 'PRIVATE-MEMORY-SENTINEL');
    });
    test(
      'SDK clearMemory removes durable facts and later prompt summaries',
      () async {
        final memory = coach.InMemoryUserMemoryStore([
          coach.MemoryEntry(
            coach.MemoryKind.preference,
            'CLEAR-THIS-HABIT',
            at: DateTime(2026),
          ),
        ]);
        final client = coach.FakeLlmClient([
          '第一条',
          '第二条',
        ], latency: Duration.zero);
        final ai = engine(client, memoryStore: memory, enableUserMemory: true);
        await ai.reply('先介绍呼吸', const ChatState());
        expect(_wire(client.requests.first), contains('CLEAR-THIS-HABIT'));
        await ai.clearMemory();
        expect(memory.entries, isEmpty);
        await ai.reply('继续介绍', const ChatState());
        expect(
          _wire(client.requests.last),
          isNot(contains('CLEAR-THIS-HABIT')),
        );
      },
    );
    test(
      'durable memory failure propagates instead of reporting success',
      () async {
        await expectLater(
          engine(
            coach.FakeLlmClient([]),
            memoryStore: _FailingMemory(),
          ).clearMemory(),
          throwsStateError,
        );
      },
    );
  });
}
