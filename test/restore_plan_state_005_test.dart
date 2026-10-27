import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

late coach.Catalog _catalog;
late ExerciseLibrary _library;
late coach.CoachProfile _profile;

const _hip = PlanItem(
  exerciseId: 's-kneel-hipflex',
  mode: DoseMode.time,
  sets: 2,
  workSeconds: 60,
  perSide: true,
  restSeconds: 20,
);
const _shortHip = PlanItem(
  exerciseId: 's-kneel-hipflex',
  mode: DoseMode.time,
  sets: 1,
  workSeconds: 60,
  perSide: true,
  restSeconds: 0,
);
const _butterfly = PlanItem(
  exerciseId: 's-butterfly',
  mode: DoseMode.time,
  sets: 2,
  workSeconds: 80,
  perSide: false,
  restSeconds: 20,
);
const _frog = PlanItem(
  exerciseId: 's-frog',
  mode: DoseMode.time,
  sets: 2,
  workSeconds: 80,
  perSide: false,
  restSeconds: 20,
);
const _bodyweight = PlanItem(
  exerciseId: 'h-step-jack',
  mode: DoseMode.time,
  sets: 3,
  workSeconds: 60,
  perSide: false,
  restSeconds: 40,
);

TrainingPlan _plan({
  required int minutes,
  List<String> equipment = const ['mat'],
  List<PlanItem> items = const [_hip, _butterfly],
  int rounds = 1,
}) => TrainingPlan(
  id: 'restore-fixture',
  source: 'ai',
  title: '髋部放松',
  summary: '按确认条件安排训练。',
  goal: 'relax',
  scene: 'home',
  equipment: equipment,
  level: 1,
  targetMinutes: minutes,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '训练',
      type: BlockType.main,
      rounds: rounds,
      restBetweenRoundsSeconds: 0,
      items: items,
    ),
  ],
);

coach.LlmResponse _show(TrainingPlan plan) => coach.LlmResponse(
  content: '',
  toolCalls: [
    coach.LlmToolCall(
      id: 'restored-plan',
      name: coach.CoachTools.showPlan,
      arguments: jsonEncode(plan.toJson()),
    ),
  ],
);

({ChatController chat, AiChatEngine engine, coach.FakeLlmClient client})
_session(AppStore store, List<coach.LlmResponse> responses) {
  final client = coach.FakeLlmClient(responses, latency: Duration.zero);
  final engine = AiChatEngine(
    local: RuleChatEngine(
      lib: _library,
      templates: TemplatePlanGenerator(lib: _library, catalog: loadCatalog()),
    ),
    catalog: _catalog,
    profile: _profile,
    client: client,
    enableUserMemory: false,
  );
  final chat = ChatController(
    engine: engine,
    store: store,
    replyDelay: Duration.zero,
  )..start();
  addTearDown(chat.dispose);
  addTearDown(engine.dispose);
  return (chat: chat, engine: engine, client: client);
}

Future<({MemoryStorage storage, String initialId})>
_createPersistedCard() async {
  final storage = MemoryStorage();
  final store = AppStore(storage);
  await store.acceptSafety(blocked: false);
  final first = _session(store, [_show(_plan(minutes: 10))]);
  // The actual plan uses only a mat, but the user also has a chair available.
  await first.chat.send('在家有瑜伽垫和椅子10分钟做髋部放松');
  expect(
    first.engine.lastResult?.plan,
    isNotNull,
    reason: '${first.engine.lastResult?.issues}',
  );
  final card = first.chat.messages.lastWhere((m) => m.validatedPlan != null);
  expect(card.plan!.equipment, ['mat']);
  expect(card.planState, isNotNull);
  expect(
    card.planState!.planId,
    card.plan!.id,
    reason: 'The persisted snapshot must use the renamed App card ID.',
  );
  expect(card.planState!.context.equipment, containsAll(['mat', 'chair']));

  // Controller persistence uses AppStore; wait for the asynchronous save and
  // assert the serialized JSON before constructing a fresh store and engine.
  await Future<void>.delayed(Duration.zero);
  final row = store.chatLog.lastWhere((m) => m['isAiPlan'] == true);
  expect(row['planState'], isA<Map>());
  expect((row['planState'] as Map)['planId'], card.plan!.id);
  return (storage: storage, initialId: card.plan!.id);
}

Future<({ChatController chat, AiChatEngine engine, coach.FakeLlmClient client})>
_reopen(MemoryStorage storage, List<coach.LlmResponse> responses) async {
  final store = AppStore(storage);
  await store.load();
  return _session(store, responses);
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
    _profile = coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    );
  });

  test(
    'snapshot survives disk reload and restores unused available equipment',
    () async {
      final saved = await _createPersistedCard();
      final restored = await _reopen(saved.storage, []);
      final card = restored.chat.messages.lastWhere(
        (m) => m.validatedPlan != null,
      );
      expect(card.plan!.id, saved.initialId);
      expect(card.planState!.planId, saved.initialId);
      final sdkCard = restored.engine.conversation.state.messages.lastWhere(
        (m) => m.plan != null,
      );
      expect(
        sdkCard.planState!.context.equipment,
        containsAll(['mat', 'chair']),
      );
      final active = restored.engine.agent.planStateFor(card.validatedPlan!);
      expect(
        active.context.equipment,
        containsAll(['mat', 'chair']),
        reason: 'Chair was available even though the plan did not use it.',
      );
      expect(active.context.scene, 'home');
      expect(active.context.minutes, 10);
    },
  );

  for (final (phrase, updated) in [
    ('短一点', _plan(minutes: 5, items: [_shortHip])),
    ('缩短到 7 分钟', _plan(minutes: 7, items: [_shortHip, _butterfly])),
    (
      '换成徒手',
      _plan(minutes: 10, equipment: const [], items: [_bodyweight], rounds: 2),
    ),
    // One of two distinct exercises is new, exactly meeting the SDK threshold.
    ('换一套', _plan(minutes: 10, items: [_hip, _frog])),
  ]) {
    test(
      'restored plan responds to $phrase without another confirmation',
      () async {
        final saved = await _createPersistedCard();
        final restored = await _reopen(saved.storage, [_show(updated)]);
        expect(restored.chat.currentPlan!.id, saved.initialId);
        await restored.chat.send(phrase);
        expect(restored.engine.conversation.state.pendingQuestion, isNull);
        expect(
          restored.engine.lastResult?.plan,
          isNotNull,
          reason:
              'SDK did not admit the $phrase adjustment: ${restored.engine.lastResult?.issues}',
        );
        final card = restored.chat.messages.lastWhere(
          (m) => m.validatedPlan != null,
        );
        expect(card.plan!.id, isNot(saved.initialId));
        expect(card.plan!.targetMinutes, updated.targetMinutes);
        expect(card.plan!.equipment, updated.equipment);
        if (phrase == '换一套') {
          final newIds = card.plan!.exerciseIds;
          final oldIds = _plan(minutes: 10).exerciseIds;
          expect(
            newIds.difference(oldIds).length * 2,
            greaterThanOrEqualTo(newIds.length),
          );
        }
        expect(card.planState, isNotNull);
        expect(card.planState!.planId, card.plan!.id);
      },
    );
  }

  test(
    'legacy plan without a snapshot restores safely and infers conditions',
    () async {
      final saved = await _createPersistedCard();
      final legacyStore = AppStore(saved.storage);
      await legacyStore.load();
      final legacy = [
        for (final entry in legacyStore.chatLog)
          {...entry}..remove('planState'),
      ];
      await legacyStore.setChatLog(legacy);
      final restored = await _reopen(saved.storage, [
        _show(_plan(minutes: 7, items: [_shortHip, _butterfly])),
      ]);
      final oldCard = restored.chat.messages.lastWhere(
        (m) => m.validatedPlan != null,
      );
      expect(oldCard.planState, isNull);
      final inferred = restored.engine.agent.planStateFor(
        oldCard.validatedPlan!,
      );
      expect(inferred.context.scene, 'home');
      expect(inferred.context.minutes, 10);
      expect(inferred.context.equipment, contains('mat'));
      // Legacy plans know actual equipment only; they must not invent the chair.
      expect(inferred.context.equipment, isNot(contains('chair')));
      await restored.chat.send('缩短到 7 分钟');
      expect(
        restored.engine.lastResult?.plan,
        isNotNull,
        reason: '${restored.engine.lastResult?.issues}',
      );
      expect(restored.chat.currentPlan!.targetMinutes, 7);
    },
  );
}
