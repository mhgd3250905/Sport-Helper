import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/guide_media.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show services;

TrainingPlan _plan({int count = 3}) => TrainingPlan(
  id: 'guide-layout',
  source: 'template',
  title: '居家颈肩舒展训练',
  summary: '按顺序轻柔活动，保持自然呼吸。',
  goal: 'stretch',
  scene: 'home',
  equipment: const ['mat'],
  level: 1,
  targetMinutes: 5,
  safetyNotes: const ['出现疼痛时停止训练。'],
  blocks: [
    PlanBlock(
      id: 'main',
      name: 'main',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        for (var index = 0; index < count; index++)
          PlanItem(
            exerciseId: index.isEven ? 'h-catcow-quad' : 'h-banana',
            mode: DoseMode.time,
            sets: 2,
            workSeconds: 30,
            perSide: index.isOdd,
            restSeconds: 10,
          ),
      ],
    ),
  ],
);

Future<AppServices> _show(
  WidgetTester tester, {
  SfPalette palette = SfPalette.light,
  double width = 390,
  double scale = 1,
  int count = 3,
  TrainingPlan? plan,
  List<String>? firstCues,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = services();
  if (firstCues != null) {
    app.library['h-catcow-quad'].cues
      ..clear()
      ..addAll(firstCues);
  }
  await app.store.acceptSafety(blocked: false);
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(palette),
        builder: (context, child) => SfPaletteScope(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: child!,
          ),
        ),
        home: PlanPage(plan: plan ?? _plan(count: count)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  return app;
}

Finder _key(String value) => find.byKey(ValueKey(value));
ListView _list(WidgetTester tester) =>
    tester.widget<ListView>(_key('plan-article'));

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets('guide uses approved ${palette.brightness.name} card values', (
      tester,
    ) async {
      final app = await _show(
        tester,
        palette: palette,
        // A two-step fixture makes the exact inter-step gap measurable.
        firstCues: const ['四点支撑，缓慢活动背部。', '保持自然呼吸，轻柔回到中立位。'],
      );
      final title = tester.widget<Text>(_key('guide-title'));
      expect(title.style!.fontSize, 24);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(tester.getTopLeft(_key('guide-title')).dx, 20);
      for (var index = 0; index < 4; index++) {
        final chip = tester.widget<Container>(_key('guide-tag-$index'));
        final shape = chip.decoration! as BoxDecoration;
        final text = tester.widget<Text>(
          find.descendant(
            of: _key('guide-tag-$index'),
            matching: find.byType(Text),
          ),
        );
        expect(tester.getSize(_key('guide-tag-$index')).height, 26);
        expect(chip.padding, const EdgeInsets.symmetric(horizontal: 10));
        expect(shape.borderRadius, BorderRadius.circular(13));
        expect(text.style!.fontSize, 12);
        expect(text.style!.fontWeight, FontWeight.w500);
      }
      expect(
        tester.getTopLeft(_key('guide-tag-0')).dy -
            tester.getBottomLeft(_key('guide-title')).dy,
        8,
      );
      final tags = tester.widget<Wrap>(
        find.ancestor(of: _key('guide-tag-0'), matching: find.byType(Wrap)),
      );
      expect(tags.spacing, 6);
      expect(tags.runSpacing, 6);
      final section = tester.widget<Padding>(_key('guide-section-main'));
      expect(section.padding, const EdgeInsets.only(top: 28, bottom: 10));
      final sectionText = tester.widget<Text>(find.text('主训'));
      expect(sectionText.style!.fontSize, 13);
      expect(sectionText.style!.fontWeight, FontWeight.w600);
      expect(sectionText.style!.letterSpacing, .5);
      expect(sectionText.style!.color, palette.muted);
      final decoration =
          tester.widget<DecoratedBox>(_key('guide-card-0:0')).decoration
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(decoration.color, palette.surface);
      if (palette.isDark) {
        expect(decoration.boxShadow, isEmpty);
      } else {
        expect(decoration.boxShadow, hasLength(1));
        final shadow = decoration.boxShadow!.single;
        expect(shadow.offset, const Offset(0, 1));
        expect(shadow.blurRadius, 3);
        expect(shadow.color, Colors.black.withValues(alpha: .06));
      }
      expect(_key('guide-repaint-0:0'), findsOneWidget);
      expect(tester.widget(_key('guide-repaint-0:0')), isA<RepaintBoundary>());
      expect(
        tester.widget<AspectRatio>(_key('article-video-0:0')).aspectRatio,
        4 / 3,
      );
      final media = tester.getSize(_key('article-video-0:0'));
      expect(media.width, 350);
      expect(media.height, closeTo(262.5, .01));
      expect(
        tester.widget<Padding>(_key('guide-body-0:0')).padding,
        const EdgeInsets.fromLTRB(16, 14, 16, 16),
      );
      final number = tester.widget<Container>(_key('guide-number-0:0'));
      expect(tester.getSize(_key('guide-number-0:0')), const Size(24, 24));
      final numberStyle = tester
          .widget<Text>(
            find.descendant(
              of: _key('guide-number-0:0'),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(numberStyle.fontSize, 13);
      expect(numberStyle.fontWeight, FontWeight.w700);
      expect(
        (number.decoration! as BoxDecoration).color,
        palette.accent.withValues(alpha: .12),
      );
      expect(
        (number.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(12),
      );
      final name = tester.widget<Text>(_key('guide-name-0:0'));
      expect(name.data, app.library['h-catcow-quad'].name);
      expect(name.style!.fontSize, 17);
      expect(name.style!.fontWeight, FontWeight.w600);
      expect(name.maxLines, 2);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(
        tester.getTopLeft(_key('guide-name-0:0')).dx -
            tester.getTopRight(_key('guide-number-0:0')).dx,
        10,
      );
      final muscles = tester.widget<Text>(_key('guide-muscles-0:0'));
      expect(muscles.style!.fontSize, 13);
      expect(muscles.maxLines, 1);
      expect(
        tester.getTopLeft(_key('guide-muscles-0:0')).dx,
        tester.getTopLeft(_key('guide-name-0:0')).dx,
      );
      final dose = tester.widget<Container>(_key('guide-dose-chip-0:0'));
      expect(tester.getSize(_key('guide-dose-chip-0:0')).height, 26);
      expect(dose.padding, const EdgeInsets.symmetric(horizontal: 10));
      expect(
        (dose.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(13),
      );
      expect(
        (dose.decoration! as BoxDecoration).color,
        palette.accent.withValues(alpha: palette.isDark ? .18 : .10),
      );
      final doseText = tester.widget<Text>(_key('plan-dose-0:0'));
      expect(doseText.data, _plan().items.first.doseText());
      expect(doseText.style!.fontSize, 13);
      expect(doseText.style!.fontWeight, FontWeight.w600);
      expect(doseText.style!.color, palette.accent);
      final divider = tester.widget<SizedBox>(_key('guide-divider-0:0'));
      expect(divider.height, 1);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: _key('guide-divider-0:0'),
                matching: find.byType(ColoredBox),
              ),
            )
            .color,
        palette.line.withValues(alpha: .6),
      );
      final stepNumber = tester.widget<Container>(
        _key('guide-step-number-0:0-1'),
      );
      expect(
        tester.getSize(_key('guide-step-number-0:0-1')),
        const Size(18, 18),
      );
      final stepNumberText = tester.widget<Text>(
        find.descendant(
          of: _key('guide-step-number-0:0-1'),
          matching: find.byType(Text),
        ),
      );
      expect(stepNumberText.style!.fontSize, 11);
      expect(stepNumberText.style!.fontWeight, FontWeight.w600);
      expect(
        (stepNumber.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(9),
      );
      final stepText = tester.widget<Text>(_key('guide-step-text-0:0-1'));
      expect(stepText.style!.fontSize, 14);
      expect(stepText.style!.height, 1.5);
      expect(
        tester.getTopLeft(_key('guide-step-text-0:0-1')).dx -
            tester.getTopRight(_key('guide-step-number-0:0-1')).dx,
        8,
      );
      expect(
        tester.getTopLeft(_key('guide-step-0:0-2')).dy -
            tester.getBottomLeft(_key('guide-step-0:0-1')).dy,
        8,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guide lazily builds cards and keeps the 14px inter-card gap', (
    tester,
  ) async {
    await _show(tester, count: 40);
    expect(_list(tester).childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(_key('guide-card-0:39'), findsNothing);
    expect(find.byType(GuideMedia).evaluate().length, lessThan(40));
    final first = tester.getRect(_key('guide-card-0:0'));
    final view = tester.getRect(_key('plan-article'));
    _list(tester).controller!.jumpTo(first.bottom - view.top - 80);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_key('guide-card-0:1')).dy -
          tester.getBottomLeft(_key('guide-card-0:0')).dy,
      14,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new section is 28px from prior card without stacked gap', (
    tester,
  ) async {
    final firstPlan = _plan(count: 1);
    final second = PlanBlock.fromJson({
      ...firstPlan.blocks.single.toJson(),
      'id': 'second',
      'name': '放松收尾',
    });
    await _show(
      tester,
      plan: firstPlan.copyWith(blocks: [...firstPlan.blocks, second]),
    );
    final first = tester.getRect(_key('guide-card-0:0'));
    final view = tester.getRect(_key('plan-article'));
    _list(tester).controller!.jumpTo(first.bottom - view.top - 100);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('放松收尾')).dy -
          tester.getBottomLeft(_key('guide-card-0:0')).dy,
      28,
    );
    expect(
      tester.widget<Padding>(_key('plan-move-0:0')).padding,
      EdgeInsets.zero,
    );
    await tester.scrollUntilVisible(_key('guide-card-1:0'), 200);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Padding>(_key('plan-move-1:0')).padding,
      EdgeInsets.zero,
    );
    expect(_list(tester).padding, const EdgeInsets.fromLTRB(20, 0, 20, 120));
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('guide clears its fixed action at ${width}px and ${scale}x', (
        tester,
      ) async {
        await _show(tester, width: width, scale: scale);
        final button = tester.getRect(_key('guide-training-button'));
        expect(button.left, 20);
        expect(button.right, width - 20);
        expect(button.height, 52);
        expect(button.bottom, 844 - 24 - 12);
        final face = tester.widget<Container>(_key('guide-training-button'));
        expect(
          (face.decoration! as BoxDecoration).borderRadius,
          BorderRadius.circular(26),
        );
        expect(
          (face.decoration! as BoxDecoration).color,
          SfPalette.light.accent,
        );
        final text = tester.widget<Text>(find.text('前往训练'));
        expect(text.style!.fontSize, 16);
        expect(text.style!.fontWeight, FontWeight.w600);
        final gradient =
            tester
                    .widget<DecoratedBox>(_key('guide-training-gradient'))
                    .decoration
                as BoxDecoration;
        expect(tester.getSize(_key('guide-training-gradient')).height, 24);
        expect(
          (gradient.gradient! as LinearGradient).colors.map((color) => color.a),
          [0, 1],
        );
        expect(
          _list(tester).padding,
          const EdgeInsets.fromLTRB(20, 0, 20, 120),
        );
        await tester.scrollUntilVisible(_key('guide-card-0:2'), 300);
        await tester.pumpAndSettle();
        final scroll = _list(tester).controller!;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text('出现疼痛时停止训练。'), findsOneWidget);
        expect(
          tester.getBottomLeft(_key('guide-card-0:2')).dy,
          lessThanOrEqualTo(button.top - 24),
        );
        expect(_key('start').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
