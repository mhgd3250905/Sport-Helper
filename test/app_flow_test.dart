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

class InterruptibleTestOutput extends MutedVoiceOutput implements InterruptibleVoiceOutput {
  final events = StreamController<AudioInterruption>.broadcast(sync: true);
  @override
  Stream<AudioInterruption> get interruptions => events.stream;
  @override
  Future<void> reactivate() async {}
}

Future<void> showPlayer(WidgetTester tester, AppServices s, {TrainingPlan? plan}) async {
  tall(tester);
  final generated = await s.generator.generate(const ScenarioRequest(templateId: 'office-relax'));
  await tester.pumpWidget(AppScope(
    services: s,
    child: MaterialApp(home: PlayerPage(plan: plan ?? generated.plan!)),
  ));
  await tester.pump();
}

/// Tall phone so the lazy lists build every row the test taps.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('skipping the last exercise while paused still records the result', (tester) async {
    final s = services();
    const plan = TrainingPlan(
      id: 'single', source: 'template', title: '单动作', summary: '', goal: 'relax', scene: 'home',
      equipment: [], level: 1, targetMinutes: 1,
      blocks: [PlanBlock(id: 'main', name: '主训练', type: BlockType.main, rounds: 1, restBetweenRoundsSeconds: 0, items: [
        PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 1, reps: 10, perSide: false, restSeconds: 10),
      ])],
    );
    await showPlayer(tester, s, plan: plan);
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discomfort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过这个动作'));
    await tester.pumpAndSettle();
    expect(find.text('训练完成！'), findsOneWidget);
    expect(s.store.history, hasLength(1));
    expect(s.store.history.single.completed, 1);
    expect(s.store.history.single.total, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pause and audio interruption freeze the demonstration until resumed', (tester) async {
    final output = InterruptibleTestOutput();
    final s = services(output: output);
    await showPlayer(tester, s);
    bool paused() => tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused;
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
  });

  testWidgets('ending from discomfort while paused records an incomplete workout once', (tester) async {
    final s = services();
    await showPlayer(tester, s);
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discomfort')));
    await tester.pumpAndSettle();
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
  });

  testWidgets('skipping from discomfort preserves an existing pause', (tester) async {
    await showPlayer(tester, services());
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('discomfort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过这个动作'));
    await tester.pumpAndSettle();
    expect(tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused, isTrue);
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

  testWidgets('safety talk → describe → plan card → player → back in the chat', (tester) async {
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

    // Describe → the card.
    await say(tester, '在办公室午休 10 分钟，肩颈很僵');
    expect(find.byType(PlanCard), findsOneWidget);
    expect(find.text('工位肩颈腰放松'), findsOneWidget);
    final plan = s.chat.currentPlan!;
    expect(plan.templateId, 'office-relax');

    // Save from the card.
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    expect(s.store.savedPlans.single.plan.id, plan.id);
    expect(find.text('已保存'), findsOneWidget);

    // 开始训练 → the existing player.
    await tester.tap(find.byKey(ValueKey('plan-start-${plan.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(s.store.lastPlan?.id, plan.id);
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(s.store.history, hasLength(1));
    expect(find.byType(ChatHomePage), findsOneWidget);
    expect(s.chat.messages.last.isUser, isFalse);
    expect(s.chat.messages.last.isPlan, isFalse); // a word after the workout
  });

  testWidgets('a "是" in the safety talk → advice, no plans, library still open', (tester) async {
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
  });

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

  testWidgets('drawer: saved plans, show one in the chat, app entries', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    await say(tester, '在家 15 分钟练核心，徒手');
    final plan = s.chat.currentPlan!;
    await tester.tap(find.byKey(ValueKey('plan-save-${plan.id}')));
    await tester.pumpAndSettle();
    await say(tester, '讲个笑话');

    await tester.tap(find.byKey(const ValueKey('open-plans')));
    await tester.pumpAndSettle();
    expect(find.text('我的计划'), findsWidgets);
    final saved = s.store.savedPlans.single;
    await tester.tap(find.byKey(ValueKey('saved-${saved.id}')));
    await tester.pumpAndSettle();
    expect(s.chat.messages.last.plan?.id, plan.id); // shown again as a card

    await tester.tap(find.byKey(const ValueKey('open-plans')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('drawer-custom')));
    await tester.pumpAndSettle();
    expect(find.text('描述你今天想怎么练'), findsOneWidget);
  });

  testWidgets('the custom form (drawer entry) still generates plans', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(AppScope(services: s, child: const MaterialApp(home: CustomPlanPage())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prompt')), '在办公室午休 10 分钟，肩颈很僵');
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('工位肩颈腰放松'), findsWidgets);
    expect(find.text('开始跟练'), findsOneWidget);
  });
}
