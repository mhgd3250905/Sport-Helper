import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/ui/chat/chat_composer_dock.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_timeline.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_route.dart';

import 'app_flow_test.dart'
    show services, showManualChatCard, warmTrainingPoster;

Finder _key(String value, {bool offstage = false}) =>
    find.byKey(ValueKey(value), skipOffstage: !offstage);

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name}: IME hide at 150ms cannot move the source list',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final app = services();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await app.dispose();
          SfColors.palette = SfPalette.dark;
        });
        await app.store.acceptSafety(blocked: false);
        app.chat.start();
        final plan = await showManualChatCard(app, template: 'office-relax');
        await tester.pumpWidget(
          AppScope(
            services: app,
            child: MaterialApp(
              theme: buildTheme(palette),
              builder: (_, child) => SfPaletteScope(child: child!),
              home: const ChatHomePage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(_key('chat-input'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 360);
        await tester.pumpAndSettle();
        final source = tester.element(find.byType(ChatHomePage));
        final dock = tester.widget<ChatComposerDock>(
          find.byType(ChatComposerDock),
        );
        expect(dock.focusNode.hasFocus, isTrue);
        final start = _key('plan-start-${plan.id}');
        await tester.ensureVisible(start);
        await tester.pumpAndSettle();
        await warmTrainingPoster(tester, app, plan, sourceContext: source);
        final viewport = _key('chat-messages-boundary', offstage: true);
        final viewportBefore = tester.getRect(viewport);
        final card = find.byType(PlanCard, skipOffstage: false);
        final cardBefore = tester.getRect(card);
        final scroll = tester
            .widget<ChatTimeline>(find.byType(ChatTimeline))
            .controller;
        final offsetBefore = scroll.offset;
        final extentBefore = dock.extent.value;
        expect(extentBefore, greaterThan(360));
        await tester.tap(start);
        final player = find.byType(PlayerPage, skipOffstage: false);
        for (var i = 0; i < 12 && player.evaluate().isEmpty; i++) {
          await tester.pump();
        }
        await tester.pump();
        expect(player, findsOneWidget);
        final control = TrainingRouteScope.maybeOf(tester.element(player))!;
        expect(control.entered, isFalse);
        expect(dock.focusNode.hasFocus, isFalse);
        expect(dock.extent.value, extentBefore);
        expect(tester.getRect(viewport), viewportBefore);
        expect(tester.getRect(card), cardBefore);
        await tester.pump(const Duration(milliseconds: 150));
        tester.view.viewInsets = const FakeViewPadding();
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        await tester.pump();
        expect(control.entered, isFalse);
        expect(dock.extent.value, extentBefore);
        expect(tester.getRect(viewport), viewportBefore);
        expect(tester.getRect(card), cardBefore);
        expect(scroll.offset, offsetBefore);
        expect(find.byType(ExerciseVideo, skipOffstage: false), findsNothing);
        await tester.pump(const Duration(milliseconds: 149));
        expect(dock.extent.value, extentBefore);
        expect(tester.getRect(viewport), viewportBefore);
        expect(scroll.offset, offsetBefore);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        expect(control.entered, isTrue);
        expect(dock.extent.value, lessThan(extentBefore - 300));
        final normalExtent = dock.extent.value;
        await tester.tap(_key('close'));
        await tester.pumpAndSettle();
        await tester.tap(_key('close-confirm'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerPage), findsNothing);
        expect(tester.element(find.byType(ChatHomePage)), same(source));
        expect(dock.extent.value, normalExtent);
        expect(scroll.offset, offsetBefore);
        // The guard must not suppress ordinary keyboard behavior after return.
        await tester.tap(_key('chat-input'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(dock.focusNode.hasFocus, isTrue);
        expect(dock.extent.value, greaterThan(normalExtent + 200));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
