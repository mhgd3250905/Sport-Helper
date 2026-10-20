// The aesthetic rules of docs/design-audit-2026-10-19.md written as
// assertions (after HipLab's tactile budget test): only two raised parts in
// the whole app, flat primary buttons, and no press scaling under reduced
// motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show services, tall;

Iterable<SfTactile> _tactiles(WidgetTester t) => t.widgetList<SfTactile>(find.byType(SfTactile));

String? _keyOf(Widget w) => (w.key as ValueKey<String>?)?.value;

void main() {
  testWidgets('chat with a plan card: the 开始 disc is the one raised accent', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await s.chat.send('在家 15 分钟练核心，徒手');
    await tester.pumpAndSettle();

    final raised = _tactiles(tester).toList();
    expect(raised.where((w) => _keyOf(w) == 'start-disc'), hasLength(1));
    expect(raised.every((w) => _keyOf(w) == 'start-disc' || _keyOf(w) == 'segment-thumb'), isTrue);
  });

  testWidgets('settings: the segmented thumb is the only raised part', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: buildTheme(), home: const AboutPage())));
    await tester.pumpAndSettle();
    final raised = _tactiles(tester).toList();
    expect(raised, hasLength(1));
    expect(_keyOf(raised.single), 'segment-thumb');
  });

  testWidgets('primary buttons are flat: no tactile face, no shadow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Center(child: SfPrimaryButton(label: '完成', onPressed: () {}))),
    ));
    final button = find.byType(SfPrimaryButton);
    expect(find.descendant(of: button, matching: find.byType(SfTactile)), findsNothing);
    for (final box in tester.widgetList<DecoratedBox>(find.descendant(of: button, matching: find.byType(DecoratedBox)))) {
      final d = box.decoration;
      if (d is BoxDecoration) expect(d.boxShadow, isNull);
      if (d is ShapeDecoration) expect(d.shadows, isNull);
    }
  });

  testWidgets('reduced motion: presses do not scale', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Center(child: SfPrimaryButton(label: '完成', onPressed: () {}))),
      ),
    ));
    final g = await tester.startGesture(tester.getCenter(find.byType(SfPrimaryButton)));
    await tester.pump(const Duration(milliseconds: 150));
    final scale = tester.widget<AnimatedScale>(find.descendant(of: find.byType(SfPrimaryButton), matching: find.byType(AnimatedScale)));
    expect(scale.scale, 1);
    await g.up();
    await tester.pumpAndSettle();
  });
}
