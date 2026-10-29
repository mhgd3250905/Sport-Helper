import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/coach_delivery_transition.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/validated_plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/polish_card.dart';
import 'package:smartfit/ui/theme/widgets.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services, tall;
import 'support.dart';
import 'support/coach_v2_fixtures.dart';

class _SessionEngine
    implements ManagedChatEngine, RestorableChatEngine, ProgressChatEngine {
  _SessionEngine(this.gate);
  final coach.ToolGate gate;
  final pending = <Completer<ChatReply>>[];
  final states = <ChatState>[];
  final inputs = <String>[];
  int cancellations = 0;
  int resets = 0;
  final eventBus = StreamController<coach.AgentEvent>.broadcast(sync: true);
  @override
  Stream<coach.AgentEvent> get events => eventBus.stream;
  @override
  String get id => 'test-session';
  @override
  Future<ChatReply> reply(String text, ChatState state) {
    inputs.add(text);
    states.add(state);
    final result = Completer<ChatReply>();
    pending.add(result);
    return result.future;
  }

  @override
  void cancelPending() => cancellations++;
  @override
  void reset() => resets++;
  @override
  void dispose() => unawaited(eventBus.close());
  @override
  coach.ValidatedActions? restoreActions(List<String> ids) => gate.check('', [
    coach.LlmToolCall(
      id: 'restored',
      name: 'show_actions',
      arguments: jsonEncode({
        'items': [
          for (final id in ids) {'actionId': id},
        ],
      }),
    ),
  ]).actions;
  @override
  coach.ValidatedPlan? restorePlan(
    TrainingPlan plan,
    ScenarioRequest? request,
  ) => gate.admitTemplate(const coach.PlanCodec().decode(plan.toJson()));
}

void main() {
  final library = loadLibrary();
  final packs = loadPacksSync();
  final catalog = const coach.DrillPackAdapter().build(
    version: 'chat-test',
    packs: {for (final pack in packs.exercises) pack.id: pack.json},
  );
  final profile = coach.CoachProfile.fromJson(
    jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
  );
  final gate = coach.ToolGate(catalog: catalog, profile: profile);

  TrainingPlan aiPlan() => const TrainingPlan(
    id: 'validated-test-plan',
    source: 'ai',
    title: '轻松早安式',
    summary: '用徒手早安式活动髋部。',
    goal: 'fullbody',
    scene: 'home',
    equipment: [],
    level: 1,
    targetMinutes: 10,
    blocks: [
      PlanBlock(
        id: 'main',
        name: '主训练',
        type: BlockType.main,
        rounds: 1,
        restBetweenRoundsSeconds: 0,
        items: [
          PlanItem(
            exerciseId: 'h-good-morning',
            mode: DoseMode.reps,
            sets: 1,
            reps: 10,
            perSide: false,
            restSeconds: 10,
          ),
        ],
      ),
    ],
  );

  Future<(ChatController, _SessionEngine, AppServices)> setup() async {
    final app = services();
    await app.store.acceptSafety(blocked: false);
    final engine = _SessionEngine(gate);
    final chat = ChatController(
      engine: engine,
      store: app.store,
      replyDelay: Duration.zero,
    )..start();
    addTearDown(chat.dispose);
    addTearDown(engine.dispose);
    return (chat, engine, app);
  }

  Future<void> showChat(
    WidgetTester tester,
    ChatController chat,
    AppServices app,
  ) => tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(),
        home: ChatHomePage(controller: chat),
      ),
    ),
  );

  coach.CoachTaskState taskSnapshot({
    required String current,
    required String stamp,
  }) => coach.CoachTaskState(
    type: 'plan',
    reused: false,
    nodes: [
      const coach.CoachNodeState(
        id: 'understand',
        status: 'done',
        stamp: '已确认训练目标',
        doneAtTurn: 1,
      ),
      coach.CoachNodeState(id: current, status: 'current', stamp: stamp),
    ],
  );

  Finder cancelButton() =>
      find.byKey(const ValueKey('generation-cancel-target')).hitTestable();

  void expectTask(ChatController chat, String current, String stamp) {
    final nodes = chat.activeTask!.nodes;
    expect(nodes.map((node) => node.id), ['understand', current]);
    expect(nodes.map((node) => node.status), ['done', 'current']);
    expect(nodes.map((node) => node.stamp), ['已确认训练目标', stamp]);
  }

  testWidgets(
    'SDK node snapshots render before mount and cancellation filters late events',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      final pending = chat.send('给我排计划');
      // The first event arrives before the bubble mounts; it must be replayed.
      engine.eventBus.add(
        coach.AgentEvent(
          'turn',
          coach.AgentEventKind.node,
          step: 1,
          task: taskSnapshot(current: 'actions', stamp: '候选动作来自 SDK'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expectTask(chat, 'actions', '候选动作来自 SDK');
      expect(find.text('读懂你的需求'), findsOneWidget);
      expect(find.text('候选动作来自 SDK'), findsNothing);
      expect(find.text('已确认训练目标'), findsNothing);
      engine.eventBus.add(
        coach.AgentEvent(
          'turn',
          coach.AgentEventKind.node,
          step: 2,
          task: taskSnapshot(current: 'review', stamp: 'SDK 正在核对动作编排'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expectTask(chat, 'review', 'SDK 正在核对动作编排');
      expect(find.text('最后检查一遍'), findsOneWidget);
      expect(find.text('SDK 正在核对动作编排'), findsNothing);
      expect(find.text('候选动作来自 SDK'), findsNothing);
      final beforeCancel = chat.activeTask;
      await tester.tap(cancelButton());
      await tester.pump();
      engine.eventBus.add(
        coach.AgentEvent(
          'turn',
          coach.AgentEventKind.node,
          step: 3,
          task: taskSnapshot(current: 'output', stamp: '取消后的旧节点'),
        ),
      );
      engine.pending.single.complete(
        ChatReply(
          messages: const [BotMessage('迟到')],
          state: engine.states.single,
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(chat.activeTask, same(beforeCancel));
      expectTask(chat, 'review', 'SDK 正在核对动作编排');
      expect(find.text('迟到'), findsNothing);
      expect(find.byType(CoachTaskBubble), findsNothing);
      expect(find.text('取消后的旧节点'), findsNothing);
    },
  );

  testWidgets(
    'retries do not replace SDK task nodes and done ignores late events',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      final pending = chat.send('给我排计划');
      await tester.pump();
      engine.eventBus.add(
        coach.AgentEvent(
          'retry-turn',
          coach.AgentEventKind.node,
          task: taskSnapshot(current: 'review', stamp: 'SDK 核对中的任务'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expectTask(chat, 'review', 'SDK 核对中的任务');
      expect(find.text('最后检查一遍'), findsOneWidget);
      expect(find.text('SDK 核对中的任务'), findsNothing);
      final beforeRetry = chat.activeTask;
      engine.eventBus.add(
        const coach.AgentEvent(
          'retry-turn',
          coach.AgentEventKind.retrying,
          attempt: 1,
          maxAttempts: 4,
        ),
      );
      await tester.pump();
      expect(find.text('网络不稳，正在重试（1/4）…'), findsNothing);
      expect(chat.activeTask, same(beforeRetry));
      expectTask(chat, 'review', 'SDK 核对中的任务');
      expect(find.text('最后检查一遍'), findsOneWidget);
      expect(
        tester.widget<ChatInputBar>(find.byType(ChatInputBar)).enabled,
        isFalse,
      );
      engine.eventBus.add(
        const coach.AgentEvent(
          'retry-turn',
          coach.AgentEventKind.done,
          status: coach.TurnStatus.ok,
        ),
      );
      engine.eventBus.add(
        coach.AgentEvent(
          'retry-turn',
          coach.AgentEventKind.node,
          task: taskSnapshot(current: 'actions', stamp: '结束后的迟到节点'),
        ),
      );
      await tester.pump();
      expect(chat.activeTask, same(beforeRetry));
      expectTask(chat, 'review', 'SDK 核对中的任务');
      expect(find.text('结束后的迟到节点'), findsNothing);
      expect(find.text('最后检查一遍'), findsOneWidget);
      expect(find.text('SDK 核对中的任务'), findsNothing);
      engine.pending.single.complete(
        ChatReply(
          messages: const [BotMessage('计划准备好了')],
          state: engine.states.single,
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(find.byType(CoachTaskBubble).hitTestable(), findsNothing);
      for (final bubble in find.byType(CoachTaskBubble).evaluate()) {
        expect(TickerMode.valuesOf(bubble).enabled, isFalse);
      }
      expect(find.text('计划准备好了'), findsOneWidget);
    },
  );

  testWidgets('cancelled turn events cannot overwrite the next request', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    final cancelled = chat.send('第一条请求');
    engine.eventBus.add(
      const coach.AgentEvent('cancelled-turn', coach.AgentEventKind.thinking),
    );
    await tester.pump();
    await tester.tap(cancelButton());
    await tester.pump();
    final current = chat.send('新的请求');
    engine.eventBus.add(
      coach.AgentEvent(
        'cancelled-turn',
        coach.AgentEventKind.node,
        task: taskSnapshot(current: 'review', stamp: '已取消轮次的任务节点'),
      ),
    );
    expect(chat.activeTask, isNull);
    engine.eventBus.add(
      coach.AgentEvent(
        'current-turn',
        coach.AgentEventKind.node,
        task: taskSnapshot(current: 'actions', stamp: '当前轮次的动作节点'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expectTask(chat, 'actions', '当前轮次的动作节点');
    expect(find.text('读懂你的需求'), findsOneWidget);
    expect(find.text('当前轮次的动作节点'), findsNothing);
    expect(find.text('已取消轮次的任务节点'), findsNothing);
    engine.pending[1].complete(
      ChatReply(messages: const [BotMessage('当前回复')], state: engine.states[1]),
    );
    await current;
    engine.pending[0].complete(
      ChatReply(
        messages: const [BotMessage('迟到的旧回复')],
        state: engine.states[0],
      ),
    );
    await cancelled;
    await tester.pumpAndSettle();
    expectTask(chat, 'actions', '当前轮次的动作节点');
    expect(find.text('当前回复'), findsOneWidget);
    expect(find.text('迟到的旧回复'), findsNothing);
  });

  test(
    'one pending turn disables duplicates; cancel hides late replies',
    () async {
      final (chat, engine, _) = await setup();
      final first = chat.send('给我看动作');
      await chat.send('重复发送');
      expect(engine.pending, hasLength(1));
      expect(chat.messages.where((m) => m.isUser), hasLength(1));
      expect(chat.typing, isTrue);
      chat.cancelRequest();
      expect(chat.typing, isFalse);
      expect(engine.cancellations, 1);
      final second = chat.send('新的请求');
      engine.pending[1].complete(
        ChatReply(messages: const [BotMessage('新回复')], state: engine.states[1]),
      );
      await second;
      engine.pending[0].complete(
        ChatReply(
          messages: const [BotMessage('迟到的回复')],
          state: engine.states[0],
        ),
      );
      await first;
      expect(chat.messages.last.text, '新回复');
      expect(chat.messages.any((m) => m.text == '迟到的回复'), isFalse);
    },
  );

  test(
    'new conversation resets SDK and retains safety, saved plans and history',
    () async {
      final (chat, engine, app) = await setup();
      final generated = await app.generator.generate(
        const ScenarioRequest(templateId: 'office-relax'),
      );
      final plan = generated.plan!;
      await chat.save(plan);
      await app.store.addHistory(
        HistoryEntry(
          title: plan.title,
          at: DateTime.now(),
          minutes: 10,
          completed: 1,
          total: 1,
        ),
      );
      final pending = chat.send('生成计划');
      await chat.newConversation();
      expect(engine.resets, 1);
      expect(chat.typing, isFalse);
      expect(chat.currentPlan, isNull);
      expect(chat.messages.single.greeting, isTrue);
      expect(app.store.trainingAllowed, isTrue);
      expect(app.store.savedPlans, hasLength(1));
      expect(app.store.history, hasLength(1));
      expect(app.store.chatLog, hasLength(1));
      engine.pending.single.complete(
        ChatReply(
          messages: const [BotMessage('旧对话回复')],
          state: engine.states.single,
        ),
      );
      await pending;
      expect(chat.messages, hasLength(1));
    },
  );

  test('action persistence contains only IDs and restores through gate', () {
    final engine = _SessionEngine(gate);
    final actions = engine.restoreActions(['h-wall-angel'])!;
    final original = ChatMessage(
      id: 'actions',
      role: ChatRole.assistant,
      at: DateTime(2026),
      actions: actions,
    );
    final json = original.toJson().cast<String, dynamic>();
    expect(json['actionIds'], ['h-wall-angel']);
    expect(json.containsKey('actions'), isFalse);
    expect(
      ChatMessage.fromJson(json, restoreWith: engine).actions?.items.single.id,
      'h-wall-angel',
    );
    json['actionIds'] = ['unknown-action'];
    expect(ChatMessage.fromJson(json, restoreWith: engine).actions, isNull);
  });

  test('AI snapshots and edited training plans must pass the gate', () async {
    final (chat, engine, app) = await setup();
    final valid = aiPlan();
    expect(
      coach.PlanValidator(catalog: catalog, profile: profile)
          .validate(const coach.PlanCodec().decode(valid.toJson()))
          .errors
          .map((issue) => issue.message),
      isEmpty,
      reason: 'The rendering fixture must itself pass the current SDK gate.',
    );
    final invalid = valid.copyWith(
      blocks: [
        valid.blocks.single.copyWith(
          items: [
            const PlanItem(
              exerciseId: 'unknown-action',
              mode: DoseMode.reps,
              sets: 1,
              reps: 10,
              perSide: false,
              restSeconds: 10,
            ),
          ],
        ),
      ],
    );
    final pending = chat.send('显示已存的计划');
    engine.pending.single.complete(
      ChatReply(
        messages: [BotMessage('这个计划', plan: invalid)],
        state: engine.states.single,
      ),
    );
    await pending;
    expect(chat.messages.last.plan, isNull);
    expect(chat.messages.last.validatedPlan, isNull);
    expect(await chat.started(invalid), isFalse);
    expect(app.store.lastPlan, isNull);
    expect(await chat.started(valid), isTrue);
    expect(chat.messages.last.validatedPlan, isNotNull);
    expect(app.store.lastPlan?.id, valid.id);
  });

  test(
    'stored AI plan needs a current gate before it becomes a card',
    () async {
      final plan = aiPlan();
      final json = ChatMessage(
        id: 'plan',
        role: ChatRole.assistant,
        at: DateTime(2026),
        plan: plan,
      ).toJson().cast<String, dynamic>();
      expect(json['isAiPlan'], isTrue);
      expect(ChatMessage.fromJson(json).plan, isNull);
      final restored = ChatMessage.fromJson(
        json,
        restoreWith: _SessionEngine(gate),
      );
      expect(restored.validatedPlan, isNotNull);
      expect(restored.plan?.id, plan.id);
    },
  );

  testWidgets('waiting before SDK task nodes blocks send and offers cancel', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    await tester.pumpAndSettle();
    final pending = chat.send('排个计划');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(CoachTaskBubble), findsOneWidget);
    expect(chat.activeTask, isNull);
    expect(find.text('正在想怎么练'), findsOneWidget);
    expect(find.text('读懂你的需求'), findsOneWidget);
    expect(find.byKey(const ValueKey('generation-core')), findsOneWidget);
    expect(
      tester.widget<ChatInputBar>(find.byType(ChatInputBar)).enabled,
      isFalse,
    );
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '稍后再发');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    expect(engine.pending, hasLength(1));
    await tester.tap(cancelButton());
    await tester.pump();
    expect(find.byType(CoachTaskBubble), findsNothing);
    expect(
      tester.widget<ChatInputBar>(find.byType(ChatInputBar)).enabled,
      isTrue,
    );
    engine.pending.single.complete(
      ChatReply(
        messages: const [BotMessage('取消后不能显示')],
        state: engine.states.single,
      ),
    );
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('取消后不能显示'), findsNothing);
  });

  testWidgets('reply data and typing finish before the 890ms visual delivery', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    await tester.pumpAndSettle();
    final generated = await app.generator.generate(
      const ScenarioRequest(templateId: 'office-relax'),
    );
    final plan = generated.plan!;
    final request = chat.send('在家安排一套拉伸');
    await tester.pump();
    final wrapper = find.byType(CoachDeliveryTransition);
    final originalState = tester.state(wrapper);
    expect(
      tester.widget<CoachDeliveryTransition>(wrapper).key,
      isA<GlobalKey>(),
    );
    engine.pending.single.complete(
      ChatReply(
        messages: [BotMessage('已经写入的计划', plan: plan)],
        state: engine.states.single.copyWith(plan: plan),
      ),
    );
    await request;
    await chat.flushPersistence();
    expect(chat.typing, isFalse);
    expect(chat.currentPlan, same(plan));
    expect(chat.messages.last.plan, same(plan));
    expect(app.store.chatLog.last['plan'], isNotNull);
    await tester.pump();
    expect(tester.state(wrapper), same(originalState));
    expect(
      tester.widget<ChatInputBar>(find.byType(ChatInputBar)).enabled,
      isTrue,
    );
    expect(find.byType(PlanCard), findsNothing);
    expect(find.text('已经写入的计划'), findsNothing);
    expect(
      tester
          .widget<CoachTaskBubble>(find.byType(CoachTaskBubble))
          .visualComplete,
      isTrue,
    );
    // CoachAppear removes its entry-animation ancestors after 640 ms. The
    // wrapper must keep its state when that SDK subtree is reparented.
    await tester.pump(const Duration(milliseconds: 650));
    expect(tester.state(wrapper), same(originalState));
    expect(find.byType(PlanCard), findsNothing);
    await tester.pump(const Duration(milliseconds: 239));
    expect(tester.state(wrapper), same(originalState));
    expect(find.byType(PlanCard), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.text('已经写入的计划'), findsOneWidget);
    expect(find.byType(CoachTaskBubble), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recommendation also uses the successful visual marker', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    await tester.pumpAndSettle();
    final request = chat.send('推荐一个动作');
    await tester.pump();
    final actions = engine.restoreActions(['h-wall-angel'])!;
    engine.pending.single.complete(
      ChatReply(
        messages: [BotMessage('这个动作适合你', actions: actions)],
        state: engine.states.single,
      ),
    );
    await request;
    expect(chat.typing, isFalse);
    expect(chat.messages.last.actions, same(actions));
    await tester.pump();
    expect(
      tester
          .widget<CoachDeliveryTransition>(find.byType(CoachDeliveryTransition))
          .successful,
      isTrue,
    );
    expect(find.byType(CoachRecommendCard), findsNothing);
    await tester.pump(const Duration(milliseconds: 890));
    expect(find.byType(CoachRecommendCard), findsOneWidget);
    expect(find.byType(CoachTaskBubble), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new request skips the previous completed visual immediately', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    await tester.pumpAndSettle();
    final plan = (await app.generator.generate(
      const ScenarioRequest(templateId: 'office-relax'),
    )).plan!;
    final first = chat.send('第一套计划');
    await tester.pump();
    engine.pending.single.complete(
      ChatReply(
        messages: [BotMessage('', plan: plan)],
        state: engine.states.single.copyWith(plan: plan),
      ),
    );
    await first;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlanCard), findsNothing);
    final second = chat.send('把时间改短');
    await tester.pump();
    final deliveryKeys = tester
        .widgetList<CoachDeliveryTransition>(
          find.byType(CoachDeliveryTransition),
        )
        .map((widget) => widget.key)
        .toList();
    expect(deliveryKeys, hasLength(2));
    expect(deliveryKeys.every((key) => key is GlobalKey), isTrue);
    expect(deliveryKeys.toSet(), hasLength(2));
    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.byType(CoachTaskBubble), findsOneWidget);
    expect(
      tester
          .widget<CoachTaskBubble>(find.byType(CoachTaskBubble))
          .visualComplete,
      isFalse,
    );
    expect(find.byKey(const ValueKey('generation-check')), findsNothing);
    engine.pending.last.complete(
      ChatReply(
        messages: const [BotMessage('继续讨论')],
        state: engine.states.last,
      ),
    );
    await second;
    await tester.pumpAndSettle();
    final cachedPreparation = find.byType(CoachTaskBubble);
    expect(cachedPreparation, findsOneWidget);
    expect(cachedPreparation.hitTestable(), findsNothing);
    expect(
      TickerMode.valuesOf(tester.element(cachedPreparation)).enabled,
      isFalse,
    );
    final cachedFade = find
        .ancestor(of: cachedPreparation, matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(cachedFade).opacity.value, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byKey(const ValueKey('generation-check')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final failure in [true, false]) {
    testWidgets(
      '${failure ? 'failure' : 'ordinary text'} retains the original 300ms transition without a check',
      (tester) async {
        tall(tester);
        final (chat, engine, app) = await setup();
        await showChat(tester, chat, app);
        await tester.pumpAndSettle();
        final request = chat.send('生成计划');
        await tester.pump();
        engine.eventBus.add(
          coach.AgentEvent(
            'done-without-successful-reply',
            coach.AgentEventKind.node,
            task: coach.CoachTaskState(
              type: 'plan',
              reused: false,
              nodes: [
                coach.CoachNodeState(
                  id: 'output',
                  status: 'done',
                  stamp: 'SDK事实',
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('generation-check')), findsNothing);
        engine.pending.single.complete(
          ChatReply(
            messages: [
              failure
                  ? const BotMessage('', isPlanningFailure: true)
                  : const BotMessage('普通文字回复'),
            ],
            state: engine.states.single,
          ),
        );
        await request;
        await tester.pump();
        expect(chat.typing, isFalse);
        expect(
          tester
              .widget<CoachDeliveryTransition>(
                find.byType(CoachDeliveryTransition),
              )
              .successful,
          isFalse,
        );
        final fade = tester.widget<AnimatedCrossFade>(
          find.byKey(const ValueKey('coach-delivery-crossfade')),
        );
        expect(fade.duration, const Duration(milliseconds: 300));
        expect(fade.sizeCurve, Curves.easeOutCubic);
        expect(fade.crossFadeState, CrossFadeState.showSecond);
        final preparation = find.byType(CoachTaskBubble, skipOffstage: false);
        expect(
          tester.widget<CoachTaskBubble>(preparation).visualComplete,
          isFalse,
        );
        expect(
          TickerMode.valuesOf(tester.element(preparation)).enabled,
          isFalse,
        );
        expect(find.byKey(const ValueKey('generation-check')), findsNothing);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('generation-check')), findsNothing);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('new conversation removes a completed visual hold safely', (
    tester,
  ) async {
    tall(tester);
    final (chat, engine, app) = await setup();
    await showChat(tester, chat, app);
    await tester.pumpAndSettle();
    final plan = (await app.generator.generate(
      const ScenarioRequest(templateId: 'office-relax'),
    )).plan!;
    final request = chat.send('安排一套计划');
    await tester.pump();
    engine.pending.single.complete(
      ChatReply(
        messages: [BotMessage('', plan: plan)],
        state: engine.states.single.copyWith(plan: plan),
      ),
    );
    await request;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('generation-check')), findsOneWidget);
    final oldKey =
        tester
                .widget<CoachDeliveryTransition>(
                  find.byType(CoachDeliveryTransition),
                )
                .key!
            as GlobalKey;
    await chat.newConversation();
    await tester.pumpAndSettle();
    expect(chat.messages.single.greeting, isTrue);
    expect(find.byType(CoachTaskBubble), findsNothing);
    expect(find.byType(CoachDeliveryTransition), findsNothing);
    expect(find.byType(PlanCard), findsNothing);
    expect(oldKey.currentState, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('generation-check')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing the page keeps conversation; new conversation clears it',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      final pending = chat.send('保留这个对话');
      engine.pending.single.complete(
        ChatReply(
          messages: const [BotMessage('会话仍在')],
          state: engine.states.single,
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await showChat(tester, chat, app);
      await tester.pumpAndSettle();
      expect(find.text('会话仍在'), findsOneWidget);
      expect(engine.resets, 0);
      expect(find.byKey(const ValueKey('chat-new-conversation')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-new-conversation')));
      await tester.pumpAndSettle();
      expect(find.text('会话仍在'), findsNothing);
      expect(engine.resets, 1);
    },
  );

  testWidgets(
    'recommendation uses SDK rendering once and sends the exact plan request',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      const note = '慢慢舒展肩部，保持自然呼吸。';
      final reply = chat.send('推荐一下');
      engine.pending.single.complete(
        ChatReply(
          messages: [
            BotMessage(note, actions: engine.restoreActions(['h-wall-angel'])),
          ],
          state: engine.states.single,
        ),
      );
      await reply;
      await tester.pumpAndSettle();
      final card = find.byType(CoachRecommendCard);
      expect(card, findsOneWidget);
      expect(find.text(note), findsOneWidget);
      final style = CoachUiTheme.of(tester.element(card));
      final defaults = CoachUiStyle.fromTheme(Theme.of(tester.element(card)));
      expect(style.builders.surface, isNull);
      expect(style.builders.controlFace, isNull);
      expect(style.builders.pressable, isNull);
      expect(style.builders.media, isNull);
      expect(style.builders.icon, isNull);
      expect(style.builders.textAction, isNull);
      expect(style.builders.startButton, isNull);
      expect(style.colors.cardSurface, defaults.colors.cardSurface);
      expect(style.colors.cardBorder, defaults.colors.cardBorder);
      expect(style.colors.primaryForeground, defaults.colors.primaryForeground);
      expect(style.typography.callout, defaults.typography.callout);
      expect(style.typography.caption, defaults.typography.caption);
      expect(
        find.descendant(of: card, matching: find.byType(SfPolishCard)),
        findsNothing,
      );
      final title = tester.widget<Text>(
        find.text(library['h-wall-angel'].name),
      );
      expect(title.style!.fontSize, 15);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(title.style!.height, 1.35);
      final tags = tester.widget<Text>(find.text('入门 · 墙'));
      expect(tags.style!.fontSize, 12);
      final recommendation = tester.widget<CoachRecommendCard>(card);
      expect(recommendation.library.tryGet('h-wall-angel')!.levelLabel, '入门');
      expect(
        recommendation.library.tryGet('h-wall-angel')!.equipmentLabel,
        '墙',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('recommend-plan-button')),
      );
      await tester.tap(find.byKey(const ValueKey('recommend-plan-button')));
      await tester.pump();
      expect(engine.inputs.last, '请把刚才推荐的动作排成计划。');
      engine.pending.last.complete(
        ChatReply(messages: const [], state: engine.states.last),
      );
      await tester.pumpAndSettle();
    },
  );

  test(
    'PoseHub recommendations reuse the action browser first-frame asset',
    () async {
      final fixture = await CoachV2Fixtures.load();
      final exercise = fixture.library['s-butterfly'];
      final adapted = toCoachRecommendationExercise(exercise);
      expect(
        adapted.stillCutout,
        'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/s-butterfly.webp',
      );
      expect(adapted.name, exercise.name);
      expect(adapted.levelLabel, isNotEmpty);
      expect(adapted.equipmentLabel, isNotEmpty);
    },
  );

  testWidgets(
    'validated recommendations use the SDK card, trusted metadata and callbacks',
    (tester) async {
      String? opened;
      final actions = _SessionEngine(gate).restoreActions(['h-wall-angel'])!;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => withSmartfitRecommendUi(
                context,
                CoachRecommendCard(
                  actionIds: actions.items.map((action) => action.id).toList(),
                  note: '慢慢舒展肩部。',
                  library: CoachExerciseLibrary([
                    for (final action in actions.items)
                      toCoachRecommendationExercise(library[action.id]),
                  ]),
                  onOpenAction: (id) => opened = id,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(library['h-wall-angel'].name), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('recommend-action-h-wall-angel')),
      );
      expect(opened, 'h-wall-angel');
    },
  );

  testWidgets(
    'a validated plan keeps its explanation and saves through the card',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      final plan = aiPlan();
      final validated = engine.restorePlan(plan, null)!;
      final pending = chat.send('帮我排一下');
      engine.pending.single.complete(
        ChatReply(
          messages: [
            BotMessage('给你一套轻松的计划。', plan: plan, validatedPlan: validated),
          ],
          state: engine.states.single,
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(find.text('给你一套轻松的计划。'), findsOneWidget);
      expect(find.byType(ValidatedPlanCard), findsOneWidget);
      expect(find.byType(PlanCard), findsOneWidget);
      final expand = find.byKey(ValueKey('plan-expand-${validated.plan.id}'));
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      expect(find.text('给你一套轻松的计划。'), findsOneWidget);
      final save = find.byWidgetPredicate(
        (widget) => widget is SfTextAction && widget.label == '保存',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(app.store.savedPlans.single.plan.id, validated.plan.id);
    },
  );
}
