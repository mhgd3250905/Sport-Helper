import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  late Map<String, Object?> originalCard;
  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
    final store = AppStore(MemoryStorage());
    await store.acceptSafety(blocked: false);
    final chat = fakeHostChat(
      sdkChatServices(store, fixture),
      coach.FakeLlmClient(fixture.planTurn(), latency: Duration.zero),
    );
    expect((await chat.start()).ok, isTrue);
    await chat.send('在家徒手10分钟拉伸');
    final card = chat.messages.lastWhere((row) => row.plan != null);
    originalCard = {
      ...card.toJson(),
      'planState': chat.agent.planStateFor(card.validatedPlan!).toJson(),
    };
    await chat.close();
    store.dispose();
  });

  for (final variant in ['valid', 'missing', 'corrupt', 'mismatched']) {
    test(
      'pre-v2 $variant planState is imported through the SDK, leaving old bytes intact',
      () async {
        final raw = Map<String, Object?>.from(
          jsonDecode(jsonEncode(originalCard)) as Map,
        );
        if (variant == 'missing') raw.remove('planState');
        if (variant == 'corrupt') raw['planState'] = {'context': 'damaged'};
        if (variant == 'mismatched') {
          raw['planState'] = {...raw['planState'] as Map, 'planId': 'other'};
        }
        final disk = MemoryStorage();
        disk.data[AppStore.key] = jsonEncode({
          'safetyAccepted': true,
          'chat': [raw],
        });
        final store = AppStore(disk);
        await store.load();
        final client = coach.FakeLlmClient([], latency: Duration.zero);
        final chat = fakeHostChat(sdkChatServices(store, fixture), client);
        addTearDown(() async {
          await chat.close();
          store.dispose();
        });
        expect((await chat.start()).ok, isTrue);
        final restored = chat.messages.singleWhere(
          (row) => row.id == raw['id'],
        );
        expect(restored.validatedPlan, isNotNull);
        expect(restored.plan!.toJson(), raw['plan']);
        expect(restored.toJson().containsKey('planState'), isFalse);
        expect(store.chatLog.single, raw);
        expect(store.chatEnvelope(smartfitCoachChatNamespace), isNotNull);
        expect(client.requests, isEmpty);
      },
    );
  }
}
