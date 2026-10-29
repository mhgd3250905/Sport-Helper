import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/chat/expand_route.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services;

TrainingPlan _plan(int index, {int moves = 2}) => TrainingPlan(
  id: 'saved-expansion-$index',
  source: 'template',
  title: '原计划 $index',
  summary: '按原始剂量完成动作。',
  goal: 'mixed',
  scene: 'home',
  equipment: const [],
  level: 1,
  targetMinutes: 10,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        for (var move = 0; move < moves; move++)
          PlanItem(
            exerciseId: const ['h-squat', 'h-banana', 'h-wall-angel'][move % 3],
            mode: DoseMode.time,
            sets: 3,
            workSeconds: 47 + move,
            perSide: false,
            restSeconds: 11,
          ),
      ],
    ),
  ],
);

Future<AppServices> _show(
  WidgetTester tester, {
  int count = 2,
  int moves = 2,
  double height = 844,
  ValueChanged<SavedPlan>? onShow,
  void Function(SavedPlan, OriginRect)? onStart,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = services();
  await app.store.acceptSafety(blocked: false);
  for (var index = 0; index < count; index++) {
    await app.store.savePlan(
      _plan(index, moves: moves),
      name: '已保存方案 $index',
      now: DateTime.utc(2026, 10, 29, 0, index),
    );
  }
  addTearDown(app.dispose);
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(SfPalette.light),
        builder: (context, child) => SfPaletteScope(child: child!),
        home: SavedPlansPage(
          store: app.store,
          library: app.library,
          onShow: onShow ?? (_) {},
          onStart: onStart ?? (_, _) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

CoachPlanExpanded _expanded(WidgetTester tester, SavedPlan plan) =>
    tester.widget<CoachPlanExpanded>(
      find.byKey(ValueKey('saved-expanded-${plan.id}')),
    );

Future<void> _tapRow(WidgetTester tester, SavedPlan plan) async {
  await tester.tap(find.byKey(ValueKey('saved-${plan.id}')));
  await tester.pump();
}

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const ValueKey('saved-plans-scroll')))
    .controller!;

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  testWidgets(
    'saved entries reuse the controlled SDK card and preserve start and detail data',
    (tester) async {
      SavedPlan? started;
      OriginRect? origin;
      final app = await _show(
        tester,
        onStart: (plan, from) {
          started = plan;
          origin = from;
        },
      );
      final first = app.store.savedPlans.first;
      final second = app.store.savedPlans.last;
      final firstState = tester.state(
        find.byKey(ValueKey('saved-expanded-${first.id}')),
      );
      expect(find.text('2 套'), findsOneWidget);
      expect(_expanded(tester, first).expanded, isFalse);
      await _tapRow(tester, first);
      expect(
        tester.state(find.byKey(ValueKey('saved-expanded-${first.id}'))),
        same(firstState),
      );
      expect(_expanded(tester, first).expanded, isTrue);
      expect(_expanded(tester, second).expanded, isFalse);
      final collapsed = find.byKey(ValueKey('saved-collapsed-${first.id}'));
      final beforeHeight = tester.getSize(collapsed).height;
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.getSize(collapsed).height,
        inExclusiveRange(0, beforeHeight),
      );
      expect(find.byKey(ValueKey('saved-${first.id}')), findsOneWidget);
      final rowFade = tester.widget<FadeTransition>(
        find
            .descendant(of: collapsed, matching: find.byType(FadeTransition))
            .first,
      );
      expect(rowFade.opacity.value, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(tester.getSize(collapsed).height, 0);
      expect(
        _scroll(tester).offset,
        0,
        reason: 'A fully visible card needs no reveal scroll.',
      );
      final sdk = _expanded(tester, first);
      expect(sdk.plan.title, first.name);
      expect(sdk.plan.id, first.plan.id);
      expect(
        sdk.plan.items.first.detailDose,
        first.plan.items.first.doseText(),
      );
      expect(sdk.actionIcon, CoachGlyph.chevronRight);
      expect(sdk.actionLabel, '查看详情');
      final action = find.descendant(
        of: find.byKey(ValueKey('saved-expanded-${first.id}')),
        matching: find.text('查看详情'),
      );
      final text = tester.widget<Text>(action);
      expect(text.style!.fontSize, 14);
      expect(text.style!.color, SfColors.accent);
      await tester.tap(find.byKey(ValueKey('plan-start-${first.plan.id}')));
      expect(started, same(first));
      expect(origin!(), isNotNull);
      await tester.tap(action);
      await tester.pumpAndSettle();
      final details = tester.widget<PlanPage>(find.byType(PlanPage));
      expect(details.plan.title, first.name);
      expect(details.plan.id, first.plan.id);
      expect(details.plan.toJson(), {
        ...first.plan.toJson(),
        'title': first.name,
      });
      expect(first.plan.title, isNot(first.name));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one entry expands and the original row menu survives collapse and rename',
    (tester) async {
      SavedPlan? shown;
      final app = await _show(tester, onShow: (plan) => shown = plan);
      final first = app.store.savedPlans.first;
      final second = app.store.savedPlans.last;
      await _tapRow(tester, first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('saved-${second.id}')));
      await _tapRow(tester, second);
      await tester.pumpAndSettle();
      expect(_expanded(tester, first).expanded, isFalse);
      expect(_expanded(tester, second).expanded, isTrue);
      expect(
        tester
            .widgetList<CoachPlanExpanded>(find.byType(CoachPlanExpanded))
            .where((card) => card.expanded),
        hasLength(1),
      );
      await tester.tap(find.byKey(ValueKey('plan-expand-${second.plan.id}')));
      await tester.pumpAndSettle();
      expect(_expanded(tester, second).expanded, isFalse);
      await tester.tap(find.byKey(ValueKey('saved-menu-${second.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        '重命名后方案',
      );
      await tester.tap(find.byKey(const ValueKey('rename-ok')));
      await tester.pumpAndSettle();
      await _tapRow(tester, second);
      await tester.pumpAndSettle();
      expect(_expanded(tester, second).plan.title, '重命名后方案');
      await tester.tap(find.byKey(ValueKey('plan-expand-${second.plan.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('saved-menu-${second.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('点一下在对话里调出'));
      await tester.pumpAndSettle();
      expect(shown!.id, second.id);
      expect(shown!.name, '重命名后方案');
      expect(find.text('2 套'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'reveal waits for expansion layout and cancelled auto-scroll cannot keep pulling',
    (tester) async {
      final app = await _show(tester, count: 3, moves: 8, height: 540);
      final bottom = app.store.savedPlans.last;
      final scroll = _scroll(tester);
      await _tapRow(tester, bottom);
      await tester.pump(const Duration(milliseconds: 270));
      expect(scroll.offset, 0);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(scroll.offset, greaterThan(0));
      expect(scroll.position.isScrollingNotifier.value, isTrue);
      final before = scroll.offset;
      _expanded(tester, bottom).onCollapse();
      expect(scroll.offset, closeTo(before, .01));
      expect(scroll.position.isScrollingNotifier.value, isFalse);
      await tester.pumpAndSettle();
      expect(_expanded(tester, bottom).expanded, isFalse);
      expect(scroll.position.isScrollingNotifier.value, isFalse);

      // Closing before 280ms cancels the delayed request altogether.
      await _tapRow(tester, bottom);
      await tester.pump(const Duration(milliseconds: 100));
      _expanded(tester, bottom).onCollapse();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('deleting an expanding entry invalidates its pending reveal', (
    tester,
  ) async {
    final app = await _show(tester, count: 3, moves: 8, height: 540);
    final bottom = app.store.savedPlans.last;
    await _tapRow(tester, bottom);
    await tester.pump(const Duration(milliseconds: 100));
    await app.store.deletePlan(bottom.id);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('saved-expanded-${bottom.id}')), findsNothing);
    expect(_scroll(tester).position.isScrollingNotifier.value, isFalse);
    expect(find.text('2 套'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
