import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import 'theme.dart' show minutesZh;

/// Cards and articles describe the time the same executable plan takes.
String planDurationLabel(TrainingPlan plan, ExerciseLibrary library) =>
    minutesZh(SessionBuilder(library).planSeconds(plan));

/// Keep authored Chinese names, while localizing protocol section names.
/// Unknown protocol values fall back to the block's known semantic type.
String planSectionLabel(PlanBlock block) {
  final name = block.name.trim();
  final translated = switch (name.toLowerCase()) {
    'warmup' || 'warm_up' || 'warm-up' || 'warm up' => '热身',
    'main' || 'main_set' || 'main-set' || 'workout' => '主练',
    'cooldown' || 'cool_down' || 'cool-down' || 'cool down' => '放松',
    'circuit' => '循环',
    'preparation' || 'prepare' => '准备',
    'stretch' || 'stretching' => '拉伸',
    'rest' || 'recovery' => '休息',
    'mobility' => '活动',
    'balance' => '平衡',
    'cardio' || 'aerobic' => '有氧',
    'interval' || 'intervals' => '间歇',
    'core' => '核心',
    'activation' => '激活',
    _ => null,
  };
  if (translated != null) return translated;
  if (name.isNotEmpty && !RegExp(r'[A-Za-z]').hasMatch(name)) return name;
  return switch (block.type) {
    BlockType.warmup => '热身',
    BlockType.main => '主练',
    BlockType.circuit => '循环',
    BlockType.cooldown => '放松',
  };
}
