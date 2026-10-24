import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

const _plan = TrainingPlan(
  id: 'wrapped-dose-integration',
  source: 'template',
  title: '分段循环训练',
  summary: '',
  goal: 'mobility',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 12,
  blocks: [
    PlanBlock(
      id: 'circuit',
      name: '循环',
      type: BlockType.circuit,
      rounds: 3,
      restBetweenRoundsSeconds: 30,
      items: [
        PlanItem(
          exerciseId: 's-figure4',
          mode: DoseMode.time,
          sets: 3,
          perSide: true,
          restSeconds: 20,
          segments: [
            coach.PlanSegment(
              id: 'slow',
              exerciseId: 's-figure4',
              label: '缓慢进入并保持呼吸顺畅',
              mode: coach.DoseMode.time,
              workSeconds: 30,
            ),
            coach.PlanSegment(
              id: 'steady',
              exerciseId: 's-figure4',
              label: '保持髋部稳定再缓慢退出',
              mode: coach.DoseMode.time,
              workSeconds: 20,
            ),
          ],
        ),
        PlanItem(
          exerciseId: 'w-dead-bug',
          mode: DoseMode.reps,
          sets: 3,
          reps: 8,
          perSide: true,
          restSeconds: 20,
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(sfFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await loader.load();
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'App localized circuit/segment dose wraps at 320px and 2x ${palette.brightness}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final previous = SfColors.palette;
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = previous);
        final library = loadLibrary();
        final routine = toCoachRoutine(_plan, library);
        final expectedDose = routine.items.first.detailDose;
        expect(expectedDose, contains('缓慢进入并保持呼吸顺畅'));
        expect(expectedDose, isNot(contains('3 组')));
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(palette),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PlanCard(
                    plan: _plan,
                    library: library,
                    saved: false,
                    onStart: (_) {},
                    onSave: () {},
                    onOpen: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = find.byType(PlanCard);
        final closedHeight = tester.getSize(card).height;
        await tester.tap(
          find.byKey(const ValueKey('plan-expand-wrapped-dose-integration')),
        );
        await tester.pump();
        for (var frame = 0; frame < 36; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        final first = find.byKey(const ValueKey('plan-row-0'));
        final second = find.byKey(const ValueKey('plan-row-1'));
        final dose = find.descendant(
          of: first,
          matching: find.text(expectedDose),
        );
        expect(dose, findsOneWidget);
        final text = tester.widget<Text>(dose);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(text.softWrap, isNot(false));
        final paragraph = tester.renderObject<RenderParagraph>(dose);
        expect(paragraph.textScaler.scale(14), 28);
        expect(tester.getSize(dose).height, greaterThan(48));
        final rowRect = tester.getRect(first);
        final doseRect = tester.getRect(dose);
        expect(doseRect.left, greaterThanOrEqualTo(rowRect.left));
        expect(doseRect.right, lessThanOrEqualTo(rowRect.right + .01));
        expect(doseRect.bottom, lessThanOrEqualTo(rowRect.bottom + .01));
        expect(
          tester.getRect(second).top,
          greaterThanOrEqualTo(rowRect.bottom),
        );
        final out = Platform.environment['SMARTFIT_COACH_UI_OVERFLOW_SHOTS'];
        if (out != null) {
          Directory(out).createSync(recursive: true);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              Uri.file('$out/app-${palette.brightness.name}.png'),
            ),
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('plan-expand-wrapped-dose-integration')),
        );
        await tester.pump();
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(card).height, closedHeight);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
