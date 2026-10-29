import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support/coach_v2_fixtures.dart';

const _statePrefix = '当前状态（系统生成）：';
const _selectionPrefix = '用户从「我的计划」选中了计划（系统生成）：';
const _freshAction = 's-figure4';

class _MemoryStorage implements LocalStateStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _DiskStorage implements LocalStateStorage {
  _DiskStorage(this.directory);
  final Directory directory;

  File _file(String key) => File('${directory.path}/$key.json');

  @override
  Future<String?> read(String key) async =>
      await _file(key).exists() ? _file(key).readAsString() : null;

  @override
  Future<void> write(String key, String value) async {
    await directory.create(recursive: true);
    await _file(key).writeAsString(value, flush: true);
  }
}

class _DelayedDisplayStorage extends _MemoryStorage {
  final started = Completer<void>();
  final release = Completer<void>();
  final finished = Completer<void>();
  final completed = <Map<String, dynamic>>[];
  String? watchedPlanId;
  bool _delayed = false;

  @override
  Future<void> write(String key, String value) async {
    final state = jsonDecode(value) as Map<String, dynamic>;
    final hasDisplay =
        watchedPlanId != null &&
        (state['chat'] as List? ?? const []).any(
          (row) => row is Map && (row['plan'] as Map?)?['id'] == watchedPlanId,
        );
    if (key == AppStore.key && hasDisplay && !_delayed) {
      _delayed = true;
      started.complete();
      await release.future;
    }
    await super.write(key, value);
    if (watchedPlanId != null) {
      completed.add(state);
      if (_delayed && !finished.isCompleted) finished.complete();
    }
  }
}

class _App {
  _App(this.storage, this.store, this.client, this.engine, this.chat);
  final LocalStateStorage storage;
  final AppStore store;
  final coach.FakeLlmClient client;
  final AiChatEngine engine;
  final ChatController chat;
  bool _closed = false;

  coach.CoachSessionSnapshot get snapshot =>
      coach.CoachSessionSnapshot.fromJson(jsonDecode(store.coachSessionJson!));

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await chat.flushPersistence();
    chat.dispose();
    // dispose schedules one last queued write. Drain that queue while the SDK
    // is still readable, before another process loads JSON or temp files close.
    await chat.flushPersistence();
    engine.dispose();
    store.dispose();
  }
}

Map<String, dynamic> _tail(coach.LlmRequest request) {
  final message = request.messages.lastWhere(
    (message) => message.content.startsWith(_statePrefix),
  );
  expect(message.role, coach.LlmRole.user);
  return jsonDecode(message.content.substring(_statePrefix.length))
      as Map<String, dynamic>;
}

ChatMessage _lastVersionedCard(_App app) =>
    app.chat.messages.lastWhere((message) => message.planVersion != null);

void main() {
  late CoachV2Fixtures fixture;
  var generation = 0;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  Future<_App> app(List<Object> script, {LocalStateStorage? storage}) async {
    final disk = storage ?? _MemoryStorage();
    final store = AppStore(disk);
    await store.load();
    if (!store.safetyAccepted) await store.acceptSafety(blocked: false);
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final engine = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: client,
      enableUserMemory: false,
    );
    final clockGeneration = generation++;
    final chat = ChatController(
      engine: engine,
      store: store,
      replyDelay: Duration.zero,
      clock: () => DateTime.utc(2026, 10, 29, 12, clockGeneration),
    )..start();
    final result = _App(disk, store, client, engine, chat);
    addTearDown(result.close);
    return result;
  }

  TrainingPlan hostPlan(String id, {String? title}) {
    final equipment = {
      for (final action in CoachV2Fixtures.stretching)
        ...fixture.catalog[action]!.equipment,
    }.toList()..sort();
    final plan = TrainingPlan(
      id: 'host-$id',
      source: 'template',
      title: title ?? '保存前的计划 $id',
      summary: '完整保留动作顺序、左右侧和剂量。',
      goal: 'relax',
      scene: 'home',
      equipment: equipment,
      level: 1,
      targetMinutes: 10,
      blocks: [
        PlanBlock(
          id: 'saved-main',
          name: '主练',
          type: BlockType.main,
          rounds: 1,
          restBetweenRoundsSeconds: 0,
          items: [
            for (final id in CoachV2Fixtures.stretching)
              PlanItem(
                exerciseId: id,
                mode:
                    fixture.catalog[id]!.defaultDose.mode == coach.DoseMode.reps
                    ? DoseMode.reps
                    : DoseMode.time,
                sets: 1,
                workSeconds:
                    fixture.catalog[id]!.defaultDose.mode == coach.DoseMode.time
                    ? fixture.catalog[id]!.defaultDose.seconds ?? 30
                    : null,
                reps:
                    fixture.catalog[id]!.defaultDose.mode == coach.DoseMode.reps
                    ? fixture.catalog[id]!.defaultDose.reps ?? 8
                    : null,
                perSide: fixture.catalog[id]!.unilateral,
                restSeconds: 10,
              ),
          ],
        ),
      ],
    );
    final decoded = const coach.PlanCodec().decodeStrict(plan.toJson());
    expect(decoded.ok, isTrue, reason: '${decoded.issues}');
    final report =
        coach.PlanValidator(
          catalog: fixture.catalog,
          profile: fixture.profile,
        ).validate(
          decoded.plan!,
          coach.CoachContext(
            scene: plan.scene,
            equipment: equipment.toSet(),
            minutes: plan.targetMinutes,
            level: plan.level,
            goal: plan.goal,
          ),
        );
    expect(report.ok, isTrue, reason: '${report.errors}');
    return plan;
  }

  Future<SavedPlan> keep(_App value, String id) => value.store.savePlan(
    hostPlan(id),
    name: '我的计划 $id',
    sdkVersion: 1,
    now: DateTime.utc(2026, 10, 29, 1, id.codeUnitAt(0)),
  );

  void completeSummary(Object? raw, SavedPlan saved, {required int version}) {
    expect(raw, isA<Map>());
    final focus = raw! as Map;
    expect(focus['plan_id'], 'ext:${saved.id}');
    expect(focus['title'], saved.name);
    expect(focus['version'], version);
    expect(focus['equipment'], saved.plan.equipment);
    expect(focus['estimateSec'], greaterThan(0));
    final rows = focus['items'] as List;
    final items = saved.plan.items.toList();
    expect(rows, hasLength(items.length));
    for (var index = 0; index < items.length; index++) {
      final row = rows[index] as Map;
      expect(row['index'], index + 1);
      expect(row['actionId'], items[index].exerciseId);
      expect(
        row['name'],
        fixture.catalog[items[index].exerciseId]!.name.of('zh'),
      );
      final dose = row['dose'] as Map;
      for (final entry in items[index].toJson().entries) {
        if (entry.key != 'exerciseId') expect(dose[entry.key], entry.value);
      }
    }
  }

  List<Object> editScript(
    String savedId, {
    String prefix = 'focus-edit',
    String newAction = _freshAction,
    int expectedVersion = 2,
  }) => [
    CoachV2Fixtures.batch([
      CoachV2Fixtures.call('$prefix-start', 'start_task', {
        'type': 'plan',
        'reuse': true,
      }),
      CoachV2Fixtures.call('$prefix-params', 'set_params', {
        'fields': {'operation': CoachV2Fixtures.sourced('edit', '换掉第3个动作')},
      }),
      CoachV2Fixtures.call('$prefix-search', 'search_actions', {
        'tags': <String>[],
        'keywords': fixture.catalog[newAction]!.name.of('en'),
      }),
    ]),
    (coach.LlmRequest request) {
      final params = CoachV2Fixtures.receipt(request, '$prefix-params');
      expect(params['ok'], isTrue, reason: '$params');
      final search = CoachV2Fixtures.receipt(request, '$prefix-search');
      expect(search['ok'], isTrue, reason: '$search');
      return CoachV2Fixtures.batch([
        CoachV2Fixtures.call('$prefix-draft', 'draft_plan', {
          'plan_id': 'ext:$savedId',
          'title': '更新后的放松计划',
          'blocks': [
            {
              'kind': 'main',
              'items': [
                {'id': CoachV2Fixtures.stretching[0], 'sourceIndex': 1},
                {'id': CoachV2Fixtures.stretching[1], 'sourceIndex': 2},
                {'id': newAction},
              ],
            },
          ],
        }),
      ]);
    },
    (coach.LlmRequest request) {
      final draft = CoachV2Fixtures.receipt(request, '$prefix-draft');
      expect(draft['ok'], isTrue, reason: '$draft');
      expect(draft['plan_id'], 'ext:$savedId');
      expect(draft['version'], expectedVersion);
      return CoachV2Fixtures.batch([
        CoachV2Fixtures.call('$prefix-planning', 'check', {'node': 'planning'}),
        CoachV2Fixtures.call('$prefix-checked', 'check_plan', {
          'plan_id': 'ext:$savedId',
        }),
      ]);
    },
    (coach.LlmRequest request) {
      final checked = CoachV2Fixtures.receipt(request, '$prefix-checked');
      expect(checked['ok'], isTrue, reason: '$checked');
      return CoachV2Fixtures.batch([
        CoachV2Fixtures.call('$prefix-review', 'check', {'node': 'review'}),
        CoachV2Fixtures.call('$prefix-show', 'show_plan', {
          'plan_id': 'ext:$savedId',
          'note': '已更新当前讨论计划的第3个动作。',
        }),
      ]);
    },
  ];

  Future<ChatMessage> edit(_App value) async {
    await value.chat.send('换掉第3个动作');
    await value.chat.flushPersistence();
    expect(
      value.engine.lastResult?.status,
      coach.TurnStatus.ok,
      reason:
          '${value.engine.lastResult?.issues}; ${value.engine.lastResult?.error}',
    );
    final card = _lastVersionedCard(value);
    expect(card.validatedPlan!.version, 2);
    expect(card.plan!.items.last.exerciseId, _freshAction);
    return card;
  }

  test(
    'showSaved imports locally and the next model request gets the complete selected plan',
    () async {
      final value = await app(['这是当前讨论的放松计划。']);
      final saved = await keep(value, 'B');
      await value.chat.showSaved(saved);
      expect(value.client.requests, isEmpty);
      expect(value.chat.planFocus!.savedRef.externalId, saved.id);
      expect(value.chat.planFocus!.title, saved.name);
      expect(value.chat.planFocus!.version, 1);
      expect(
        value.chat.messages.where(
          (message) => message.plan?.id == saved.plan.id,
        ),
        isNotEmpty,
        reason: 'Selecting a plan retains the ordinary local display card.',
      );
      final selection = value.engine.agent.history.lastWhere(
        (message) => message.content.startsWith(_selectionPrefix),
      );
      expect(selection.role, coach.LlmRole.user);
      completeSummary(
        jsonDecode(selection.content.substring(_selectionPrefix.length)),
        saved,
        version: 1,
      );
      expect(value.snapshot.sessionState.focusPlanId, 'ext:${saved.id}');

      await value.chat.send('这是什么计划');
      completeSummary(
        _tail(value.client.requests.first)['focus_plan'],
        saved,
        version: 1,
      );
      expect(value.chat.messages.last.text, '这是当前讨论的放松计划。');
    },
  );

  test(
    'showSaved waits for a delayed display write and the ordered focus snapshot',
    () async {
      final storage = _DelayedDisplayStorage();
      final value = await app([], storage: storage);
      final saved = await keep(value, 'B');
      storage.watchedPlanId = saved.plan.id;
      addTearDown(() {
        if (!storage.release.isCompleted) storage.release.complete();
      });
      var finished = false;
      final selection = value.chat.showSaved(saved).then((_) {
        finished = true;
      });
      await storage.started.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(Duration.zero);
      expect(
        finished,
        isFalse,
        reason:
            'Selection cannot return while an older display write is pending.',
      );

      storage.release.complete();
      await selection.timeout(const Duration(seconds: 3));
      expect(finished, isTrue);
      expect(storage.completed.length, greaterThanOrEqualTo(2));
      final durable = jsonDecode(storage.values[AppStore.key]!) as Map;
      final snapshot = coach.CoachSessionSnapshot.fromJson(
        jsonDecode(durable['coachSessionJson'] as String),
      );
      expect(snapshot.isValid, isTrue);
      expect(snapshot.sessionState.focusPlanId, 'ext:${saved.id}');
      expect(snapshot.sessionState.savedRef!.externalId, saved.id);
      expect(value.client.requests, isEmpty);
    },
  );

  test(
    'selecting B after A edits B and keeps A and its saved contents unchanged',
    () async {
      final disk = _MemoryStorage();
      final seed = AppStore(disk);
      final a = await seed.savePlan(
        hostPlan('A'),
        name: '我的计划 A',
        sdkVersion: 1,
      );
      final b = await seed.savePlan(
        hostPlan('B'),
        name: '我的计划 B',
        sdkVersion: 1,
      );
      seed.dispose();
      final value = await app(editScript(b.id), storage: disk);
      await value.chat.showSaved(a);
      final firstPlan = jsonEncode(
        value.engine.agent.sessionState.plans['ext:${a.id}']!
            .map((version) => version.toJson())
            .toList(),
      );
      await value.chat.showSaved(b);
      final card = await edit(value);
      expect(card.plan!.id, 'ext:${b.id}');
      expect(card.validatedPlan!.savedRef!.externalId, b.id);
      expect(value.chat.savedTargetFor(card)!.id, b.id);
      expect(value.chat.planFocus!.planId, 'ext:${b.id}');
      expect(value.chat.planFocus!.version, 2);
      expect(
        jsonEncode(
          value.engine.agent.sessionState.plans['ext:${a.id}']!
              .map((version) => version.toJson())
              .toList(),
        ),
        firstPlan,
      );
      expect(
        value.store.savedPlans
            .singleWhere((saved) => saved.id == a.id)
            .plan
            .toJson(),
        a.plan.toJson(),
      );
      expect(
        value.store.savedPlans
            .singleWhere((saved) => saved.id == b.id)
            .plan
            .toJson(),
        b.plan.toJson(),
      );
      for (final request in value.client.requests) {
        expect((_tail(request)['focus_plan'] as Map)['plan_id'], 'ext:${b.id}');
      }
    },
  );

  test(
    'a new App process restores focus from disk before sending another turn',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'smartfit-focus-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final storage = _DiskStorage(directory);
      final first = await app([], storage: storage);
      final saved = await keep(first, 'B');
      await first.chat.showSaved(saved);
      final persisted = await storage.read(AppStore.key);
      expect(persisted, contains('focusPlanId'));
      final focus = first.chat.planFocus!.toJson();
      await first.close();

      final restored = await app(['恢复后仍在讨论刚才的计划。'], storage: storage);
      expect(restored.client.requests, isEmpty);
      expect(restored.chat.planFocus!.toJson(), focus);
      expect(restored.snapshot.isValid, isTrue);
      await restored.chat.send('这是什么计划');
      completeSummary(
        _tail(restored.client.requests.first)['focus_plan'],
        saved,
        version: 1,
      );
    },
  );

  test(
    'a fresh-session AI saved display stays saved without losing its SDK version',
    () async {
      final value = await app([]);
      final plan = TrainingPlan.fromJson({
        ...hostPlan('saved-ai').toJson(),
        'source': 'ai',
      });
      final saved = await value.store.savePlan(
        plan,
        name: '已经保存的 AI 计划',
        sdkVersion: 1,
      );
      await value.chat.showSaved(saved);
      final card = value.chat.messages.singleWhere(
        (message) => message.isSavedPlanDisplay && message.plan?.id == plan.id,
      );
      expect(card.validatedPlan, isNotNull);
      expect(card.planSavedRef, isNull);
      expect(value.chat.isPlanCardSaved(card), isTrue);
      expect(value.chat.planFocus!.savedRef.externalId, saved.id);
      expect(value.client.requests, isEmpty);

      final kept = await value.chat.savePlanCard(card);
      expect(kept.id, saved.id);
      expect(kept.sdkVersion, 1);
      expect(value.store.savedPlans, hasLength(1));
      expect(value.store.savedPlans.single.sdkVersion, 1);
      final persisted =
          jsonDecode((await value.storage.read(AppStore.key))!) as Map;
      expect((persisted['savedPlans'] as List).single['sdkVersion'], 1);
      final storage = value.storage;
      await value.close();

      final restored = await app([], storage: storage);
      final restoredCard = restored.chat.messages.singleWhere(
        (message) => message.isSavedPlanDisplay && message.plan?.id == plan.id,
      );
      expect(restored.chat.isPlanCardSaved(restoredCard), isTrue);
      expect((await restored.chat.savePlanCard(restoredCard)).sdkVersion, 1);
      expect(restored.store.savedPlans.single.sdkVersion, 1);
    },
  );

  test(
    'saving an edited card updates its source, preserves metadata and allows a separate copy',
    () async {
      final disk = _MemoryStorage();
      final seed = AppStore(disk);
      final saved = await seed.savePlan(
        hostPlan('B'),
        name: '用户命名的午休计划',
        sdkVersion: 1,
        now: DateTime.utc(2026, 10, 28),
      );
      final usedAt = DateTime.utc(2026, 10, 29, 2);
      await seed.touchPlan(saved.id, now: usedAt);
      seed.dispose();
      final value = await app(editScript(saved.id), storage: disk);
      await value.chat.showSaved(value.store.savedPlans.single);
      final card = await edit(value);
      expect(value.chat.isPlanCardSaved(card), isFalse);
      expect(value.chat.savedTargetFor(card)!.id, saved.id);
      final updated = await value.chat.savePlanCard(card);
      expect(updated.id, saved.id);
      expect(updated.name, saved.name);
      expect(updated.savedAt, saved.savedAt);
      expect(updated.lastUsedAt, usedAt);
      expect(updated.sdkVersion, 2);
      expect(updated.plan.toJson(), card.plan!.toJson());
      expect(value.store.savedPlans, hasLength(1));
      expect(value.chat.isPlanCardSaved(card), isTrue);
      expect((await value.chat.savePlanCard(card)).id, saved.id);

      final copy = await value.chat.savePlanCard(card, saveAsCopy: true);
      expect(copy.id, isNot(saved.id));
      expect(copy.name, '${saved.name} 新版');
      expect(copy.sdkVersion, 2);
      expect(copy.plan.toJson(), updated.plan.toJson());
      expect(value.store.savedPlans, hasLength(2));
      expect(value.chat.isPlanCardSaved(card), isTrue);
      await value.chat.flushPersistence();
      await value.close();

      final restored = await app([], storage: disk);
      final restoredCard = _lastVersionedCard(restored);
      expect(restoredCard.planVersion, 2);
      expect(restored.chat.savedTargetFor(restoredCard)!.id, saved.id);
      expect(restored.chat.isPlanCardSaved(restoredCard), isTrue);
    },
  );

  test(
    'an edited card with a deleted source falls back to an ordinary save',
    () async {
      final disk = _MemoryStorage();
      final seed = AppStore(disk);
      final source = await seed.savePlan(
        hostPlan('B'),
        name: '会被删除的计划',
        sdkVersion: 1,
      );
      seed.dispose();
      final value = await app(editScript(source.id), storage: disk);
      await value.chat.showSaved(source);
      final card = await edit(value);
      await value.store.deletePlan(source.id);
      expect(value.chat.savedTargetFor(card), isNull);
      final saved = await value.chat.savePlanCard(card);
      expect(saved.id, isNot(source.id));
      expect(saved.name, card.plan!.title);
      expect(saved.sdkVersion, 2);
      expect(saved.plan.toJson(), card.plan!.toJson());
      expect(value.store.savedPlans, hasLength(1));
      expect(value.chat.isPlanCardSaved(card), isTrue);
    },
  );

  test(
    'an invalid saved plan is still displayed with a hint and cannot replace focus',
    () async {
      final value = await app([]);
      final good = await keep(value, 'A');
      await value.chat.showSaved(good);
      final focus = value.chat.planFocus!.toJson();
      final facts = jsonEncode(value.engine.agent.sessionState.toJson());
      final goodPlan = hostPlan('bad');
      final invalid = goodPlan.copyWith(
        blocks: [
          goodPlan.blocks.single.copyWith(
            items: [
              goodPlan.items.first.copyWith(exerciseId: 'unknown-saved-action'),
            ],
          ),
        ],
      );
      final bad = await value.store.savePlan(invalid, name: '坏计划');
      final before = value.chat.messages.length;
      await value.chat.showSaved(bad);
      expect(value.client.requests, isEmpty);
      expect(value.chat.planFocus!.toJson(), focus);
      expect(jsonEncode(value.engine.agent.sessionState.toJson()), facts);
      final appended = value.chat.messages.skip(before).toList();
      expect(appended.any((message) => message.plan?.id == invalid.id), isTrue);
      expect(
        appended.any(
          (message) =>
              !message.isUser &&
              !message.isPlan &&
              message.text.contains('计划') &&
              RegExp('无法|未能|失败|暂时').hasMatch(message.text),
        ),
        isTrue,
        reason:
            'The visible local card must explain that AI focus was not updated.',
      );
      expect(value.snapshot.sessionState.focusPlanId, 'ext:${good.id}');
    },
  );

  test(
    'a rejected AI saved card remains readable after a process restart',
    () async {
      final value = await app([]);
      final good = await keep(value, 'A');
      await value.chat.showSaved(good);
      final focus = value.chat.planFocus!.toJson();
      final invalid = TrainingPlan.fromJson({
        ...hostPlan('invalid-ai').toJson(),
        'source': 'ai',
        'blocks': [
          {
            ...hostPlan('invalid-ai').blocks.single.toJson(),
            'items': [
              {
                ...hostPlan('invalid-ai').items.first.toJson(),
                'exerciseId': 'unknown-saved-action',
              },
            ],
          },
        ],
      });
      final saved = await value.store.savePlan(invalid, name: '旧版本的 AI 计划');
      await value.chat.showSaved(saved);
      final card = value.chat.messages.lastWhere(
        (message) => message.plan?.id == invalid.id,
      );
      expect(card.isSavedPlanDisplay, isTrue);
      expect(card.validatedPlan, isNull);
      expect(value.chat.planFocus!.toJson(), focus);
      expect(value.chat.messages.last.text, '这套计划暂时无法在对话里编辑');
      final disk = value.storage;
      await value.close();
      final restored = await app([], storage: disk);
      final restoredCard = restored.chat.messages.lastWhere(
        (message) => message.plan?.id == invalid.id,
      );
      expect(restoredCard.isSavedPlanDisplay, isTrue);
      expect(restoredCard.validatedPlan, isNull);
      expect(restored.chat.planFocus!.toJson(), focus);
      expect(restored.client.requests, isEmpty);
    },
  );

  test(
    'historical card provenance survives a newer edit and rejects forged metadata',
    () async {
      final disk = _MemoryStorage();
      final seed = AppStore(disk);
      final a = await seed.savePlan(
        hostPlan('A'),
        name: '不能被错误覆盖的 A',
        sdkVersion: 1,
      );
      final b = await seed.savePlan(
        hostPlan('B'),
        name: '正在编辑的 B',
        sdkVersion: 1,
      );
      seed.dispose();
      final value = await app([
        ...editScript(b.id, prefix: 'history-v2'),
        ...editScript(
          b.id,
          prefix: 'history-v3',
          newAction: 'h-adductor-rock',
          expectedVersion: 3,
        ),
      ], storage: disk);
      await value.chat.showSaved(b);
      final v2 = await edit(value);
      await value.chat.send('换掉第3个动作');
      await value.chat.flushPersistence();
      final v3 = _lastVersionedCard(value);
      expect(v3.planVersion, 3);
      expect(v3.plan!.items.last.exerciseId, 'h-adductor-rock');
      expect(v3.planSavedRef!.externalId, b.id);
      await value.close();
      final baseline = disk.values[AppStore.key]!;

      final restored = await app([], storage: disk);
      final oldCard = restored.chat.messages.singleWhere((m) => m.id == v2.id);
      final newCard = restored.chat.messages.singleWhere((m) => m.id == v3.id);
      expect(oldCard.plan!.toJson(), v2.plan!.toJson());
      expect(oldCard.planVersion, 2);
      expect(oldCard.planSavedRef!.externalId, b.id);
      expect(restored.chat.savedTargetFor(oldCard)!.id, b.id);
      expect(newCard.planVersion, 3);
      expect(newCard.planSavedRef!.externalId, b.id);
      await restored.close();

      for (final forged in <Map<String, Object?>>[
        {
          'sdkVersion': 2,
          'savedRef': {'externalId': a.id, 'baseVersion': 1},
        },
        {
          'sdkVersion': 3,
          'savedRef': {'externalId': b.id, 'baseVersion': 1},
        },
      ]) {
        final state = jsonDecode(baseline) as Map<String, dynamic>;
        final rows = state['chat'] as List;
        final index = rows.indexWhere((row) => (row as Map)['id'] == v2.id);
        rows[index] = {...rows[index] as Map, ...forged};
        disk.values[AppStore.key] = jsonEncode(state);
        final checked = await app([], storage: disk);
        final historical = checked.chat.messages.singleWhere(
          (message) => message.id == v2.id,
        );
        expect(historical.plan!.toJson(), v2.plan!.toJson());
        expect(historical.planVersion, isNot(3));
        expect(historical.planSavedRef?.externalId, isNot(a.id));
        expect(checked.chat.savedTargetFor(historical)?.id, isNot(a.id));
        expect(
          checked.store.savedPlans
              .singleWhere((saved) => saved.id == a.id)
              .toJson(),
          a.toJson(),
        );
        expect(checked.chat.planFocus!.planId, 'ext:${b.id}');
        expect(checked.client.requests, isEmpty);
        await checked.close();
      }
    },
  );

  test(
    'production disposal order persists focus before the SDK resets its session',
    () async {
      final storage = _DelayedDisplayStorage();
      final seed = AppStore(storage);
      final saved = await seed.savePlan(
        hostPlan('B'),
        name: '关闭前的计划',
        sdkVersion: 1,
      );
      seed.dispose();
      final value = await app(editScript(saved.id), storage: storage);
      await value.chat.showSaved(saved);
      await edit(value);
      final planId = value.chat.planFocus!.planId;
      expect(value.chat.planFocus!.version, 2);
      storage.watchedPlanId = saved.plan.id;
      addTearDown(() async {
        if (!storage.release.isCompleted) storage.release.complete();
        if (storage.started.isCompleted) {
          await storage.finished.future.timeout(const Duration(seconds: 3));
        }
      });

      // Follow AppServices exactly: it does not await a second persistence call
      // between disposing ChatController and disposing its SDK-owned engine.
      value._closed = true;
      value.chat.dispose();
      value.engine.dispose();
      value.store.dispose();
      expect(value.engine.agent.sessionState.focusPlanId, isNull);
      await storage.started.future.timeout(const Duration(seconds: 3));
      storage.release.complete();
      await storage.finished.future.timeout(const Duration(seconds: 3));

      final durable = jsonDecode(storage.values[AppStore.key]!) as Map;
      final snapshot = coach.CoachSessionSnapshot.fromJson(
        jsonDecode(durable['coachSessionJson'] as String),
      );
      expect(snapshot.isValid, isTrue);
      expect(snapshot.sessionState.focusPlanId, planId);
      expect(snapshot.sessionState.savedRef!.externalId, saved.id);
      expect(snapshot.sessionState.plans[planId], hasLength(2));
      expect(snapshot.sessionState.plans[planId]!.last.version, 2);
    },
  );

  test(
    'clearing focus cancels a waiting turn and persists without late delivery',
    () async {
      final entered = Completer<void>();
      final pending = Completer<Object>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete('已取消。');
      });
      final value = await app([
        (coach.LlmRequest request) {
          entered.complete();
          return pending.future;
        },
        '现在可以聊其他训练问题。',
      ]);
      final saved = await keep(value, 'B');
      await value.chat.showSaved(saved);
      expect(value.chat.planFocus!.savedRef.externalId, saved.id);
      final task = value.chat.send('解释这个计划');
      await entered.future;
      expect(value.chat.typing, isTrue);
      await value.chat.clearPlanFocus();
      expect(value.chat.typing, isFalse);
      expect(value.chat.planFocus, isNull);
      await task.timeout(const Duration(seconds: 2));
      await value.chat.flushPersistence();
      expect(value.snapshot.sessionState.focusPlanId, isNull);
      expect(value.snapshot.sessionState.savedRef, isNull);

      await value.chat.send('说说日常活动');
      expect(
        _tail(value.client.requests.last).containsKey('focus_plan'),
        isFalse,
      );
      final displayed = jsonEncode(
        value.chat.messages.map((message) => message.toJson()).toList(),
      );
      pending.complete('迟到的计划回复，不得重新显示。');
      await Future<void>.delayed(Duration.zero);
      await value.chat.flushPersistence();
      expect(value.chat.planFocus, isNull);
      expect(
        jsonEncode(
          value.chat.messages.map((message) => message.toJson()).toList(),
        ),
        displayed,
      );
      expect(value.snapshot.sessionState.focusPlanId, isNull);
      final disk = value.storage;
      await value.close();
      final restored = await app([], storage: disk);
      expect(restored.chat.planFocus, isNull);
      expect(restored.snapshot.sessionState.savedRef, isNull);
    },
  );
}
