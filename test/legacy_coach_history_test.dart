import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show MemoryStorage;
import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  AiChatEngine engine(List<Object> script) => AiChatEngine(
    local: const AppChatActions(),
    catalog: fixture.catalog,
    profile: fixture.profile,
    client: coach.FakeLlmClient(script, latency: Duration.zero),
  );

  Future<Map<String, dynamic>> legacyCard() async {
    final first = engine(fixture.planTurn());
    addTearDown(first.dispose);
    final reply = await first.reply('在家徒手10分钟拉伸', const ChatState());
    final card = reply.messages.single;
    expect(card.validatedPlan, isNotNull);
    return {
      ...ChatMessage(
        id: 'old-card',
        role: ChatRole.assistant,
        at: DateTime(2026),
        text: card.text,
        plan: card.plan,
        validatedPlan: card.validatedPlan,
        request: card.request,
        aiVisible: true,
      ).toJson(),
      'planState': first.agent.planStateFor(card.validatedPlan!).toJson(),
    };
  }

  for (final snapshot in ['valid', 'missing', 'corrupt', 'mismatched']) {
    test(
      'pre-v2 $snapshot plan state uses SDK legacy restoration safely',
      () async {
        final raw = await legacyCard();
        if (snapshot == 'missing') raw.remove('planState');
        if (snapshot == 'corrupt') raw['planState'] = {'context': 'damaged'};
        if (snapshot == 'mismatched') {
          raw['planState'] = {
            ...raw['planState'] as Map,
            'planId': 'another-plan',
          };
        }
        final storage = MemoryStorage();
        final store = AppStore(storage);
        await store.acceptSafety(blocked: false);
        await store.setChatLog([
          jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
        ]);
        final next = engine([]);
        final chat = ChatController(
          engine: next,
          store: store,
          replyDelay: Duration.zero,
        );
        addTearDown(chat.dispose);
        chat.start();
        final restored = chat.messages.firstWhere((m) => m.id == 'old-card');
        expect(restored.validatedPlan, isNotNull);
        expect(restored.validatedPlan!.plan.id, (raw['plan'] as Map)['id']);
        expect(next.agent.sessionState.lastDeliveredPlanId, restored.plan!.id);
        expect(
          restored.toJson().containsKey('planState'),
          isFalse,
          reason:
              'Legacy per-card conditions are read once, never maintained by App.',
        );
      },
    );
  }

  test('presentation task snapshots round-trip without App planning state', () {
    final task = coach.CoachTaskState.fromJson({
      'type': 'recommend',
      'reused': false,
      'nodes': [
        {
          'id': 'understand',
          'status': 'done',
          'stamp': '要推荐动作',
          'doneAtTurn': 1,
        },
      ],
    });
    final message = ChatMessage(
      id: 'task',
      role: ChatRole.assistant,
      at: DateTime(2026),
      text: '按你的目标挑选。',
      coachTask: task,
    );
    final restored = ChatMessage.fromJson(
      jsonDecode(jsonEncode(message.toJson())),
    );
    expect(restored.coachTask!.toJson(), task.toJson());
    expect(restored.text, message.text);
    final corrupt = {
      ...message.toJson(),
      'coachTask': {'nodes': 'bad'},
    };
    expect(ChatMessage.fromJson(corrupt).coachTask, isNull);
  });
}
