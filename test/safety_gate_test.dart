import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/custom_plan_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';

import 'app_flow_test.dart'
    show MemoryStorage, services, tall, showManualChatCard;
import 'package:smartfit/domain/session.dart' show trainerPlan;
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

void main() {
  testWidgets(
    'first launch: the custom form cannot bypass safety with custom plans or templates',
    (tester) async {
      tall(tester);
      final s = services();
      await tester.runAsync(s.chat.start);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      // The form opens from the chat now (「自己选条件」→ @custom); the page
      // still checks the safety talk itself.
      s.chat.command('@custom');
      await tester.pumpAndSettle();
      expect(find.byType(CustomPlanPage), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('generate')));
      await tester.tap(find.byKey(const ValueKey('generate')));
      await tester.pumpAndSettle();
      expect(find.text('先完成安全确认'), findsOneWidget);
      expect(find.byType(PlanPage), findsNothing);
      expect(s.store.lastPlan, isNull);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      final template = find.byKey(const ValueKey('template-office-relax'));
      await tester.ensureVisible(template);
      await tester.tap(template);
      await tester.pumpAndSettle();
      expect(find.text('先完成安全确认'), findsOneWidget);
      expect(find.byType(PlanPage), findsNothing);
      expect(find.byType(PlayerPage), findsNothing);
      expect(s.store.lastPlan, isNull);
    },
  );

  testWidgets(
    'an unfinished recheck blocks old plan cards and saved drawer starts',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await tester.runAsync(s.chat.start);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      final p = await showManualChatCard(s, tester: tester);
      final saved = await s.chat.save(trainerPlan(p));
      await s.chat.showSaved(saved);
      s.chat.startSafetyCheck();
      await tester.pumpAndSettle();
      expect(s.store.safetyBlocked, isFalse);
      expect(s.store.trainingAllowed, isFalse);

      final start = find.byKey(ValueKey('plan-start-${p.id}'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(s.store.lastPlan, isNull);

      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-plans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('saved-start-${saved.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(s.store.lastPlan, isNull);
    },
  );

  testWidgets('plan details also require a completed safety check', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    final result = await s.generator.generate(
      const ScenarioRequest(templateId: 'office-relax'),
    );
    await s.store.beginSafetyCheck();
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(home: PlanPage(plan: result.plan!)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.text('请先在对话里完成安全确认，再开始训练。'), findsOneWidget);
  });

  test(
    'rechecking revokes prior acceptance across a restart and cannot remember a started plan',
    () async {
      final mem = MemoryStorage();
      final store = AppStore(mem);
      await store.acceptSafety(blocked: false);
      final c = services(persistedStore: store).chat;
      expect((await c.start()).ok, isTrue);
      final p = await showManualChatCard(services(persistedStore: store));
      final saved = await c.save(trainerPlan(p));
      await c.showSaved(saved);
      await c.startSafetyCheck();
      expect(await c.started(trainerPlan(p)), isFalse);
      expect(store.lastPlan, isNull);

      final reloaded = AppStore(mem);
      await reloaded.load();
      expect(reloaded.safetyAccepted, isFalse);
      expect(reloaded.trainingAllowed, isFalse);
      final afterRestart = services(persistedStore: reloaded).chat;
      expect((await afterRestart.start()).ok, isTrue);
      expect(afterRestart.inSafetyCheck, isTrue);
      expect(afterRestart.messages.last.text, contains('开始之前'));
      await c.close();
      await afterRestart.close();
    },
  );

  test(
    'a real SDK reply in flight cannot append a card after the host safety recheck',
    () async {
      final fixture = await CoachV2Fixtures.load();
      final app = sdkChatServices(AppStore(MemoryStorage()), fixture);
      await app.store.acceptSafety(blocked: false);
      final entered = Completer<void>();
      final reply = Completer<Object>();
      final client = coach.FakeLlmClient([
        (coach.LlmRequest request) {
          entered.complete();
          return reply.future;
        },
      ], latency: Duration.zero);
      final chat = fakeHostChat(app, client);
      expect((await chat.start()).ok, isTrue);
      final pending = chat.send('在家徒手10分钟拉伸');
      await entered.future;
      expect(chat.typing, isTrue);
      await chat.startSafetyCheck();
      expect(chat.typing, isFalse);
      await chat.choose(chat.messages.last, 0);
      await chat.choose(chat.messages.last, 1);
      expect(app.store.safetyBlocked, isTrue);
      reply.complete(fixture.planTurn().first);
      await pending;
      expect(chat.messages.where((row) => row.isPlan), isEmpty);
      expect(chat.currentPlan, isNull);
      expect(app.store.lastPlan, isNull);
      await chat.close();
      app.store.dispose();
    },
  );
}
