import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show MemoryStorage;
import 'support/coach_v2_fixtures.dart';

class _AppConversation {
  _AppConversation(
    this.storage,
    this.store,
    this.client,
    this.engine,
    this.chat,
  );
  final MemoryStorage storage;
  final AppStore store;
  final coach.FakeLlmClient client;
  final AiChatEngine engine;
  final ChatController chat;
  final events = <coach.AgentEvent>[];
  StreamSubscription<coach.AgentEvent>? subscription;

  coach.CoachSessionSnapshot get saved =>
      coach.CoachSessionSnapshot.fromJson(jsonDecode(store.coachSessionJson!));

  void dispose() {
    unawaited(subscription?.cancel());
    chat.dispose();
    engine.dispose();
    store.dispose();
  }
}

class _RecordingStorage extends MemoryStorage {
  final writes = <Map<String, dynamic>>[];
  @override
  Future<void> write(String key, String value) async {
    if (key == AppStore.key) {
      writes.add(jsonDecode(value) as Map<String, dynamic>);
    }
    await super.write(key, value);
  }
}

coach.LlmResponse _ask(Map<String, Object?> question) => CoachV2Fixtures.batch([
  CoachV2Fixtures.call('snapshot-ask', 'ask_user', question),
]);

Map<String, Object?> _question(String mode) => mode == 'choice'
    ? {
        'question': '你在什么场景训练？',
        'mode': 'choice',
        'options': ['在家', '办公室'],
      }
    : {
        'question': '这次准备练多久？',
        'mode': 'form',
        'fields': [
          {
            'key': 'minutes',
            'label': '时长',
            'options': ['10分钟', '15分钟'],
            'multiple': false,
          },
        ],
        'skipLabel': '直接出方案',
      };

void main() {
  late CoachV2Fixtures fixture;
  var generation = 0;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  Future<_AppConversation> app(
    List<Object> script, {
    MemoryStorage? storage,
    Duration replyDelay = Duration.zero,
  }) async {
    final disk = storage ?? MemoryStorage();
    final store = AppStore(disk);
    await store.load();
    if (!store.safetyAccepted) {
      await store.acceptSafety(blocked: false);
    }
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final engine = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: client,
      enableUserMemory: false,
    );
    final clockSequence = generation++;
    final chat = ChatController(
      engine: engine,
      store: store,
      replyDelay: replyDelay,
      clock: () => DateTime(2026, 10, 28, 20, 0, clockSequence),
    );
    final result = _AppConversation(disk, store, client, engine, chat);
    result.subscription = engine.events.listen(result.events.add);
    addTearDown(result.dispose);
    chat.start();
    return result;
  }

  Future<void> send(_AppConversation app, String input) async {
    await app.chat.send(input);
    await app.chat.flushPersistence();
    expect(
      app.engine.lastResult?.status,
      coach.TurnStatus.ok,
      reason:
          '${app.engine.lastResult?.issues} ${app.engine.lastResult?.error}',
    );
    expect(app.saved.isValid, isTrue);
  }

  void sameLedger(coach.CoachSessionSnapshot expected, _AppConversation next) {
    final actual = next.engine.conversation.exportSession();
    expect(actual.sessionState.toJson(), expected.sessionState.toJson());
    expect(actual.ledger.toJson(), expected.ledger.toJson());
    expect(actual.loadedSkillNames, expected.loadedSkillNames);
    expect(actual.candidates, expected.candidates);
    expect(
      next.client.requests,
      isEmpty,
      reason: 'Restoration never calls a model.',
    );
  }

  void restoredRequestHasNoOldWireMessages(
    coach.LlmRequest request,
    String input,
  ) {
    expect(request.messages.first.role, coach.LlmRole.system);
    expect(
      request.messages.where(
        (message) =>
            message.role == coach.LlmRole.assistant ||
            message.role == coach.LlmRole.tool,
      ),
      isEmpty,
    );
    expect(
      request.messages.every((message) => message.reasoning == null),
      isTrue,
    );
    expect(
      request.messages.where((message) => message.content == input),
      hasLength(1),
    );
    final bytes = utf8
        .encode(
          jsonEncode({
            'messages': request.messages
                .map((message) => message.toJson())
                .toList(),
            'tools': request.tools.map((tool) => tool.toJson()).toList(),
          }),
        )
        .length;
    expect(
      bytes,
      lessThan(65536),
      reason: 'Restored request uses the default SDK hard budget.',
    );
  }

  test(
    'recommendation survives a new App instance and becomes a fifteen-minute plan',
    () async {
      final first = await app(fixture.recommendationTurn());
      await send(first, '在家徒手拉伸，先推荐几个动作');
      final snapshot = first.saved;
      expect(snapshot.recommendations, hasLength(1));
      expect(snapshot.sessionState.params['goal']!.quote, '拉伸');
      expect(
        first.store.chatLog.every((row) => !row.containsKey('planState')),
        isTrue,
      );
      final note = snapshot.recommendations.single.note;
      final ids = snapshot.recommendations.single.actionIds;
      await first.store.setConversation([
        for (final row in first.store.chatLog)
          if (row['conversationMessageId'] ==
              snapshot.recommendations.single.messageId)
            {...row, 'text': '显示缓存不能覆盖真实交付。'}..remove('actionIds')
          else
            row,
      ], sessionJson: first.store.coachSessionJson);
      final next = await app(
        fixture.planTurn(
          prefix: 'restored-plan',
          minutes: 15,
          minutesQuote: '15分钟',
          goalQuote: null,
        ),
        storage: first.storage,
      );
      sameLedger(snapshot, next);
      final card = next.chat.messages.singleWhere(
        (message) => message.actions != null,
      );
      expect(card.actions!.items.map((item) => item.id), ids);
      expect(card.text, note);
      await send(next, '把这几个排成15分钟');
      final plan = next.chat.messages
          .lastWhere((message) => message.validatedPlan != null)
          .validatedPlan!
          .plan;
      expect(plan.targetMinutes, 15);
      expect(plan.items.map((item) => item.exerciseId).toSet(), ids.toSet());
      expect(
        next.engine.agent.sessionState.userTurns.map((turn) => turn.text),
        ['在家徒手拉伸，先推荐几个动作', '把这几个排成15分钟'],
      );
      restoredRequestHasNoOldWireMessages(
        next.client.requests.first,
        '把这几个排成15分钟',
      );
    },
  );

  test(
    'sourced plan parameters and versions survive restart before a relative edit',
    () async {
      final first = await app(fixture.planTurn());
      await send(first, '在家徒手10分钟做拉伸');
      final snapshot = first.saved;
      final planId = first.engine.agent.sessionState.lastDeliveredPlanId!;
      final next = await app(
        fixture.planTurn(
          prefix: 'restored-shorter',
          reuse: true,
          minutes: null,
          goalQuote: null,
          sceneQuote: null,
          equipmentQuote: null,
          operation: 'edit',
          operationQuote: '短一点',
          fields: {
            'minutes': {
              'value': 5,
              'source': 'derived',
              'quote': '短一点',
              'direction': 'shorter',
            },
          },
        ),
        storage: first.storage,
      );
      sameLedger(snapshot, next);
      await send(next, '短一点');
      final plan = next.chat.messages
          .lastWhere((message) => message.plan != null)
          .plan!;
      expect(plan.id, planId);
      expect(plan.targetMinutes, 5);
      expect(next.engine.agent.sessionState.plans[planId], hasLength(2));
      final param = next.engine.agent.sessionState.params['minutes']!;
      expect(
        (param.source, param.direction, param.quote),
        ('derived', 'shorter', '短一点'),
      );
      expect((param.basedOn!.source, param.basedOn!.quote), ('user', '10分钟'));
      restoredRequestHasNoOldWireMessages(next.client.requests.first, '短一点');
    },
  );

  test(
    'question-and-answer without any card restores its completed-turn ledger',
    () async {
      const input = '训练前要注意什么？';
      const answer = '先确认身体状态，准备好安全的活动空间。';
      final first = await app([answer]);
      await send(first, input);
      expect(
        first.chat.messages.where(
          (message) => message.plan != null || message.actions != null,
        ),
        isEmpty,
      );
      expect(first.saved.ledger.turns.single.userText, input);
      expect(first.saved.ledger.turns.single.finalDeliveryText, answer);
      final next = await app(['从简单动作开始，慢慢增加活动范围。'], storage: first.storage);
      sameLedger(first.saved, next);
      expect(
        next.chat.messages.any((message) => message.text == answer),
        isTrue,
      );
      await send(next, '还有什么建议？');
      restoredRequestHasNoOldWireMessages(
        next.client.requests.first,
        '还有什么建议？',
      );
      expect(next.saved.ledger.turns.first.finalDeliveryText, answer);
      expect(next.saved.ledger.turns, hasLength(2));
    },
  );

  for (final mode in ['choice', 'form']) {
    test(
      'restored $mode remains answerable and display flags cannot close it',
      () async {
        final first = await app([_ask(_question(mode))]);
        await send(first, '我想练一下');
        final pending = first.chat.messages.singleWhere(
          (message) => message.question != null,
        );
        final snapshot = first.saved;
        final alteredDisplay = [
          for (final row in first.store.chatLog)
            if (row['id'] == pending.id)
              {...row, 'questionAnswered': true}
            else
              row,
        ];
        await first.store.setConversation(
          alteredDisplay,
          sessionJson: first.store.coachSessionJson,
        );
        final next = await app(['这些条件已经记下。'], storage: first.storage);
        sameLedger(snapshot, next);
        final question = next.chat.messages.singleWhere(
          (message) => message.question != null,
        );
        expect(question.questionAnswered, isFalse);
        expect(next.chat.canAnswerQuestion(question), isTrue);
        expect(
          question.conversationMessageId,
          snapshot.pendingQuestionMessageId,
        );
        if (mode == 'choice') {
          await next.chat.answerChoices(question, ['在家']);
        } else {
          await next.chat.answerForm(question, {
            'minutes': ['15分钟'],
          });
        }
        await next.chat.flushPersistence();
        expect(next.engine.lastResult?.status, coach.TurnStatus.ok);
        final answered = next.chat.messages.firstWhere(
          (message) => message.id == question.id,
        );
        expect(answered.questionAnswered, isTrue);
        expect(next.chat.canAnswerQuestion(answered), isFalse);
        final again = await app([], storage: next.storage);
        final readOnly = again.chat.messages.singleWhere(
          (message) => message.id == question.id,
        );
        expect(readOnly.questionAnswered, isTrue);
        expect(again.chat.canAnswerQuestion(readOnly), isFalse);
        expect(again.client.requests, isEmpty);
      },
    );
  }

  test(
    'interrupted task saves progress and continues in a new App without replay',
    () async {
      final entered = Completer<void>();
      final blocked = Completer<Object>();
      final id = CoachV2Fixtures.stretching.first;
      final first = await app([
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('interrupted-start', 'start_task', {
            'type': 'recommend',
          }),
          CoachV2Fixtures.call('interrupted-params', 'set_params', {
            'fields': {
              'goal': CoachV2Fixtures.sourced(['purpose.stretch'], '拉伸'),
            },
          }),
          CoachV2Fixtures.call('interrupted-search', 'search_actions', {
            'tags': <String>[],
            'keywords': fixture.catalog[id]!.name.of('en'),
          }),
        ]),
        (coach.LlmRequest request) {
          entered.complete();
          return blocked.future;
        },
      ]);
      final request = first.chat.send('在家徒手拉伸');
      await entered.future;
      await first.chat.flushPersistence();
      final saved = first.saved;
      expect(saved.ledger.turns.last.outcome, 'interrupted');
      expect(saved.sessionState.params['goal']!.quote, '拉伸');
      expect(saved.sessionState.seenActionIds, contains(id));
      final crashCopy = MemoryStorage()..data.addAll(first.storage.data);
      first.chat.cancelRequest();
      blocked.complete('迟到内容不进入已保存的快照。');
      await request;
      final next = await app([
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('interrupted-output', 'show_actions', {
            'ids': [id],
            'note': '从舒适范围内的拉伸开始。',
          }),
        ]),
      ], storage: crashCopy);
      sameLedger(saved, next);
      expect(next.saved.ledger.turns.last.outcome, 'interrupted');
      await send(next, '继续刚才的拉伸');
      expect(
        next.chat.messages
            .lastWhere((message) => message.actions != null)
            .actions!
            .items
            .single
            .id,
        id,
      );
      expect(
        next.chat.messages.any((message) => message.text.contains('迟到内容')),
        isFalse,
      );
      restoredRequestHasNoOldWireMessages(
        next.client.requests.first,
        '继续刚才的拉伸',
      );
    },
  );

  for (final raw in ['{broken', '{"schemaVersion":999}', '{}']) {
    test(
      'invalid snapshot $raw falls back observably without a chat warning',
      () async {
        final logBefore = RuntimeLog.instance;
        final log = RuntimeLog(enabled: true);
        RuntimeLog.instance = log;
        addTearDown(() => RuntimeLog.instance = logBefore);
        final first = await app(fixture.recommendationTurn());
        await send(first, '在家徒手拉伸');
        final texts = first.chat.messages
            .map((message) => message.text)
            .toList();
        await first.store.setConversation(
          first.store.chatLog.toList(),
          sessionJson: raw,
        );
        final next = await app([], storage: first.storage);
        await Future<void>.delayed(Duration.zero);
        expect(
          next.events.where(
            (event) =>
                event.kind == coach.AgentEventKind.snapshotRestoreFallback,
          ),
          hasLength(1),
        );
        expect(next.chat.messages.map((message) => message.text), texts);
        expect(next.client.requests, isEmpty);
        final events = (jsonDecode(log.exportJson()) as Map)['events'] as List;
        expect(
          events.where(
            (event) => '${(event as Map)['event']}'.contains('snapshot'),
          ),
          isNotEmpty,
        );
      },
    );
  }

  test(
    'pending question is rebuilt when saved display messages omit it',
    () async {
      final first = await app([_ask(_question('choice'))]);
      await send(first, '我想练一下');
      final question = first.chat.messages.singleWhere(
        (message) => message.question != null,
      );
      final saved = first.saved;
      await first.store.setConversation(
        [
          for (final row in first.store.chatLog)
            if (row['id'] != question.id) row,
        ],
        sessionJson: first.store.coachSessionJson,
        sdkMessages: [
          for (final row in first.store.coachDisplayMessages)
            if (row['id'] != question.conversationMessageId) row,
        ],
      );
      final next = await app(['已经记下，继续准备。'], storage: first.storage);
      sameLedger(saved, next);
      final restored = next.chat.messages.singleWhere(
        (message) => message.question != null,
      );
      expect(restored.conversationMessageId, saved.pendingQuestionMessageId);
      expect(next.chat.canAnswerQuestion(restored), isTrue);
      await next.chat.answerQuestion(restored, '在家');
      await next.chat.flushPersistence();
      expect(next.engine.lastResult?.status, coach.TurnStatus.ok);
      expect(next.chat.canAnswerQuestion(restored), isFalse);
    },
  );

  test(
    'SDK question delivered during App display delay survives a process restart',
    () async {
      final first = await app([
        _ask(_question('choice')),
      ], replyDelay: const Duration(milliseconds: 800));
      final pending = first.chat.send('我想练一下');
      for (
        var spin = 0;
        first.engine.conversation.state.pendingQuestion == null;
        spin++
      ) {
        expect(
          spin,
          lessThan(1000),
          reason: 'Fake question should be delivered promptly.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(first.chat.typing, isTrue);
      expect(
        first.chat.messages.where((message) => message.question != null),
        isEmpty,
      );
      await first.chat.flushPersistence();
      final saved = first.saved;
      expect(saved.pendingQuestion, isNotNull);
      expect(
        first.store.coachDisplayMessages.any((row) => row['question'] != null),
        isTrue,
      );
      final crashCopy = MemoryStorage()..data.addAll(first.storage.data);
      first.chat.cancelRequest();
      await pending;
      final next = await app([], storage: crashCopy);
      sameLedger(saved, next);
      final restored = next.chat.messages.singleWhere(
        (message) => message.question != null,
      );
      expect(next.chat.canAnswerQuestion(restored), isTrue);
    },
  );

  test(
    'conversation writes keep opaque snapshot and both display lists paired atomically',
    () async {
      final storage = _RecordingStorage();
      final store = AppStore(storage);
      addTearDown(store.dispose);
      await store.acceptSafety(blocked: false);
      storage.writes.clear();
      await Future.wait([
        for (final value in ['a', 'b'])
          store.setConversation(
            [
              {'case': value},
            ],
            sessionJson: jsonEncode({'case': value}),
            sdkMessages: [
              {'case': value},
            ],
          ),
      ]);
      expect(storage.writes, isNotEmpty);
      for (final write in storage.writes) {
        final snapshot = jsonDecode(write['coachSessionJson'] as String) as Map;
        expect((write['chat'] as List).single['case'], snapshot['case']);
        expect(
          (write['coachDisplay'] as List).single['case'],
          snapshot['case'],
        );
      }
      final reloaded = AppStore(storage);
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(jsonDecode(reloaded.coachSessionJson!)['case'], 'b');
      expect(reloaded.chatLog.single['case'], 'b');
      expect(reloaded.coachDisplayMessages.single['case'], 'b');
    },
  );

  test(
    'new conversation persists an empty SDK ledger and does not revive old cards',
    () async {
      final first = await app(fixture.recommendationTurn());
      await send(first, '在家徒手拉伸，编号 Saved-Conversation-Case');
      await first.chat.newConversation();
      await first.chat.flushPersistence();
      expect(first.saved.sessionState.userTurns, isEmpty);
      expect(first.saved.ledger.turns, isEmpty);
      expect(first.saved.recommendations, isEmpty);
      expect(first.saved.pendingQuestion, isNull);
      final next = await app(['你好，今天想怎么练？'], storage: first.storage);
      expect(next.engine.agent.sessionState.userTurns, isEmpty);
      expect(
        next.chat.messages.where((message) => message.actions != null),
        isEmpty,
      );
      await send(next, '你好');
      expect(
        jsonEncode(
          next.client.requests.first.messages
              .map((message) => message.toJson())
              .toList(),
        ),
        isNot(contains('Saved-Conversation-Case')),
      );
    },
  );
}
