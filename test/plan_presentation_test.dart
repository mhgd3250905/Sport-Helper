import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/plan_presentation.dart';

PlanBlock _block(String name, [BlockType type = BlockType.main]) => PlanBlock(
  id: 'section',
  name: name,
  type: type,
  rounds: 1,
  restBetweenRoundsSeconds: 0,
  items: const [],
);

void main() {
  test('protocol section labels are localized without exposing English', () {
    for (final (input, expected) in [
      ('warmup', '热身'),
      (' WARM-UP ', '热身'),
      ('main', '主练'),
      ('cooldown', '放松'),
      ('circuit', '循环'),
      ('stretching', '拉伸'),
      ('recovery', '休息'),
      ('mobility', '活动'),
      ('activation', '激活'),
    ]) {
      expect(planSectionLabel(_block(input)), expected);
    }
    expect(planSectionLabel(_block('先活动开')), '先活动开');
    expect(planSectionLabel(_block('unknown section')), '主练');
    expect(planSectionLabel(_block('', BlockType.cooldown)), '放松');
  });
}
