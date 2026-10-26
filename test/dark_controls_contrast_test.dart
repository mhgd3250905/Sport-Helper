// Solid controls retain readable labels and their existing interaction bounds.
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

  test('labels meet text contrast on each opaque surface in both themes', () {
    for (final p in [SfPalette.dark, SfPalette.light]) {
      for (final face in [p.surfaceLow, p.surface, p.surfaceHigh]) {
        expect(face.a, 1);
        expect(contrast(p.text, face), greaterThanOrEqualTo(4.5));
      }
    }
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

  testWidgets('dark: idle input and suggestions keep opaque surface fills', (
    tester,
  ) async {
    SfColors.palette = SfPalette.dark;
    await pumpControls(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ChatInputBar)).height,
      greaterThanOrEqualTo(40),
    );
    expect(
      tester.getSize(find.byType(SuggestionStrip)).height,
      greaterThanOrEqualTo(40),
    );
  });

  testWidgets('light: input stays usable with a solid fill', (tester) async {
    SfColors.palette = SfPalette.light;
    await pumpControls(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
    expect(
      tester.getSize(find.byType(ChatInputBar)).height,
      greaterThanOrEqualTo(40),
    );
  });
}
