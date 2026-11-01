import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/coach_chat_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

class _ControlledStorage extends MemoryStorage {
  bool fail = false;
  bool holdNextWrite = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (holdNextWrite && key == AppStore.key) {
      holdNextWrite = false;
      entered.complete();
      await release.future;
    }
    if (fail) throw StateError('Fixture disk unavailable');
    await super.write(key, value);
  }
}

void main() {
  late CoachV2Fixtures fixture;
  late coach.ValidatedPlan admitted;

  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
    final store = AppStore(MemoryStorage());
    await store.acceptSafety(blocked: false);
    final services = sdkChatServices(store, fixture);
    final client = coach.FakeLlmClient(
      fixture.planTurn(),
      latency: Duration.zero,
    );
    final chat = fakeHostChat(services, client);
    expect((await chat.start()).ok, isTrue);
    await chat.send('在家徒手10分钟拉伸');
    expect(
      chat.lastResult?.status,
      coach.TurnStatus.ok,
      reason: '${chat.lastResult?.issues}',
    );
    admitted = chat.messages
        .lastWhere((row) => row.plan != null)
        .validatedPlan!;
    await chat.close();
    await services.dispose();
  });

  CoachPlanWriteRequest request({
    CoachPlanWriteMode mode = CoachPlanWriteMode.create,
    String name = '我的练习',
    CoachSavedPlanSnapshot? saved,
    int version = 1,
    Object? revision,
  }) => CoachPlanWriteRequest(
    admittedPlan: admitted,
    mode: mode,
    name: name,
    sdkVersion: version,
    externalId: saved?.externalId,
    expectedStorageRevision: revision,
  );

  test(
    'SDK adapter writes one durable record, preserving version and dose',
    () async {
      final disk = MemoryStorage();
      final store = AppStore(disk);
      addTearDown(store.dispose);
      final adapter = SmartfitCoachPlanStore(store);
      final result = await adapter.save(request());
      expect(result.ok, isTrue);
      expect(store.savedPlans, hasLength(1));
      expect(result.saved!.plan.toJson(), admitted.plan.toJson());
      expect(result.saved!.sdkVersion, 1);
      expect(
        result.saved!.storageRevision,
        AppStore.savedPlanStorageRevision(store.savedPlans.single),
      );
      final restarted = AppStore(disk);
      await restarted.load();
      addTearDown(restarted.dispose);
      expect(
        restarted.savedPlans.single.toJson(),
        store.savedPlans.single.toJson(),
      );
      expect(
        (await SmartfitCoachPlanStore(restarted).load()).single.storageRevision,
        result.saved!.storageRevision,
      );
    },
  );

  test(
    'copy creates its own identity and unique name without changing original',
    () async {
      final store = AppStore(MemoryStorage());
      addTearDown(store.dispose);
      final adapter = SmartfitCoachPlanStore(store);
      final original = (await adapter.save(request())).saved!;
      final copy = (await adapter.save(
        request(mode: CoachPlanWriteMode.copy),
      )).saved!;
      final next = (await adapter.save(
        request(mode: CoachPlanWriteMode.copy),
      )).saved!;
      expect({original.id, copy.id, next.id}, hasLength(3));
      expect(
        [original.name, copy.name, next.name],
        ['我的练习', '我的练习 新版', '我的练习 新版 2'],
      );
      expect(
        (await adapter.read(original.id))!.storageRevision,
        original.storageRevision,
      );
    },
  );

  test(
    'two SDK updates with the same record token cannot both commit',
    () async {
      final disk = MemoryStorage();
      final store = AppStore(disk);
      addTearDown(store.dispose);
      final adapter = SmartfitCoachPlanStore(store);
      final saved = (await adapter.save(request())).saved!;
      final results = await Future.wait([
        adapter.save(
          request(
            mode: CoachPlanWriteMode.update,
            saved: saved,
            revision: saved.storageRevision,
            version: 2,
          ),
        ),
        adapter.save(
          request(
            mode: CoachPlanWriteMode.update,
            saved: saved,
            revision: saved.storageRevision,
            version: 3,
          ),
        ),
      ]);
      expect(results.map((row) => row.status), [
        CoachPlanWriteStatus.saved,
        CoachPlanWriteStatus.conflict,
      ]);
      expect(store.savedPlans.single.sdkVersion, 2);
      final restarted = AppStore(disk);
      await restarted.load();
      addTearDown(restarted.dispose);
      expect(restarted.savedPlans.single.sdkVersion, 2);
    },
  );

  test(
    'missing revision is read-only and deleting never silently creates a copy',
    () async {
      final store = AppStore(MemoryStorage());
      addTearDown(store.dispose);
      final adapter = SmartfitCoachPlanStore(store);
      final saved = (await adapter.save(request())).saved!;
      final missing = await adapter.save(
        request(mode: CoachPlanWriteMode.update, saved: saved),
      );
      expect(missing.status, CoachPlanWriteStatus.readOnly);
      await store.deletePlan(saved.id);
      final deleted = await adapter.save(
        request(
          mode: CoachPlanWriteMode.update,
          saved: saved,
          revision: saved.storageRevision,
        ),
      );
      expect(deleted.status, CoachPlanWriteStatus.deleted);
      expect(store.savedPlans, isEmpty);
    },
  );

  test(
    'disk rejection is explicit and cannot publish an in-memory SDK save',
    () async {
      final disk = _ControlledStorage()..fail = true;
      final store = AppStore(disk);
      addTearDown(store.dispose);
      final result = await SmartfitCoachPlanStore(store).save(request());
      expect(result.status, CoachPlanWriteStatus.failed);
      expect(result.error, isA<StateError>());
      expect(store.savedPlans, isEmpty);
      expect(disk.data[AppStore.key], isNull);
    },
  );

  for (final operation in ['rename', 'delete', 'touch']) {
    test(
      'pending SDK update serializes the actual My plans $operation intent',
      () async {
        final disk = _ControlledStorage();
        final store = AppStore(disk);
        addTearDown(store.dispose);
        final adapter = SmartfitCoachPlanStore(store);
        final saved = (await adapter.save(request())).saved!;
        disk.holdNextWrite = true;
        final pending = adapter.save(
          request(
            mode: CoachPlanWriteMode.update,
            saved: saved,
            revision: saved.storageRevision,
            version: 2,
          ),
        );
        await disk.entered.future;
        final at = DateTime.utc(2026, 11, 1, 12);
        final intent = switch (operation) {
          'rename' => store.renamePlan(saved.id, '用户刚改的名字'),
          'delete' => store.deletePlan(saved.id),
          _ => store.touchPlan(saved.id, now: at),
        };
        disk.release.complete();
        expect((await pending).ok, isTrue);
        await intent;
        final restarted = AppStore(disk);
        await restarted.load();
        addTearDown(restarted.dispose);
        if (operation == 'delete') {
          expect(store.savedPlans, isEmpty);
          expect(
            restarted.savedPlans,
            isEmpty,
            reason: 'The pending CAS cannot resurrect a user-deleted plan',
          );
        } else {
          final current = store.savedPlans.single;
          expect(current.sdkVersion, 2);
          if (operation == 'rename') expect(current.name, '用户刚改的名字');
          if (operation == 'touch') expect(current.lastUsedAt, at);
          expect(restarted.savedPlans.single.toJson(), current.toJson());
          final stale = await adapter.save(
            request(
              mode: CoachPlanWriteMode.update,
              saved: saved,
              revision: saved.storageRevision,
              version: 3,
            ),
          );
          expect(stale.status, CoachPlanWriteStatus.conflict);
        }
      },
    );
  }

  test(
    'new chat envelope preserves legacy keys and fails atomically on disk error',
    () async {
      final disk = _ControlledStorage();
      final store = AppStore(disk);
      addTearDown(store.dispose);
      await store.acceptSafety(blocked: false);
      final plan = TrainingPlan.fromJson(admitted.plan.toJson());
      await store.rememberPlan(plan);
      final legacyChat = [
        {
          'id': 'legacy',
          'role': 'assistant',
          'at': DateTime(2026).toIso8601String(),
          'text': '原来的对话',
        },
      ];
      await store.setConversation(legacyChat, sessionJson: null);
      final services = sdkChatServices(store, fixture);
      final chat = fakeHostChat(
        services,
        coach.FakeLlmClient([], latency: Duration.zero),
      );
      addTearDown(chat.close);
      expect((await chat.start()).ok, isTrue);
      await chat.flushPersistence();
      final history = SmartfitCoachChatHistoryStore(store);
      final envelope = (await history.load(smartfitCoachChatNamespace))!;
      expect(envelope.appId, fixture.profile.id);
      expect(store.chatLog, legacyChat);
      expect(store.coachSessionJson, isNull);
      expect(
        (await history.readTrainingContext()).lastPlan!.toJson(),
        admitted.plan.toJson(),
      );
      final original = jsonEncode(
        store.chatEnvelope(smartfitCoachChatNamespace),
      );
      disk.fail = true;
      await expectLater(
        history.write('other.namespace', envelope),
        throwsStateError,
      );
      expect(store.chatEnvelope('other.namespace'), isNull);
      expect(
        jsonEncode(store.chatEnvelope(smartfitCoachChatNamespace)),
        original,
      );
      disk.fail = false;
    },
  );

  test(
    'SDK preference port shares safety, theme, audio, memory and stars with settings',
    () async {
      final disk = MemoryStorage();
      final store = AppStore(disk);
      addTearDown(store.dispose);
      final preferences = SmartfitCoachChatPreferenceStore(store);
      final observed = <CoachChatPreferences>[];
      final subscription = preferences.changes.listen(observed.add);
      addTearDown(subscription.cancel);
      await preferences.update(
        const CoachChatPreferences(
          safetyAccepted: true,
          safetyBlocked: false,
          appearance: 'light',
          voice: false,
          chimes: false,
          enableUserMemory: false,
          starfield: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(observed.last.trainingAllowed, isTrue);
      expect(store.appearance, 'light');
      expect(store.voice.voice, isFalse);
      expect(store.voice.chimes, isFalse);
      expect(store.aiMemoryEnabled, isFalse);
      expect(store.starfield, isFalse);
      final restarted = AppStore(disk);
      await restarted.load();
      addTearDown(restarted.dispose);
      expect(
        (await SmartfitCoachChatPreferenceStore(restarted).load()).appearance,
        'light',
      );
      await store.beginSafetyCheck();
      await Future<void>.delayed(Duration.zero);
      expect(observed.last.trainingAllowed, isFalse);
    },
  );
}
