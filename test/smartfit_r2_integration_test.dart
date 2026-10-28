import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show MemoryStorage, tall;
import 'support.dart';
import 'support/coach_v2_fixtures.dart';

late CoachV2Fixtures fixtures;

AppServices _services() => AppServices(
  library: fixtures.library,
  catalog: loadCatalog(),
  store: AppStore(MemoryStorage())..starfield = false,
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
  chatReplyDelay: Duration.zero,
);

AiChatEngine _engine(coach.LlmClient client) => AiChatEngine(
  local: const AppChatActions(),
  catalog: fixtures.catalog,
  profile: fixtures.profile,
  client: client,
  enableUserMemory: false,
);

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
  addTearDown(engine.dispose);
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

Future<void> _settleRequest(WidgetTester tester, ChatController chat) async {
  for (var i = 0; i < 15 && chat.typing; i++) {
    await tester.pump(const Duration(seconds: 30));
  }
  await tester.pumpAndSettle();
  expect(chat.typing, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => fixtures = await CoachV2Fixtures.load());

  testWidgets(
    'SDK model form reaches answerForm without App preselection or condition inheritance',
    (tester) async {
      final app = _services();
      final previous = (await app.generator.generate(
        const ScenarioRequest(templateId: 'office-relax', minutes: 15),
      )).plan!;
      await app.store.setChatLog([
        ChatMessage(
          id: 'old-plan',
          role: ChatRole.assistant,
          at: DateTime.now(),
          text: '上一套',
          plan: previous,
          request: const ScenarioRequest(scene: 'office', minutes: 15),
        ).toJson(),
      ]);
      final client = coach.FakeLlmClient([
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('start', 'start_task', {'type': 'plan'}),
          CoachV2Fixtures.call('ask', 'ask_user', {
            'question': '在哪里训练、使用什么器械，练多久？',
            'mode': 'form',
            'fields': [
              {
                'key': 'scene',
                'label': '场景',
                'options': ['家里', '办公室'],
                'multiple': false,
              },
              {
                'key': 'equipment',
                'label': '器械',
                'options': ['徒手', '椅子'],
                'multiple': true,
              },
              {
                'key': 'minutes',
                'label': '时长',
                'options': ['10 分钟', '15 分钟'],
                'multiple': false,
              },
            ],
          }),
        ]),
        ...fixtures.planTurn(
          prefix: 'answer',
          sceneQuote: '家里',
          minutesQuote: '10 分钟',
        ),
      ], latency: Duration.zero);
      final engine = _engine(client);
      final chat = await _mount(tester, app, engine);
      final send = chat.send('我想针对大腿内侧进行拉伸');
      await tester.pump();
      await _settleRequest(tester, chat);
      await send;
      final message = chat.messages.singleWhere((m) => m.question != null);
      expect(
        client.requests,
        hasLength(1),
        reason: 'Only SDK model tools create a question.',
      );
      expect(engine.agent.sessionState.params['scene'], isNull);
      expect(engine.agent.sessionState.params['minutes'], isNull);
      final q = tester
          .widget<CoachQuestionBubble>(find.byType(CoachQuestionBubble))
          .question;
      expect(q.isConfirmation, isFalse);
      expect(
        q.fields.every(
          (field) =>
              field.previousSelections.isEmpty &&
              field.initialSelections.isEmpty,
        ),
        isTrue,
      );
      for (final (key, label) in [
        ('scene', '家里'),
        ('equipment', '徒手'),
        ('minutes', '10 分钟'),
      ]) {
        final field = q.fields.singleWhere((field) => field.key == key);
        final pill = find.byKey(
          ValueKey(
            'question-field-${q.id}-$key-${field.options.indexOf(label)}',
          ),
        );
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pump();
      }
      final submit = find.byKey(ValueKey('question-submit-${q.id}'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await _settleRequest(tester, chat);
      final answered = chat.messages.singleWhere((m) => m.id == message.id);
      expect(answered.questionAnswered, isTrue);
      expect(answered.answeredForm, {
        'scene': ['家里'],
        'equipment': ['徒手'],
        'minutes': ['10 分钟'],
      });
      final sdkAnswer = engine.conversation.state.messages.singleWhere(
        (m) => m.id == answered.conversationMessageId,
      );
      expect(sdkAnswer.answeredForm, answered.answeredForm);
      expect(engine.lastResult!.plan, isNotNull);
      expect(chat.currentPlan!.targetMinutes, 10);
      expect(engine.agent.sessionState.params['scene']!.value, 'home');
      expect(engine.agent.sessionState.params['minutes']!.value, 10);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline turn shows failure bubble and no App preset plan', (
    tester,
  ) async {
    final app = _services();
    final client = coach.FakeLlmClient([
      for (var i = 0; i < 8; i++)
        const coach.LlmException(coach.LlmErrorKind.network, 'offline'),
    ], latency: Duration.zero);
    final engine = _engine(client);
    final chat = await _mount(tester, app, engine);
    final send = chat.send('在家徒手10分钟练全身');
    await tester.pump();
    await _settleRequest(tester, chat);
    await send;
    expect(find.byType(CoachFailureBubble), findsOneWidget);
    expect(chat.messages.where((m) => m.isPlanningFailure), hasLength(1));
    expect(chat.messages.where((m) => m.isPlan), isEmpty);
    expect(find.textContaining('预设方案'), findsNothing);
    expect(find.textContaining('当前模板未通过安全检查'), findsNothing);
  });
}
