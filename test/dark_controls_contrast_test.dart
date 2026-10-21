// Round 5 (user feedback): in dark mode an idle tappable control must read
// as a button. WCAG 1.4.11: the control boundary (rim) ≥ 3:1 against every
// background it sits on; labels on the control fill ≥ 4.5:1. Light mode
// keeps its own look (no SfControlFace paint).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/theme.dart';

double contrast(Color fg, Color bg) {
  final f = Color.alphaBlend(fg, bg);
  final a = f.computeLuminance(), b = bg.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  const p = SfPalette.dark;
  // Where idle controls sit in dark: the sky (top/bottom), the sky under
  // the glass field's 4.5 % lift, the clear glass card (2 % white), and
  // the assistant bubble (option pills).
  final backgrounds = <String, Color>{
    'skyTop': p.skyTop,
    'skyBottom': p.skyBottom,
    'sky+lift': Color.alphaBlend(const Color(0x0BFFFFFF), p.skyTop),
    'glass card': Color.alphaBlend(const Color(0x05FFFFFF), p.skyTop),
    'assistant bubble': p.assistantBubble,
  };

  test('dark control rim ≥ 3:1 against every background (WCAG 1.4.11)', () {
    for (final MapEntry(:key, :value) in backgrounds.entries) {
      expect(contrast(SfControlInk.rim, value), greaterThanOrEqualTo(3), reason: '$key rim');
      expect(contrast(SfControlInk.pressedRim, value), greaterThanOrEqualTo(3), reason: '$key pressed rim');
    }
  });

  test('dark control labels ≥ 4.5:1 on the control fill', () {
    for (final MapEntry(:key, :value) in backgrounds.entries) {
      for (final fill in [SfControlInk.fillTop, SfControlInk.fill, SfControlInk.pressedTop, SfControlInk.pressedFill]) {
        final face = Color.alphaBlend(fill, value);
        expect(contrast(p.text, face), greaterThanOrEqualTo(4.5), reason: '$key text');
        expect(contrast(p.text.withValues(alpha: .9), face), greaterThanOrEqualTo(4.5), reason: '$key text .9');
      }
    }
  });

  test('pressed is visibly brighter than idle', () {
    expect(SfControlInk.pressedFill.a, greaterThan(SfControlInk.fill.a));
    expect(SfControlInk.pressedRim.a, greaterThan(SfControlInk.rim.a));
  });

  Future<void> pumpControls(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            OptionPill(label: '20 分钟', onTap: () {}),
            SuggestionStrip(items: const ['换个动作'], onTap: (_) {}),
            ChatInputBar(onSend: (_) {}, onPlans: () {}),
          ],
        ),
      ),
    ),
  );

  testWidgets('dark: idle chips, options and the plans button get a control face ≥ 40 tall', (tester) async {
    SfColors.palette = SfPalette.dark;
    await pumpControls(tester);
    await tester.pumpAndSettle();
    final faces = find.byKey(const ValueKey('sf-control-face'));
    expect(faces, findsNWidgets(3));
    for (final e in faces.evaluate()) {
      expect((e.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(SfControlInk.minHeight));
    }
  });

  testWidgets('light: no control face (light unchanged)', (tester) async {
    SfColors.palette = SfPalette.light;
    await pumpControls(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sf-control-face')), findsNothing);
  });
}
