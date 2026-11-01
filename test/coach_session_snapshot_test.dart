import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

void main() {
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

  test(
    'corrupt legacy SDK JSON fails observably and preserves original storage',
    () async {
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
      final original = disk.data[AppStore.key];
      final store = AppStore(disk);
      await store.load();
      final client = coach.FakeLlmClient([], latency: Duration.zero);
      final chat = fakeHostChat(sdkChatServices(store, fixture), client);
      final result = await chat.start();
      expect(result.ok, isFalse);
      expect(result.error, isA<FormatException>());
      expect(store.coachSessionJson, '{damaged');
      expect(store.chatEnvelope(smartfitCoachChatNamespace), isNull);
      expect(disk.data[AppStore.key], original);
      expect(client.requests, isEmpty);
      await chat.close();
      store.dispose();
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
