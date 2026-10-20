import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/custom_plan_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';

import 'app_flow_test.dart' show MemoryStorage, services, tall;

void main() {
  testWidgets(
    'first launch: the custom form cannot bypass safety with custom plans or templates',
    (tester) async {
      tall(tester);
      final s = services();
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
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await s.chat.send('在办公室午休 10 分钟，肩颈很僵');
      final p = s.chat.currentPlan!;
      final saved = await s.chat.save(p);
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

      await tester.tap(find.byKey(const ValueKey('open-plans')));
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
      final s = services();
      final store = AppStore(mem);
      await store.acceptSafety(blocked: false);
      final c = ChatController(
        engine: RuleChatEngine(lib: s.library, templates: s.templates),
        store: store,
        replyDelay: Duration.zero,
      )..start();
      await c.send('在办公室午休 10 分钟，肩颈很僵');
      final p = c.currentPlan!;
      c.startSafetyCheck();
      expect(await c.started(p), isFalse);
      expect(store.lastPlan, isNull);

      final reloaded = AppStore(mem);
      await reloaded.load();
      expect(reloaded.safetyAccepted, isFalse);
      expect(reloaded.trainingAllowed, isFalse);
      final afterRestart = ChatController(
        engine: c.engine,
        store: reloaded,
        replyDelay: Duration.zero,
      )..start();
      expect(afterRestart.inSafetyCheck, isTrue);
      expect(afterRestart.messages.last.text, contains('开始之前'));
      c.dispose();
      afterRestart.dispose();
    },
  );

  test(
    'a reply already in flight cannot append a plan after a safety recheck',
    () async {
      final s = services();
      await s.store.acceptSafety(blocked: false);
      final generated = await s.generator.generate(
        const ScenarioRequest(templateId: 'office-relax'),
      );
      final engine = _DeferredEngine();
      final c = ChatController(
        engine: engine,
        store: s.store,
        replyDelay: Duration.zero,
      )..start();
      final pending = c.send('在办公室午休 10 分钟，肩颈很僵');
      expect(c.typing, isTrue);

      c.startSafetyCheck();
      expect(c.typing, isFalse);
      await c.choose(c.messages.last, 0); // acknowledge
      await c.choose(c.messages.last, 1); // first safety question: 是
      expect(s.store.safetyBlocked, isTrue);
      engine.result.complete(
        ChatReply(
          messages: [BotMessage('', plan: generated.plan)],
          state: ChatState(plan: generated.plan),
        ),
      );
      await pending;
      expect(c.messages.where((m) => m.isPlan), isEmpty);
      expect(c.currentPlan, isNull);
      c.dispose();
    },
  );
}

class _DeferredEngine implements ChatEngine {
  final result = Completer<ChatReply>();
  @override
  String get id => 'deferred-test';
  @override
  Future<ChatReply> reply(String text, ChatState state) => result.future;
}
