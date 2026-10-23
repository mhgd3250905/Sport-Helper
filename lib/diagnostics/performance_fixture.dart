import '../chat/chat_controller.dart';
import '../chat/chat_models.dart';
import '../core/storage/local_state_storage.dart';
import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import 'frame_recorder.dart';

/// Versioned, offline data used by every cell of the internal comparison.
/// Nothing references the user's chat log, saved plans or training history.
class PerformanceFixture {
  PerformanceFixture._({
    required this.id,
    required this.store,
    required this.controller,
  });

  static const messageCount = 72;
  static const exerciseIds = ['h-squat', 'h-calf-raise', 'w-dead-bug'];
  static final referenceTime = DateTime.utc(2000, 1, 1, 8);

  final String id;
  final AppStore store;
  final ChatController controller;

  factory PerformanceFixture.create({
    required ExerciseLibrary library,
    required FrameScenario scenario,
    bool starfield = true,
    String appearance = 'system',
  }) {
    if (scenario != FrameScenario.longChatScroll &&
        scenario != FrameScenario.planCardScroll) {
      throw ArgumentError.value(scenario, 'scenario');
    }
    final plans = scenario == FrameScenario.planCardScroll;
    if (plans && exerciseIds.any((id) => !library.contains(id))) {
      throw StateError('固定测试动作不可用，无法生成可对照的测试会话。');
    }
    final id = plans ? 'plan_cards_72_v1' : 'long_chat_72_v1';
    final store = AppStore(_MemoryFixtureStorage())
      ..safetyAccepted = true
      ..starfield = starfield
      ..appearance = appearance;
    final plan = plans ? _fixedPlan(library) : null;
    for (var index = 0; index < messageCount; index++) {
      final isUser = index.isEven;
      final hasPlan = plans && index % 6 == 5;
      store.chatLog.add(
        Map<String, dynamic>.from(
          ChatMessage(
            id: '${id}_$index',
            role: isUser ? ChatRole.user : ChatRole.assistant,
            at: referenceTime.add(Duration(seconds: index * 20)),
            text: hasPlan
                ? '这是一组固定测试计划。保持相同动作、顺序和封面，用于比较计划卡滑动。'
                : _messages[index % _messages.length],
            plan: hasPlan ? plan : null,
            request: hasPlan ? requestForPlan(plan!) : null,
          ).toJson(),
        ),
      );
    }
    final controller = ChatController(
      engine: const _OfflineFixtureEngine(),
      store: store,
      replyDelay: Duration.zero,
      clock: () => referenceTime.add(const Duration(minutes: 30)),
    )..start();
    return PerformanceFixture._(id: id, store: store, controller: controller);
  }

  static TrainingPlan _fixedPlan(ExerciseLibrary library) => TrainingPlan(
    id: 'performance_plan_v1',
    source: 'template',
    title: '内测固定全身计划',
    summary: '仅供滑动对照，不会开始训练或下载视频。',
    goal: 'mixed',
    scene: 'home',
    equipment: const [],
    level: 1,
    targetMinutes: 8,
    blocks: [
      PlanBlock(
        id: 'performance_main_v1',
        name: '固定动作组',
        type: BlockType.main,
        rounds: 1,
        restBetweenRoundsSeconds: 0,
        items: [
          for (final id in exerciseIds)
            PlanItem(
              exerciseId: id,
              mode: library[id].dose.mode,
              sets: 1,
              reps: library[id].dose.mode == DoseMode.reps ? 10 : null,
              workSeconds: library[id].dose.mode == DoseMode.time ? 30 : null,
              perSide: library[id].unilateral,
              restSeconds: 20,
            ),
        ],
      ),
    ],
  );

  void dispose() {
    controller.dispose();
    store.dispose();
  }

  static const _messages = [
    '今天想做一组轻松的活动，先从呼吸和关节热身开始。',
    '可以。先留意身体感受，动作在舒服的范围内完成，保持自然呼吸。',
    '工作时坐得比较久，准备站起来活动一下肩颈和双腿。',
    '放慢节奏，让肩膀向后放松。每次休息都可以做几次轻松的走动。',
    '训练中会安排短暂休息，保持动作稳定，不追求速度。',
    '这是一条固定的长聊天测试消息。它的文字、顺序和长度在每次采样时完全相同。\n'
        '滑动时会经过多行文本、不同高度的消息气泡和底部输入栏，使用正式页面的渲染组件。',
  ];
}

class _MemoryFixtureStorage implements LocalStateStorage {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class _OfflineFixtureEngine implements ChatEngine {
  const _OfflineFixtureEngine();

  @override
  String get id => 'offline_performance_fixture';

  @override
  Future<ChatReply> reply(String text, ChatState state) async =>
      ChatReply(messages: const [], state: state);
}
