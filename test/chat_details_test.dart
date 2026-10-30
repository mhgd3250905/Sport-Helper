import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/guide_media.dart';
import 'package:smartfit/ui/training_route.dart';

import 'app_flow_test.dart' show services, tall, showManualChatCard;

void main() {
  testWidgets('appearance changes keep a pushed route and conversation state', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await showManualChatCard(s);
    final plan = s.chat.currentPlan!;
    await s.chat.save(plan);
    final messages = s.chat.messages.length;
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel-settings')));
    await tester.pumpAndSettle();
    for (final mode in ['light', 'system', 'dark']) {
      await tester.tap(find.byKey(ValueKey('appearance-$mode')));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(s.store.appearance, mode);
      expect(s.chat.messages.length, messages);
      expect(s.chat.currentPlan?.id, plan.id);
      expect(s.store.savedPlans.single.plan.id, plan.id);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'starting from chat details restores its source and records one recall and summary',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      s.chat.start();
      await showManualChatCard(s, template: 'office-relax');
      final plan = s.chat.currentPlan!;
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      final chatElement = tester.element(find.byType(ChatHomePage));
      await tester.tap(find.byKey(ValueKey('plan-open-${plan.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(PlanPage), findsOneWidget);
      final detailElement = tester.element(find.byType(PlanPage));
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final retiringDetails = find.descendant(
        of: find.byType(PlanPage, skipOffstage: false),
        matching: find.byType(GuideMedia, skipOffstage: false),
        skipOffstage: false,
      );
      expect(retiringDetails, findsWidgets);
      expect(
        tester
            .widgetList<GuideMedia>(retiringDetails)
            .every((v) => v.coordinator.activeSlot == null),
        isTrue,
        reason: 'The source preview stops before the trainer starts',
      );
      await tester.pump();
      expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 560));
      await tester.pump();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(s.store.lastPlan?.id, plan.id);
      final route =
          ModalRoute.of(tester.element(find.byType(PlayerPage)))!
              as TrainingRoute;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      final summaries = s.chat.messages
          .where((message) => message.text.contains('这次先到这儿'))
          .length;
      await tester.tap(find.byKey(const ValueKey('close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束'));
      await tester.pump();
      await tester.pump();
      expect(s.store.history, hasLength(1));
      await tester.pump(const Duration(milliseconds: 249));
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(
        s.chat.messages
            .where((message) => message.text.contains('这次先到这儿'))
            .length,
        summaries,
        reason: 'Saving can complete while real controls are still retiring.',
      );
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(find.byType(PlayerPage), findsNothing);
      expect(
        find.byKey(const ValueKey('training-return-poster')),
        findsOneWidget,
      );
      expect(
        s.chat.messages
            .where((message) => message.text.contains('这次先到这儿'))
            .length,
        summaries,
        reason:
            'The zero-duration pop does not insert the chat receipt before the independent shrink finishes.',
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanPage), findsOneWidget);
      expect(tester.element(find.byType(PlanPage)), same(detailElement));
      final restoredPreview = tester.widgetList<GuideMedia>(
        find.byType(GuideMedia),
      );
      expect(restoredPreview, isNotEmpty);
      expect(restoredPreview.every((media) => media.enabled), isTrue);
      expect(s.store.history, hasLength(1));
      expect(s.chat.messages.last.text, contains('这次先到这儿'));
      Navigator.of(tester.element(find.byType(PlanPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChatHomePage), findsOneWidget);
      expect(tester.element(find.byType(ChatHomePage)), same(chatElement));
      expect(s.store.history, hasLength(1));
      expect(s.chat.messages.last.text, contains('这次先到这儿'));
      expect(
        s.chat.messages
            .where((message) => message.text.contains('这次先到这儿'))
            .length,
        summaries + 1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
