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
      rounds: goal == 'core'
          ? 2
          : minutes >= 20
          ? 4
          : minutes >= 15
          ? 3
          : 2,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-step-jack',
          mode: DoseMode.time,
          sets: 3,
          workSeconds: minutes == 7 ? 60 : 80,
          perSide: false,
          restSeconds: 30,
        ),
        if (goal == 'core')
          const PlanItem(
            exerciseId: 'o-stand-sidebend',
            mode: DoseMode.time,
            sets: 2,
            workSeconds: 60,
            perSide: true,
            restSeconds: 30,
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
  final line = RegExp(r'^当前条件：(.+)$', multiLine: true).firstMatch(system);
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
    'remembered scene and equipment are offered only as previous choices',
    () async {
      final app = services();
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(coach.MemoryKind.scene, '家里', at: DateTime.utc(2026)),
        coach.MemoryEntry(
          coach.MemoryKind.equipment,
          '哑铃',
          at: DateTime.utc(2026),
        ),
      ]);
      final client = coach.FakeLlmClient([], latency: Duration.zero);
      final engine = _engine(
        app,
        client,
        memoryStore: memory,
        enableUserMemory: true,
      );
      final reply = await engine.reply('帮我安排一组训练', const ChatState());
      expect(
        client.requests,
        isEmpty,
        reason: 'r2 confirmation is local preflight',
      );
      final question = reply.messages.single.question!;
      expect(question.isConfirmation, isTrue);
      expect(question.fields.map((f) => f.key), [
        'scene',
        'equipment',
        'minutes',
      ]);
      expect(question.fields.first.previousSelections, ['家里']);
      expect(question.fields[1].previousSelections, contains('哑铃'));
      expect(question.fields.last.preselected, isEmpty);
      expect(reply.messages.single.plan, isNull);
      expect(engine.agent.lastConfirmedForm, isNull);
    },
  );

  testWidgets(
    'r2 confirmation submits all selections and persists an answered summary',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([
        const coach.LlmException(
          coach.LlmErrorKind.http,
          'test failure',
          statusCode: 401,
        ),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      final message = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      final question = message.question!;
      expect(question.isConfirmation, isTrue);
      expect(client.requests, isEmpty);
      for (final (field, value) in [
        ('scene', '家里'),
        ('equipment', '徒手'),
        ('minutes', '10 分钟'),
      ]) {
        final group = question.fields.firstWhere((f) => f.key == field);
        final index = group.options.indexOf(value);
        expect(index, greaterThanOrEqualTo(0));
        await tester.tap(
          find.byKey(ValueKey('question-field-${message.id}-$field-$index')),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${message.id}')));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      _expectKnownEquipment(client.requests.single, {});
      final updated = chat.messages.firstWhere((m) => m.id == message.id);
      expect(updated.questionAnswered, isTrue);
      expect(updated.answeredForm, {
        'scene': ['家里'],
        'equipment': ['徒手'],
        'minutes': ['10 分钟'],
      });
      expect(
        find.byKey(ValueKey('question-summary-${message.id}')),
        findsOneWidget,
      );
      expect(chat.canAnswerQuestion(updated), isFalse);
      expect(
        ChatMessage.fromJson(
          jsonDecode(jsonEncode(updated.toJson())),
        ).answeredForm,
        updated.answeredForm,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('default action closes confirmation with SDK default summary', (
    tester,
  ) async {
    final app = services();
    final client = coach.FakeLlmClient([
      const coach.LlmException(
        coach.LlmErrorKind.http,
        'test failure',
        statusCode: 401,
      ),
    ], latency: Duration.zero);
    final engine = _engine(app, client);
    final chat = await _mount(tester, app, engine);
    await chat.send('帮我安排一组训练');
    await tester.pumpAndSettle();
    final message = _expectForm(tester, chat, [
      'scene',
      'equipment',
      'minutes',
    ]);
    expect(message.question!.skipLabel, '按默认来');
    final defaults = message.question!.defaultSelections;
    await tester.tap(find.byKey(ValueKey('question-skip-${message.id}')));
    await tester.pumpAndSettle();
    expect(_inputs(engine).last, '按默认来');
    expect(client.requests, hasLength(1));
    final updated = chat.messages.firstWhere((m) => m.id == message.id);
    expect(updated.questionAnswered, isTrue);
    expect(updated.answeredForm, defaults);
    expect(
      find.byKey(ValueKey('question-summary-${message.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'office and ten minutes are preselected while all three groups remain editable',
    (tester) async {
      final app = services();
      final client = coach.FakeLlmClient([], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('在办公室10分钟安排一组训练');
      await tester.pumpAndSettle();
      final message = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      final question = message.question!;
      expect(question.isConfirmation, isTrue);
      expect(question.fields.first.preselected, ['办公室']);
      expect(question.fields.first.previousSelections, isEmpty);
      expect(question.fields.last.preselected, ['10 分钟']);
      expect(question.fields[1].preselected, isEmpty);
      expect(client.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (source, state) in [
    (
      'coachContext',
      const ChatState(
        coachContext: Slots(scene: 'home', equipment: {}, minutes: 10),
      ),
    ),
    (
      'pending',
      const ChatState(
        pending: Slots(scene: 'home', equipment: {}, minutes: 10),
      ),
    ),
    (
      'previous plan',
      ChatState(plan: _plan(), request: const ScenarioRequest()),
    ),
  ]) {
    test(
      '$source provides optional previous choices, never a completed confirmation',
      () async {
        final app = services();
        final client = coach.FakeLlmClient([], latency: Duration.zero);
        final engine = _engine(app, client);
        final reply = await engine.reply('帮我安排一组训练', state);
        final question = reply.messages.single.question!;
        expect(question.isConfirmation, isTrue);
        expect(question.fields.map((f) => f.key), [
          'scene',
          'equipment',
          'minutes',
        ]);
        expect(question.fields.first.previousSelections, ['家里']);
        expect(question.fields.last.previousSelections, ['10 分钟']);
        expect(engine.agent.lastConfirmedForm, isNull);
        expect(reply.messages.single.plan, isNull);
        expect(client.requests, isEmpty);
      },
    );
  }

  testWidgets(
    'new focus after an existing plan presents previous choices and permits changing equipment',
    (tester) async {
      final app = services();
      await _restorePlanOnly(app);
      final client = coach.FakeLlmClient([
        const coach.LlmException(
          coach.LlmErrorKind.http,
          'test failure',
          statusCode: 401,
        ),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      await chat.send('我想针对大腿内侧进行拉伸');
      await tester.pumpAndSettle();
      final message = _expectForm(tester, chat, [
        'scene',
        'equipment',
        'minutes',
      ]);
      expect(message.question!.focus, '大腿内侧');
      final fields = message.question!.fields;
      expect(fields.first.previousSelections, ['家里']);
      expect(fields.last.previousSelections, ['10 分钟']);
      final equipment = fields.firstWhere((f) => f.key == 'equipment');
      for (final id in ['chair', 'wall']) {
        final label = _catalog.taxonomy.equipmentLabel(id);
        final index = equipment.options.indexOf(label);
        expect(index, greaterThanOrEqualTo(0));
        await tester.tap(
          find.byKey(ValueKey('question-field-${message.id}-equipment-$index')),
        );
        await tester.pump();
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${message.id}')));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(1));
      _expectKnownEquipment(client.requests.single, {'chair', 'wall'});
      final updated = chat.messages.firstWhere((m) => m.id == message.id);
      expect(updated.answeredForm['minutes'], ['10 分钟']);
      expect(updated.answeredForm['equipment']!.toSet(), {
        _catalog.taxonomy.equipmentLabel('chair'),
        _catalog.taxonomy.equipmentLabel('wall'),
      });
      expect(
        find.byKey(ValueKey('question-summary-${message.id}')),
        findsOneWidget,
      );
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
      expect(client.requests, isEmpty);
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
      expect(client.requests, hasLength(1));
      expect(_inputs(engine), ['帮我安排一组训练']);
      expect(find.byType(CoachPlanCard), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
