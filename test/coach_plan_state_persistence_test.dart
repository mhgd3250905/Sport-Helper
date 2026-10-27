import 'dart:convert';
import 'dart:io';

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
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

late coach.Catalog _catalog;
late ExerciseLibrary _library;

TrainingPlan _chairPlan() => const TrainingPlan(
  id: 'model-reused-id',
  source: 'ai',
  title: '大腿内侧拉伸',
  summary: '用椅子进行拉伸。',
  goal: 'cooldown',
  scene: 'home',
  equipment: ['chair'],
  level: 1,
  targetMinutes: 10,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'n-wide-fold',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 60,
        ),
        PlanItem(
          exerciseId: 'h-chair-lat',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 60,
        ),
        PlanItem(
          exerciseId: 'h-chair-tspine',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 60,
          perSide: false,
          restSeconds: 60,
        ),
      ],
    ),
  ],
);

coach.LlmResponse _showPlan() => coach.LlmResponse(
  content: '',
  toolCalls: [
    coach.LlmToolCall(
      id: 'snapshot-plan',
      name: coach.CoachTools.showPlan,
      arguments: jsonEncode(_chairPlan().toJson()),
    ),
  ],
);

({ChatController chat, AiChatEngine engine}) _session(
  AppStore store,
  List<coach.LlmResponse> responses,
) {
  final app = AppServices(
    library: _library,
    catalog: loadCatalog(),
    store: store,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );
  final engine = AiChatEngine(
    local: RuleChatEngine(lib: app.library, templates: app.templates),
    catalog: _catalog,
    profile: coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    ),
    client: coach.FakeLlmClient(responses, latency: Duration.zero),
    enableUserMemory: false,
  );
  final chat = ChatController(
    engine: engine,
    store: store,
    replyDelay: Duration.zero,
  )..start();
  addTearDown(chat.dispose);
  addTearDown(engine.dispose);
  return (chat: chat, engine: engine);
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

  test(
    'plan conditions persist on the renamed card and restore precise gear',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage)..safetyAccepted = true;
      final first = _session(store, [_showPlan()]);
      await first.chat.send('在家有椅子和墙，10分钟拉伸大腿内侧');
      expect(
        first.engine.lastResult?.plan,
        isNotNull,
        reason: '${first.engine.lastResult?.issues}',
      );
      final card = first.chat.messages.singleWhere(
        (m) => m.validatedPlan != null,
      );
      expect(card.plan!.equipment, ['chair']);
      expect(card.planState, isNotNull);
      expect(card.planState!.planId, card.validatedPlan!.plan.id);
      expect(card.planState!.planId, isNot('model-reused-id'));
      expect(card.planState!.context.equipment, {'chair', 'wall'});
      expect(card.planState!.context.minutes, 10);
      await store.setChatLog([for (final m in first.chat.messages) m.toJson()]);

      final reloaded = AppStore(storage);
      await reloaded.load();
      final next = _session(reloaded, []);
      final restored = next.chat.messages.singleWhere(
        (m) => m.validatedPlan != null,
      );
      expect(restored.planState?.planId, restored.validatedPlan!.plan.id);
      expect(restored.planState?.context.equipment, {'chair', 'wall'});
      final restoredSdk = next.engine.agent.planStateFor(
        restored.validatedPlan!,
      );
      expect(restoredSdk.context.equipment, {'chair', 'wall'});
      expect(restoredSdk.context.minutes, 10);

      // Old conditions remain editable pre-selections for a new goal.
      await next.chat.send('我想练肩颈放松');
      final question = next.chat.messages.last.question!;
      final gear = question.fields.singleWhere(
        (field) => field.key == 'equipment',
      );
      expect(
        gear.previousSelections,
        containsAll([
          _catalog.taxonomy.equipmentLabel('chair'),
          _catalog.taxonomy.equipmentLabel('wall'),
        ]),
      );
    },
  );

  test(
    'legacy and invalid snapshot keep the admitted card and infer conditions',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage)..safetyAccepted = true;
      final first = _session(store, [_showPlan()]);
      await first.chat.send('在家有椅子和墙，10分钟拉伸大腿内侧');
      final card = first.chat.messages.singleWhere(
        (m) => m.validatedPlan != null,
      );
      final json = card.toJson().cast<String, dynamic>();
      final legacy = Map<String, dynamic>.of(json)..remove('planState');
      final corrupt = Map<String, dynamic>.of(json)
        ..['planState'] = {
          'planId': 'different-plan',
          'context': {'scene': 'office'},
        };
      for (final stored in [legacy, corrupt]) {
        final decoded = ChatMessage.fromJson(stored, restoreWith: first.engine);
        expect(decoded.validatedPlan, isNotNull);
        expect(decoded.planState, isNull);
        first.engine.conversation.restoreHistory([
          coach.CoachConversationMessage(
            id: decoded.id,
            at: decoded.at,
            plan: decoded.validatedPlan,
            planState: decoded.planState,
          ),
        ]);
        expect(
          first.engine.agent.planStateFor(decoded.validatedPlan!).context.scene,
          'home',
        );
      }
    },
  );
}
