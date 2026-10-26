import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme.dart';

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  testWidgets('segmented thumb stays flat and still activates choices', (
    tester,
  ) async {
    var selected = 'first';
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: StatefulBuilder(
          builder: (context, update) => Scaffold(
            body: SfSegmented<String>(
              items: const [('first', '第一个'), ('second', '第二个')],
              value: selected,
              keyPrefix: 'choice-',
              onChanged: (value) => update(() => selected = value),
            ),
          ),
        ),
      ),
    );
    final thumb = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('segment-thumb')),
    );
    final decoration = thumb.decoration as ShapeDecoration;
    expect(decoration.color!.a, 1);
    expect(decoration.gradient, isNull);
    expect(decoration.shadows, isNull);
    await tester.tap(find.byKey(const ValueKey('choice-second')));
    await tester.pumpAndSettle();
    expect(selected, 'second');
  });

  testWidgets('primary button retains activation and reduced-motion presses', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: SfPrimaryButton(label: '完成', onPressed: () => taps++),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SfPrimaryButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final scale = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(SfPrimaryButton),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(scale.scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
