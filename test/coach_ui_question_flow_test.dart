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

TrainingPlan _plan({int minutes = 10}) => TrainingPlan(
  id: 'form-plan-$minutes',
  source: 'ai',
  title: '训练计划',
  summary: '按确认条件编排。',
  goal: 'fullbody',
  scene: 'home',
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
          sets: minutes == 15 ? 6 : 5,
          workSeconds: 120,
          perSide: false,
          restSeconds: minutes == 15 ? 30 : 0,
        ),
      ],
    ),
  ],
);

List<String> _inputs(AiChatEngine engine) => [
  for (final message in engine.conversation.state.messages)
    if (message.isUser) message.text,
];

late coach.Catalog _catalog;

AiChatEngine _engine(AppServices app, coach.FakeLlmClient client) {
  final engine = AiChatEngine(
    local: RuleChatEngine(lib: app.library, templates: app.templates),
    catalog: _catalog,
    profile: coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    ),
    client: client,
    enableUserMemory: false,
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
      await chat.send('帮我排个训练组');
      await tester.pumpAndSettle();
      final question = chat.messages.last;
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
      await chat.send('帮我排个训练组');
      await tester.pumpAndSettle();
      final question = chat.messages.last;
      await tester.tap(find.byKey(ValueKey('question-skip-${question.id}')));
      await tester.pumpAndSettle();
      expect(_inputs(engine).last, '直接出方案');
      expect(client.requests, hasLength(2));
      expect(engine.lastResult!.plan!.plan.targetMinutes, 15);
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'known App scene, equipment and minutes reach SDK without a clarification',
    () async {
      final app = services();
      final client = coach.FakeLlmClient([
        _tool(coach.CoachTools.showPlan, _plan().toJson()),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
      final result = await engine.reply(
        '帮我排个训练组',
        const ChatState(
          coachContext: Slots(
            scene: 'home',
            equipment: {},
            minutes: 10,
            level: 1,
            avoid: {'wrist'},
          ),
        ),
      );
      expect(result.messages.single.question, isNull);
      expect(result.messages.single.validatedPlan, isNotNull);
      expect(client.requests, hasLength(1));
      expect(engine.conversation.state.pendingQuestion, isNull);
      expect(result.state.coachContext!.avoid, {'wrist'});
    },
  );
}
