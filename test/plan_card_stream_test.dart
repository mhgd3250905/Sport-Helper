import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';

import 'app_flow_test.dart' show services;

const _plan = TrainingPlan(
  id: 'card-stream',
  source: 'template',
  title: '今天的舒展安排',
  summary: '先活动肩背，再轻柔舒展腰侧，最后放松。',
  goal: 'fullbody',
  scene: 'home',
  equipment: ['mat'],
  level: 1,
  targetMinutes: 10,
  notes: ['按你的徒手和居家条件安排'],
  blocks: [
    PlanBlock(
      id: 'warm',
      name: '先活动开',
      type: BlockType.warmup,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-catcow-quad',
          mode: DoseMode.reps,
          sets: 1,
          reps: 8,
          perSide: false,
          restSeconds: 10,
        ),
      ],
    ),
    PlanBlock(
      id: 'main',
      name: '重点舒展',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-banana',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 30,
          perSide: true,
          restSeconds: 10,
          note: '两侧依次进行，保持自然呼吸',
        ),
      ],
    ),
    PlanBlock(
      id: 'cool',
      name: '收尾放松',
      type: BlockType.cooldown,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'n-windshield',
          mode: DoseMode.reps,
          sets: 1,
          reps: 6,
          perSide: false,
          restSeconds: 10,
        ),
      ],
    ),
  ],
);

Future<void> _show(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = services();
  await s.store.acceptSafety(blocked: false);
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const PlanPage(plan: _plan),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Iterable<ExerciseVideo> _playing(WidgetTester tester) => tester
    .widgetList<ExerciseVideo>(find.byType(ExerciseVideo))
    .where((v) => v.playing);

void main() {
  testWidgets(
    'sectioned cards keep one central demonstration and the start action',
    (tester) async {
      await _show(tester);
      expect(find.byKey(const ValueKey('plan-introduction')), findsOneWidget);
      expect(find.text('安排说明'), findsOneWidget);
      expect(find.text('先活动开'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview')), findsNothing);
      expect(_playing(tester), hasLength(1));
      final first = _playing(tester).single.exercise.id;
      final list = find.byKey(const ValueKey('plan-card-stream'));
      for (var i = 0; i < 4; i++) {
        await tester.drag(list, const Offset(0, -260));
        await tester.pumpAndSettle();
        expect(_playing(tester).length, lessThanOrEqualTo(1));
        expect(
          find.byKey(const ValueKey('start')).hitTestable(),
          findsOneWidget,
        );
      }
      expect(_playing(tester), hasLength(1));
      expect(_playing(tester).single.exercise.id, isNot(first));
      expect(find.text('收尾放松'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320px cards wrap at 1.5x without overflow while scrolling', (
    tester,
  ) async {
    await _show(tester, width: 320, scale: 1.5);
    final list = find.byKey(const ValueKey('plan-card-stream'));
    for (var i = 0; i < 7; i++) {
      expect(tester.takeException(), isNull);
      expect(_playing(tester).length, lessThanOrEqualTo(1));
      expect(find.byKey(const ValueKey('start')).hitTestable(), findsOneWidget);
      await tester.drag(list, const Offset(0, -260));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
