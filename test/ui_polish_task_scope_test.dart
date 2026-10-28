import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services, tall;
import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  testWidgets(
    'new request preparation cannot display the previous completed SDK task',
    (tester) async {
      tall(tester);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      final client = coach.FakeLlmClient(
        fixture.planTurn(),
        latency: Duration.zero,
      );
      final ai = AiChatEngine(
        local: const AppChatActions(),
        catalog: fixture.catalog,
        profile: fixture.profile,
        client: client,
        enableUserMemory: false,
      );
      final preparation = Completer<void>();
      var holdPreparation = false;
      var preparationCount = 0;
      final chat = ChatController(
        engine: ai,
        store: app.store,
        replyDelay: Duration.zero,
        prepareReply: () {
          preparationCount++;
          return holdPreparation ? preparation.future : Future<void>.value();
        },
      )..start();
      addTearDown(() {
        chat.cancelRequest();
        if (!preparation.isCompleted) preparation.complete();
        chat.dispose();
        ai.dispose();
        app.store.dispose();
      });
      await tester.runAsync(() => chat.send('在家徒手10分钟做拉伸'));
      expect(ai.lastResult?.status, coach.TurnStatus.ok);
      expect(ai.lastResult?.plan, isNotNull);
      expect(client.requests, hasLength(2));
      final completed = ai.agent.sessionState;
      expect(
        completed.task!.nodes.singleWhere((node) => node.id == 'output').status,
        'done',
      );
      expect(completed.params['scene']!.value, 'home');
      expect(completed.params['goal']!.value, ['purpose.stretch']);
      expect(completed.picks, isNotEmpty);

      holdPreparation = true;
      final pending = chat.send('再排一套');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: chat,
              builder: (context, _) => chat.typing
                  ? CoachTaskBubble(
                      task: chat.activeTask,
                      sessionState: chat.activeSessionState,
                      library: fixture.library,
                      waiting: true,
                      onCancel: chat.cancelRequest,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(chat.typing, isTrue);
      expect(preparationCount, 2);
      expect(preparation.isCompleted, isFalse);
      expect(client.requests, hasLength(2));
      expect(ai.agent.sessionState, same(completed));
      expect(ai.agent.sessionState.userTurns, hasLength(1));
      expect(chat.activeTask, isNull);
      expect(chat.activeSessionState, isNull);
      final bubble = tester.widget<CoachTaskBubble>(
        find.byType(CoachTaskBubble),
      );
      expect(bubble.task, isNull);
      expect(bubble.sessionState, isNull);
      expect(find.text('正在想怎么练…'), findsOneWidget);
      expect(find.text('读懂你的需求'), findsOneWidget);
      expect(find.text('马上就好'), findsNothing);
      expect(find.text('正在为你准备 · 居家拉伸'), findsNothing);
      for (var segment = 1; segment < 4; segment++) {
        expect(
          tester
              .widget<FractionallySizedBox>(
                find.byKey(ValueKey('generation-progress-fill-$segment')),
              )
              .widthFactor,
          0,
        );
      }

      chat.cancelRequest();
      preparation.complete();
      await pending;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(chat.typing, isFalse);
      expect(find.byType(CoachTaskBubble), findsNothing);
      expect(client.requests, hasLength(2));
      expect(ai.agent.sessionState, same(completed));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
