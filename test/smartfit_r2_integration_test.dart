import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'app_flow_test.dart' show MemoryStorage, tall;
import 'support.dart';

late coach.Catalog _catalog;
late ExerciseLibrary _library;

AppServices _services() => AppServices(
  library: _library,
  catalog: loadCatalog(),
  store: AppStore(MemoryStorage())..starfield = false,
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
  chatReplyDelay: Duration.zero,
);

AiChatEngine _engine(AppServices app, coach.LlmClient client) => AiChatEngine(
  local: RuleChatEngine(lib: app.library, templates: app.templates),
  catalog: _catalog,
  profile: coach.CoachProfile.fromJson(
    jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
  ),
  client: client,
  enableUserMemory: false,
);

TrainingPlan _plan({
  String source = 'ai',
  int minutes = 10,
  List<String> equipment = const ['chair', 'wall'],
}) => TrainingPlan(
  id: 'r2-confirmed-plan',
  source: source,
  title: '拉伸训练',
  summary: '活动下肢。',
  goal: 'cooldown',
  scene: 'home',
  equipment: equipment,
  level: 1,
  targetMinutes: minutes,
  blocks: const [
    PlanBlock(
      id: 'main',
      name: '训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-wall-straddle',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 90,
          perSide: false,
          restSeconds: 20,
        ),
        PlanItem(
          exerciseId: 'n-wide-fold',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 20,
        ),
        PlanItem(
          exerciseId: 'h-chair-lat',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 20,
        ),
        PlanItem(
          exerciseId: 'h-chair-tspine',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 20,
        ),
      ],
    ),
  ],
);

coach.LlmResponse _showPlan() => coach.LlmResponse(
  content: '',
  toolCalls: [
    coach.LlmToolCall(
      id: 'r2-plan',
      name: coach.CoachTools.showPlan,
      arguments: jsonEncode(_plan().toJson()),
    ),
  ],
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
  setUpAll(() async {
    final sdk = await PoseHubActionLibrary.load();
    _catalog = sdk.toAiCatalog();
    _library = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(sdk),
      legacyLibrary: loadLibrary(),
    ).library;
  });

  testWidgets(
    'previous plan becomes confirmation suggestions, form reaches SDK and card',
    (tester) async {
      final app = _services();
      final previous = _plan(
        source: 'template',
        minutes: 15,
        equipment: const [],
      );
      await app.store.setChatLog([
        ChatMessage(
          id: 'old-plan',
          role: ChatRole.assistant,
          at: DateTime.now(),
          text: '上一套',
          plan: previous,
          request: const ScenarioRequest(minutes: 15),
          aiVisible: true,
        ).toJson(),
      ]);
      final client = coach.FakeLlmClient([_showPlan()], latency: Duration.zero);
      final engine = _engine(app, client);
      final chat = await _mount(tester, app, engine);
      expect(chat.currentPlan, isNotNull);

      await chat.send('我想针对大腿内侧进行拉伸');
      await tester.pumpAndSettle();
      final message = chat.messages.singleWhere((m) => m.question != null);
      expect(message.question!.isConfirmation, isTrue);
      expect(
        client.requests,
        isEmpty,
        reason: 'The confirmation is deterministic and local.',
      );
      final bubble = tester.widget<CoachQuestionBubble>(
        find.byType(CoachQuestionBubble),
      );
      final q = bubble.question;
      expect(q.isConfirmation, isTrue);
      expect(q.fields.map((f) => f.key).toSet(), {
        'scene',
        'equipment',
        'minutes',
      });
      expect(
        q.fields.singleWhere((f) => f.key == 'scene').previousSelections,
        contains('家里'),
      );
      expect(
        q.fields.singleWhere((f) => f.key == 'equipment').previousSelections,
        contains('徒手'),
      );
      expect(
        q.fields.singleWhere((f) => f.key == 'minutes').previousSelections,
        contains('15 分钟'),
      );

      Future<void> choose(String key, String label) async {
        final field = q.fields.singleWhere((f) => f.key == key);
        final index = field.options.indexOf(label);
        expect(index, greaterThanOrEqualTo(0));
        final pill = find.byKey(ValueKey('question-field-${q.id}-$key-$index'));
        await tester.ensureVisible(pill);
        await tester.tap(pill);
        await tester.pump();
      }

      final chair = _catalog.taxonomy.equipmentLabel('chair');
      final wall = _catalog.taxonomy.equipmentLabel('wall');
      await choose('equipment', chair);
      await choose('equipment', wall);
      await choose('minutes', '10 分钟');
      final submit = find.byKey(ValueKey('question-submit-${q.id}'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await _settleRequest(tester, chat);

      final answered = chat.messages.singleWhere((m) => m.id == message.id);
      expect(answered.questionAnswered, isTrue);
      expect(answered.answeredForm['scene'], ['家里']);
      expect(answered.answeredForm['equipment']!.toSet(), {chair, wall});
      expect(answered.answeredForm['minutes'], ['10 分钟']);
      final sdkAnswer = engine.conversation.state.messages.singleWhere(
        (m) => m.id == answered.conversationMessageId,
      );
      expect(sdkAnswer.answeredForm['equipment']!.toSet(), {chair, wall});
      expect(sdkAnswer.answeredForm['minutes'], ['10 分钟']);
      expect(find.byKey(ValueKey('question-summary-${q.id}')), findsOneWidget);
      expect(find.textContaining('10 分钟'), findsWidgets);
      expect(client.requests, isNotEmpty);
      expect(
        engine.lastResult!.plan,
        isNotNull,
        reason: 'The fake response still passes actual SDK and App gates.',
      );
      expect(chat.currentPlan!.equipment.toSet(), {'chair', 'wall'});
      final routine = toCoachRoutine(chat.currentPlan!, _library);
      expect(routine.durationLabel, '10 分钟');
      expect(routine.gearLabel, contains('椅子'));
      expect(routine.gearLabel, contains('墙'));
    },
  );

  testWidgets(
    'offline planning failure shows failure bubble and no preset card',
    (tester) async {
      final app = _services();
      final client = coach.FakeLlmClient([
        for (var i = 0; i < 8; i++)
          const coach.LlmException(coach.LlmErrorKind.network, 'offline'),
      ], latency: Duration.zero);
      final engine = _engine(app, client);
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
    },
  );
}
