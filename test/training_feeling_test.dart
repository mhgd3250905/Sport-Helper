import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'support.dart';
import 'support/coach_v2_fixtures.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  var failures = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failures > 0) {
      failures--;
      throw StateError('private storage details must never enter diagnostics');
    }
    values[key] = value;
  }
}

AppServices _services(_Storage storage) => AppServices(
  library: loadLibrary(),
  catalog: loadCatalog(),
  store: AppStore(storage)
    ..starfield = false
    ..voice = const VoiceSettings(voice: false, chimes: false),
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
  chatReplyDelay: Duration.zero,
);

trainer.SessionResult _receipt({trainer.TrainingFeeling? feeling}) =>
    trainer.SessionResult(
      sessionId: 'private-feedback-session',
      planId: 'private-feedback-plan',
      planTitle: 'private-training-title',
      startedAt: DateTime.utc(2026, 10, 29, 1),
      endedAt: DateTime.utc(2026, 10, 29, 1, 2),
      activeSeconds: 121,
      endedEarly: false,
      completedExercises: 1,
      totalExercises: 1,
      items: const [],
      feeling: feeling,
    );

const _plan = TrainingPlan(
  id: 'feeling-player-plan',
  source: 'template',
  title: '完成感受验证',
  summary: '',
  goal: 'mixed',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-forearm-plank',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 2,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

List<Map<String, dynamic>> _events(RuntimeLog log) =>
    (jsonDecode(log.exportJson())['events'] as List)
        .cast<Map<String, dynamic>>();

Future<void> _completeWorkout(
  WidgetTester tester,
  AppServices app,
  List<trainer.SessionResult> returned,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(SfPalette.light),
        builder: (context, child) => SfPaletteScope(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .push<trainer.SessionResult>(
                      MaterialPageRoute(
                        builder: (_) => const PlayerPage(plan: _plan),
                      ),
                    );
                if (result != null) returned.add(result);
              },
              child: const Text('打开训练'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开训练'));
  await tester.pump();
  for (var second = 0; second < 15; second++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(app.store.sessionResults, hasLength(1));
  expect(app.store.history, hasLength(1));
  expect(app.store.sessionResults.single.feeling, isNull);
  expect(find.byKey(const ValueKey('finish')), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  setUp(() {
    final previous = RuntimeLog.instance;
    RuntimeLog.instance = RuntimeLog(enabled: true);
    addTearDown(() => RuntimeLog.instance = previous);
    addTearDown(() => SfColors.palette = SfPalette.dark);
  });

  for (final feeling in <trainer.TrainingFeeling?>[
    null,
    ...trainer.TrainingFeeling.values,
  ]) {
    testWidgets(
      'completion ${feeling?.name ?? 'unselected'} updates the one automatically saved workout',
      (tester) async {
        final storage = _Storage();
        final app = _services(storage);
        addTearDown(app.store.dispose);
        final returned = <trainer.SessionResult>[];
        await _completeWorkout(tester, app, returned);
        final automatic = app.store.sessionResults.single;
        if (feeling != null) {
          final choice = find.byKey(
            ValueKey('completion-feeling-${feeling.name}'),
          );
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pump();
        }
        expect(app.store.sessionResults.single.feeling, isNull);
        await tester.tap(find.byKey(const ValueKey('finish')));
        await tester.pumpAndSettle();

        expect(returned, hasLength(1));
        expect(returned.single.sessionId, automatic.sessionId);
        expect(returned.single.feeling, feeling);
        expect(app.store.history, hasLength(1));
        expect(app.store.sessionResults, hasLength(1));
        expect(app.store.history.single.sessionId, automatic.sessionId);
        expect(app.store.history.single.feeling, feeling);
        expect(
          app.store.sessionResults.single.toJson(),
          automatic.withFeeling(feeling).toJson(),
        );
        final restored = AppStore(storage);
        addTearDown(restored.dispose);
        await restored.load();
        expect(restored.history.single.feeling, feeling);
        expect(restored.sessionResults.single.feeling, feeling);
        final records = _events(RuntimeLog.instance);
        expect(
          records.where((event) => event['event'] == 'training.finished'),
          hasLength(1),
        );
        final feedback = records.singleWhere(
          (event) => event['event'] == 'training.completion.feedback',
        );
        expect(feedback['fields']['feeling'], feeling?.name ?? 'unselected');
        expect(feedback['fields']['success'], isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'failed completion stays on screen and SDK retries the same receipt',
    (tester) async {
      final storage = _Storage();
      final app = _services(storage);
      addTearDown(app.store.dispose);
      final returned = <trainer.SessionResult>[];
      await _completeWorkout(tester, app, returned);
      final automatic = app.store.sessionResults.single;
      await tester.tap(find.byKey(const ValueKey('completion-feeling-tired')));
      await tester.pump();
      storage.failures = 1;
      await tester.tap(find.byKey(const ValueKey('finish')));
      await tester.pumpAndSettle();
      expect(returned, isEmpty);
      expect(find.byKey(const ValueKey('save-retry')), findsOneWidget);
      expect(app.store.history.single.feeling, isNull);
      expect(app.store.sessionResults.single.toJson(), automatic.toJson());

      await tester.tap(find.byKey(const ValueKey('save-retry')));
      await tester.pumpAndSettle();
      expect(app.store.sessionResults.single.sessionId, automatic.sessionId);
      expect(
        app.store.sessionResults.single.feeling,
        trainer.TrainingFeeling.tired,
      );
      expect(app.store.history, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('finish')));
      await tester.pumpAndSettle();
      expect(returned.single.sessionId, automatic.sessionId);
      expect(returned.single.feeling, trainer.TrainingFeeling.tired);
      final records = _events(
        RuntimeLog.instance,
      ).where((event) => event['event'] == 'training.completion.feedback');
      expect(records.map((event) => event['fields']['success']), [false, true]);
      expect(
        RuntimeLog.instance.exportJson(),
        isNot(contains('private storage')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('legacy and unselected results keep optional feeling absent', () async {
    final storage = _Storage();
    storage.values[AppStore.key] = jsonEncode({
      'history': [
        {
          'title': '历史训练',
          'at': '2026-10-01T01:00:00Z',
          'minutes': 2,
          'completed': 1,
          'total': 1,
        },
      ],
      'sessions': [_receipt().toJson()],
    });
    final store = AppStore(storage);
    addTearDown(store.dispose);
    await store.load();
    expect(store.history.single.feeling, isNull);
    expect(store.history.single.toJson().containsKey('feeling'), isFalse);
    expect(store.sessionResults.single.feeling, isNull);
    expect(
      store.sessionResults.single.toJson().containsKey('feeling'),
      isFalse,
    );
    final unknown = HistoryEntry.fromJson({
      ...store.history.single.toJson(),
      'feeling': 'future-enum-value',
    });
    expect(unknown.feeling, isNull);
    await store.saveSession(_receipt());
    expect(store.history.last.title, '历史训练');
    expect(store.history.last.feeling, isNull);
  });

  test(
    'same-session feedback and late automatic retries retain one chosen result',
    () async {
      final storage = _Storage();
      final app = _services(storage);
      addTearDown(app.store.dispose);
      final automatic = _receipt();
      final completed = automatic.withFeeling(
        trainer.TrainingFeeling.justRight,
      );
      await app.store.saveSession(automatic);
      await Future.wait([
        app.recordTrainingCompletion(completed),
        app.recordTrainingCompletion(completed),
        app.store.saveSession(automatic),
      ]);
      expect(app.store.history, hasLength(1));
      expect(app.store.sessionResults, hasLength(1));
      expect(
        app.store.history.single.feeling,
        trainer.TrainingFeeling.justRight,
      );
      expect(app.store.sessionResults.single.toJson(), completed.toJson());
      final restored = AppStore(storage);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.history, hasLength(1));
      expect(
        restored.history.single.feeling,
        trainer.TrainingFeeling.justRight,
      );
      expect(restored.sessionResults.single.toJson(), completed.toJson());
    },
  );

  test(
    'completion feedback is local and absent from subsequent real coach requests',
    () async {
      final app = _services(_Storage());
      addTearDown(app.store.dispose);
      await app.store.acceptSafety(blocked: false);
      final client = coach.FakeLlmClient(['你好。'], latency: Duration.zero);
      final ai = AiChatEngine(
        local: const AppChatActions(),
        catalog: fixture.catalog,
        profile: fixture.profile,
        client: client,
        enableUserMemory: false,
      );
      final chat = ChatController(
        engine: ai,
        store: app.store,
        replyDelay: Duration.zero,
      )..start();
      addTearDown(ai.dispose);
      addTearDown(chat.dispose);
      final before = ai.conversation.exportSession().toJson();
      await app.recordTrainingCompletion(
        _receipt(feeling: trainer.TrainingFeeling.justRight),
      );
      expect(client.requests, isEmpty);
      expect(ai.conversation.exportSession().toJson(), before);
      expect(await app.store.aiMemoryStore.load(), isEmpty);
      await chat.send('你好');
      expect(client.requests, hasLength(1));
      final request = client.requests.single;
      final wire = jsonEncode({
        'messages': request.messages
            .map((message) => message.toJson())
            .toList(),
        'tools': request.tools.map((tool) => tool.toJson()).toList(),
      });
      expect(wire, isNot(contains('justRight')));
      expect(wire, isNot(contains('private-feedback-session')));
      expect(wire, isNot(contains('private-training-title')));
      expect(wire, isNot(contains('"feeling"')));
      final exported = RuntimeLog.instance.exportJson();
      expect(
        _events(RuntimeLog.instance).singleWhere(
          (event) => event['event'] == 'training.completion.feedback',
        )['fields']['feeling'],
        'justRight',
      );
      expect(exported, isNot(contains('private-training-title')));
    },
  );

  test('feeling diagnostics accept enumerated values only', () {
    final log = RuntimeLog.instance;
    log.record(
      'training.completion.feedback',
      fields: {'feeling': 'arbitrary-safe-token'},
    );
    expect(_events(log).single['fields'], isEmpty);
  });
}
