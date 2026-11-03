import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_ai_tags.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';
import 'support/coach_v2_fixtures.dart';
import 'support/widget_test_timeout.dart';

coach.LlmResponse _tool(String name, Map<String, Object?> args) =>
    CoachV2Fixtures.batch([CoachV2Fixtures.call(name, name, args)]);

coach.LlmResponse _form({
  String intent = 'actions',
  String place = 'unknown',
  String next = 'answer',
  bool equipmentKnown = false,
  List<String> equipment = const [],
  String status = 'none',
  List<String> types = const ['static-stretch'],
}) => _tool('fill_form', {
  'language': 'zh',
  'intent': intent,
  'place': place,
  'place_word': place == 'home' ? '居家' : place,
  'equipment_known': equipmentKnown,
  'equipment': equipment,
  'muscles': ['adductors'],
  'types': types,
  'answer_status': status,
  'next': next,
  if (intent == 'plan') 'minutes': 15,
});

List<String> _candidates(coach.LlmRequest request) => RegExp(
  r'^([A-Za-z0-9_-]+) \| ',
  multiLine: true,
).allMatches(request.messages.last.content).map((m) => m[1]!).take(3).toList();

Future<void> _pump(WidgetTester tester) async {
  for (var index = 0; index < 3; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  configureWidgetTestTimeout();
  late CoachV2Fixtures fixture;
  late Map<String, Map<String, Object?>> tags;
  setUpAll(() async {
    fixture = CoachV2Fixtures.loadSync();
    tags = await loadAppAiTags();
  });

  Future<(AppServices, CoachChatController, coach.FakeLlmClient)> open(
    List<Object> script, {
    MemoryStorage? disk,
    WidgetTester? tester,
  }) async {
    final store = AppStore(disk ?? MemoryStorage());
    await store.load();
    await store.acceptSafety(blocked: false);
    await store.setStarfield(false);
    final services = AppServices(
      library: fixture.library,
      catalog: loadCatalog(),
      store: store,
      coachCatalog: fixture.catalog,
      coachProfile: fixture.profile,
      poseHubCatalog: fixture.poseHub,
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
      chatReplyDelay: Duration.zero,
      agentMode: CoachChatAgentMode.qaV2,
      appAiTags: tags,
    );
    final client = coach.FakeLlmClient(script, latency: Duration.zero);
    final chat = createSmartfitChat(
      services,
      gateway: CoachGatewayBinding.shared(client),
      clock: () => DateTime(2026, 11, 4, 12),
    );
    expect((await chat.start()).ok, isTrue);
    expect(chat.profile.agentMode, CoachChatAgentMode.qaV2);
    expect(chat.profile.aiTags, tags);
    addTearDown(() async {
      if (tester == null) {
        await chat.close();
      } else {
        var closed = false;
        unawaited(chat.close().then((_) => closed = true));
        for (var index = 0; index < 10 && !closed; index++) {
          await _pump(tester);
        }
        expect(closed, isTrue, reason: 'The native SDK controller must close');
      }
      chat.dispose();
      await services.dispose();
      store.dispose();
    });
    return (services, chat, client);
  }

  Future<void> mount(
    WidgetTester tester,
    AppServices services,
    CoachChatController chat,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildTheme(),
          home: ChatHomePage(controller: chat),
        ),
      ),
    );
    await _pump(tester);
    expect(find.byType(CoachChatPage), findsOneWidget);
  }

  Future<(AppServices, CoachChatController, coach.FakeLlmClient)> openOn(
    WidgetTester tester,
    List<Object> script, {
    MemoryStorage? disk,
  }) async =>
      (await tester.runAsync(() => open(script, disk: disk, tester: tester)))!;

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await _pump(tester);
  }

  test(
    'App tag loader preserves all 249 raw drafts and provenance hash',
    () async {
      final provenance =
          jsonDecode(
                File('assets/coach/ai-tags/provenance.json').readAsStringSync(),
              )
              as Map;
      final data = (await rootBundle.load(
        'assets/coach/ai-tags/actions.json',
      )).buffer.asUint8List();
      final aggregate = provenance['aggregate'] as Map;
      expect(tags, hasLength(249));
      expect(tags, jsonDecode(utf8.decode(data)));
      expect(sha256.convert(data).toString(), aggregate['sha256']);
      expect(data.length, aggregate['bytes']);
      expect(tags.length, aggregate['actionCount']);
      expect(provenance['reviewed'], isFalse);
      expect(provenance['testOnly'], isTrue);
      expect(
        tags.values.every((value) => value['status'] == 'ai-draft'),
        isTrue,
      );
      expect(() => tags['new'] = {}, throwsUnsupportedError);
    },
  );

  testWidgets(
    'native QA asks single/multiple choices, numbers cards and sends chips',
    (tester) async {
      final (services, chat, client) = await openOn(tester, [
        _form(next: 'ask_place'),
        _tool('ask_user', {
          'question': '这次在哪里练？',
          'options': ['居家', '健身房', '办公室', '直接推荐'],
        }),
        _form(place: 'home', status: 'answered', next: 'ask_equipment'),
        _tool('ask_user', {
          'question': '手边有哪些器械？',
          'options': ['哑铃', '瑜伽垫', '椅子', '弹力带', '徒手', '直接推荐'],
        }),
        _form(
          place: 'home',
          equipmentKnown: true,
          equipment: const ['dumbbell', 'mat'],
          status: 'answered',
        ),
        (coach.LlmRequest request) => _tool('respond', {
          'text': '按你的条件选择了这些动作。',
          'items': [
            for (final id in _candidates(request).take(2))
              {'id': id, 'why': '适合当前条件'},
          ],
          'chips': ['换场地'],
        }),
        _form(intent: 'change_place', place: 'home', next: 'ask_place'),
        _tool('ask_user', {
          'question': '换到哪里练？',
          'options': ['居家', '健身房', '办公室', '直接推荐'],
        }),
      ]);
      await mount(tester, services, chat);
      await say(tester, '推荐内收肌拉伸动作');
      final place = chat.messages.last;
      expect(place.question!.multiple, isFalse);
      await tester.tap(find.byKey(ValueKey('question-option-${place.id}-0')));
      await _pump(tester);
      final equipment = chat.messages.last;
      expect(equipment.question!.multiple, isTrue);
      expect(
        chat.canAnswerQuestion(
          chat.messages.firstWhere((m) => m.id == place.id),
        ),
        isFalse,
      );
      for (final index in [0, 1]) {
        final choice = find.byKey(
          ValueKey('question-option-${equipment.id}-$index'),
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await _pump(tester);
      }
      expect(
        client.requests,
        hasLength(4),
        reason: 'Multi-select waits for Submit',
      );
      final submit = find.byKey(ValueKey('question-submit-${equipment.id}'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await _pump(tester);
      expect(
        chat.lastResult?.status,
        coach.TurnStatus.ok,
        reason: '${chat.lastResult?.error}',
      );
      expect(chat.messages.where((m) => m.isUser).last.text, '哑铃、瑜伽垫');
      expect(find.byKey(const ValueKey('recommend-number-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('recommend-number-2')), findsOneWidget);
      final card = tester.widget<CoachRecommendCard>(
        find.byType(CoachRecommendCard),
      );
      expect(card.actionIds, chat.lastQaReply!.cards.map((c) => c.id));
      final recommendation = chat.messages.last;
      final chip = find.byKey(
        ValueKey('coach-quick-action-${recommendation.id}-0'),
      );
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await _pump(tester);
      expect(chat.messages.where((m) => m.isUser).last.text, '换场地');
      expect(find.text('换到哪里练？'), findsOneWidget);
      expect(client.requests, hasLength(8));
      for (final request in client.requests) {
        expect(request.extraBody['reasoning_effort'], 'max');
        expect(request.extraBody['thinking'], {'type': 'enabled'});
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  // Known SDK product issue: gym QA does not declare the equipment used by
  // its generated plan. This regression verifies rejection, not a gym fix.
  // The original positive failure and exact diagnostic are preserved in
  // deliveries/sdk-pin-v0.7.1-9dd9316-plus18-20261104/gym-plan-admission-issue.json.
  testWidgets(
    'rejects SDK QA gym plan lacking required equipment declarations',
    (tester) async {
      var selectedIds = <String>[];
      final (services, chat, _) = await openOn(tester, [
        _form(intent: 'plan', place: 'gym', types: const ['strength']),
        (coach.LlmRequest request) {
          selectedIds = _candidates(request);
          return _tool('build_plan', {
            'main_ids': selectedIds,
            'minutes': 15,
            'title': '力量训练',
            'block_names': {'warmup': '热身', 'main': '主训练', 'cooldown': '收操'},
            'text': '按你的条件安排好了。',
            'chips': ['换第一个'],
          });
        },
      ]);
      await mount(tester, services, chat);
      await say(tester, '健身房练内收肌力量十五分钟');
      expect(selectedIds, [
        'adductors-B',
        'h-band-standing-adduction',
        'h-lateral-step-lunge',
      ]);
      expect(chat.lastResult?.status, coach.TurnStatus.error);
      expect(
        '${chat.lastResult?.error}',
        contains('QA output failed the App action/plan admission gate'),
      );
      expect(chat.lastQaReply, isNull);
      expect(chat.messages.where((message) => message.plan != null), isEmpty);
      expect(find.byType(CoachPlanCard), findsNothing);
      expect(services.store.savedPlans, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native QA home plan keeps all section numbers and host save behavior',
    (tester) async {
      final (services, chat, _) = await openOn(tester, [
        _form(
          intent: 'plan',
          place: 'home',
          equipmentKnown: true,
          equipment: const ['dumbbell', 'mat', 'chair', 'band'],
          types: const ['strength'],
        ),
        (coach.LlmRequest request) => _tool('build_plan', {
          'main_ids': _candidates(request),
          'minutes': 15,
          'title': '力量训练',
          'block_names': {'warmup': '热身', 'main': '主训练', 'cooldown': '收操'},
          'text': '按你的条件安排好了。',
          'chips': ['换第一个'],
        }),
      ]);
      await mount(tester, services, chat);
      await say(tester, '在家用哑铃、瑜伽垫、椅子、弹力带练内收肌十五分钟');
      expect(
        chat.lastResult?.status,
        coach.TurnStatus.ok,
        reason: '${chat.lastResult?.error}',
      );
      final reply = chat.lastQaReply!;
      expect(reply.plan!.blocks.first.type, coach.BlockType.warmup);
      expect(reply.plan!.blocks.last.type, coach.BlockType.cooldown);
      final plan = chat.messages.last.plan!;
      final expand = find.byKey(ValueKey('plan-expand-${plan.id}'));
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await _pump(tester);
      final expanded = tester.widget<CoachPlanExpanded>(
        find.byType(CoachPlanExpanded),
      );
      expect(
        expanded.plan.items.map((item) => item.exerciseId),
        reply.planOrderedIds,
      );
      final rows = [
        for (var index = 0; index < reply.planOrderedIds.length; index++)
          find.byKey(ValueKey('plan-row-$index')),
      ];
      for (var index = 0; index < rows.length; index++) {
        expect(rows[index], findsOneWidget);
        expect(
          find.descendant(of: rows[index], matching: find.text('${index + 1}')),
          findsOneWidget,
        );
      }
      final save = find.byKey(ValueKey('plan-save-${plan.id}'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _pump(tester);
      expect(services.store.savedPlans, hasLength(1));
      expect(
        services.store.savedPlans.single.plan.items.map(
          (item) => item.exerciseId,
        ),
        reply.planOrderedIds,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native QA restores pending host snapshot and New conversation resets it',
    (tester) async {
      final disk = MemoryStorage();
      final (_, first, _) = await openOn(tester, [
        _form(next: 'ask_place'),
        _tool('ask_user', {
          'question': '准备在哪里练？',
          'options': ['居家', '办公室'],
        }),
      ], disk: disk);
      await tester.runAsync(() async {
        await first.send('推荐拉伸动作');
        await first.flushPersistence();
      });
      final original = first.exportSnapshot().qaState;
      await tester.runAsync(first.close);
      final (services, restored, client) = await openOn(tester, [], disk: disk);
      expect(restored.exportSnapshot().qaState, original);
      expect(client.requests, isEmpty);
      await mount(tester, services, restored);
      expect(find.text('准备在哪里练？'), findsOneWidget);
      expect(restored.canAnswerQuestion(restored.messages.last), isTrue);
      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await _pump(tester);
      await tester.tap(find.text('新对话'));
      await _pump(tester);
      expect(restored.qaAgent.state.lastAsk, isNull);
      expect(restored.qaAgent.state.place, isNull);
      expect(
        restored.messages.any((message) => message.question != null),
        isFalse,
      );
      expect(client.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
