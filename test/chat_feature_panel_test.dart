import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/library_page.dart';

import 'app_flow_test.dart' show MemoryStorage, services, tall;

const _toggle = ValueKey('chat-panel-toggle');
const _panel = ValueKey('chat-feature-panel');
const _input = ValueKey('chat-input');

void main() {
  for (final appearance in ['light', 'dark']) {
    testWidgets(
      '$appearance panel toggles, dismisses and opens each destination',
      (tester) async {
        tall(tester);
        final app = services();
        app.store.appearance = appearance;
        await app.store.acceptSafety(blocked: false);
        await tester.pumpWidget(SmartFitApp(services: app));
        await tester.pumpAndSettle();
        expect(find.byType(Drawer), findsNothing);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(find.byKey(_panel), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
        for (final key in [
          'panel-plans',
          'chat-new-conversation',
          'panel-library',
          'panel-settings',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget);
        }
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        expect(find.byKey(_panel), findsNothing);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(_panel), findsNothing);
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(30, 100));
        await tester.pumpAndSettle();
        expect(find.byKey(_panel), findsNothing);

        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('panel-library')));
        await tester.pumpAndSettle();
        expect(find.byType(LibraryPage), findsOneWidget);
        await tester.tap(find.byTooltip('返回').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('panel-settings')));
        await tester.pumpAndSettle();
        expect(find.byType(AboutPage), findsOneWidget);
        await tester.tap(find.byTooltip('返回').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_toggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-new-conversation')));
        await tester.pumpAndSettle();
        expect(find.byKey(_panel), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'keyboard height is persisted and panel swaps without moving the input',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      await tester.pumpWidget(SmartFitApp(services: app));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_input));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(app.store.lastKeyboardHeight, 320);
      final before = tester.getBottomLeft(find.byKey(_input)).dy;
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      final after = tester.getBottomLeft(find.byKey(_input)).dy;
      expect(after, closeTo(before, 2));
      expect(
        tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
        isFalse,
      );
      await tester.tap(find.byKey(_input));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
        isTrue,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(find.byKey(_panel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'keyboard height survives store reload without affecting saved preferences',
    () async {
      final storage = MemoryStorage();
      final store = AppStore(storage);
      await store.setAppearance('light');
      await store.setLastKeyboardHeight(314);
      final restored = AppStore(storage);
      await restored.load();
      expect(restored.lastKeyboardHeight, 314);
      expect(restored.appearance, 'light');
    },
  );

  testWidgets('saved plans page can show and delete a saved plan', (
    tester,
  ) async {
    tall(tester);
    final app = services();
    await app.store.acceptSafety(blocked: false);
    final plan = (await app.generator.generate(
      const ScenarioRequest(templateId: 'office-relax'),
    )).plan!;
    final saved = await app.store.savePlan(plan);
    await tester.pumpWidget(SmartFitApp(services: app));
    await tester.pumpAndSettle();
    Future<void> openPlans() async {
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-plans')));
      await tester.pumpAndSettle();
      expect(find.byType(SavedPlansPage), findsOneWidget);
    }

    await openPlans();
    await tester.tap(find.byKey(ValueKey('saved-${saved.id}')));
    await tester.pumpAndSettle();
    expect(app.chat.messages.last.plan?.id, plan.id);
    await openPlans();
    await tester.tap(find.byKey(ValueKey('saved-menu-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-ok')));
    await tester.pumpAndSettle();
    expect(app.store.savedPlans, isEmpty);
  });
}
