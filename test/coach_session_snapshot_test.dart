import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachRecommendCard;

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';
import 'support/widget_test_timeout.dart';

void main() {
  configureWidgetTestTimeout();
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  Future<(AppStore, CoachChatController, coach.FakeLlmClient)> open(
    MemoryStorage disk,
    List<Object> script,
  ) async {
    final store = AppStore(disk);
    await store.load();
    if (!store.safetyAccepted) await store.acceptSafety(blocked: false);
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final chat = fakeHostChat(sdkChatServices(store, fixture), client);
    addTearDown(() async {
      await chat.close();
      store.dispose();
    });
    expect((await chat.start()).ok, isTrue);
    return (store, chat, client);
  }

  test(
    'a new App instance restores the exact admitted SDK session and display without a model call',
    () async {
      final disk = MemoryStorage();
      final (store, first, _) = await open(disk, fixture.planTurn());
      await first.send('在家徒手10分钟拉伸');
      expect(first.lastResult?.status, coach.TurnStatus.ok);
      await first.flushPersistence();
      final session = first.conversation.exportSession().toJson();
      final cards = first.messages
          .where((row) => row.plan != null)
          .map((row) => row.toJson())
          .toList();
      expect(store.chatEnvelope(smartfitCoachChatNamespace), isNotNull);
      await first.close();
      final (_, restored, client) = await open(disk, []);
      expect(restored.conversation.exportSession().toJson(), session);
      expect(
        restored.messages
            .where((row) => row.plan != null)
            .map((row) => row.toJson()),
        cards,
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'an unanswered SDK question and sourced ledger survive the host envelope',
    () async {
      final disk = MemoryStorage();
      final (_, first, _) = await open(disk, [
        CoachV2Fixtures.batch([
          CoachV2Fixtures.call('host-question', 'ask_user', {
            'question': '这次准备练多久？',
            'mode': 'choice',
            'options': ['10分钟', '15分钟'],
          }),
        ]),
      ]);
      await first.send('帮我安排一下');
      final pending = first.conversation.state.pendingQuestion;
      expect(pending, isNotNull);
      final session = first.conversation.exportSession().toJson();
      await first.close();
      final (_, restored, client) = await open(disk, []);
      expect(restored.conversation.state.pendingQuestion!.id, pending!.id);
      expect(restored.conversation.exportSession().toJson(), session);
      expect(restored.messages.any(restored.canAnswerQuestion), isTrue);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'all three legacy keys import into a namespaced envelope without being rewritten',
    () async {
      final firstDisk = MemoryStorage();
      final (_, first, _) = await open(firstDisk, fixture.planTurn());
      await first.send('在家徒手10分钟拉伸');
      final display = [for (final row in first.messages) row.toJson()];
      final session = jsonEncode(first.conversation.exportSession().toJson());
      final disk = MemoryStorage();
      disk.data[AppStore.key] = jsonEncode({
        'safetyAccepted': true,
        'safetyBlocked': false,
        'chat': display,
        'coachDisplay': display,
        'coachSessionJson': session,
      });
      final (store, restored, client) = await open(disk, []);
      expect(restored.currentPlan!.toJson(), first.currentPlan!.toJson());
      expect(
        restored.conversation.exportSession().toJson(),
        jsonDecode(session),
      );
      expect(store.chatLog, display);
      expect(store.coachDisplayMessages, display);
      expect(store.coachSessionJson, session);
      expect(store.chatEnvelope(smartfitCoachChatNamespace), isNotNull);
      final durable = jsonDecode(disk.data[AppStore.key]!) as Map;
      expect(durable['chat'], display);
      expect(durable['coachDisplay'], display);
      expect(durable['coachSessionJson'], session);
      expect(client.requests, isEmpty);
    },
  );

  testWidgets(
    'corrupt legacy SDK JSON recovers to a sendable persisted conversation',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<void> pump() async {
        for (var index = 0; index < 3; index++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
          await tester.pump(const Duration(milliseconds: 400));
        }
      }

      Future<void> close(CoachChatController controller) async {
        var closed = false;
        unawaited(controller.close().then((_) => closed = true));
        for (var index = 0; index < 10 && !closed; index++) {
          await pump();
        }
        expect(closed, isTrue);
      }

      final disk = MemoryStorage();
      disk.data[AppStore.key] = jsonEncode({
        'safetyAccepted': true,
        'coachSessionJson': '{damaged',
        'coachDisplay': [
          {
            'id': 'before',
            'role': 'assistant',
            'at': DateTime(2026).toIso8601String(),
            'text': '旧记录',
          },
        ],
        'chat': [
          {
            'id': 'before',
            'role': 'assistant',
            'at': DateTime(2026).toIso8601String(),
            'text': '旧记录',
          },
        ],
      });
      final (store, services, chat, client, result) = (await tester.runAsync(
        () async {
          final store = AppStore(disk);
          await store.load();
          await store.setStarfield(false);
          final services = sdkChatServices(store, fixture);
          final client = coach.FakeLlmClient(
            fixture.recommendationTurn(),
            latency: Duration.zero,
          );
          final chat = fakeHostChat(services, client);
          return (store, services, chat, client, await chat.start());
        },
      ))!;
      addTearDown(() async {
        await close(chat);
        chat.dispose();
        await services.dispose();
        store.dispose();
      });
      expect(result.ok, isTrue, reason: '${result.error}');
      expect(store.coachSessionJson, '{damaged');
      expect(client.requests, isEmpty);
      const recoveredNotice = '之前的对话记录无法读取，已开始新的对话。';
      expect(
        chat.messages.where((row) => row.text == recoveredNotice),
        hasLength(1),
      );
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: chat),
          ),
        ),
      );
      await pump();
      expect(find.text(recoveredNotice), findsOneWidget);
      const request = '在家徒手拉伸，先推荐几个动作';
      await tester.enterText(find.byKey(const ValueKey('chat-input')), request);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await pump();
      expect(
        chat.lastResult?.status,
        coach.TurnStatus.ok,
        reason: '${chat.lastResult?.error}',
      );
      expect(chat.messages.where((row) => row.isUser).single.text, request);
      expect(find.text(request), findsOneWidget);
      expect(find.byType(CoachRecommendCard), findsOneWidget);
      expect(client.requests, isNotEmpty);
      await tester.runAsync(chat.flushPersistence);
      // The SDK binds legacy user display rows to their conversation id on
      // restore; all other persisted display content must remain unchanged.
      final display = [
        for (final row in chat.messages)
          {
            ...row.toJson(),
            if (row.isUser)
              'conversationMessageId': row.conversationMessageId ?? row.id,
          },
      ];
      expect(store.chatEnvelope(smartfitCoachChatNamespace), isNotNull);
      final durable = jsonDecode(disk.data[AppStore.key]!) as Map;
      expect(durable['coachSessionJson'], '{damaged');
      await tester.pumpWidget(const SizedBox());
      await close(chat);

      final (
        reopenedStore,
        reopenedServices,
        reopened,
        reopenedClient,
        reopenedResult,
      ) = (await tester.runAsync(() async {
        final reopenedStore = AppStore(disk);
        await reopenedStore.load();
        final reopenedServices = sdkChatServices(reopenedStore, fixture);
        final reopenedClient = coach.FakeLlmClient([], latency: Duration.zero);
        final reopened = fakeHostChat(reopenedServices, reopenedClient);
        return (
          reopenedStore,
          reopenedServices,
          reopened,
          reopenedClient,
          await reopened.start(),
        );
      }))!;
      addTearDown(() async {
        await close(reopened);
        reopened.dispose();
        await reopenedServices.dispose();
        reopenedStore.dispose();
      });
      expect(reopenedResult.ok, isTrue, reason: '${reopenedResult.error}');
      expect(reopened.messages.map((row) => row.toJson()), display);
      // The original notice remains in history; reopening must not add another
      // recovery notice or replay the user's model request.
      expect(
        reopened.messages.where((row) => row.text == recoveredNotice),
        hasLength(1),
      );
      expect(reopenedClient.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'an envelope from another namespace cannot silently replace this App conversation',
    () async {
      final disk = MemoryStorage();
      final (store, first, _) = await open(disk, fixture.recommendationTurn());
      await first.send('在家徒手拉伸，先推荐几个动作');
      await first.flushPersistence();
      final original = store.chatEnvelope(smartfitCoachChatNamespace)!;
      final bad = CoachChatSnapshot.fromJson({
        ...original,
        'storageNamespace': 'another.app',
      });
      final display = [for (final row in first.messages) row.toJson()];
      final result = await first.restoreSnapshot(bad);
      expect(result.ok, isFalse);
      expect(
        result.issues.map((issue) => issue.code),
        contains('snapshot_not_admitted'),
      );
      expect(first.messages.map((row) => row.toJson()), display);
      expect(store.chatEnvelope(smartfitCoachChatNamespace), original);
    },
  );

  test(
    'new conversation persists an empty core ledger and cannot revive old cards',
    () async {
      final disk = MemoryStorage();
      final (_, first, _) = await open(disk, fixture.planTurn());
      await first.send('在家徒手10分钟拉伸');
      expect(first.currentPlan, isNotNull);
      expect((await first.newConversation()).ok, isTrue);
      expect(first.currentPlan, isNull);
      await first.close();
      final (_, restored, client) = await open(disk, []);
      expect(restored.currentPlan, isNull);
      expect(restored.messages.where((row) => row.isPlan), isEmpty);
      expect(restored.agent.sessionState.userTurns, isEmpty);
      expect(client.requests, isEmpty);
    },
  );
}
