import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/coach_delivery_transition.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/ui/theme/ui_polish_tokens.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services;

class _DeferredEngine implements ProgressChatEngine {
  final pending = Completer<ChatReply>();
  @override
  String get id => 'ui-transition-test';
  @override
  Stream<coach.AgentEvent> get events => const Stream.empty();
  @override
  Future<ChatReply> reply(String text, ChatState state) => pending.future;
}

void main() {
  for (final appearance in ['light', 'dark']) {
    testWidgets('composer fade follows input bounds in $appearance', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await s.store.setAppearance(appearance);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();

      void checkBounds() {
        final input = tester.getRect(
          find.byKey(const ValueKey('chat-composer-face')),
        );
        final fade = tester.getRect(
          find.byKey(const ValueKey('chat-composer-dock')),
        );
        expect(fade.top, closeTo(input.top - 72, .01));
        expect(fade.bottom, closeTo(input.bottom, .01));
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('chat-composer-dock')),
                    )
                    .decoration
                as BoxDecoration;
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.stops, [0, .35, .70, 1]);
        expect(gradient.colors.map((c) => c.a), [0, .18, .72, 1]);
        expect(gradient.colors.last, SfFeaturePanelTokens.background);
        expect(gradient.colors.last, SfDockPolishTokens.background);
        expect(decoration.border, isNull);
        expect(tester.takeException(), isNull);
      }

      checkBounds();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '第一行\n第二行\n第三行\n第四行',
      );
      await tester.pumpAndSettle();
      checkBounds();
      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await tester.pumpAndSettle();
      checkBounds();
    });
  }

  testWidgets('preparation holds 590ms then collapses 300ms before delivery', (
    tester,
  ) async {
    Widget host(bool preparing) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: CoachDeliveryTransition(
            preparing: preparing,
            successful: true,
            child: SizedBox(
              key: ValueKey(preparing ? 'preparing' : 'delivered'),
              width: 240,
              height: preparing ? 120 : 300,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(true));
    final transition = find.byType(CoachDeliveryTransition);
    expect(tester.getSize(transition).height, 120);
    await tester.pumpWidget(host(false));
    await tester.pump(const Duration(milliseconds: 590));
    expect(tester.getSize(transition).height, 120);
    expect(find.byKey(const ValueKey('preparing')), findsOneWidget);
    expect(find.byKey(const ValueKey('delivered')), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      tester.getSize(transition).height,
      closeTo(120 * (1 - Curves.easeOutCubic.transform(.5)), .001),
    );
    expect(find.byKey(const ValueKey('delivered')), findsNothing);
    await tester.pump(const Duration(milliseconds: 149));
    expect(find.byKey(const ValueKey('delivered')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.getSize(transition).height, 300);
    expect(find.byKey(const ValueKey('preparing')), findsNothing);
  });

  testWidgets(
    'chat keeps the preparation entry alive when a plan is delivered',
    (tester) async {
      final s = services();
      await s.store.acceptSafety(blocked: false);
      addTearDown(s.dispose);
      final engine = _DeferredEngine();
      final controller = ChatController(
        engine: engine,
        store: s.store,
        replyDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      final generated = await s.generator.generate(
        const ScenarioRequest(templateId: 'office-relax'),
      );
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = controller.send('在家安排一套拉伸');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final transition = find.byType(CoachDeliveryTransition);
      final originalState = tester.state(transition);
      engine.pending.complete(
        ChatReply(
          messages: [BotMessage('', plan: generated.plan)],
          state: const ChatState(),
        ),
      );
      await request;
      await tester.pump();
      expect(tester.state(transition), same(originalState));
      expect(
        tester
            .widget<CoachTaskBubble>(find.byType(CoachTaskBubble))
            .visualComplete,
        isTrue,
      );
      expect(find.byType(PlanCard), findsNothing);
      await tester.pump(const Duration(milliseconds: 890));
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.byType(CoachTaskBubble), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new conversation never treats its greeting as a prior delivery',
    (tester) async {
      final s = services();
      await s.store.acceptSafety(blocked: false);
      addTearDown(s.dispose);
      final engine = _DeferredEngine();
      final controller = ChatController(
        engine: engine,
        store: s.store,
        replyDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = controller.send('在家拉伸');
      await tester.pump();
      expect(find.byType(CoachDeliveryTransition), findsOneWidget);
      await controller.newConversation();
      await tester.pumpAndSettle();
      expect(find.byType(GreetingBlock), findsOneWidget);
      expect(find.byType(CoachDeliveryTransition), findsNothing);
      engine.pending.complete(
        const ChatReply(messages: [BotMessage('迟到的旧回复')], state: ChatState()),
      );
      await request;
      await tester.pumpAndSettle();
      expect(find.text('迟到的旧回复'), findsNothing);
      expect(find.byType(GreetingBlock), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
