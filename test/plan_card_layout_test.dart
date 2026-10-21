// Chat cards have fixed, compact heights by type (like link-share cards):
// a set is 240 px, one move is 130 px; the move list lives on the plan page
// (no in-chat 展开全部), and save / start stay reachable; start sits at the
// end of the bottom line, details are the card itself.
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
    final start = find.byKey(ValueKey('plan-start-${plan.id}'));
    expect(start, findsOneWidget);
    final startNode = find.bySemanticsLabel('开始训练');
    expect(startNode, findsOneWidget);
    expect(tester.getSemantics(startNode), containsSemantics(label: '开始训练', isButton: true, hasTapAction: true));
    // One bottom row: thumbnails (+N) then 开始训练 at its right end; no
    // separate 详情 entry on the compact card.
    expect(find.descendant(of: card, matching: find.text('详情')), findsNothing);
    expect(find.byKey(ValueKey('plan-details-${plan.id}')), findsNothing);
    final cardRect = tester.getRect(card);
    final startRect = tester.getRect(start);
    expect(startRect.height, greaterThanOrEqualTo(44));
    expect(cardRect.right - startRect.right, lessThan(16));
    expect(cardRect.bottom - startRect.bottom, lessThan(16));
    if (plan.items.length > 5) {
      expect(find.descendant(of: card, matching: find.textContaining(RegExp(r'^\+\d+$'))), findsOneWidget);
    }
    // Collapsed by default: the move list and 保存 are folded away.
    expect(find.byKey(ValueKey('plan-save-${plan.id}')), findsNothing);
    final toggle = find.byKey(ValueKey('plan-expand-${plan.id}'));
    expect(tester.getSemantics(toggle), matchesSemantics(
      label: '展开详情', isButton: true, hasEnabledState: true, isEnabled: true,
      hasTapAction: true, hasFocusAction: true, hasExpandedState: true, isExpanded: false, isFocusable: true,
    ));

    // Expand in place: the full list and 保存 appear; the card grows; the
    // one 开始训练 stays put (no second start, no 详情 row).
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, greaterThan(PlanCard.setHeight + 48.0 * plan.items.length));
    expect(find.byKey(ValueKey('plan-save-${plan.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('plan-details-${plan.id}')), findsNothing);
    expect(start, findsOneWidget);
    // Same spot on the card (the chat may scroll as the card grows).
    expect(tester.getRect(start).topLeft - tester.getRect(card).topLeft, startRect.topLeft - cardRect.topLeft);
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
    final start = find.byKey(const ValueKey('plan-start-single-move'));
    expect(start, findsOneWidget);
    // 开始训练 bottom-right inside the content; no separate start row.
    final r = tester.getRect(card), sr = tester.getRect(start);
    expect(r.right - sr.right, lessThan(12));
    expect(r.bottom - sr.bottom, lessThan(12));

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
