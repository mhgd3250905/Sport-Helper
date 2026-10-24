import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services, tall;
import 'support.dart' show loadPacksSync;

coach.LlmResponse _tool(String name, Map<String, Object?> arguments) =>
    coach.LlmResponse(
      content: '',
      toolCalls: [
        coach.LlmToolCall(
          id: 'question-ui-$name',
          name: name,
          arguments: jsonEncode(arguments),
        ),
      ],
    );

List<String> _inputs(AiChatEngine engine) => [
  for (final message in engine.conversation.state.messages)
    if (message.isUser) message.text,
];

void main() {
  testWidgets(
    'SDK text and multi-choice bubbles continue into a routine card',
    (tester) async {
      tall(tester);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      final generated = await app.generator.generate(
        const ScenarioRequest(templateId: 'office-relax', scene: 'office'),
      );
      final client = coach.FakeLlmClient([
        _tool('ask_user', {'question': '现在主要哪里紧？', 'mode': 'text'}),
        _tool('ask_user', {
          'question': '可以用哪些器械？',
          'mode': 'choice',
          'options': ['瑜伽垫', '弹力带', '椅子'],
          'multiple': true,
        }),
        _tool(coach.CoachTools.showPlan, generated.plan!.toJson()),
      ], latency: Duration.zero);
      final packs = loadPacksSync();
      final engine = AiChatEngine(
        local: RuleChatEngine(lib: app.library, templates: app.templates),
        catalog: const coach.DrillPackAdapter().build(
          version: 'smartfit-question-ui-test',
          packs: {for (final pack in packs.exercises) pack.id: pack.json},
        ),
        profile: coach.CoachProfile.fromJson(
          jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
        ),
        client: client,
        enableUserMemory: false,
      );
      final agent = engine.agent;
      expect(engine.conversation.agent, same(agent));
      addTearDown(engine.dispose);
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
      await chat.send('在办公室帮我安排训练');
      await tester.pumpAndSettle();
      expect(find.byType(CoachChatList), findsOneWidget);
      expect(find.text('现在主要哪里紧？'), findsOneWidget);
      final textQuestion = chat.messages.last;
      expect(textQuestion.text, isEmpty);
      await tester.enterText(
        find.byKey(ValueKey('question-input-${textQuestion.id}')),
        '下背紧',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('question-submit-${textQuestion.id}')),
      );
      await tester.pumpAndSettle();
      expect(_inputs(engine), ['在办公室帮我安排训练', '下背紧']);
      expect(engine.agent, same(agent));
      expect(find.text('现在主要哪里紧？'), findsOneWidget);
      expect(find.text('可以用哪些器械？'), findsOneWidget);
      final choiceQuestion = chat.messages.last;
      await tester.tap(
        find.byKey(ValueKey('question-option-${choiceQuestion.id}-2')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('question-option-${choiceQuestion.id}-0')),
      );
      await tester.pump();
      expect(_inputs(engine), hasLength(2));
      await tester.tap(
        find.byKey(ValueKey('question-submit-${choiceQuestion.id}')),
      );
      await tester.pumpAndSettle();
      expect(_inputs(engine).last, '瑜伽垫、椅子');
      expect(client.requests, hasLength(3));
      expect(client.requests.last.messages.last.content, endsWith('瑜伽垫、椅子'));
      expect(engine.agent, same(agent));
      expect(agent.turnCount, 3);
      expect(
        chat.messages
            .firstWhere((m) => m.id == choiceQuestion.id)
            .answeredChoices,
        ['瑜伽垫', '椅子'],
      );
      expect(
        chat.messages
            .where((m) => m.question != null)
            .every((m) => m.questionAnswered),
        isTrue,
      );
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.byType(CoachPlanCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
