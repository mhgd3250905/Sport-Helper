import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../data/app_store.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import '../domain/session.dart' show trainerPlan;

/// The existing My plans store is the sole durable writer for SDK chat cards.
class SmartfitCoachPlanStore extends CoachPlanStorageAdapter {
  SmartfitCoachPlanStore(this.store);
  final AppStore store;

  CoachSavedPlanSnapshot snapshot(SavedPlan saved) => CoachSavedPlanSnapshot(
    externalId: saved.id,
    title: saved.name,
    plan: trainerPlan(saved.plan),
    storageRevision: AppStore.savedPlanStorageRevision(saved),
    sdkVersion: saved.sdkVersion,
    updatedAt: saved.touchedAt,
  );

  @override
  Future<List<CoachSavedPlanSnapshot>> load() async => [
    for (final saved in store.savedPlans) snapshot(saved),
  ];

  @override
  Stream<void> get changes => _storeChanges(store).map((_) {});

  @override
  Future<CoachPlanWriteResult> save(CoachPlanWriteRequest request) async {
    final result = await store.writeSavedPlan(
      TrainingPlan.fromJson(request.plan.toJson()),
      mode: SavedPlanWriteMode.values.byName(request.mode.name),
      name: request.name,
      sdkVersion: request.sdkVersion,
      externalId: request.externalId,
      expectedStorageRevision: request.expectedStorageRevision,
    );
    if (result.saved case final saved?) {
      return CoachPlanWriteResult.saved(snapshot(saved));
    }
    return CoachPlanWriteResult.failure(
      CoachPlanWriteStatus.values.byName(result.status.name),
      error: result.error,
    );
  }
}

/// New envelopes use their own namespace/key; all three legacy fields survive.
class SmartfitCoachChatHistoryStore extends CoachChatHistoryStore {
  SmartfitCoachChatHistoryStore(this.store, {this.beforeWrite});
  final AppStore store;
  final Future<void> Function()? beforeWrite;

  @override
  Future<CoachChatSnapshot?> load(String namespace) async {
    final json = store.chatEnvelope(namespace);
    return json == null ? null : CoachChatSnapshot.fromJson(json);
  }

  @override
  Future<void> write(String namespace, CoachChatSnapshot snapshot) async {
    await beforeWrite?.call();
    await store.writeChatEnvelope(namespace, snapshot.toJson());
  }

  @override
  Future<CoachChatLegacyData?> loadLegacy(String namespace) async =>
      store.chatLog.isEmpty &&
          store.coachDisplayMessages.isEmpty &&
          store.coachSessionJson == null
      ? null
      : CoachChatLegacyData(
          chat: [
            for (final row in store.chatLog) Map<String, Object?>.from(row),
          ],
          coachDisplay: [
            for (final row in store.coachDisplayMessages)
              Map<String, Object?>.from(row),
          ],
          coachSessionJson: store.coachSessionJson,
        );

  @override
  Future<CoachChatHistoryContext> readTrainingContext() async =>
      CoachChatHistoryContext(
        lastPlan: store.lastPlan == null ? null : trainerPlan(store.lastPlan!),
        history: [
          for (final row in store.history)
            WorkoutLog(
              title: row.title,
              at: row.at,
              minutes: row.minutes,
              completed: row.completed,
              total: row.total,
            ),
        ],
      );

  @override
  Future<void> rememberStartedPlan(
    coach.TrainingPlan plan, {
    String? savedExternalId,
  }) async {
    await store.rememberPlan(TrainingPlan.fromJson(plan.toJson()));
    if (savedExternalId != null) await store.touchPlan(savedExternalId);
  }
}

class SmartfitCoachChatPreferenceStore extends CoachChatPreferenceStore {
  SmartfitCoachChatPreferenceStore(this.store);
  final AppStore store;

  CoachChatPreferences get _value => CoachChatPreferences(
    safetyAccepted: store.safetyAccepted,
    safetyBlocked: store.safetyBlocked,
    appearance: store.appearance,
    voice: store.voice.voice,
    chimes: store.voice.chimes,
    enableUserMemory: store.aiMemoryEnabled,
    starfield: store.starfield,
  );

  @override
  Future<CoachChatPreferences> load() async => _value;

  @override
  Stream<CoachChatPreferences> get changes =>
      _storeChanges(store).map((_) => _value);

  @override
  Future<void> update(CoachChatPreferences preferences) =>
      store.writeCoachPreferences(
        safetyAccepted:
            preferences.safetyAccepted && !preferences.safetyChecking,
        safetyBlocked: preferences.safetyBlocked,
        appearance: preferences.appearance,
        voice: preferences.voice,
        chimes: preferences.chimes,
        enableUserMemory: preferences.enableUserMemory,
        starfield: preferences.starfield,
      );
}

Stream<void> _storeChanges(AppStore store) => Stream<void>.multi((listener) {
  void changed() => listener.add(null);
  store.addListener(changed);
  listener.onCancel = () => store.removeListener(changed);
}, isBroadcast: true);
