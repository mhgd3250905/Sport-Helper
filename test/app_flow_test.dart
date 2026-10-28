import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/cosmos.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/custom_plan_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'support.dart';

class MemoryStorage implements LocalStateStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

AppServices services({VoiceOutput output = const MutedVoiceOutput()}) {
  final store = AppStore(MemoryStorage())
    // A drifting sky never settles: keep it still so pumpAndSettle can.
    ..starfield = false;
  return AppServices(
    library: loadLibrary(),
    catalog: loadCatalog(),
    store: store,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: output,
    chatReplyDelay: Duration.zero,
  );
}

class InterruptibleTestOutput extends MutedVoiceOutput
    implements InterruptibleVoiceOutput {
  final events = StreamController<AudioInterruption>.broadcast(sync: true);
  @override
  Stream<AudioInterruption> get interruptions => events.stream;
  @override
  Future<void> reactivate() async {}
}

Future<void> showPlayer(
  WidgetTester tester,
  AppServices s, {
  TrainingPlan? plan,
}) async {
  tall(tester);
  final generated = await s.generator.generate(
    const ScenarioRequest(templateId: 'office-relax'),
  );
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(home: PlayerPage(plan: plan ?? generated.plan!)),
    ),
  );
  await tester.pump();
}

/// Tall phone so the lazy lists build every row the test taps.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

// Product navigation tests use an explicit manually composed plan fixture;
// natural-language plan generation is exercised by the SDK integration tests.
Future<TrainingPlan> showManualChatCard(
  AppServices services, {
  String template = 'core',
}) async {
  final result = await services.generator.generate(
    ScenarioRequest(templateId: template),
  );
  final plan = result.plan!;
  await services.chat.started(plan);
  return plan;
}

// Paused Morph Pulse breathing intentionally keeps scheduling frames behind
// the modal. Wait for the finite route animation, not for the whole app to idle.
Future<void> _openDiscomfort(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('discomfort')));
  await tester.pump();
  final sheet = find.byType(BottomSheet);
  expect(sheet, findsOneWidget);
  final animation = ModalRoute.of(tester.element(sheet))!.animation!;
  for (var frame = 0; frame < 90 && !animation.isCompleted; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(animation.status, AnimationStatus.completed);
  expect(find.text('跳过这个动作').hitTestable(), findsOneWidget);
}

Future<void> _closeDiscomfort(WidgetTester tester) async {
  for (var frame = 0; frame < 90; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (find.byType(BottomSheet).evaluate().isEmpty) return;
  }
  fail('Discomfort sheet did not finish its finite closing transition.');
}

void main() {
  testWidgets(
    'skipping the last exercise while paused still records the result',
    (tester) async {
      final s = services();
      const plan = TrainingPlan(
        id: 'single',
        source: 'template',
        title: '单动作',
        summary: '',
        goal: 'relax',
        scene: 'home',
        equipment: [],
        level: 1,
        targetMinutes: 1,
        blocks: [
          PlanBlock(
            id: 'main',
            name: '主训练',
            type: BlockType.main,
            rounds: 1,
            restBetweenRoundsSeconds: 0,
            items: [
              PlanItem(
                exerciseId: 'h-squat',
                mode: DoseMode.reps,
                sets: 1,
                reps: 10,
                perSide: false,
                restSeconds: 10,
              ),
            ],
          ),
        ],
      );
      await showPlayer(tester, s, plan: plan);
      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      await _openDiscomfort(tester);
      await tester.tap(find.text('跳过这个动作'));
      await tester.pumpAndSettle();
      expect(find.text('今天先到这里'), findsOneWidget);
      expect(s.store.history, hasLength(1));
      // ugk_trainer records only completed work, never skipped exercises.
      expect(s.store.history.single.completed, 0);
      expect(s.store.history.single.total, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pause and audio interruption freeze the demonstration until resumed',
    (tester) async {
      final output = InterruptibleTestOutput();
      final s = services(output: output);
      await showPlayer(tester, s);
      bool paused() =>
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused;
      expect(paused(), isFalse);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      expect(paused(), isTrue);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      expect(paused(), isFalse);
      output.events.add(AudioInterruption.began);
      await tester.pump();
      expect(paused(), isTrue);
      output.events.add(AudioInterruption.ended);
      await tester.pump();
      expect(paused(), isTrue);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      expect(paused(), isFalse);
      await tester.pumpWidget(const SizedBox());
      await output.events.close();
    },
  );

  testWidgets(
    'the player keeps its sky still and shows pause through the resume control',
    (tester) async {
      final s = services();
      s.store.starfield =
          true; // even with star dust on, the workout keeps it still
      await showPlayer(tester, s);
      final sky = tester.widget<CosmosBackground>(
        find.byType(CosmosBackground),
      );
      expect(sky.animate, isFalse);
      expect(find.text('已暂停'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      expect(find.text('已暂停'), findsNothing);
      expect(find.byTooltip('继续训练'), findsOneWidget);
      expect(find.byKey(const ValueKey('counter')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ending from discomfort while paused records an incomplete workout once',
    (tester) async {
      final s = services();
      await showPlayer(tester, s);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      await _openDiscomfort(tester);
      await tester.tap(find.text('结束今天的训练'));
      await tester.pumpAndSettle();
      expect(find.text('今天先到这里'), findsOneWidget);
      expect(find.text('训练完成！'), findsNothing);
      expect(s.store.history, hasLength(1));
      expect(s.store.history.single.completed, 0);
      expect(s.store.history.single.total, greaterThan(0));
      await tester.pump(const Duration(seconds: 2));
      expect(s.store.history, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('skipping from discomfort preserves an existing pause', (
    tester,
  ) async {
    await showPlayer(tester, services());
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    await _openDiscomfort(tester);
    await tester.tap(find.text('跳过这个动作'));
    await _closeDiscomfort(tester);
    expect(
      tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  /// The safety question buttons that are still open (older answered ones
  /// stay on screen, locked).
  Finder openOption(String label) => find.byWidgetPredicate(
    (w) => w is OptionPill && w.label == label && w.enabled,
  );

  Future<void> answerSafety(WidgetTester tester, List<String> answers) async {
    expect(find.textContaining('开始之前'), findsOneWidget);
    await tester.tap(openOption('我已了解'));
    await tester.pumpAndSettle();
    for (final a in answers) {
      await tester.tap(openOption(a));
      await tester.pumpAndSettle();
    }
  }

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('safety talk → manual plan card → player → back in the chat', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    // First launch: the chat opens with the safety talk, four "否".
    expect(find.byType(ChatHomePage), findsOneWidget);
    await answerSafety(tester, ['否', '否', '否', '否']);
    expect(s.store.safetyAccepted, isTrue);
    expect(s.store.safetyBlocked, isFalse);
    expect(find.textContaining('都没问题'), findsOneWidget);

    // An explicit manual-plan fixture supplies the card.
    await showManualChatCard(s, template: 'office-relax');
    await tester.pumpAndSettle();
    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.text('工位肩颈腰放松'), findsOneWidget);
    final plan = s.chat.currentPlan!;
    expect(plan.templateId, 'office-relax');

    // Save from the card.
    await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    expect(s.store.savedPlans.single.plan.id, plan.id);
    expect(find.text('已保存'), findsOneWidget);
    expect(find.textContaining('已保存为「'), findsOneWidget);

    // Training opens at stable full-screen bounds, hiding the old chat.
    // The visible informational toast must let this tap reach the start button.
    final screen = tester.getRect(find.byType(ChatHomePage));
    await tester.tap(find.byKey(ValueKey('plan-start-${plan.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(tester.getRect(find.byType(PlayerPage)), screen);
    expect(find.byType(ChatHomePage), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(find.byType(PlayerPage)), screen); // full screen
    expect(s.store.lastPlan?.id, plan.id);
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerPage), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(s.store.history, hasLength(1));
    expect(find.byType(ChatHomePage), findsOneWidget);
    expect(s.chat.messages.last.isUser, isFalse);
    expect(s.chat.messages.last.isPlan, isFalse); // a word after the workout
  });

  testWidgets('reduced motion: the player opens directly at full screen', (
    tester,
  ) async {
    tall(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await showManualChatCard(s);
    await tester.pumpAndSettle();
    final plan = s.chat.currentPlan!;
    final screen = tester.getRect(find.byType(ChatHomePage));
    await tester.tap(find.byKey(ValueKey('plan-start-${plan.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getRect(find.byType(PlayerPage)), screen);
    expect(
      find.ancestor(
        of: find.byType(PlayerPage),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets(
    'drawer ▶ starts a saved plan in the player and comes back to the chat',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await showManualChatCard(s);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('plan-expand-${s.chat.currentPlan!.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('plan-save-${s.chat.currentPlan!.id}')),
      );
      await tester.pumpAndSettle();
      final saved = s.store.savedPlans.single;
      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-plans')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('saved-start-${saved.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlayerPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('结束'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(ChatHomePage), findsOneWidget);
      expect(s.store.history, hasLength(1));
    },
  );

  testWidgets(
    'a "是" in the safety talk → advice, no plans, library still open',
    (tester) async {
      tall(tester);
      final s = services();
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await answerSafety(tester, ['否', '是']);
      expect(s.store.safetyAccepted, isTrue);
      expect(s.store.safetyBlocked, isTrue);
      expect(find.textContaining('医生的康复安排'), findsOneWidget);

      await say(tester, '在家 10 分钟拉伸');
      expect(find.byType(PlanCard), findsNothing);
      expect(find.textContaining('先不生成训练计划'), findsWidgets);

      await tester.tap(openOption('浏览动作库').first);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
    },
  );

  testWidgets('typing during the safety talk waits for it', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await say(tester, '在家 10 分钟拉伸');
    expect(find.byType(PlanCard), findsNothing);
    expect(find.textContaining('先把上面的安全确认做完'), findsOneWidget);
    expect(s.store.safetyAccepted, isFalse);
  });

  testWidgets('drawer: saved plans, show one in the chat, app entries', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    await showManualChatCard(s);
    await tester.pumpAndSettle();
    final plan = s.chat.currentPlan!;
    await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    await say(tester, '讲个笑话');

    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('我的计划'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('panel-plans')));
    await tester.pumpAndSettle();
    final saved = s.store.savedPlans.single;
    await tester.tap(find.byKey(ValueKey('saved-${saved.id}')));
    await tester.pumpAndSettle();
    expect(s.chat.messages.last.plan?.id, plan.id); // shown again as a card

    // New conversation is in the drawer; the form opens from the chat.
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('panel-library')), findsOneWidget);
    expect(find.byKey(const ValueKey('panel-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-new-conversation')), findsOneWidget);
    expect(find.byKey(const ValueKey('drawer-custom')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-library')));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage), findsOneWidget);
    await tester.tap(find.byTooltip('返回').first);
    await tester.pumpAndSettle();
    s.chat.command('@custom');
    await tester.pumpAndSettle();
    expect(find.byType(CustomPlanPage), findsOneWidget);
  });

  testWidgets('the custom form (opened from the chat) still generates plans', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: const MaterialApp(home: CustomPlanPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt')),
      '在办公室午休 10 分钟，肩颈很僵',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('工位肩颈腰放松'), findsWidgets);
    expect(find.text('前往训练'), findsOneWidget);
    expect(find.byKey(const ValueKey('start')).hitTestable(), findsOneWidget);
  });
}
