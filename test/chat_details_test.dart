import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
  testWidgets('appearance changes keep a pushed route and conversation state', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await s.chat.send('在家 15 分钟练核心，徒手');
    final plan = s.chat.currentPlan!;
    await s.chat.save(plan);
    final messages = s.chat.messages.length;
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-plans')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-about')));
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

  testWidgets('starting from chat details returns to chat and records recall and summary', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await s.chat.send('在办公室午休 10 分钟，肩颈很僵');
    final plan = s.chat.currentPlan!;
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-open-${plan.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(PlanPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(s.store.lastPlan?.id, plan.id);
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanPage), findsNothing);
    expect(find.byType(ChatHomePage), findsOneWidget);
    expect(s.store.history, hasLength(1));
    expect(s.chat.messages.last.text, contains('这次先到这儿'));
    await tester.pumpWidget(const SizedBox());
  });
}
