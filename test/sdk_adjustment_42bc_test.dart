import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
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

const _hip = PlanItem(
  exerciseId: 's-kneel-hipflex',
  mode: DoseMode.time,
  sets: 2,
  workSeconds: 60,
  perSide: true,
  restSeconds: 20,
);
const _butterfly = PlanItem(
  exerciseId: 's-butterfly',
  mode: DoseMode.time,
  sets: 2,
  workSeconds: 80,
  perSide: false,
  restSeconds: 20,
);
const _hipShort = PlanItem(
  exerciseId: 's-kneel-hipflex',
  mode: DoseMode.time,
  sets: 1,
  workSeconds: 60,
  perSide: true,
  restSeconds: 0,
);
const _standing = PlanItem(
  exerciseId: 'h-step-jack',
  mode: DoseMode.time,
  sets: 3,
  workSeconds: 60,
  perSide: false,
  restSeconds: 40,
);

TrainingPlan _plan({
  required int minutes,
  String scene = 'home',
  List<String> equipment = const ['mat'],
  List<PlanItem> items = const [_hip, _butterfly],
  int rounds = 1,
}) => TrainingPlan(
  id: 'adjustment-fixture',
  source: 'ai',
  title: '髋部放松',
  summary: '按确认条件安排训练。',
  goal: 'relax',
  scene: scene,
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
      id: 'adjustment-plan',
      name: coach.CoachTools.showPlan,
      arguments: jsonEncode(plan.toJson()),
    ),
  ],
);

({ChatController chat, AiChatEngine engine, coach.FakeLlmClient client})
_session(List<coach.LlmResponse> responses) {
  final app = AppServices(
    library: _library,
    catalog: loadCatalog(),
    store: AppStore(MemoryStorage())..safetyAccepted = true,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );
  final client = coach.FakeLlmClient(responses, latency: Duration.zero);
  final engine = AiChatEngine(
    local: RuleChatEngine(lib: app.library, templates: app.templates),
    catalog: _catalog,
    profile: coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    ),
    client: client,
    enableUserMemory: false,
  );
  final chat = ChatController(
    engine: engine,
    store: app.store,
    replyDelay: Duration.zero,
  )..start();
  addTearDown(chat.dispose);
  addTearDown(engine.dispose);
  return (chat: chat, engine: engine, client: client);
}

Future<coach.TrainingPlan> _begin(
  ({ChatController chat, AiChatEngine engine, coach.FakeLlmClient client}) s,
) async {
  await s.chat.send('在家有瑜伽垫10分钟做髋部放松');
  expect(
    s.engine.lastResult?.plan,
    isNotNull,
    reason:
        'Initial plan must pass SDK and App gates: ${s.engine.lastResult?.issues}',
  );
  expect(s.chat.currentPlan, isNotNull);
  return s.engine.lastResult!.plan!.plan;
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

  test('absolute seven-minute adjustment rejects the old target', () async {
    final initial = _plan(minutes: 10);
    final revised = _plan(minutes: 7, items: [_hipShort, _butterfly]);
    final s = _session([_show(initial), _show(initial), _show(revised)]);
    await _begin(s);
    await s.chat.send('把这套训练缩短到7分钟');
    expect(
      s.engine.lastResult?.plan,
      isNotNull,
      reason: '${s.engine.lastResult?.issues}',
    );
    expect(s.chat.currentPlan!.targetMinutes, 7);
    expect(s.chat.currentPlan!.scene, 'home');
    expect(s.chat.currentPlan!.equipment, ['mat']);
    expect(s.client.requests, hasLength(3));
    expect(
      s.client.requests.last.messages
          .where((m) => m.role == coach.LlmRole.tool)
          .any((m) => m.content.contains('targetMinutes')),
      isTrue,
      reason: 'The stale 10-minute model proposal must be rejected.',
    );
  });

  for (final (phrase, minutes, items, rounds, shorter) in [
    ('再短一点', 5, const [_hipShort], 1, true),
    ('再长一点', 19, const [_hip, _butterfly], 3, false),
  ]) {
    test(
      'relative $phrase uses real duration direction without 25% gate',
      () async {
        final s = _session([
          _show(_plan(minutes: 10)),
          _show(_plan(minutes: minutes, items: items, rounds: rounds)),
        ]);
        final previous = await _begin(s);
        await s.chat.send(phrase);
        final revised = s.engine.lastResult?.plan?.plan;
        expect(revised, isNotNull, reason: '${s.engine.lastResult?.issues}');
        const duration = coach.PlanDuration();
        final before = duration.estimateSeconds(previous, _catalog);
        final after = duration.estimateSeconds(revised!, _catalog);
        expect(after, shorter ? lessThan(before) : greaterThan(before));
        expect(((after / 60 - minutes).abs() / minutes), greaterThan(.25));
        expect(s.chat.currentPlan!.targetMinutes, minutes);
        expect(s.chat.currentPlan!.equipment, ['mat']);
      },
    );
  }

  for (final (phrase, scene) in [
    ('把这套训练改成徒手', 'home'),
    ('把这套训练改成在办公室徒手', 'office'),
  ]) {
    test('adjustment $phrase replaces stale conditions', () async {
      final initial = _plan(minutes: 10);
      final revised = _plan(
        minutes: 10,
        scene: scene,
        equipment: const [],
        items: const [_standing],
        rounds: 2,
      );
      final s = _session([_show(initial), _show(initial), _show(revised)]);
      await _begin(s);
      await s.chat.send(phrase);
      expect(
        s.engine.lastResult?.plan,
        isNotNull,
        reason: '${s.engine.lastResult?.issues}',
      );
      expect(s.chat.currentPlan!.scene, scene);
      expect(s.chat.currentPlan!.equipment, isEmpty);
      expect(s.chat.currentPlan!.targetMinutes, 10);
      expect(s.client.requests, hasLength(3));
      expect(
        s.client.requests.last.messages
            .where((m) => m.role == coach.LlmRole.tool)
            .any(
              (m) =>
                  m.content.contains('equipment') ||
                  m.content.contains('scene'),
            ),
        isTrue,
        reason: 'Stale mat/home conditions must be rejected.',
      );
    });
  }
}
