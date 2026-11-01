import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  late coach.TrainingPlan generated;
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
    generated = chat.currentPlan!;
    await chat.close();
    store.dispose();
  });

  Future<(AppStore, CoachChatController, coach.FakeLlmClient)> open(
    MemoryStorage disk, {
    List<Object> script = const [],
  }) async {
    final store = AppStore(disk);
    await store.load();
    if (!store.safetyAccepted) await store.acceptSafety(blocked: false);
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final chat = fakeHostChat(sdkChatServices(store, fixture), client);
    expect((await chat.start()).ok, isTrue);
    addTearDown(() async {
      await chat.close();
      store.dispose();
    });
    return (store, chat, client);
  }

  test(
    'My plans selection imports the entire saved plan and its independent CAS revision locally',
    () async {
      final (store, chat, client) = await open(
        MemoryStorage(),
        script: ['这是当前讨论的计划。'],
      );
      final saved = await store.savePlan(
        TrainingPlan.fromJson(generated.toJson()),
        name: '用户原来的名字',
        sdkVersion: 7,
      );
      final selection = SmartfitCoachPlanStore(store).snapshot(saved);
      final result = await chat.sendPlanToConversation(selection);
      expect(result.ok, isTrue, reason: '${result.errors}');
      expect(client.requests, isEmpty);
      expect(chat.focus!.savedRef.externalId, saved.id);
      expect(chat.focus!.title, saved.name);
      final card = chat.messages.lastWhere((row) => row.plan != null);
      expect(card.plan!.toJson(), generated.toJson());
      expect(card.storageRevision, AppStore.savedPlanStorageRevision(saved));
      expect(card.storageRevision, isNot(chat.focus!.savedRef.baseVersion));
      await chat.send('这是什么计划');
      expect(client.requests, hasLength(1));
      final wire = jsonEncode(
        client.requests.single.messages.map((row) => row.toJson()).toList(),
      );
      expect(wire, contains(saved.id));
      for (final item in generated.items) {
        expect(wire, contains(item.exerciseId));
      }
      expect(store.savedPlans.single.name, '用户原来的名字');
    },
  );

  test(
    'saved focus and the exact per-card host revision survive restart without a model call',
    () async {
      final disk = MemoryStorage();
      final (store, first, _) = await open(disk);
      final saved = await store.savePlan(
        TrainingPlan.fromJson(generated.toJson()),
        sdkVersion: 1,
      );
      expect(
        (await first.sendPlanToConversation(
          SmartfitCoachPlanStore(store).snapshot(saved),
        )).ok,
        isTrue,
      );
      final card = first.messages.lastWhere((row) => row.plan != null);
      await first.close();
      final (_, restored, client) = await open(disk);
      final restoredCard = restored.messages.lastWhere(
        (row) => row.plan != null,
      );
      expect(restored.focus!.savedRef.externalId, saved.id);
      expect(restoredCard.storageRevision, card.storageRevision);
      expect(restoredCard.plan!.toJson(), card.plan!.toJson());
      expect(restoredCard.savedExternalId, saved.id);
      expect(client.requests, isEmpty);
    },
  );

  test(
    'rename invalidates an old card token, while a fresh selection obtains the new token',
    () async {
      final (store, chat, _) = await open(MemoryStorage());
      final saved = await store.savePlan(
        TrainingPlan.fromJson(generated.toJson()),
        sdkVersion: 1,
      );
      final adapter = SmartfitCoachPlanStore(store);
      await chat.sendPlanToConversation(adapter.snapshot(saved));
      final oldCard = chat.messages.lastWhere((row) => row.plan != null);
      await store.renamePlan(saved.id, '刚改好的名字');
      final current = (await adapter.read(saved.id))!;
      expect(current.storageRevision, isNot(oldCard.storageRevision));
      await chat.sendPlanToConversation(current);
      final card = chat.messages.lastWhere((row) => row.plan != null);
      expect(card.storageRevision, current.storageRevision);
      expect(chat.focus!.title, '刚改好的名字');
      expect(store.savedPlans, hasLength(1));
    },
  );

  test(
    'a deleted saved source is reported explicitly and cannot be revived by an old update token',
    () async {
      final (store, chat, _) = await open(MemoryStorage());
      final saved = await store.savePlan(
        TrainingPlan.fromJson(generated.toJson()),
        sdkVersion: 1,
      );
      final adapter = SmartfitCoachPlanStore(store);
      await chat.sendPlanToConversation(adapter.snapshot(saved));
      final card = chat.messages.lastWhere((row) => row.plan != null);
      await store.deletePlan(saved.id);
      final result = await adapter.save(
        CoachPlanWriteRequest(
          admittedPlan: card.validatedPlan!,
          mode: CoachPlanWriteMode.update,
          name: saved.name,
          externalId: saved.id,
          expectedStorageRevision: card.storageRevision,
          sdkVersion: 2,
        ),
      );
      expect(result.status, CoachPlanWriteStatus.deleted);
      expect(store.savedPlans, isEmpty);
    },
  );

  test(
    'invalid saved action cannot replace the current admitted focus or write a plan',
    () async {
      final (store, chat, client) = await open(MemoryStorage());
      final saved = await store.savePlan(
        TrainingPlan.fromJson(generated.toJson()),
        sdkVersion: 1,
      );
      final adapter = SmartfitCoachPlanStore(store);
      await chat.sendPlanToConversation(adapter.snapshot(saved));
      final before = chat.focus!.toJson();
      final json =
          jsonDecode(jsonEncode(generated.toJson())) as Map<String, dynamic>;
      (json['blocks'] as List).first['items'][0]['exerciseId'] =
          'unknown-saved-action';
      final bad = const coach.PlanCodec().decode(json);
      final result = await chat.sendPlanToConversation(
        CoachSavedPlanSnapshot(
          externalId: 'bad',
          title: '损坏计划',
          plan: bad,
          storageRevision: 'opaque-bad',
        ),
      );
      expect(result.ok, isFalse);
      expect(result.errors, isNotEmpty);
      expect(chat.focus!.toJson(), before);
      expect(store.savedPlans.single.id, saved.id);
      expect(client.requests, isEmpty);
    },
  );
}
