import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/domain/single_exercise_plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/basic_home_page.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/safety_check_page.dart';

import 'app_flow_test.dart' show services, tall;
import 'support.dart';

void main() {
  test(
    'AI stays disabled unless both key and explicit HTTPS endpoint exist',
    () {
      for (final config in [
        const AiCoachConfig(),
        const AiCoachConfig(token: 'fixture'),
        const AiCoachConfig(baseUrl: 'https://fixture.invalid/v1'),
        const AiCoachConfig(token: ' ', baseUrl: 'https://fixture.invalid/v1'),
        const AiCoachConfig(
          token: 'fixture',
          baseUrl: 'http://fixture.invalid/v1',
        ),
        const AiCoachConfig(
          token: 'fixture',
          baseUrl: 'https://user@fixture.invalid/v1',
        ),
        const AiCoachConfig(
          token: 'fixture',
          baseUrl: 'https://fixture.invalid/v1?key=fixture',
        ),
        const AiCoachConfig(
          token: 'fixture',
          baseUrl: 'https://fixture.invalid/v1#fixture',
        ),
      ]) {
        expect(config.enabled, isFalse);
        expect(() => config.createClient(deviceId: 'unused'), throwsStateError);
      }
      expect(
        const AiCoachConfig(
          token: 'fixture',
          baseUrl: 'https://fixture.invalid/v1',
        ).enabled,
        isTrue,
      );
      expect(const AiCoachConfig.fromEnvironment().baseUrl, isEmpty);
      expect(const AiCoachConfig.fromEnvironment().token, isEmpty);
    },
  );

  test(
    'single-action plans retain the published dose without an AI result',
    () {
      final library = loadLibrary();
      for (final exercise in library.all) {
        final plan = singleExercisePlan(exercise);
        final item = plan.items.single;
        expect(plan.source, 'template');
        expect(plan.title, exercise.name);
        expect(item.exerciseId, exercise.id);
        expect(item.mode, exercise.dose.mode);
        expect(item.sets, exercise.dose.sets);
        expect(item.reps, exercise.dose.reps);
        expect(item.workSeconds, exercise.dose.seconds);
        expect(item.perSide, exercise.unilateral);
        expect(item.restSeconds, exercise.dose.restSeconds);
        expect(plan.targetMinutes, greaterThan(0));
      }
    },
  );

  testWidgets(
    'unconfigured app opens local training and exposes no AI settings',
    (tester) async {
      tall(tester);
      final s = services(ai: false);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      expect(find.byType(BasicHomePage), findsOneWidget);
      expect(find.byType(ChatHomePage), findsNothing);
      expect(find.byKey(const ValueKey('chat-input')), findsNothing);
      expect(find.byKey(const ValueKey('basic-library')), findsOneWidget);
      expect(s.chatEngine, isA<RuleChatEngine>());

      await tester.tap(find.byKey(const ValueKey('basic-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-memory-switch')), findsNothing);
      expect(find.byKey(const ValueKey('ai-memory-clear')), findsNothing);
      expect(find.text('隐私与 AI'), findsNothing);
      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.textContaining('mhgd3250905@gmail.com'), findsOneWidget);
      expect(find.textContaining('api.uuugk.win'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('local safety risk blocks a routine without creating a plan', (
    tester,
  ) async {
    tall(tester);
    final s = services(ai: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('basic-routine-${s.catalog.templates.first.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SafetyCheckPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('basic-safety-understood')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('basic-safety-yes')));
    await tester.pumpAndSettle();
    expect(s.store.trainingAllowed, isFalse);
    expect(s.store.lastPlan, isNull);
    expect(find.byType(PlayerPage), findsNothing);
    await tester.tap(find.text('返回浏览'));
    await tester.pumpAndSettle();
    expect(find.byType(BasicHomePage), findsOneWidget);
    expect(find.text('当前仅开放动作浏览'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'choose action, complete local safety and enter the training player',
    (tester) async {
      tall(tester);
      final s = services(ai: false);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('basic-library')));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      final pageContext = tester.element(find.byType(LibraryPage));
      final details = showExerciseDetails(pageContext, s.library['h-squat']);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('basic-train-action')));
      await tester.pumpAndSettle();
      expect(find.byType(SafetyCheckPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('basic-safety-understood')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('basic-safety-no')));
        await tester.pumpAndSettle();
      }
      await details;
      expect(s.store.trainingAllowed, isTrue);
      expect(find.byType(PlanPage), findsOneWidget);
      expect(s.store.lastPlan!.items.single.exerciseId, 'h-squat');
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(find.byType(ChatHomePage), findsNothing);
      // Finish the actual timer phases, rather than injecting a saved result.
      await tester.pump(const Duration(minutes: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(s.store.history, hasLength(1));
      expect(s.store.history.single.completed, 1);
      expect(find.text('训练完成！'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
