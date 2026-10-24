import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services, tall;

class _QuestionEngine implements ChatEngine {
  _QuestionEngine(this.plan);
  final TrainingPlan plan;
  final inputs = <String>[];
  @override
  String get id => 'question-ui-test';
  @override
  Future<ChatReply> reply(String text, ChatState state) async {
    inputs.add(text);
    if (inputs.length <= 2) {
      final question = coach.AskUserGate.check(
        jsonEncode(
          inputs.length == 1
              ? {'question': '现在主要哪里紧？', 'mode': 'text'}
              : {
                  'question': '可以用哪些器械？',
                  'mode': 'choice',
                  'options': ['瑜伽垫', '弹力带', '椅子'],
                  'multiple': true,
                },
        ),
      ).question!;
      return ChatReply(
        aiTurn: true,
        state: state,
        messages: [BotMessage(question.question, question: question)],
      );
    }
    return ChatReply(
      aiTurn: true,
      state: state.copyWith(plan: plan),
      messages: [BotMessage('按刚才的回答安排好了。', plan: plan)],
    );
  }
}

void main() {
  testWidgets(
    'SDK text and multi-choice bubbles continue into a routine card',
    (tester) async {
      tall(tester);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      final generated = await app.generator.generate(
        const ScenarioRequest(templateId: 'office-relax'),
      );
      final engine = _QuestionEngine(generated.plan!);
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
      await chat.send('帮我安排训练');
      await tester.pumpAndSettle();
      expect(find.byType(CoachChatList), findsOneWidget);
      expect(find.text('现在主要哪里紧？'), findsOneWidget);
      final textQuestion = chat.messages.last;
      await tester.enterText(
        find.byKey(ValueKey('question-input-${textQuestion.id}')),
        '下背紧',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('question-submit-${textQuestion.id}')),
      );
      await tester.pumpAndSettle();
      expect(engine.inputs, ['帮我安排训练', '下背紧']);
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
      expect(engine.inputs, hasLength(2));
      await tester.tap(
        find.byKey(ValueKey('question-submit-${choiceQuestion.id}')),
      );
      await tester.pumpAndSettle();
      expect(engine.inputs.last, '瑜伽垫、椅子');
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
