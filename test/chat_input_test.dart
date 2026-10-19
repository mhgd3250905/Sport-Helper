import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/theme/app_theme.dart';

void main() {
  const inputKey = ValueKey('chat-input');

  Future<void> showInput(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ChatInputBar(onSend: (_) {}, onPlans: () {}),
        ),
      ),
    ));
  }

  Rect capsuleRect(WidgetTester tester) => tester.getRect(find.descendant(
    of: find.byType(ChatInputBar),
    matching: find.byType(Material),
  ));

  EditableText editor(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  for (final edge in ['top', 'bottom']) {
    testWidgets('tapping the input $edge padding focuses and opens the keyboard', (tester) async {
      await showInput(tester);
      final capsule = capsuleRect(tester);
      expect(capsule.height, 52);
      final x = tester.getCenter(find.byKey(inputKey)).dx;
      await tester.tapAt(Offset(x, edge == 'top' ? capsule.top + 2 : capsule.bottom - 2));
      await tester.pump();

      expect(editor(tester).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  }

  testWidgets('tapping the input reopens a hidden keyboard without losing the draft', (tester) async {
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
    await tester.tapAt(Offset(tester.getCenter(find.byKey(inputKey)).dx, capsule.bottom - 2));
    await tester.pump();

    expect(tester.testTextInput.isVisible, isTrue);
    expect(editor(tester).controller.text, '办公室 10 分钟');
  });

  testWidgets('the input grows with a draft up to four lines', (tester) async {
    await showInput(tester);
    final singleLineHeight = capsuleRect(tester).height;
    expect(singleLineHeight, 52);
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
}
