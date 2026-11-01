import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/training_route.dart';

import 'app_flow_test.dart'
    show services, tall, showManualChatCard, warmTrainingPoster;

void main() {
  testWidgets('appearance changes keep a pushed route and conversation state', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await showManualChatCard(s, tester: tester);
    final plan = s.chat.currentPlan!;
    await s.chat.save(plan);
    final messages = s.chat.messages.length;
    await tester.runAsync(s.chat.start);
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
      await showManualChatCard(s, template: 'office-relax', tester: tester);
      final plan = s.chat.currentPlan!;
      await tester.runAsync(s.chat.start);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      final chatElement = tester.element(find.byType(ChatHomePage));
      await tester.tap(find.byKey(ValueKey('plan-open-${plan.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(CoachChatPlanDetailsPage), findsOneWidget);
      final detailElement = tester.element(
        find.byType(CoachChatPlanDetailsPage),
      );
      await warmTrainingPoster(tester, s, plan, sourceContext: detailElement);
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final retiringDetails = find.descendant(
        of: find.byType(CoachChatPlanDetailsPage, skipOffstage: false),
        matching: find.byType(CachedExerciseMedia, skipOffstage: false),
        skipOffstage: false,
      );
      expect(retiringDetails, findsWidgets);
      expect(
        tester
            .widgetList<CachedExerciseMedia>(retiringDetails)
            .every((v) => v.paused || !v.playing),
        isTrue,
        reason: 'The source preview stops before the trainer starts',
      );
      await tester.pump();
      expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(
        TrainingRouteScope.maybeOf(
          tester.element(find.byType(PlayerPage)),
        )!.entered,
        isTrue,
      );
      expect(s.store.lastPlan?.id, plan.id);
      final route =
          ModalRoute.of(tester.element(find.byType(PlayerPage)))!
              as TrainingRoute;
      expect(route.transitionDuration, const Duration(milliseconds: 300));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 280),
      );
      final summaries = s.chat.messages
          .where((message) => message.text.contains('这次先到这儿'))
          .length;
      await tester.tap(find.byKey(const ValueKey('close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束'));
      await tester.pump();
      await tester.pump();
      expect(s.store.history, hasLength(1));
      await tester.pump(const Duration(milliseconds: 279));
      expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
      expect(
        s.chat.messages
            .where((message) => message.text.contains('这次先到这儿'))
            .length,
        summaries,
        reason: 'A saved receipt is not presented before the slide finishes.',
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PlayerPage), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(CoachChatPlanDetailsPage), findsOneWidget);
      expect(
        tester.element(find.byType(CoachChatPlanDetailsPage)),
        same(detailElement),
      );
      final restoredPreview = tester.widgetList<CachedExerciseMedia>(
        find.byType(CachedExerciseMedia),
      );
      expect(restoredPreview, isNotEmpty);
      expect(restoredPreview.every((media) => !media.paused), isTrue);
      expect(s.store.history, hasLength(1));
      expect(s.chat.messages.last.text, contains('这次先到这儿'));
      Navigator.of(tester.element(find.byType(CoachChatPlanDetailsPage))).pop();
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
