import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme/sf_icons.dart';
import 'package:smartfit/ui/theme/tokens.dart';

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
        expect(find.byIcon(Icons.add_rounded), findsNothing);
        expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
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
    'compact panel animates open and closed, then returns focus to keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      await tester.pumpWidget(SmartFitApp(services: app));
      await tester.pumpAndSettle();
      const transition = ValueKey('chat-panel-transition');
      expect(tester.getSize(find.byKey(transition)).height, 0);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final midOpening = tester.getSize(find.byKey(transition)).height;
      await tester.pumpAndSettle();
      final expanded = tester.getSize(find.byKey(transition)).height;
      expect(midOpening, greaterThan(0));
      expect(midOpening, lessThan(expanded));
      expect(expanded, lessThan(180));
      expect(
        tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
        isFalse,
      );
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final midClosing = tester.getSize(find.byKey(transition)).height;
      expect(midClosing, greaterThan(0));
      expect(midClosing, lessThan(expanded));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(transition)).height, 0);
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
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
    'obsolete keyboard height is ignored without disturbing preferences',
    () async {
      final storage = MemoryStorage();
      storage.data[AppStore.key] = jsonEncode({
        'appearance': 'light',
        'lastKeyboardHeight': 314,
        'mediaWifiOnly': false,
      });
      final store = AppStore(storage);
      await store.load();
      expect(store.appearance, 'light');
      expect(store.mediaWifiOnly, isFalse);
      await store.setAppearance('dark');
      expect(
        (jsonDecode(storage.data[AppStore.key]!) as Map).containsKey(
          'lastKeyboardHeight',
        ),
        isFalse,
      );
      final restored = AppStore(storage);
      await restored.load();
      expect(restored.appearance, 'dark');
      expect(restored.mediaWifiOnly, isFalse);
    },
  );

  testWidgets('panel height follows rows and text scaling with page colour', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final initialPalette = SfColors.palette;
    addTearDown(() => SfColors.palette = initialPalette);
    Future<void> show({required double width, double textScale = 1}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(400, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                child: ChatFeaturePanel(
                  key: _panel,
                  actions: [
                    for (var i = 0; i < 4; i++)
                      ChatPanelAction(
                        key: ValueKey('tool-$i'),
                        label: ['我的计划', '新对话', '动作库', '设置'][i],
                        icon: SfGlyph.grid,
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    SfColors.palette = SfPalette.light;
    await show(width: 400);
    final oneRow = tester.getSize(find.byKey(_panel)).height;
    final first = tester.getTopLeft(find.byKey(const ValueKey('tool-0')));
    final last = tester.getTopLeft(find.byKey(const ValueKey('tool-3')));
    expect(last.dy, first.dy);
    expect(oneRow, lessThan(180));
    ColoredBox surface() => tester.widget<ColoredBox>(
      find
          .descendant(of: find.byKey(_panel), matching: find.byType(ColoredBox))
          .first,
    );
    expect(surface().color, SfPalette.light.skyBottom);

    await show(width: 240);
    final twoRows = tester.getSize(find.byKey(_panel)).height;
    expect(twoRows, greaterThan(oneRow));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('tool-3'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey('tool-0'))).dy),
    );
    SfColors.palette = SfPalette.dark;
    await show(width: 400, textScale: 2);
    expect(tester.getSize(find.byKey(_panel)).height, greaterThan(oneRow));
    expect(surface().color, SfPalette.dark.skyBottom);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('1 套'), findsOneWidget);
    expect(find.textContaining('套 · 点一下'), findsNothing);
    await tester.longPress(find.byKey(ValueKey('saved-expanded-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发到对话'));
    await tester.pumpAndSettle();
    expect(app.chat.messages.last.plan?.id, plan.id);
    await openPlans();
    await tester.longPress(find.byKey(ValueKey('saved-expanded-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-ok')));
    await tester.pumpAndSettle();
    expect(app.store.savedPlans, isEmpty);
  });
}
