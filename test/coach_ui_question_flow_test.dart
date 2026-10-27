import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/domain/exercise.dart' show DoseMode;
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'app_flow_test.dart' show services, tall;

coach.LlmResponse _tool(String name, Map<String, Object?> arguments) =>
    coach.LlmResponse(
      content: '',
      toolCalls: [
        coach.LlmToolCall(
          id: 'ui-$name',
          name: name,
          arguments: jsonEncode(arguments),
        ),
      ],
    );

Map<String, Object?> _form(List<String> keys) => {
  'question': '补充一下训练条件，也可以直接出方案。',
  'mode': 'form',
  'fields': [
    for (final key in keys)
      switch (key) {
        'scene' => {
          'key': key,
          'label': '场景',
          'options': ['办公室', '家里', '健身房'],
          'multiple': false,
        },
        'equipment' => {
          'key': key,
          'label': '器械',
          'options': [
            '徒手',
            _catalog.taxonomy.equipmentLabel('mat'),
            _catalog.taxonomy.equipmentLabel('chair'),
          ],
          'multiple': true,
        },
        _ => {
          'key': key,
          'label': '时长',
          'options': ['5 分钟', '10 分钟', '15 分钟', '20+ 分钟'],
          'multiple': false,
        },
      },
  ],
  'skipLabel': '直接出方案',
};

TrainingPlan _plan({
  int minutes = 10,
  String scene = 'home',
  String goal = 'fullbody',
}) => TrainingPlan(
  id: 'form-plan-$minutes',
  source: 'ai',
  title: '训练计划',
  summary: '按确认条件编排。',
  goal: goal,
  scene: scene,
  equipment: const [],
  level: 1,
  targetMinutes: minutes,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-step-jack',
          mode: DoseMode.time,
          sets: minutes >= 15 ? 6 : 5,
          workSeconds: minutes == 7 ? 84 : 120,
          perSide: false,
          restSeconds: minutes == 20
              ? 90
              : minutes == 15
              ? 30
              : 0,
        ),
      ],
    ),
  ],
);

List<String> _inputs(AiChatEngine engine) => [
  for (final message in engine.conversation.state.messages)
    if (message.isUser) message.text,
];

Map<String, dynamic> _knownTrainingParameters(coach.LlmRequest request) {
  final system = request.messages
      .where((message) => message.role == coach.LlmRole.system)
      .map((message) => message.content)
      .join('\n');
  final line = RegExp(r'^已知：(.+)$', multiLine: true).firstMatch(system);
  expect(
    line,
    isNotNull,
    reason: 'Inspect the actual SDK-inferred parameters sent to the model.',
  );
  return jsonDecode(line!.group(1)!) as Map<String, dynamic>;
}

void _expectKnownEquipment(coach.LlmRequest request, Set<String> equipment) {
  final known = _knownTrainingParameters(request);
  expect(known['equipment'], isA<List>());
  expect((known['equipment'] as List).cast<String>().toSet(), equipment);
  expect(known['scene'], 'home');
  expect(known['minutes'], 10);
}

ChatMessage _expectForm(
  WidgetTester tester,
  ChatController chat,
  List<String> fields,
) {
  final questions = chat.messages
      .where((message) => message.question != null)
      .toList();
  expect(
    questions,
    hasLength(1),
    reason:
        'Missing user facts must produce one admitted SDK form, not a default plan.',
  );
  final question = questions.single;
  expect(find.byType(CoachQuestionBubble), findsOneWidget);
  final bubble = tester.widget<CoachQuestionBubble>(
    find.byType(CoachQuestionBubble),
  );
  expect(bubble.question.mode, CoachQuestionMode.form);
  expect(bubble.question.fields.map((field) => field.key), fields);
  expect(bubble.onFormAnswer, isNotNull);
  expect(find.byKey(ValueKey('question-skip-${question.id}')), findsOneWidget);
  expect(chat.canAnswerQuestion(question), isTrue);
  return question;
}

void _expectAdmittedPlan(
  AiChatEngine engine,
  ChatController chat, {
  required int minutes,
}) {
  expect(engine.lastOutcome, coach.TurnOutcome.model);
  expect(engine.lastFallbackReason, isNull);
  expect(engine.lastResult!.plan, isNotNull);
  expect(engine.lastResult!.plan!.plan.targetMinutes, minutes);
  expect(
    chat.messages.where((message) => message.validatedPlan != null),
    isNotEmpty,
  );
  expect(chat.currentPlan!.targetMinutes, minutes);
}

Future<void> _restorePlanOnly(AppServices app) => app.store.setChatLog([
  ChatMessage(
    id: 'restored-default-plan',
    role: ChatRole.assistant,
    at: DateTime(2026, 10, 27),
    text: '旧计划',
    plan: _plan(),
    request: const ScenarioRequest(),
    aiVisible: true,
  ).toJson(),
]);

late coach.Catalog _catalog;

AiChatEngine _engine(
  AppServices app,
  coach.FakeLlmClient client, {
  coach.UserMemoryStore? memoryStore,
  bool enableUserMemory = false,
}) {
  final engine = AiChatEngine(
    local: RuleChatEngine(lib: app.library, templates: app.templates),
    catalog: _catalog,
    profile: coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    ),
    client: client,
    memoryStore: memoryStore,
    enableUserMemory: enableUserMemory,
  );
  addTearDown(engine.dispose);
  return engine;
}

Future<ChatController> _mount(
  WidgetTester tester,
  AppServices app,
  AiChatEngine engine,
) async {
  tall(tester);
  await app.store.acceptSafety(blocked: false);
  final chat = ChatController(
    engine: engine,
    store: app.store,
    replyDelay: Duration.zero,
  )..start();
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(),
        home: ChatHomePage(controller: chat),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    _catalog = (await PoseHubActionLibrary.load()).toAiCatalog();
  });
  test('question mapper preserves form groups and existing stored modes', () {
    for (final data in <Map<String, Object?>>[
      {'question': '哪里更紧？', 'mode': 'text'},
      {
        'question': '选一个重点',
        'mode': 'choice',
        'options': ['站姿', '坐姿'],
        'multiple': false,
      },
      _form(['scene', 'equipment', 'minutes']),
    ]) {
      final question = coach.AskUserGate.check(jsonEncode(data)).question!;
      final message = ChatMessage(
        id: 'mapped',
        role: ChatRole.assistant,
        at: DateTime(2026, 10, 27),
        question: question,
        conversationMessageId: 'sdk-question',
      );
      final mapped = toCoachQuestionData(message);
      expect(mapped.mode.name, question.mode.name);
      expect(mapped.options, question.options);
      expect(
        mapped.fields.map((f) => f.key),
        question.fields.map((f) => f.key),
      );
      expect(
        mapped.fields.map((f) => f.options),
        question.fields.map((f) => f.options),
      );
      expect(
        mapped.fields.map((f) => f.multiple),
        question.fields.map((f) => f.multiple),
      );
      expect(mapped.skipLabel, question.skipLabel);
      final restored = ChatMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())),
      );
      expect(restored.question!.toJson(), question.toJson());
    }
  });

  test(
    'memory summaries reach the model without becoming known training parameters',
    () async {
      final app = services();
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(
          coach.MemoryKind.scene,
          '家里',
          at: DateTime.utc(2026, 10, 27),
        ),
        coach.MemoryEntry(
          coach.MemoryKind.equipment,
          '哑铃',
          at: DateTime.utc(2026, 10, 27),
        ),
      ]);
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
      ], latency: Duration.zero);
      final engine = _engine(
        app,
        client,
        memoryStore: memory,
        enableUserMemory: true,
      );
      final reply = await engine.reply('帮我安排一组训练', const ChatState());
      expect(engine.agent.memoryStore, same(memory));
      expect(engine.agent.enableUserMemory, isTrue);
      expect(client.requests, hasLength(1));
      final system = client.requests.single.messages
          .where((message) => message.role == coach.LlmRole.system)
          .map((message) => message.content)
          .join('\n');
      expect(system, contains('- scene：家里'));
      expect(system, contains('- equipment：哑铃'));
      // Check both the App's retained turn slots and the actual SDK prompt.
      // Memory must remain model reference material, not explicit user facts.
      final appContext = reply.state.coachContext!;
      expect(appContext.scene, isNull);
      expect(appContext.equipment, isNull);
      expect(appContext.minutes, isNull);
      final knownLine = RegExp(
        r'^已知：(.+)$',
        multiLine: true,
      ).firstMatch(system);
      expect(knownLine, isNotNull);
      final known = jsonDecode(knownLine!.group(1)!) as Map<String, dynamic>;
      for (final key in ['scene', 'equipment', 'minutes']) {
        expect(
          known,
          isNot(contains(key)),
          reason: 'Remembered $key must not fill CoachContext.',
        );
      }
      final question = reply.messages
          .where((message) => message.question != null)
          .single
          .question!;
      expect(question.mode, coach.AskUserMode.form);
      expect(question.fields.map((field) => field.key), [
        'scene',
        'equipment',
        'minutes',
      ]);
      expect(
        reply.messages.where((message) => message.validatedPlan != null),
        isEmpty,
      );
      expect(
        engine.conversation.state.pendingQuestion!.question!.fields.map(
          (field) => field.key,
        ),
        ['scene', 'equipment', 'minutes'],
      );
      expect(engine.lastOutcome, coach.TurnOutcome.model);
      expect(engine.lastFallbackReason, isNull);
    },
  );

  for (final mode in ['text', 'choice']) {
    testWidgets('legacy $mode bubble uses the same SDK answer channel', (
      tester,
    ) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool('ask_user', {
          'question': '你更关心哪一种？',
          'mode': mode,
          if (mode == 'choice') 'options': ['站姿', '坐姿'],
        }),
        const coach.LlmResponse(content: '收到，会按你说的继续。'),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final agent = engine.agent;
      final chat = await _mount(tester, app, engine);
      await chat.send('想了解动作要领');
      await tester.pumpAndSettle();
      final question = chat.messages.last;
      expect(question.question!.mode.name, mode);
      if (mode == 'text') {
        await tester.enterText(
          find.byKey(ValueKey('question-input-${question.id}')),
          '坐姿',
        );
      } else {
        await tester.tap(
          find.byKey(ValueKey('question-option-${question.id}-1')),
        );
      }
      await tester.pump();
      if (mode == 'text') {
        await tester.tap(
          find.byKey(ValueKey('question-submit-${question.id}')),
        );
      }
      await tester.pumpAndSettle();
      expect(_inputs(engine), ['想了解动作要领', '坐姿']);
      expect(client.requests, hasLength(2));
      expect(engine.agent, same(agent));
      expect(
        chat.messages.firstWhere((m) => m.id == question.id).questionAnswered,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'one missing parameter maps only that form group and submits grouped values',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['equipment'])),
        const coach.LlmResponse(content: '收到你的条件。'),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('在家10分钟，排个训练组');
      await tester.pumpAndSettle();
      final question = chat.messages.last;
      expect(
        question.question,
        isNotNull,
        reason: client.requests.map((r) => r.messages.last.content).join('\n'),
      );
      final bubble = tester.widget<CoachQuestionBubble>(
        find.byType(CoachQuestionBubble),
      );
      expect(bubble.question.mode, CoachQuestionMode.form);
      expect(bubble.question.fields.map((f) => f.key), ['equipment']);
      expect(bubble.onFormAnswer, isNotNull);
      for (final index in [1, 2]) {
        await tester.tap(
          find.byKey(
            ValueKey('question-field-${question.id}-equipment-$index'),
          ),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${question.id}')));
      await tester.pumpAndSettle();
      expect(
        _inputs(engine).last,
        '器械：${_catalog.taxonomy.equipmentLabel('mat')}、${_catalog.taxonomy.equipmentLabel('chair')}',
      );
      expect(client.requests, hasLength(2));
      final stored = app.store.chatLog.firstWhere(
        (m) => m['id'] == question.id,
      );
      expect((stored['question'] as Map)['mode'], 'form');
      expect(((stored['question'] as Map)['fields'] as List).length, 1);
      expect(stored['questionAnswered'], isTrue);
      expect(chat.canAnswerQuestion(question), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three missing groups complete in one form and deliver the SDK routine card',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
        _tool(coach.CoachTools.showPlan, _plan().toJson()),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      final question = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      expect(find.byType(PlanCard), findsNothing);
      expect(client.requests, hasLength(1));
      final groups = {'scene': 1, 'equipment': 0, 'minutes': 1};
      for (final entry in groups.entries) {
        await tester.tap(
          find.byKey(
            ValueKey(
              'question-field-${question.id}-${entry.key}-${entry.value}',
            ),
          ),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${question.id}')));
      await tester.pumpAndSettle();
      expect(_inputs(engine).last, '场景：家里；器械：徒手；时长：10 分钟');
      expect(client.requests, hasLength(2));
      expect(chat.messages.where((m) => m.question != null), hasLength(1));
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(engine.conversation.state.pendingQuestion, isNull);
      _expectAdmittedPlan(engine, chat, minutes: 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'form skip delegates directly to SDK and delivers a default routine',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
        _tool(coach.CoachTools.showPlan, _plan(minutes: 15).toJson()),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      final question = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      await tester.tap(find.byKey(ValueKey('question-skip-${question.id}')));
      await tester.pumpAndSettle();
      expect(_inputs(engine).last, '直接出方案');
      expect(client.requests, hasLength(2));
      expect(engine.lastResult!.plan!.plan.targetMinutes, 15);
      _expectAdmittedPlan(engine, chat, minutes: 15);
      expect(engine.conversation.state.pendingQuestion, isNull);
      expect(
        chat.messages
            .firstWhere((message) => message.id == question.id)
            .questionAnswered,
        isTrue,
      );
      expect(
        chat.messages.where((message) => message.question != null),
        hasLength(1),
      );
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'office intent asks only equipment and minutes and uses grouped UI answers',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['equipment', 'minutes'])),
        _tool(
          coach.CoachTools.showPlan,
          _plan(scene: 'office', goal: 'relax').toJson(),
        ),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('在办公室放松一下');
      await tester.pumpAndSettle();
      final question = _expectForm(tester, chat, ['equipment', 'minutes']);
      expect(find.byType(PlanCard), findsNothing);
      expect(client.requests, hasLength(1));
      for (final (field, option) in [('equipment', 0), ('minutes', 1)]) {
        await tester.tap(
          find.byKey(ValueKey('question-field-${question.id}-$field-$option')),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${question.id}')));
      await tester.pumpAndSettle();
      expect(_inputs(engine), ['在办公室放松一下', '器械：徒手；时长：10 分钟']);
      expect(client.requests, hasLength(2));
      expect(
        chat.messages.where((message) => message.question != null),
        hasLength(1),
      );
      expect(engine.conversation.state.pendingQuestion, isNull);
      expect(chat.currentPlan!.scene, 'office');
      _expectAdmittedPlan(engine, chat, minutes: 10);
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (name, initial, changed, before, after)
      in <(String, String, String, Set<String>, Set<String>)>[
        ('bare hands to chair', '在家徒手10分钟练全身', '这次用椅子', {}, {'chair'}),
        (
          'band to only dumbbells',
          '在家用弹力带10分钟练全身',
          '现在只有哑铃',
          {'band'},
          {'dumbbell'},
        ),
        (
          'dumbbells to no dumbbells',
          '在家用哑铃10分钟练全身',
          '这次不用哑铃',
          {'dumbbell'},
          {},
        ),
      ]) {
    testWidgets(
      'live equipment correction survives a neutral next turn: $name',
      (tester) async {
        final app = services();
        final client = coach.FakeLlmClient([
          const coach.LlmResponse(content: '收到最初的训练条件。'),
          const coach.LlmResponse(content: '收到，按新的器械条件继续。'),
          const coach.LlmResponse(content: '会继续采用刚才确认的条件。'),
        ], latency: Duration.zero);
        final engine = _engine(app, client);
        final chat = await _mount(tester, app, engine);
        await chat.send(initial);
        await tester.pumpAndSettle();
        expect(client.requests, hasLength(1));
        _expectKnownEquipment(client.requests.single, before);
        expect(engine.lastOutcome, coach.TurnOutcome.model);
        await chat.send(changed);
        await tester.pumpAndSettle();
        expect(client.requests, hasLength(2));
        _expectKnownEquipment(client.requests.last, after);
        expect(engine.lastOutcome, coach.TurnOutcome.model);
        // No skip/defaults are involved: scene/time were explicit on turn one.
        // A neutral third input detects stale App aggregates overriding the
        // SDK's correctly interpreted equipment change from the prior turn.
        const followUp = '请按刚才的条件继续';
        await chat.send(followUp);
        await tester.pumpAndSettle();
        expect(client.requests, hasLength(3));
        _expectKnownEquipment(client.requests.last, after);
        expect(_inputs(engine), [initial, changed, followUp]);
        expect(engine.conversation.state.pendingQuestion, isNull);
        expect(engine.lastOutcome, coach.TurnOutcome.model);
        expect(engine.lastFallbackReason, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'form equipment replaces a barehand default and survives a neutral next turn',
    (tester) async {
      final app = services();
      // A restored card's empty equipment is an old App default, not a user
      // fact. Re-asking an explicitly known equipment field would violate the
      // SDK form gate, so begin with this genuine restored-state boundary.
      await _restorePlanOnly(app);
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
        const coach.LlmResponse(content: '收到你选择的瑜伽垫和椅子。'),
        const coach.LlmResponse(content: '继续采用刚才确认的器械。'),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      expect(chat.currentPlan!.equipment, isEmpty);
      const initial = '帮我安排一组训练';
      await chat.send(initial);
      await tester.pumpAndSettle();
      final question = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      // Exercise the actual UI's 徒手→瑜伽垫+椅子 replacement, then send the
      // resulting grouped values through ChatController and SDK answerForm.
      for (final (field, option) in [
        ('scene', 1),
        ('equipment', 0),
        ('equipment', 1),
        ('equipment', 2),
        ('minutes', 1),
      ]) {
        await tester.tap(
          find.byKey(ValueKey('question-field-${question.id}-$field-$option')),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${question.id}')));
      await tester.pumpAndSettle();
      final answer =
          '场景：家里；器械：${_catalog.taxonomy.equipmentLabel('mat')}、${_catalog.taxonomy.equipmentLabel('chair')}；时长：10 分钟';
      expect(_inputs(engine), [initial, answer]);
      expect(client.requests, hasLength(2));
      _expectKnownEquipment(client.requests.last, {'mat', 'chair'});
      expect(engine.conversation.state.pendingQuestion, isNull);
      const followUp = '请按刚才的条件继续';
      await chat.send(followUp);
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(3));
      _expectKnownEquipment(client.requests.last, {'mat', 'chair'});
      expect(_inputs(engine), [initial, answer, followUp]);
      expect(engine.lastOutcome, coach.TurnOutcome.model);
      expect(engine.lastFallbackReason, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit home barehand 20-minute core request delivers directly without form',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool(
          coach.CoachTools.showPlan,
          _plan(minutes: 20, goal: 'core').toJson(),
        ),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('在家徒手20分钟练核心');
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      expect(_inputs(engine), ['在家徒手20分钟练核心']);
      expect(
        chat.messages.where((message) => message.question != null),
        isEmpty,
      );
      expect(find.byType(CoachQuestionBubble), findsNothing);
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(chat.currentPlan!.scene, 'home');
      expect(chat.currentPlan!.equipment, isEmpty);
      expect(chat.currentPlan!.goal, 'core');
      _expectAdmittedPlan(engine, chat, minutes: 20);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a new simple-training request does not become an edit of the old plan',
    () async {
      final app = services();
      final oldPlan = _plan();
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final reply = await engine.reply(
        '帮我安排简单训练',
        ChatState(
          plan: oldPlan,
          request: const ScenarioRequest(),
          coachContext: const Slots(scene: 'home', equipment: {}, minutes: 10),
        ),
      );
      expect(client.requests, hasLength(1));
      final appContext = reply.state.coachContext!;
      expect(appContext.scene, isNull);
      expect(appContext.equipment, isNull);
      expect(appContext.minutes, isNull);
      final system = client.requests.single.messages
          .where((message) => message.role == coach.LlmRole.system)
          .map((message) => message.content)
          .join('\n');
      final knownLine = RegExp(
        r'^已知：(.+)$',
        multiLine: true,
      ).firstMatch(system);
      expect(knownLine, isNotNull);
      final known = jsonDecode(knownLine!.group(1)!) as Map<String, dynamic>;
      for (final key in ['scene', 'equipment', 'minutes', 'notes']) {
        expect(
          known.containsKey(key),
          isFalse,
          reason: 'A fresh request must not inherit old-plan $key.',
        );
      }
      final userInput = client.requests.single.messages
          .where((message) => message.role == coach.LlmRole.user)
          .map((message) => message.content)
          .join('\n');
      expect(userInput, isNot(contains('用户当前明确采用的训练计划')));
      expect(userInput, isNot(contains(oldPlan.id)));
      final question = reply.messages
          .where((message) => message.question != null)
          .single
          .question!;
      expect(question.mode, coach.AskUserMode.form);
      expect(question.fields.map((field) => field.key), [
        'scene',
        'equipment',
        'minutes',
      ]);
      expect(engine.conversation.state.pendingQuestion, isNotNull);
      expect(engine.lastOutcome, coach.TurnOutcome.model);
      expect(engine.lastFallbackReason, isNull);
    },
  );

  for (final (source, state) in [
    (
      'coachContext',
      const ChatState(
        coachContext: Slots(
          scene: 'home',
          equipment: {},
          minutes: 10,
          level: 1,
          avoid: {'wrist'},
        ),
      ),
    ),
    (
      'pending',
      const ChatState(
        pending: Slots(scene: 'home', equipment: {}, minutes: 10),
      ),
    ),
    (
      'restored plan request',
      ChatState(plan: _plan(), request: const ScenarioRequest()),
    ),
  ]) {
    test(
      'aggregated $source defaults are not user facts for a fresh training intent',
      () async {
        final app = services();
        final client = coach.FakeLlmClient([
          _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
        ], latency: Duration.zero);
        final engine = _engine(app, client);
        final result = await engine.reply('帮我安排一组训练', state);
        final questions = result.messages
            .where((message) => message.question != null)
            .toList();
        expect(
          questions,
          hasLength(1),
          reason:
              'Aggregate $source defaults must not suppress clarification (${engine.lastResult?.status.name}).',
        );
        final question = questions.single.question!;
        expect(question.mode, coach.AskUserMode.form);
        expect(question.fields.map((field) => field.key), [
          'scene',
          'equipment',
          'minutes',
        ]);
        expect(
          result.messages.where((message) => message.validatedPlan != null),
          isEmpty,
        );
        expect(result.state.coachContext!.scene, isNull);
        expect(result.state.coachContext!.equipment, isNull);
        expect(result.state.coachContext!.minutes, isNull);
        expect(client.requests, hasLength(1));
        expect(engine.conversation.state.pendingQuestion, isNotNull);
        expect(engine.lastOutcome, coach.TurnOutcome.model);
      },
    );
  }

  testWidgets(
    'restored assistant plan without user facts still renders one complete clarification form',
    (tester) async {
      final app = services();
      await _restorePlanOnly(app);
      final client = coach.FakeLlmClient([
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      expect(chat.currentPlan!.id, _plan().id);
      expect(chat.messages.where((message) => message.isUser), isEmpty);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      _expectForm(tester, chat, ['scene', 'equipment', 'minutes']);
      expect(_inputs(engine), ['帮我安排一组训练']);
      expect(client.requests, hasLength(1));
      // The restored card stays available, but must not count as three user facts
      // or cause another plan to be delivered before the form is answered.
      expect(
        chat.messages.where((message) => message.plan != null),
        hasLength(1),
      );
      expect(engine.lastResult!.plan, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit adjustment can reuse the adopted plan conditions without another form',
    (tester) async {
      final app = services();
      await _restorePlanOnly(app);
      final client = coach.FakeLlmClient([
        _tool(coach.CoachTools.showPlan, _plan(minutes: 7).toJson()),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('把当前方案缩短到7分钟');
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      expect(find.byType(CoachQuestionBubble), findsNothing);
      expect(
        chat.messages.where((message) => message.question != null),
        isEmpty,
      );
      expect(chat.currentPlan!.scene, 'home');
      expect(chat.currentPlan!.equipment, isEmpty);
      _expectAdmittedPlan(engine, chat, minutes: 7);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new conversation clears old explicit facts before a fresh grouped question',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool(coach.CoachTools.showPlan, _plan().toJson()),
        _tool('ask_user', _form(['scene', 'equipment', 'minutes'])),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('在家徒手10分钟练全身');
      await tester.pumpAndSettle();
      _expectAdmittedPlan(engine, chat, minutes: 10);
      await chat.newConversation();
      await tester.pumpAndSettle();
      expect(chat.currentPlan, isNull);
      expect(_inputs(engine), isEmpty);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      _expectForm(tester, chat, ['scene', 'equipment', 'minutes']);
      expect(client.requests, hasLength(2));
      expect(_inputs(engine), ['帮我安排一组训练']);
      expect(find.byType(CoachPlanCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
