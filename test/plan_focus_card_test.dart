import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/validated_plan_card.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'support.dart';
import 'support/coach_v2_fixtures.dart';

const _plan = TrainingPlan(
  id: 'focus-card',
  source: 'ai',
  title: '舒展练习',
  summary: '保持原有动作和剂量。',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 10,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 's-butterfly',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 10,
        ),
        PlanItem(
          exerciseId: 's-frog',
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

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _primary => _key('plan-primary-save-${_plan.id}');
Finder get _copy => _key('plan-save-copy-${_plan.id}');

Future<void> _host(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  SfPalette palette = SfPalette.light,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SfColors.palette = palette;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(palette),
      builder: (context, child) => SfPaletteScope(child: child!),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, {String id = 'focus-card'}) async {
  final toggle = _key('plan-expand-$id');
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  late ExerciseLibrary library;
  late coach.ValidatedPlan admitted;
  setUpAll(() async {
    // Measure CJK with the same font as the App rather than Ahem fallback.
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    library = loadLibrary();
    final fixture = await CoachV2Fixtures.load();
    final ids = _plan.exerciseIds.toList();
    final sdkPlan = coach.TrainingPlan(
      id: _plan.id,
      source: 'ai',
      title: _plan.title,
      summary: _plan.summary,
      goal: _plan.goal,
      scene: _plan.scene,
      equipment: {
        for (final id in ids) ...fixture.catalog[id]!.equipment,
      }.toList(),
      level: _plan.level,
      targetMinutes: _plan.targetMinutes,
      blocks: [
        coach.PlanBlock(
          id: 'main',
          name: '主训练',
          type: coach.BlockType.main,
          items: [
            for (final id in ids)
              coach.PlanItem(
                exerciseId: id,
                mode: fixture.catalog[id]!.defaultDose.mode,
                sets: 1,
                reps:
                    fixture.catalog[id]!.defaultDose.mode == coach.DoseMode.reps
                    ? 8
                    : null,
                workSeconds:
                    fixture.catalog[id]!.defaultDose.mode == coach.DoseMode.time
                    ? 30
                    : null,
                perSide: fixture.catalog[id]!.unilateral,
                restSeconds: 10,
              ),
          ],
        ),
      ],
    );
    final context = coach.CoachContext(
      scene: sdkPlan.scene,
      equipment: sdkPlan.equipment.toSet(),
      level: sdkPlan.level,
      minutes: sdkPlan.targetMinutes,
      goal: sdkPlan.goal,
    );
    final validation = coach.PlanValidator(
      catalog: fixture.catalog,
      profile: fixture.profile,
    ).validate(sdkPlan, context);
    expect(
      validation.ok,
      isTrue,
      reason: const JsonEncoder.withIndent(
        '  ',
      ).convert([for (final issue in validation.issues) issue.toJson()]),
    );
    admitted = coach.ToolGate(
      catalog: fixture.catalog,
      profile: fixture.profile,
    ).admitTemplate(sdkPlan, context)!;
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    for (final width in [320.0, 390.0]) {
      testWidgets(
        '${palette.brightness.name} $width update and copy fit beside SDK start',
        (tester) async {
          var saves = 0;
          var copies = 0;
          var starts = 0;
          await _host(
            tester,
            PlanCard(
              plan: _plan,
              library: library,
              saved: false,
              saveLabel: '更新到我的计划',
              savedLabel: '已更新',
              onStart: () => starts++,
              onSave: () => saves++,
              onSaveCopy: () => copies++,
              onOpen: () {},
            ),
            width: width,
            palette: palette,
          );
          await _expand(tester);
          expect(find.text('更新到我的计划'), findsOneWidget);
          expect(find.text('另存一份'), findsOneWidget);
          final primaryRect = tester.getRect(_primary);
          final copyRect = tester.getRect(_copy);
          final startRect = tester.getRect(_key('plan-start-${_plan.id}'));
          expect(copyRect.left - primaryRect.right, 12);
          expect(copyRect.height, primaryRect.height);
          expect(copyRect.height, 44);
          expect(copyRect.center.dy, primaryRect.center.dy);
          expect(copyRect.right, lessThanOrEqualTo(startRect.left));
          final copyText = find.descendant(
            of: _copy,
            matching: find.text('另存一份'),
          );
          final style = DefaultTextStyle.of(
            tester.element(copyText),
          ).style.merge(tester.widget<Text>(copyText).style);
          expect(style.fontFamily, 'NotoSansSC');
          expect(style.fontSize, 14);
          expect(style.fontWeight, FontWeight.w500);
          expect(style.color, palette.accent);
          for (final decoration in tester.widgetList<DecoratedBox>(
            find.descendant(of: _copy, matching: find.byType(DecoratedBox)),
          )) {
            if (decoration.decoration case final BoxDecoration box) {
              expect(box.color, isNull);
            }
          }
          await tester.tap(_copy);
          await tester.pumpAndSettle();
          expect(copies, 1);
          expect(saves, 0);
          await tester.tap(_primary);
          await tester.pumpAndSettle();
          expect(saves, 1);
          await tester.tap(_key('plan-start-${_plan.id}'));
          expect(starts, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('completed update disables only primary and keeps copy active', (
    tester,
  ) async {
    var saved = false;
    var saves = 0;
    var copies = 0;
    await _host(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PlanCard(
          plan: _plan,
          library: library,
          saved: saved,
          saveLabel: '更新到我的计划',
          savedLabel: '已更新',
          onStart: () {},
          onSave: () {
            saves++;
            setState(() => saved = true);
          },
          onSaveCopy: () => copies++,
          onOpen: () {},
        ),
      ),
    );
    await _expand(tester);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('已更新'), findsOneWidget);
    final disabled = tester.widget<SfPressable>(
      find.descendant(of: _primary, matching: find.byType(SfPressable)),
    );
    expect(disabled.onTap, isNull);
    await tester.tap(_copy);
    await tester.pumpAndSettle();
    expect(copies, 1);
    expect(saves, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'validated override wins and copy receives the exact App snapshot',
    (tester) async {
      var isSavedCalls = 0;
      TrainingPlan? copied;
      await _host(
        tester,
        ValidatedPlanCard(
          validatedPlan: admitted,
          library: library,
          isSaved: (_) {
            isSavedCalls++;
            return false;
          },
          savedOverride: true,
          updatingSavedPlan: true,
          onStart: (_) {},
          onSave: (_) =>
              fail('The saved override disables the primary action.'),
          onSaveCopy: (plan) => copied = plan,
          onOpen: (_) {},
        ),
      );
      await _expand(tester);
      expect(isSavedCalls, 0);
      expect(find.text('已更新'), findsOneWidget);
      await tester.tap(_copy);
      await tester.pumpAndSettle();
      expect(
        copied!.toJson(),
        TrainingPlan.fromJson(admitted.plan.toJson()).toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save labels are local and ordinary cards retain SDK footer', (
    tester,
  ) async {
    final ordinary = TrainingPlan.fromJson({
      ..._plan.toJson(),
      'id': 'ordinary-card',
    });
    await _host(
      tester,
      CoachUiTheme(
        style: smartfitCoachUiStyle(),
        child: Column(
          children: [
            PlanCard(
              plan: _plan,
              library: library,
              saved: false,
              saveLabel: '更新到我的计划',
              savedLabel: '已更新',
              onSaveCopy: () {},
              onStart: () {},
              onSave: () {},
              onOpen: () {},
            ),
            PlanCard(
              plan: ordinary,
              library: library,
              saved: false,
              onStart: () {},
              onSave: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
    await _expand(tester);
    await _expand(tester, id: ordinary.id);
    expect(find.text('更新到我的计划'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('另存一份'), findsOneWidget);
    expect(_key('plan-save-copy-${ordinary.id}'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
