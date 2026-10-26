import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/library_page.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
  testWidgets('route return leaves composer unfocused until an explicit tap', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('chat-input'));
    await tester.tap(input);
    await tester.pump();
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.byKey(const ValueKey('open-plans')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-library')));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(input);
    await tester.pump();
    expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'foreground return hides keyboard; explicit compose still focuses',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('chat-input'));
      await tester.tap(input);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const ValueKey('open-plans')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('去排一套'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
