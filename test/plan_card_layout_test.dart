// Chat cards have fixed, compact heights by type (like link-share cards):
// a set is 240 px, one move is 130 px; the move list lives on the plan page
// (no in-chat 展开全部), and save / start / details stay reachable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/plan_page.dart';

import 'app_flow_test.dart' show services, tall;

const _single = TrainingPlan(
  id: 'single-move',
  source: 'template',
  title: '俄罗斯转体',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'b',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-russian-twist',
          mode: DoseMode.reps,
          sets: 2,
          reps: 12,
          perSide: false,
          restSeconds: 20,
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('a set card is a compact 240 px card; no in-chat move list', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await s.chat.send('在家 15 分钟练核心，徒手');
    final plan = s.chat.currentPlan!;
    expect(plan.items.length, greaterThan(1));
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(PlanCard)).height, PlanCard.setHeight);
    expect(find.textContaining('展开全部'), findsNothing);
    final card = find.byType(PlanCard);
    expect(find.descendant(of: card, matching: find.text(plan.title)), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('${plan.items.length} 个动作')), findsOneWidget);
    if (plan.items.length > 6) {
      expect(find.descendant(of: card, matching: find.text('+${plan.items.length - 6}')), findsOneWidget);
    }
    expect(find.byKey(ValueKey('plan-start-${plan.id}')), findsOneWidget);
    // Collapsed by default: the move list and 保存 are folded away.
    expect(find.byKey(ValueKey('plan-save-${plan.id}')), findsNothing);
    final toggle = find.byKey(ValueKey('plan-expand-${plan.id}'));
    expect(tester.getSemantics(toggle), matchesSemantics(
      label: '展开详情', isButton: true, hasEnabledState: true, isEnabled: true,
      hasTapAction: true, hasFocusAction: true, hasExpandedState: true, isExpanded: false, isFocusable: true,
    ));

    // Expand in place: the full list, 保存 and 详情 appear; the card grows.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, greaterThan(PlanCard.setHeight + 48.0 * plan.items.length));
    expect(find.byKey(ValueKey('plan-save-${plan.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plan-details-${plan.id}')), findsOneWidget);
    expect(tester.getSemantics(toggle), matchesSemantics(
      label: '收起详情', isButton: true, hasEnabledState: true, isEnabled: true,
      hasTapAction: true, hasFocusAction: true, hasExpandedState: true, isExpanded: true, isFocusable: true,
    ));
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    expect(s.store.savedPlans.single.plan.id, plan.id);

    // Collapse back to the compact 240 px card.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, PlanCard.setHeight);

    // The card itself opens the plan page, where every move is listed.
    await tester.tap(find.byKey(ValueKey('plan-open-${plan.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(PlanPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a one-move card is a compact 130 px horizontal card', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await s.store.setChatLog([
      ChatMessage(id: 'single-card', role: ChatRole.assistant, at: DateTime.now(), plan: _single)
          .toJson()
          .cast<String, dynamic>(),
    ]);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    final card = find.byType(PlanCard);
    expect(tester.getSize(card).height, PlanCard.exerciseHeight);
    expect(find.descendant(of: card, matching: find.textContaining('2 组 × 12 次')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-start-single-move')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('plan-expand-single-move')));
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, greaterThan(PlanCard.exerciseHeight));
    await tester.tap(find.byKey(const ValueKey('plan-save-single-move')));
    await tester.pumpAndSettle();
    expect(s.store.savedPlans.single.plan.id, 'single-move');
    expect(find.text('已保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
