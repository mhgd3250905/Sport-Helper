import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/sf_icons.dart';
import 'package:smartfit/ui/theme/tokens.dart';

void main() {
  const inputKey = ValueKey('chat-input');

  Future<void> showInput(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(onSend: (_) {}, onPlans: () {}),
          ),
        ),
      ),
    );
  }

  Rect capsuleRect(WidgetTester tester) => tester.getRect(
    find.descendant(
      of: find.byType(ChatInputBar),
      matching: find.byType(Material),
    ),
  );

  EditableText editor(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  for (final edge in ['top', 'bottom']) {
    testWidgets(
      'tapping the input $edge padding focuses and opens the keyboard',
      (tester) async {
        await showInput(tester);
        final capsule = capsuleRect(tester);
        expect(capsule.height, SfComposerTokens.inputHeight);
        final x = tester.getCenter(find.byKey(inputKey)).dx;
        await tester.tapAt(
          Offset(x, edge == 'top' ? capsule.top + 2 : capsule.bottom - 2),
        );
        await tester.pump();

        expect(editor(tester).focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      },
    );
  }

  testWidgets(
    'tapping the input reopens a hidden keyboard without losing the draft',
    (tester) async {
      await showInput(tester);
      await tester.tap(find.byKey(inputKey));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('办公室 10 分钟');
      await tester.pump();

      // Android Back can dismiss the IME while the editor keeps its focus.
      tester.testTextInput.hide();
      expect(editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isFalse);
      final capsule = capsuleRect(tester);
      await tester.tapAt(
        Offset(tester.getCenter(find.byKey(inputKey)).dx, capsule.bottom - 2),
      );
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);
      expect(editor(tester).controller.text, '办公室 10 分钟');
    },
  );

  testWidgets('the input grows with a draft up to four lines', (tester) async {
    await showInput(tester);
    final singleLineHeight = capsuleRect(tester).height;
    expect(singleLineHeight, SfComposerTokens.inputHeight);
    await tester.tap(find.byKey(inputKey));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.enterText('第一行\n第二行');
    await tester.pump();
    final twoLineHeight = capsuleRect(tester).height;
    expect(twoLineHeight, greaterThan(singleLineHeight));

    tester.testTextInput.enterText('第一行\n第二行\n第三行\n第四行');
    await tester.pump();
    final fourLineHeight = capsuleRect(tester).height;
    expect(fourLineHeight, greaterThan(twoLineHeight));

    tester.testTextInput.enterText('第一行\n第二行\n第三行\n第四行\n第五行\n第六行');
    await tester.pump();
    expect(capsuleRect(tester).height, fourLineHeight);
    expect(editor(tester).controller.text, contains('第六行'));
    expect(tester.takeException(), isNull);
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name}: composer aligns content and keeps full action targets',
      (tester) async {
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = SfPalette.dark);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final sent = <String>[];
        var plans = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(palette),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(onSend: sent.add, onPlans: () => plans++),
              ),
            ),
          ),
        );
        final leading = find.byKey(const ValueKey('chat-panel-toggle'));
        final sending = find.byKey(const ValueKey('chat-send'));
        for (final action in [leading, sending]) {
          final size = tester.getSize(action);
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
        expect(
          find.descendant(of: leading, matching: find.byType(Container)),
          findsNothing,
        );
        final menuIcon = find.byIcon(Icons.grid_view_rounded);
        final sendIcon = find.byWidgetPredicate(
          (widget) => widget is SfIcon && widget.glyph == SfGlyph.arrowUp,
        );
        expect(
          tester.getCenter(menuIcon).dy,
          closeTo(tester.getCenter(sendIcon).dy, .1),
        );
        expect(
          tester.getCenter(find.byType(EditableText)).dy,
          closeTo(tester.getCenter(sendIcon).dy, .1),
        );
        await tester.tap(leading);
        expect(plans, 1);
        await tester.enterText(find.byKey(inputKey), '  办公室 10 分钟  ');
        await tester.pump();
        final rect = tester.getRect(sending);
        await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
        await tester.pumpAndSettle();
        expect(sent, ['办公室 10 分钟']);
        expect(editor(tester).controller.text, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
