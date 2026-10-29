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
  SfPalette palette = SfPalette.light,
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
        theme: buildTheme(palette),
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

Finder _card(SavedPlan plan) =>
    find.byKey(ValueKey('saved-expanded-${plan.id}'));

Finder _shell(SavedPlan plan) =>
    find.descendant(of: _card(plan), matching: find.byType(CoachCardSurface));

Finder _slot(SavedPlan plan, String key) =>
    find.descendant(of: _card(plan), matching: find.byKey(ValueKey(key)));

double _fade(WidgetTester tester, SavedPlan plan, String key) =>
    tester.widget<FadeTransition>(_slot(plan, key)).opacity.value;

Future<void> _tapRow(WidgetTester tester, SavedPlan plan) async {
  final row = _expanded(tester, plan).expanded
      ? find.byKey(ValueKey('saved-open-header-${plan.id}'))
      : _card(plan);
  // The collapsed card's host gesture remains available while the SDK's
  // summary is temporarily inactive. Its center also avoids the play control.
  await tester.tap(row);
  await tester.pump();
}

double _contentHeight(WidgetTester tester, SavedPlan plan) =>
    tester.getSize(_slot(plan, 'plan-expanded-size')).height;

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(find.byKey(const ValueKey('saved-plans-scroll')))
    .controller!;

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'one ${palette.brightness.name} SDK surface and summary survive every 16ms frame',
      (tester) async {
        final app = await _show(tester, count: 1, palette: palette);
        final plan = app.store.savedPlans.single;
        final sdkState = tester.state(_card(plan));
        final initial = _expanded(tester, plan);
        expect(initial.header, isNotNull);
        expect(initial.collapsedSummary, isNotNull);
        expect(initial.onToggle, isNotNull);
        expect(find.byType(CoachPlanExpanded), findsOneWidget);
        expect(_shell(plan), findsOneWidget);
        final shellElement = tester.element(_shell(plan));
        final shellRender = tester.renderObject(_shell(plan));
        final summary = find.byKey(ValueKey('saved-summary-${plan.id}'));
        final summaryElement = tester.element(summary);
        Widget? expandedHeader;
        final shellOrigin = tester.getTopLeft(_shell(plan));
        final shellWidth = tester.getSize(_shell(plan)).width;
        final collapsedHeight = tester.getSize(_card(plan)).height;
        expect(collapsedHeight, 108);

        void verifyPermanentParts() {
          expect(tester.state(_card(plan)), same(sdkState));
          expect(_shell(plan), findsOneWidget);
          expect(tester.element(_shell(plan)), same(shellElement));
          expect(tester.renderObject(_shell(plan)), same(shellRender));
          expect(tester.element(summary), same(summaryElement));
          expect(
            _expanded(tester, plan).collapsedSummary,
            same(initial.collapsedSummary),
          );
          if (_expanded(tester, plan).expanded) {
            expandedHeader ??= _expanded(tester, plan).header;
            expect(_expanded(tester, plan).header, same(expandedHeader));
            expect(
              find.byKey(ValueKey('saved-open-header-${plan.id}')),
              findsOneWidget,
            );
          } else {
            expect(_expanded(tester, plan).header, isA<SizedBox>());
            expect(
              find.byKey(ValueKey('saved-open-header-${plan.id}')),
              findsNothing,
            );
          }
          expect(tester.getTopLeft(_shell(plan)), shellOrigin);
          expect(tester.getSize(_shell(plan)).width, shellWidth);
          final entry = find.byKey(ValueKey('saved-entry-${plan.id}'));
          final prohibited = find.descendant(
            of: entry,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is AnimatedSwitcher ||
                  widget is Hero ||
                  widget is Opacity,
            ),
          );
          expect(
            find.ancestor(of: _shell(plan), matching: prohibited),
            findsNothing,
          );
          // The list's permanent exit wrappers remain fully visible outside a
          // deletion; expansion must never fade or shrink the shared shell.
          for (final fade in tester.widgetList<FadeTransition>(
            find.ancestor(
              of: _shell(plan),
              matching: find.byType(FadeTransition),
            ),
          )) {
            expect(fade.opacity.value, 1);
          }
          for (final size in tester.widgetList<SizeTransition>(
            find.ancestor(
              of: _shell(plan),
              matching: find.byType(SizeTransition),
            ),
          )) {
            expect(size.sizeFactor.value, 1);
          }
          expect(tester.takeException(), isNull);
        }

        verifyPermanentParts();
        for (final opening in [true, false, true]) {
          await _tapRow(tester, plan);
          expect(_expanded(tester, plan).expanded, opening);
          verifyPermanentParts();
          final size = tester.widget<AnimatedSize>(
            _slot(plan, 'plan-expanded-size'),
          );
          expect(size.duration, const Duration(milliseconds: 280));
          expect(size.reverseDuration, const Duration(milliseconds: 280));
          expect(size.curve, Curves.easeOutCubic);
          for (var frame = 1; frame <= 18; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            verifyPermanentParts();
            if (opening && frame == 3) {
              expect(_fade(tester, plan, 'plan-expanded-fade'), 0);
            }
            if (opening && frame == 8) {
              expect(_fade(tester, plan, 'plan-expanded-summary-fade'), 0);
              expect(
                _fade(tester, plan, 'plan-expanded-fade'),
                inExclusiveRange(0, 1),
              );
            }
            if (!opening && frame == 9) {
              expect(_fade(tester, plan, 'plan-expanded-fade'), 0);
              expect(_fade(tester, plan, 'plan-expanded-summary-fade'), 0);
            }
            if (!opening && frame == 12) {
              expect(
                _fade(tester, plan, 'plan-expanded-summary-fade'),
                inExclusiveRange(0, 1),
              );
            }
          }
          expect(_fade(tester, plan, 'plan-expanded-fade'), opening ? 1 : 0);
          expect(
            _fade(tester, plan, 'plan-expanded-summary-fade'),
            opening ? 0 : 1,
          );
          expect(
            tester.getSize(_card(plan)).height,
            opening
                ? greaterThan(collapsedHeight)
                : closeTo(collapsedHeight, .01),
          );
          expect(_scroll(tester).offset, 0);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'mid-flight reversals retain both cards and switching starts both size changes together',
    (tester) async {
      final app = await _show(tester);
      final first = app.store.savedPlans.first;
      final second = app.store.savedPlans.last;
      final plans = [first, second];
      final states = {
        for (final plan in plans) plan.id: tester.state(_card(plan)),
      };
      final shellElements = {
        for (final plan in plans) plan.id: tester.element(_shell(plan)),
      };
      final shellRenders = {
        for (final plan in plans) plan.id: tester.renderObject(_shell(plan)),
      };
      final summaries = {
        for (final plan in plans)
          plan.id: _expanded(tester, plan).collapsedSummary,
      };
      final summaryElements = {
        for (final plan in plans)
          plan.id: tester.element(
            find.byKey(ValueKey('saved-summary-${plan.id}')),
          ),
      };
      final collapsedFirst = _contentHeight(tester, first);
      final collapsedSecond = _contentHeight(tester, second);

      void verifyIdentities({
        required bool firstOpen,
        required bool secondOpen,
      }) {
        expect(_expanded(tester, first).expanded, firstOpen);
        expect(_expanded(tester, second).expanded, secondOpen);
        expect(
          tester
              .widgetList<CoachPlanExpanded>(find.byType(CoachPlanExpanded))
              .where((card) => card.expanded),
          hasLength(firstOpen || secondOpen ? 1 : 0),
        );
        for (final plan in plans) {
          expect(tester.state(_card(plan)), same(states[plan.id]));
          expect(_shell(plan), findsOneWidget);
          expect(tester.element(_shell(plan)), same(shellElements[plan.id]));
          expect(
            tester.renderObject(_shell(plan)),
            same(shellRenders[plan.id]),
          );
          expect(
            _expanded(tester, plan).collapsedSummary,
            same(summaries[plan.id]),
          );
          expect(
            tester.element(find.byKey(ValueKey('saved-summary-${plan.id}'))),
            same(summaryElements[plan.id]),
          );
        }
        expect(tester.takeException(), isNull);
      }

      verifyIdentities(firstOpen: false, secondOpen: false);
      await _tapRow(tester, first);
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        verifyIdentities(firstOpen: true, secondOpen: false);
      }
      final expandingAt80 = _contentHeight(tester, first);
      expect(expandingAt80, greaterThan(collapsedFirst));

      // Reverse at 80ms, before either the 280ms size or delayed body enter ends.
      await _tapRow(tester, first);
      expect(_contentHeight(tester, first), closeTo(expandingAt80, .01));
      verifyIdentities(firstOpen: false, secondOpen: false);
      for (var frame = 0; frame < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        verifyIdentities(firstOpen: false, secondOpen: false);
      }
      final collapsingAt32 = _contentHeight(tester, first);
      expect(collapsingAt32, lessThan(expandingAt80));
      expect(collapsingAt32, greaterThan(collapsedFirst));

      // Reverse again while collapse is still active; no replacement card.
      await _tapRow(tester, first);
      expect(_contentHeight(tester, first), closeTo(collapsingAt32, .01));
      verifyIdentities(firstOpen: true, secondOpen: false);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        verifyIdentities(firstOpen: true, secondOpen: false);
      }
      final beforeSwitchFirst = _contentHeight(tester, first);
      final beforeSwitchSecond = _contentHeight(tester, second);
      expect(beforeSwitchFirst, greaterThan(collapsingAt32));

      // The old expanded=false and new expanded=true arrive in one host frame.
      await _tapRow(tester, second);
      verifyIdentities(firstOpen: false, secondOpen: true);
      expect(_contentHeight(tester, first), closeTo(beforeSwitchFirst, .01));
      expect(_contentHeight(tester, second), closeTo(beforeSwitchSecond, .01));
      var previousFirst = beforeSwitchFirst;
      var previousSecond = beforeSwitchSecond;
      for (var frame = 0; frame < 18; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        verifyIdentities(firstOpen: false, secondOpen: true);
        final firstHeight = _contentHeight(tester, first);
        final secondHeight = _contentHeight(tester, second);
        expect(firstHeight, lessThanOrEqualTo(previousFirst + .01));
        expect(secondHeight, greaterThanOrEqualTo(previousSecond - .01));
        if (frame == 0) {
          expect(firstHeight, lessThan(beforeSwitchFirst));
          expect(secondHeight, greaterThan(beforeSwitchSecond));
        }
        previousFirst = firstHeight;
        previousSecond = secondHeight;
      }
      expect(_contentHeight(tester, first), closeTo(collapsedFirst, .01));
      expect(_contentHeight(tester, second), greaterThan(collapsedSecond));
      expect(_scroll(tester).offset, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'long-press menu, summary start and expanded start never toggle the card',
    (tester) async {
      SavedPlan? shown;
      SavedPlan? started;
      var startCount = 0;
      final app = await _show(
        tester,
        count: 1,
        onShow: (plan) => shown = plan,
        onStart: (plan, from) {
          started = plan;
          startCount++;
          expect(from(), isNotNull);
        },
      );
      final saved = app.store.savedPlans.single;
      final bodyStart = find.byKey(ValueKey('plan-start-${saved.plan.id}'));
      final summaryStart = find.byKey(ValueKey('saved-start-${saved.id}'));
      expect(bodyStart.hitTestable(), findsNothing);
      expect(summaryStart.hitTestable(), findsOneWidget);
      await tester.tap(summaryStart);
      await tester.pumpAndSettle();
      expect(started, same(saved));
      expect(startCount, 1);
      expect(_expanded(tester, saved).expanded, isFalse);

      Future<void> showFromMenu() async {
        final wasExpanded = _expanded(tester, saved).expanded;
        await tester.longPress(_card(saved));
        await tester.pumpAndSettle();
        expect(_expanded(tester, saved).expanded, wasExpanded);
        await tester.tap(find.text('发到对话'));
        await tester.pumpAndSettle();
        expect(shown, same(saved));
        expect(_expanded(tester, saved).expanded, wasExpanded);
      }

      await showFromMenu();
      await _tapRow(tester, saved);
      expect(_expanded(tester, saved).expanded, isTrue);
      expect(summaryStart.hitTestable(), findsNothing);
      expect(bodyStart.hitTestable(), findsNothing);
      await tester.pumpAndSettle();
      expect(bodyStart.hitTestable(), findsOneWidget);
      await showFromMenu();
      await tester.tap(bodyStart);
      await tester.pumpAndSettle();
      expect(started, same(saved));
      expect(startCount, 2);
      expect(_expanded(tester, saved).expanded, isTrue);
      await tester.tap(find.byKey(ValueKey('plan-expand-${saved.plan.id}')));
      await tester.pumpAndSettle();
      expect(_expanded(tester, saved).expanded, isFalse);
      expect(summaryStart.hitTestable(), findsOneWidget);
      expect(bodyStart.hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
      expect(_shell(first), findsOneWidget);
      expect(find.byKey(ValueKey('saved-${first.id}')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_fade(tester, first, 'plan-expanded-summary-fade'), 0);
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
      expect(_expanded(tester, first).expanded, isTrue);
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
    'one entry expands and its long-press menu survives collapse and rename',
    (tester) async {
      SavedPlan? shown;
      final app = await _show(tester, onShow: (plan) => shown = plan);
      final first = app.store.savedPlans.first;
      final second = app.store.savedPlans.last;
      await _tapRow(tester, first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ValueKey('saved-${second.id}')));
      await _tapRow(tester, second);
      expect(_expanded(tester, first).expanded, isFalse);
      expect(_expanded(tester, second).expanded, isTrue);
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
      await tester.longPress(_card(second));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('rename-field')),
        '重命名后方案',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rename-ok')));
      await tester.pumpAndSettle();
      await _tapRow(tester, second);
      await tester.pumpAndSettle();
      expect(_expanded(tester, second).plan.title, '重命名后方案');
      await tester.tap(find.byKey(ValueKey('plan-expand-${second.plan.id}')));
      await tester.pumpAndSettle();
      await tester.longPress(_card(second));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发到对话'));
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
