import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services, tall;
import 'support/coach_v2_fixtures.dart';

Map<String, Object?> _form({bool allFields = true}) => {
  'question': '补充这次训练的条件，也可以直接出方案。',
  'mode': 'form',
  'fields': [
    if (allFields)
      {
        'key': 'scene',
        'label': '场景',
        'options': ['家里', '办公室'],
        'multiple': false,
      },
    if (allFields)
      {
        'key': 'equipment',
        'label': '器械',
        'options': ['徒手', '椅子', '墙'],
        'multiple': true,
      },
    {
      'key': 'minutes',
      'label': '时长',
      'options': ['10分钟', '20分钟'],
      'multiple': false,
    },
  ],
  'skipLabel': '直接出方案',
};

coach.LlmResponse _ask(Map<String, Object?> data) => CoachV2Fixtures.batch([
  CoachV2Fixtures.call('ask-from-model', 'ask_user', data),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachV2Fixtures fixture;
  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
  });

  AiChatEngine engine(
    coach.FakeLlmClient client, {
    coach.UserMemoryStore? memory,
    bool enableMemory = false,
  }) {
    final ai = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: client,
      memoryStore: memory,
      enableUserMemory: enableMemory,
    );
    addTearDown(ai.dispose);
    return ai;
  }

  Future<ChatController> mount(
    WidgetTester tester,
    AppServices app,
    AiChatEngine ai,
  ) async {
    tall(tester);
    await app.store.acceptSafety(blocked: false);
    final chat = ChatController(
      engine: ai,
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

  ChatMessage question(WidgetTester tester, ChatController chat) {
    final message = chat.messages.singleWhere((m) => m.question != null);
    expect(find.byType(CoachQuestionBubble), findsOneWidget);
    expect(chat.canAnswerQuestion(message), isTrue);
    return message;
  }

  test(
    'SDK text choice and form DTOs round trip and map without rewriting',
    () {
      for (final data in [
        {'question': '现在有什么不适？', 'mode': 'text'},
        {
          'question': '想练哪里？',
          'mode': 'choice',
          'options': ['核心', '下肢'],
          'multiple': false,
        },
        _form(),
      ]) {
        final checked = coach.AskUserGate.check(jsonEncode(data)).question;
        expect(checked, isNotNull);
        final message = ChatMessage(
          id: 'mapped',
          role: ChatRole.assistant,
          at: DateTime(2026, 10, 28),
          question: checked,
          conversationMessageId: 'sdk-question',
        );
        final mapped = toCoachQuestionData(message);
        expect(mapped.mode.name, checked!.mode.name);
        expect(mapped.question, checked.question);
        expect(mapped.options, checked.options);
        expect(
          mapped.fields.map((f) => f.key),
          checked.fields.map((f) => f.key),
        );
        expect(
          mapped.fields.map((f) => f.options),
          checked.fields.map((f) => f.options),
        );
        expect(mapped.skipLabel, checked.skipLabel);
        final restored = ChatMessage.fromJson(
          jsonDecode(jsonEncode(message.toJson())),
        );
        expect(restored.question!.toJson(), checked.toJson());
      }
    },
  );

  testWidgets(
    'model can ask only duration without an App three-field preflight',
    (tester) async {
      final client = coach.FakeLlmClient([
        _ask(_form(allFields: false)),
      ], latency: Duration.zero);
      final ai = engine(client);
      final chat = await mount(tester, services(), ai);
      await chat.send('想练一下');
      await tester.pumpAndSettle();
      final m = question(tester, chat);
      expect(m.question!.fields.map((f) => f.key), ['minutes']);
      expect(client.requests, hasLength(1));
      expect(ai.agent.sessionState.userTurns.single.text, '想练一下');
      expect(ai.agent.sessionState.hostValues, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'grouped form submits via SDK and locks old question after answer',
    (tester) async {
      final client = coach.FakeLlmClient([
        _ask(_form()),
        '这些条件已经记下。',
      ], latency: Duration.zero);
      final ai = engine(client);
      final chat = await mount(tester, services(), ai);
      await chat.send('帮我安排训练');
      await tester.pumpAndSettle();
      final m = question(tester, chat);
      final choices = {
        'scene': ['家里'],
        'equipment': ['墙', '椅子'],
        'minutes': ['10分钟'],
      };
      for (final field in m.question!.fields) {
        for (final selected in choices[field.key]!) {
          final index = field.options.indexOf(selected);
          await tester.tap(
            find.byKey(ValueKey('question-field-${m.id}-${field.key}-$index')),
          );
          await tester.pump();
        }
      }
      await tester.tap(find.byKey(ValueKey('question-submit-${m.id}')));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(2));
      final answered = chat.messages.firstWhere(
        (message) => message.id == m.id,
      );
      expect(answered.questionAnswered, isTrue);
      expect(answered.answeredForm, {
        'scene': ['家里'],
        'equipment': ['椅子', '墙'],
        'minutes': ['10分钟'],
      });
      expect(chat.canAnswerQuestion(answered), isFalse);
      expect(
        ai.conversation.state.messages
            .where((message) => message.isUser)
            .last
            .text,
        '场景：家里；器械：椅子、墙；时长：10分钟',
      );
      await chat.answerForm(answered, choices);
      expect(
        client.requests,
        hasLength(2),
        reason: 'Duplicate form submission never reaches model.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('form skip uses SDK skip path and leaves defaults to SDK', (
    tester,
  ) async {
    final client = coach.FakeLlmClient([
      _ask(_form()),
      '按默认条件继续。',
    ], latency: Duration.zero);
    final ai = engine(client);
    final chat = await mount(tester, services(), ai);
    await chat.send('帮我练一下');
    await tester.pumpAndSettle();
    final m = question(tester, chat);
    await tester.tap(find.byKey(ValueKey('question-skip-${m.id}')));
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(2));
    expect(ai.conversation.state.pendingQuestion, isNull);
    expect(
      chat.messages
          .firstWhere((message) => message.id == m.id)
          .questionAnswered,
      isTrue,
    );
    expect(chat.messages.where((message) => message.plan != null), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid form option cannot be submitted to SDK or model', (
    tester,
  ) async {
    final client = coach.FakeLlmClient([_ask(_form())], latency: Duration.zero);
    final ai = engine(client);
    final chat = await mount(tester, services(), ai);
    await chat.send('安排训练');
    await tester.pumpAndSettle();
    final m = question(tester, chat);
    await chat.answerForm(m, {
      'scene': ['家里'],
      'equipment': ['不存在的器械'],
      'minutes': ['10分钟'],
    });
    await tester.pumpAndSettle();
    expect(client.requests, hasLength(1));
    expect(ai.conversation.canAnswer(m.conversationMessageId!), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'memory does not create a local confirmation before model response',
    (tester) async {
      final memory = coach.InMemoryUserMemoryStore([
        coach.MemoryEntry(coach.MemoryKind.scene, '家里', at: DateTime(2026)),
        coach.MemoryEntry(coach.MemoryKind.equipment, '哑铃', at: DateTime(2026)),
      ]);
      final client = coach.FakeLlmClient([
        _ask(_form(allFields: false)),
      ], latency: Duration.zero);
      final ai = engine(client, memory: memory, enableMemory: true);
      final chat = await mount(tester, services(), ai);
      await chat.send('帮我安排一组训练');
      await tester.pumpAndSettle();
      final m = question(tester, chat);
      expect(client.requests, hasLength(1));
      expect(m.question!.isConfirmation, isFalse);
      expect(m.question!.fields.map((f) => f.key), ['minutes']);
      expect(ai.agent.sessionState.params, isEmpty);
    },
  );

  testWidgets('new conversation expires the previous SDK question', (
    tester,
  ) async {
    final client = coach.FakeLlmClient([
      _ask(_form()),
      '新会话回答。',
    ], latency: Duration.zero);
    final ai = engine(client);
    final chat = await mount(tester, services(), ai);
    await chat.send('OLD-QUESTION-TURN');
    await tester.pumpAndSettle();
    final old = question(tester, chat);
    await chat.newConversation();
    await tester.pumpAndSettle();
    expect(chat.canAnswerQuestion(old), isFalse);
    expect(find.byType(CoachQuestionBubble), findsNothing);
    await chat.answerForm(old, {
      'scene': ['家里'],
      'equipment': ['徒手'],
      'minutes': ['10分钟'],
    });
    expect(client.requests, hasLength(1));
    await chat.send('新的提问');
    await tester.pumpAndSettle();
    expect(ai.agent.sessionState.userTurns.map((m) => m.text), ['新的提问']);
    expect(
      jsonEncode(client.requests.last.messages.map((m) => m.toJson()).toList()),
      isNot(contains('OLD-QUESTION-TURN')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SDK may directly deliver a plan without an App mandatory form', (
    tester,
  ) async {
    final client = coach.FakeLlmClient(
      fixture.planTurn(),
      latency: Duration.zero,
    );
    final ai = engine(client);
    final chat = await mount(tester, services(), ai);
    await chat.send('在家徒手10分钟做拉伸');
    await tester.pumpAndSettle();
    expect(
      ai.lastResult?.plan,
      isNotNull,
      reason: '${ai.lastResult?.issues} ${ai.lastResult?.error}',
    );
    expect(chat.currentPlan!.id, ai.lastResult!.plan!.plan.id);
    expect(find.byType(CoachQuestionBubble), findsNothing);
    expect(find.byType(CoachPlanCard), findsOneWidget);
    expect(client.requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
