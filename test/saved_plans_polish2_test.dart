import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/ui/chat/expand_route.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/plan_presentation.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show services;

TrainingPlan _plan(int index) => TrainingPlan(
  id: 'polish2-plan-$index',
  source: 'template',
  title: '训练方案 $index',
  summary: '保留原有的训练动作和剂量。',
  goal: 'mixed',
  scene: 'home',
  equipment: const [],
  level: 1,
  targetMinutes: 9,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        for (var move = 0; move < 8; move++)
          PlanItem(
            exerciseId: const ['h-squat', 'h-banana'][move % 2],
            mode: DoseMode.time,
            sets: 1,
            workSeconds: 30,
            perSide: false,
            restSeconds: 10,
          ),
      ],
    ),
  ],
);

Future<AppServices> _show(
  WidgetTester tester, {
  SfPalette palette = SfPalette.light,
  int count = 2,
  double height = 844,
  bool used = false,
  ValueChanged<SavedPlan>? onShow,
  void Function(SavedPlan, OriginRect)? onStart,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = services();
  await app.store.acceptSafety(blocked: false);
  for (var index = 0; index < count; index++) {
    final saved = await app.store.savePlan(
      _plan(index),
      name: '训练方案 $index',
      now: DateTime.utc(2026, 10, 29, 0, index),
    );
    if (used) await app.store.touchPlan(saved.id, now: DateTime.now());
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

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _card(SavedPlan saved) => _key('saved-expanded-${saved.id}');
Finder _entry(SavedPlan saved) => _key('saved-entry-${saved.id}');
Finder _title(SavedPlan saved) => _key('saved-title-${saved.id}');
Finder _meta(SavedPlan saved) => _key('saved-meta-${saved.id}');
Finder _used(SavedPlan saved) => _key('saved-used-${saved.id}');
Finder get _menu => _key('saved-plan-context-menu');

bool _expanded(WidgetTester tester, SavedPlan saved) =>
    tester.widget<CoachPlanExpanded>(_card(saved)).expanded;

TextStyle _style(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  return DefaultTextStyle.of(tester.element(finder)).style.merge(text.style);
}

double _baseline(WidgetTester tester, Finder finder) {
  final rich = find.descendant(of: finder, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(rich);
  return tester.getTopLeft(rich).dy +
      paragraph.getDryBaseline(paragraph.constraints, TextBaseline.alphabetic)!;
}

Future<void> _openMenu(WidgetTester tester, SavedPlan saved) async {
  await tester.longPress(_card(saved));
  await tester.pumpAndSettle();
  expect(_menu, findsOneWidget);
}

Future<void> _choose(
  WidgetTester tester,
  SavedPlan saved,
  String command,
) async {
  await _openMenu(tester, saved);
  await tester.tap(_key('saved-menu-$command'));
  await tester.pumpAndSettle();
}

List<BoxDecoration> _decorations(WidgetTester tester, Finder finder) => [
  for (final widget in tester.widgetList<DecoratedBox>(
    find.descendant(of: finder, matching: find.byType(DecoratedBox)),
  ))
    if (widget.decoration is BoxDecoration) widget.decoration as BoxDecoration,
];

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final theme = palette.brightness.name;
    final dark = palette.isDark;

    testWidgets('$theme collapsed rows retain the exact compact geometry', (
      tester,
    ) async {
      final app = await _show(tester, palette: palette);
      final first = app.store.savedPlans.first;
      final second = app.store.savedPlans.last;
      final card = tester.getRect(_card(first));
      final thumbnail = tester.getRect(_key('saved-thumbnail-${first.id}'));
      final title = tester.getRect(_title(first));
      final meta = tester.getRect(_meta(first));
      final textColumn = tester.getRect(
        find.ancestor(of: _title(first), matching: find.byType(Column)).first,
      );
      final play = tester.getRect(_key('saved-start-${first.id}'));

      expect(card.left, 20);
      expect(card.right, 370);
      expect(card.height, 108);
      expect(tester.getRect(_card(second)).top - card.bottom, 12);
      expect(thumbnail.size, const Size(76, 76));
      expect(thumbnail.left - card.left, 16);
      expect(thumbnail.top - card.top, 16);
      expect(card.bottom - thumbnail.bottom, 16);
      expect(title.left - thumbnail.right, 14);
      expect(meta.left, title.left);
      expect(meta.top - title.bottom, closeTo(6, .001));
      expect((title.top + meta.bottom) / 2, closeTo(thumbnail.center.dy, .001));
      expect(play.size, const Size(44, 44));
      expect(card.right - play.right, 16);
      expect(play.center.dy, thumbnail.center.dy);
      expect(play.left - textColumn.right, 12);
      expect(_used(first), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('点一下在对话里调出'), findsNothing);

      final titleWidget = tester.widget<Text>(_title(first));
      final titleStyle = _style(tester, _title(first));
      final metaStyle = _style(tester, _meta(first));
      expect(titleWidget.maxLines, 1);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(titleStyle.fontSize, 16);
      expect(titleStyle.fontWeight, FontWeight.w600);
      expect(titleStyle.height, 1.3);
      expect(titleStyle.color, palette.text);
      expect(metaStyle.fontSize, 13);
      expect(metaStyle.fontWeight, FontWeight.w400);
      expect(
        metaStyle.color,
        dark ? Colors.white.withValues(alpha: .64) : const Color(0xFF5F6B68),
      );
      expect(
        tester.widget<Text>(_meta(first)).data,
        '${planDurationLabel(first.plan, app.library)} · 8 个动作',
      );

      final count = find.text('2 套');
      final hint = find.text('长按可编辑');
      expect(_style(tester, count).fontSize, 14);
      expect(_style(tester, count).fontWeight, FontWeight.w500);
      expect(_style(tester, hint).fontSize, 12);
      expect(_style(tester, hint).fontWeight, FontWeight.w400);
      expect(
        _style(tester, hint).color,
        dark ? Colors.white.withValues(alpha: .42) : const Color(0xFF8A9592),
      );
      expect(tester.getRect(count).left, 20);
      expect(tester.getRect(hint).right, 370);
      expect(_baseline(tester, count), closeTo(_baseline(tester, hint), .001));
      expect(
        card.top -
            tester.getRect(count).expandToInclude(tester.getRect(hint)).bottom,
        closeTo(12, .001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$theme used rows keep all three lines centered', (
      tester,
    ) async {
      final app = await _show(tester, palette: palette, count: 1, used: true);
      final saved = app.store.savedPlans.single;
      final thumbnail = tester.getRect(_key('saved-thumbnail-${saved.id}'));
      final title = tester.getRect(_title(saved));
      final meta = tester.getRect(_meta(saved));
      final used = tester.getRect(_used(saved));
      expect(tester.getSize(_card(saved)).height, 108);
      expect(meta.top - title.bottom, closeTo(6, .001));
      expect(used.top - meta.bottom, closeTo(4, .001));
      expect((title.top + used.bottom) / 2, closeTo(thumbnail.center.dy, .001));
      expect(tester.widget<Text>(_used(saved)).data, '刚刚练过');
      expect(_style(tester, _used(saved)).fontSize, 12);
      expect(_style(tester, _used(saved)).fontWeight, FontWeight.w400);
      expect(
        _style(tester, _used(saved)).color,
        dark ? Colors.white.withValues(alpha: .42) : const Color(0xFF8A9592),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$theme play and long press keep the SDK card collapsed', (
      tester,
    ) async {
      SavedPlan? started;
      SavedPlan? shown;
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final app = await _show(
        tester,
        palette: palette,
        count: 1,
        onShow: (saved) => shown = saved,
        onStart: (saved, from) {
          started = saved;
          expect(from(), isNotNull);
        },
      );
      final saved = app.store.savedPlans.single;
      final sdkState = tester.state(_card(saved));
      await tester.tap(_key('saved-start-${saved.id}'));
      await tester.pumpAndSettle();
      expect(started, same(saved));
      expect(_expanded(tester, saved), isFalse);

      final original = tester.getRect(_card(saved));
      final gesture = await tester.startGesture(original.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.getRect(_card(saved)).width,
        closeTo(original.width * .98, .01),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_menu, findsOneWidget);
      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(_expanded(tester, saved), isFalse);
      expect(tester.state(_card(saved)), same(sdkState));
      expect(tester.getRect(_card(saved)), original);

      final menuRect = tester.getRect(_menu);
      expect(menuRect.width, 208);
      expect(original.right - menuRect.right, 16);
      expect(menuRect.top - original.bottom, 8);
      final show = _key('saved-menu-show');
      final rename = _key('saved-menu-rename');
      final delete = _key('saved-menu-delete');
      expect(tester.getSize(show).height, 48);
      expect(tester.getSize(rename).height, 48);
      expect(tester.getSize(delete).height, 48);
      expect(
        tester.getTopLeft(show).dy,
        lessThan(tester.getTopLeft(rename).dy),
      );
      expect(
        tester.getTopLeft(rename).dy,
        lessThan(tester.getTopLeft(delete).dy),
      );
      expect(find.text('发到对话'), findsOneWidget);
      expect(find.text('点一下在对话里调出'), findsNothing);
      expect(_style(tester, find.text('发到对话')).fontSize, 15);
      expect(_style(tester, find.text('发到对话')).fontWeight, FontWeight.w500);
      expect(
        _style(tester, find.text('删除')).color,
        dark ? const Color(0xFFFF6B6B) : const Color(0xFFD64545),
      );
      final decorations = _decorations(tester, _menu);
      expect(
        decorations.any(
          (decoration) =>
              decoration.color ==
                  (dark ? const Color(0xFF1A2324) : Colors.white) &&
              decoration.borderRadius == BorderRadius.circular(16) &&
              decoration.border ==
                  Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: .08)
                        : const Color(0xFFE3E8E6),
                  ) &&
              decoration.boxShadow?.single.offset == const Offset(0, 8) &&
              decoration.boxShadow?.single.blurRadius == 24 &&
              decoration.boxShadow?.single.color ==
                  Colors.black.withValues(alpha: dark ? .40 : .10),
        ),
        isTrue,
      );
      expect(tester.getTopLeft(show).dy - menuRect.top, 6);
      expect(menuRect.bottom - tester.getBottomRight(delete).dy, 6);
      expect(_key('saved-menu-mask'), findsOneWidget);
      await tester.tap(show);
      await tester.pumpAndSettle();
      expect(shown, same(saved));
      expect(_menu, findsNothing);
      expect(_expanded(tester, saved), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      '$theme rename selects the original and validates trimmed text',
      (tester) async {
        final app = await _show(tester, palette: palette, count: 1);
        final saved = app.store.savedPlans.single;
        await _choose(tester, saved, 'rename');
        final field = _key('rename-field');
        final input = tester.widget<TextField>(field);
        expect(input.autofocus, isTrue);
        expect(input.controller!.text, saved.name);
        expect(
          input.controller!.selection,
          TextSelection(baseOffset: 0, extentOffset: saved.name.length),
        );
        expect(
          input.focusNode?.hasFocus ?? tester.testTextInput.isVisible,
          isTrue,
        );
        expect(tester.getSize(field).height, 48);
        expect(tester.getSize(_key('rename-ok')).height, 48);
        expect(_key('saved-rename-sheet'), findsOneWidget);
        expect(_style(tester, find.text('重命名')).fontSize, 17);
        expect(_style(tester, find.text('重命名')).fontWeight, FontWeight.w600);
        final originalSheet = tester.getRect(_key('saved-rename-sheet'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        final raisedSheet = tester.getRect(_key('saved-rename-sheet'));
        expect(raisedSheet.bottom, closeTo(originalSheet.bottom - 280, .01));
        expect(raisedSheet.top, lessThan(originalSheet.top));
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        await tester.enterText(field, '   ');
        await tester.pump();
        await tester.tap(_key('rename-ok'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(app.store.savedPlans.single.name, saved.name);
        await tester.enterText(field, '  ${saved.name}  ');
        await tester.pump();
        await tester.tap(_key('rename-ok'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(field, findsOneWidget);
        expect(app.store.savedPlans.single.name, saved.name);

        await tester.enterText(field, '  新的九分钟方案  ');
        await tester.pump();
        await tester.tap(_key('rename-ok'));
        await tester.pumpAndSettle();
        expect(field, findsNothing);
        expect(app.store.savedPlans.single.name, '新的九分钟方案');
        expect(app.store.savedPlans.single.plan.toJson(), saved.plan.toJson());
        expect(find.text('新的九分钟方案'), findsOneWidget);
        expect(_expanded(tester, saved), isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '$theme delete requires confirmation and animates the row away',
      (tester) async {
        final app = await _show(tester, palette: palette);
        final saved = app.store.savedPlans.first;
        final next = app.store.savedPlans.last;
        await _choose(tester, saved, 'delete');
        expect(find.text('删除「${saved.name}」？'), findsOneWidget);
        expect(find.text('删除后无法恢复'), findsOneWidget);
        final dialog = tester.getRect(
          find
              .descendant(
                of: _key('saved-delete-dialog'),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(dialog.width, 390 - 64);
        expect(dialog.center.dx, 195);
        expect(_style(tester, find.text('删除「${saved.name}」？')).fontSize, 17);
        expect(
          _style(tester, find.text('删除「${saved.name}」？')).fontWeight,
          FontWeight.w600,
        );
        expect(_style(tester, find.text('删除后无法恢复')).fontSize, 14);
        final confirm = _key('delete-ok');
        expect(tester.getSize(confirm).height, 44);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(app.store.savedPlans, hasLength(2));
        expect(tester.getSize(_entry(saved)).height, 108);

        await _choose(tester, saved, 'delete');
        final originalNextTop = tester.getTopLeft(_entry(next)).dy;
        await tester.tap(_key('delete-ok'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.getSize(_entry(saved)).height, inExclusiveRange(0, 108));
        expect(
          tester.getTopLeft(_entry(next)).dy,
          inExclusiveRange(originalNextTop - 120, originalNextTop),
        );
        await tester.pumpAndSettle();
        expect(app.store.savedPlans, hasLength(1));
        expect(app.store.savedPlans.single.id, next.id);
        expect(_entry(saved), findsNothing);
        expect(tester.getTopLeft(_entry(next)).dy, originalNextTop - 120);
        expect(find.text('1 套'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'menu above the last visible card and backdrop/back both dismiss',
    (tester) async {
      final app = await _show(tester, count: 5, height: 600);
      final last = app.store.savedPlans.last;
      await tester.scrollUntilVisible(_card(last), 120);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_card(last));
      await tester.pumpAndSettle();
      final card = tester.getRect(_card(last));
      await _openMenu(tester, last);
      final menuRect = tester.getRect(_menu);
      expect(menuRect.width, 208);
      expect(card.right - menuRect.right, 16);
      expect(card.top - menuRect.bottom, 8);
      await tester.tapAt(const Offset(8, 80));
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      expect(find.byType(SavedPlansPage), findsOneWidget);

      await _openMenu(tester, last);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_menu, findsNothing);
      expect(find.byType(SavedPlansPage), findsOneWidget);
      expect(_expanded(tester, last), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rename stays scrollable in a short window with the keyboard', (
    tester,
  ) async {
    final app = await _show(tester, count: 1, height: 300);
    final saved = app.store.savedPlans.single;
    await _choose(tester, saved, 'rename');
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final field = _key('rename-field');
    await tester.enterText(field, '横屏时也能保存');
    await tester.pump();
    final save = _key('rename-ok');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(field, findsNothing);
    expect(app.store.savedPlans.single.name, '横屏时也能保存');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('deleting an expanded card keeps its body open while shrinking', (
    tester,
  ) async {
    final app = await _show(tester, height: 1400);
    final saved = app.store.savedPlans.first;
    final next = app.store.savedPlans.last;
    await tester.tap(_key('saved-${saved.id}'));
    await tester.pumpAndSettle();
    expect(_expanded(tester, saved), isTrue);
    final expandedHeight = tester.getSize(_card(saved)).height;
    expect(expandedHeight, greaterThan(108));
    expect(tester.getSize(_entry(saved)).height, expandedHeight);
    final originalNextTop = tester.getTopLeft(_entry(next)).dy;

    await _choose(tester, saved, 'delete');
    await tester.tap(_key('delete-ok'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(_expanded(tester, saved), isTrue);
    expect(tester.getSize(_card(saved)).height, expandedHeight);
    expect(
      tester.getSize(_entry(saved)).height,
      inExclusiveRange(0, expandedHeight),
    );
    expect(tester.getTopLeft(_entry(next)).dy, lessThan(originalNextTop));

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump();
    expect(_entry(saved), findsNothing);
    expect(app.store.savedPlans.single.id, next.id);
    expect(
      tester.getTopLeft(_entry(next)).dy,
      closeTo(originalNextTop - expandedHeight - 12, .01),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
