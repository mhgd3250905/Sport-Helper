import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme.dart';

import 'support.dart';

const _plan = TrainingPlan(
  id: 'accessible-set',
  source: 'template',
  title: '办公室肩颈放松与全身舒展训练',
  summary: '',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 2,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 20,
          perSide: false,
          restSeconds: 15,
        ),
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.reps,
          sets: 1,
          reps: 8,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

const _toggleKey = ValueKey('plan-expand-accessible-set');
const _openKey = ValueKey('plan-open-accessible-set');
const _saveKey = ValueKey('plan-save-accessible-set');
const _startKey = ValueKey('plan-start-accessible-set');

class _Actions {
  int opens = 0;
  int saves = 0;
  int starts = 0;

  List<int> get counts => [opens, saves, starts];
}

Future<_Actions> _host(
  WidgetTester tester, {
  double scale = 1,
  SfPalette palette = SfPalette.light,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(320, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousPalette = SfColors.palette;
  SfColors.palette = palette;
  addTearDown(() => SfColors.palette = previousPalette);
  final actions = _Actions();
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(palette),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PlanCard(
              plan: _plan,
              library: loadLibrary(),
              saved: false,
              onStart: () => actions.starts++,
              onSave: () => actions.saves++,
              onOpen: () => actions.opens++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

FocusNode _focusOf(WidgetTester tester, Finder control) {
  final gesture = find
      .descendant(
        of: control,
        matching: find.byType(GestureDetector, skipOffstage: false),
        skipOffstage: false,
      )
      .first;
  return Focus.of(tester.element(gesture));
}

Future<void> _focusWithTab(
  WidgetTester tester,
  FocusNode target, {
  int maximumStops = 8,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  for (var i = 0; i < maximumStops; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (target.hasPrimaryFocus) return;
  }
  fail('The visible control was not reachable with Tab.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader(sfFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
    await font.load();
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    for (final reduced in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('set header and actions fit 320 px at scale $scale '
            '(${palette.isDark ? 'dark' : 'light'}, reduced: $reduced)', (
          tester,
        ) async {
          final actions = await _host(
            tester,
            scale: scale,
            palette: palette,
            reduced: reduced,
          );
          await tester.tap(find.byKey(_toggleKey));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          final header = find.byKey(const ValueKey('plan-header'));
          final title = find.descendant(
            of: header,
            matching: find.text(_plan.title),
          );
          final meta = find.descendant(
            of: header,
            matching: find.textContaining('2 个动作'),
          );
          final toggleRect = tester.getRect(find.byKey(_toggleKey));
          final cardRect = tester.getRect(find.byType(PlanCard));
          for (final text in [title, meta]) {
            final textRect = tester.getRect(text);
            expect(textRect.width, greaterThan(0));
            expect(textRect.right, lessThanOrEqualTo(toggleRect.left));
            expect(textRect.left, greaterThanOrEqualTo(cardRect.left));
            expect(textRect.top, greaterThanOrEqualTo(cardRect.top));
          }
          expect(toggleRect.right, lessThanOrEqualTo(cardRect.right));
          expect(toggleRect.width, greaterThanOrEqualTo(44));
          expect(toggleRect.height, greaterThanOrEqualTo(44));

          await tester.tap(find.byKey(_openKey));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_startKey));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_saveKey));
          await tester.pumpAndSettle();
          expect(actions.counts, [1, 1, 1]);

          await tester.tap(find.byKey(_toggleKey));
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(PlanCard)).height,
            PlanCard.setHeight,
          );
          await tester.tap(find.byKey(_openKey));
          await tester.pumpAndSettle();
          expect(actions.opens, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final reduced in [false, true]) {
    testWidgets('Tab and Enter use visible set controls (reduced: $reduced)', (
      tester,
    ) async {
      final actions = await _host(tester, reduced: reduced);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      final controls = {
        _openKey: _focusOf(tester, find.byKey(_openKey)),
        _saveKey: _focusOf(tester, find.byKey(_saveKey)),
        _startKey: _focusOf(tester, find.byKey(_startKey)),
        _toggleKey: _focusOf(tester, find.byKey(_toggleKey)),
      };
      final allDetails = find.byKey(_openKey, skipOffstage: false);
      final detailsNodes = [
        for (final element in allDetails.evaluate())
          _focusOf(
            tester,
            find.byElementPredicate(
              (candidate) => candidate == element,
              skipOffstage: false,
            ),
          ),
      ];
      final hiddenDetails = detailsNodes.where(
        (node) => node != controls[_openKey],
      );
      for (final node in hiddenDetails) {
        expect(node.canRequestFocus, isFalse);
      }

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final visited = <Key>{};
      for (var stop = 0; stop < controls.length * 2; stop++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final node in hiddenDetails) {
          expect(node.hasPrimaryFocus, isFalse);
        }
        final focused = controls.entries.where(
          (entry) => entry.value.hasPrimaryFocus,
        );
        expect(focused, hasLength(1));
        final key = focused.single.key;
        visited.add(key);
        if (key == _toggleKey) continue;

        final before = actions.counts;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final expected = [...before];
        expected[key == _openKey
            ? 0
            : key == _saveKey
            ? 1
            : 2]++;
        expect(actions.counts, expected);
      }
      expect(visited, controls.keys.toSet());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('detail focus recovers after folding and interrupted reversal '
        '(reduced: $reduced)', (tester) async {
      final actions = await _host(tester, reduced: reduced);
      final compactFocus = _focusOf(tester, find.byKey(_openKey));

      Future<void> activateCompact() async {
        expect(compactFocus.canRequestFocus, isTrue);
        await _focusWithTab(tester, compactFocus);
        final before = actions.opens;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(actions.opens, before + 1);
      }

      await activateCompact();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(compactFocus.canRequestFocus, isFalse);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      await activateCompact();

      // Reverse an unfolding card before the end, restoring compact focus.
      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();
      await tester.pump(Duration(milliseconds: reduced ? 75 : 150));
      expect(compactFocus.canRequestFocus, isFalse);
      expect(compactFocus.hasFocus, isFalse);
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      await activateCompact();

      // Reverse a folding card, restoring the visible expanded header.
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggleKey));
      await tester.pump();
      await tester.pump(Duration(milliseconds: reduced ? 75 : 150));
      await tester.tap(find.byKey(_toggleKey));
      await tester.pumpAndSettle();
      expect(compactFocus.canRequestFocus, isFalse);
      final headerFocus = _focusOf(tester, find.byKey(_openKey));
      expect(headerFocus.canRequestFocus, isTrue);
      await _focusWithTab(tester, headerFocus);
      final before = actions.opens;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(actions.opens, before + 1);
      expect(compactFocus.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
