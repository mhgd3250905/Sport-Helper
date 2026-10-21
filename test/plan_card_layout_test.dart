// Chat cards have fixed, compact heights by type (like link-share cards):
// a set is 240 px, one move is 130 px; the move list lives on the plan page
// (no in-chat 展开全部), and save / start stay reachable; the icon-only ▶
// sits at the card's bottom-right (strip end folded, 保存 row unfolded).
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
  for (final scale in [1.3, 2.0]) {
    testWidgets('one-move card fits a narrow phone at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = services();
      var starts = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PlanCard(
                  plan: _single,
                  library: s.library,
                  saved: false,
                  onStart: (_) => starts++,
                  onSave: () => saves++,
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('plan-start-single-move')));
      await tester.pumpAndSettle();
      expect(starts, 1);
      await tester.tap(find.byKey(const ValueKey('plan-expand-single-move')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('plan-save-single-move')),
      );
      await tester.tap(find.byKey(const ValueKey('plan-save-single-move')));
      expect(saves, 1);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a set card is a compact 240 px card; no in-chat move list', (
    tester,
  ) async {
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
    expect(
      find.descendant(of: card, matching: find.text(plan.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining('${plan.items.length} 个动作'),
      ),
      findsOneWidget,
    );
    final start = find.byKey(ValueKey('plan-start-${plan.id}'));
    expect(start, findsOneWidget);
    final startNode = find.bySemanticsLabel('开始训练');
    expect(startNode, findsOneWidget);
    expect(
      tester.getSemantics(startNode),
      isSemantics(label: '开始训练', isButton: true, hasTapAction: true),
    );
    // One bottom row: thumbnails (+N) then 开始训练 at its right end; no
    // separate 详情 entry on the compact card.
    expect(find.descendant(of: card, matching: find.text('详情')), findsNothing);
    expect(find.byKey(ValueKey('plan-details-${plan.id}')), findsNothing);
    final cardRect = tester.getRect(card);
    final startRect = tester.getRect(start);
    expect(startRect.height, greaterThanOrEqualTo(44));
    // Icon-only round ▶: no visible text, the label lives in Semantics.
    expect(
      find.descendant(of: start, matching: find.text('开始训练')),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.descendant(
              of: start,
              matching: find.byKey(const ValueKey('start-disc')),
            ),
          )
          .width,
      greaterThanOrEqualTo(48),
    );
    expect(cardRect.right - startRect.right, lessThan(16));
    expect(cardRect.bottom - startRect.bottom, lessThan(16));
    if (plan.items.length > 5) {
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(RegExp(r'^\+\d+$')),
        ),
        findsOneWidget,
      );
    }
    // Collapsed by default: the move list and 保存 are folded away.
    expect(find.byKey(ValueKey('plan-save-${plan.id}')), findsNothing);
    final toggle = find.byKey(ValueKey('plan-expand-${plan.id}'));
    expect(
      tester.getSemantics(toggle),
      matchesSemantics(
        label: '展开详情',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasExpandedState: true,
        isExpanded: false,
        isFocusable: true,
      ),
    );

    // Expand in place: thumbnails fly into the rows mid-way without
    // errors; then the full list and 保存 appear and the one ▶ sits on the
    // bottom row at its right end, level with 保存 (no 详情, no start pill
    // under the hero).
    await tester.tap(toggle);
    await tester.pump();
    // Mid-unfold (~100 ms of 320): the ▶ has faded out where it was (it
    // never slides over the rows), thumbnails are in flight and no row
    // text is showing yet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(_startOpacity(tester), lessThan(.02));
    expect(find.byKey(const ValueKey('fly-0')), findsOneWidget);
    for (var i = 0; i < plan.items.length; i++) {
      expect(
        _textOpacity(tester, i),
        0,
        reason: 'row $i text before thumbnails land',
      );
    }
    for (var f = 0; f < 16; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      _expectNoOverlap(tester, plan.items.length);
    }
    await tester.pumpAndSettle();
    expect(_startOpacity(tester), 1);
    expect(
      tester.getSize(card).height,
      greaterThan(PlanCard.setHeight + 48.0 * plan.items.length),
    );
    final save = find.byKey(ValueKey('plan-save-${plan.id}'));
    expect(save, findsOneWidget);
    expect(find.byKey(ValueKey('plan-details-${plan.id}')), findsNothing);
    expect(find.descendant(of: card, matching: find.text('详情')), findsNothing);
    expect(start, findsOneWidget);
    expect(find.bySemanticsLabel('开始训练'), findsOneWidget);
    final open = tester.getRect(card),
        sr = tester.getRect(start),
        sv = tester.getRect(save);
    expect(open.right - sr.right, lessThan(16));
    expect(open.bottom - sr.bottom, lessThan(16));
    expect((sr.center.dy - sv.center.dy).abs(), lessThan(4));
    expect(sv.left - open.left, lessThan(24));
    expect(
      tester.getSemantics(toggle),
      matchesSemantics(
        label: '收起详情',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasExpandedState: true,
        isExpanded: true,
        isFocusable: true,
      ),
    );
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    expect(s.store.savedPlans.single.plan.id, plan.id);

    // Collapse back to the compact 240 px card.
    await tester.tap(toggle);
    await tester.pump();
    // Folding: ▶ is gone within ~60 ms; text leaves before thumbnails move.
    await tester.pump(const Duration(milliseconds: 60));
    expect(_startOpacity(tester), lessThan(.02));
    for (var f = 0; f < 14; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      _expectNoOverlap(tester, plan.items.length);
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, PlanCard.setHeight);
    expect(_startOpacity(tester), 1);
    expect(
      tester.getRect(start).topLeft - tester.getRect(card).topLeft,
      startRect.topLeft - cardRect.topLeft,
    );

    // The card itself opens the plan page, where every move is listed.
    await tester.tap(find.byKey(ValueKey('plan-open-${plan.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(PlanPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a one-move card is a compact 130 px horizontal card', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await s.store.setChatLog([
      ChatMessage(
        id: 'single-card',
        role: ChatRole.assistant,
        at: DateTime.now(),
        plan: _single,
      ).toJson().cast<String, dynamic>(),
    ]);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    final card = find.byType(PlanCard);
    expect(tester.getSize(card).height, PlanCard.exerciseHeight);
    expect(
      find.descendant(of: card, matching: find.textContaining('2 组 × 12 次')),
      findsOneWidget,
    );
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

  testWidgets('reduced motion: unfold is a plain cross-fade, same end state', (
    tester,
  ) async {
    tall(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await s.chat.send('在家 15 分钟练核心，徒手');
    final plan = s.chat.currentPlan!;
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    final card = find.byType(PlanCard);
    await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(card).height,
      greaterThan(PlanCard.setHeight + 48.0 * plan.items.length),
    );
    final r = tester.getRect(card),
        sr = tester.getRect(find.byKey(ValueKey('plan-start-${plan.id}')));
    expect(r.right - sr.right, lessThan(16));
    expect(r.bottom - sr.bottom, lessThan(16));
    await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, PlanCard.setHeight);
    await tester.pumpWidget(const SizedBox());
  });
}

double _startOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find.byKey(const ValueKey('plan-start-fade')))
    .opacity;

/// Row [i]'s name/dose opacity (0 when the details are folded away).
double _textOpacity(WidgetTester tester, int i) {
  final f = find.descendant(
    of: find.byKey(ValueKey('plan-row-$i')),
    matching: find.byKey(const ValueKey('row-text')),
  );
  if (f.evaluate().isEmpty) return 0;
  return tester.widget<FadeTransition>(f).opacity.value;
}

/// No flying thumbnail is ever over a row's visible text.
void _expectNoOverlap(WidgetTester tester, int rows) {
  final flyers = <Rect>[];
  for (var k = 0; k < rows; k++) {
    final f = find.byKey(ValueKey('fly-$k'));
    if (f.evaluate().isEmpty) continue;
    flyers.add(
      tester.getRect(
        find.descendant(of: f, matching: find.byType(ClipRRect)).first,
      ),
    );
  }
  if (flyers.isEmpty) return;
  for (var i = 0; i < rows; i++) {
    if (_textOpacity(tester, i) <= 0) continue;
    final text = tester.getRect(
      find.descendant(
        of: find.byKey(ValueKey('plan-row-$i')),
        matching: find.byKey(const ValueKey('row-text')),
      ),
    );
    for (final r in flyers) {
      expect(
        r.deflate(.5).overlaps(text),
        isFalse,
        reason: 'thumbnail over row $i text',
      );
    }
  }
}
