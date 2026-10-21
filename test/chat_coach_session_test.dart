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
import 'package:smartfit/ui/chat/action_card.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/validated_plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/widgets.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services, tall;
import 'support.dart';

class _SessionEngine
    implements ManagedChatEngine, RestorableChatEngine, ProgressChatEngine {
  _SessionEngine(this.gate);
  final coach.ToolGate gate;
  final pending = <Completer<ChatReply>>[];
  final states = <ChatState>[];
  int cancellations = 0;
  int resets = 0;
  final eventBus = StreamController<coach.AgentEvent>.broadcast(sync: true);
  @override
  Stream<coach.AgentEvent> get events => eventBus.stream;
  @override
  String get id => 'test-session';
  @override
  Future<ChatReply> reply(String text, ChatState state) {
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
    title: '轻松提踵',
    summary: '用提踵唤醒小腿。',
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
            exerciseId: 'h-calf-raise',
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

  testWidgets(
    'Agent progress shows reading and checking, cancellation hides late events',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      final pending = chat.send('给我排计划');
      engine.eventBus.add(
        const coach.AgentEvent('turn', coach.AgentEventKind.reading, step: 1),
      );
      await tester.pump();
      expect(find.text('正在查动作库'), findsOneWidget);
      engine.eventBus.add(
        const coach.AgentEvent('turn', coach.AgentEventKind.checking, step: 2),
      );
      await tester.pump();
      expect(find.text('正在核对计划'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-cancel')));
      await tester.pump();
      engine.eventBus.add(
        const coach.AgentEvent('turn', coach.AgentEventKind.reading, step: 3),
      );
      expect(chat.progressLabel, isNull);
      engine.pending.single.complete(
        ChatReply(
          messages: const [BotMessage('迟到')],
          state: engine.states.single,
        ),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(find.text('迟到'), findsNothing);
      expect(find.text('正在查动作库'), findsNothing);
    },
  );

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

  testWidgets(
    'waiting explains long plan generation, blocks send and offers cancel',
    (tester) async {
      tall(tester);
      final (chat, engine, app) = await setup();
      await showChat(tester, chat, app);
      await tester.pumpAndSettle();
      final pending = chat.send('排个计划');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('助理会分步查动作和核对计划，可能需要几分钟'), findsOneWidget);
      expect(
        tester.widget<ChatInputBar>(find.byType(ChatInputBar)).enabled,
        isFalse,
      );
      await tester.enterText(find.byKey(const ValueKey('chat-input')), '稍后再发');
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      expect(engine.pending, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('chat-cancel')));
      await tester.pump();
      expect(find.byType(TypingBubble), findsNothing);
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
    },
  );

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
      await tester.tap(find.byKey(const ValueKey('chat-new-conversation')));
      await tester.pumpAndSettle();
      expect(find.text('会话仍在'), findsNothing);
      expect(engine.resets, 1);
    },
  );

  testWidgets(
    'validated actions use bundled details and have no training dose',
    (tester) async {
      String? opened;
      final actions = _SessionEngine(gate).restoreActions(['h-wall-angel'])!;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ActionCard(
              actions: actions,
              library: library,
              onOpen: (exercise) => opened = exercise.id,
            ),
          ),
        ),
      );
      expect(find.text(library['h-wall-angel'].name), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('coach-action-h-wall-angel')));
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
