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
import 'package:smartfit/ui/exercise_video.dart';
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

AppServices services({VoiceOutput output = const MutedVoiceOutput()}) => AppServices(
  library: loadLibrary(),
  catalog: loadCatalog(),
  store: AppStore(MemoryStorage()),
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: output,
);

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

  testWidgets('safety → describe → plan → player → skip → close', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    // Safety: four "否" + agree.
    expect(find.text('开始之前'), findsOneWidget);
    for (final no in find.text('否').evaluate().toList()) {
      await tester.tap(find.byWidget(no.widget));
    }
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('safety-continue')));
    await tester.tap(find.byKey(const ValueKey('safety-continue')));
    await tester.pumpAndSettle();
    expect(s.store.safetyAccepted, isTrue);
    expect(s.store.safetyBlocked, isFalse);

    // Describe and generate.
    expect(find.text('描述你今天想怎么练'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt')), '在办公室午休 10 分钟，肩颈很僵');
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('工位肩颈腰放松'), findsWidgets);
    expect(find.text('开始跟练'), findsOneWidget);
    expect(s.store.lastPlan?.templateId, 'office-relax');

    // Player.
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.textContaining('准备'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('秒'), findsWidgets);

    // Close → confirm → back on the plan.
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(s.store.history, hasLength(1));
  });

  testWidgets('a "是" safety answer keeps the app in browse-only mode', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    final yes = find.text('是').evaluate().toList();
    final no = find.text('否').evaluate().toList();
    await tester.tap(find.byWidget(yes.first.widget));
    for (final n in no.skip(1)) {
      await tester.tap(find.byWidget(n.widget));
    }
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('safety-continue')));
    await tester.tap(find.byKey(const ValueKey('safety-continue')));
    await tester.pumpAndSettle();
    expect(s.store.safetyBlocked, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('暂不生成训练计划'), findsOneWidget);
  });
}
