import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
  testWidgets(
    'App media builder retains its handoff owner across rapid skips',
    (tester) async {
      tall(tester);
      final s = services();
      final plan = TrainingPlan(
        id: 'handoff',
        source: 'template',
        title: '动作切换',
        summary: '',
        goal: 'relax',
        scene: 'home',
        equipment: const [],
        level: 1,
        targetMinutes: 2,
        blocks: [
          PlanBlock(
            id: 'main',
            name: '主训练',
            type: BlockType.main,
            rounds: 1,
            restBetweenRoundsSeconds: 0,
            items: [
              for (final id in ['h-squat', 'h-banana', 'n-windshield'])
                PlanItem(
                  exerciseId: id,
                  mode: DoseMode.time,
                  sets: 1,
                  workSeconds: 30,
                  perSide: false,
                  restSeconds: 0,
                ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlayerPage(plan: plan),
          ),
        ),
      );
      await tester.pump();
      final owner = tester.state(find.byType(ExerciseVideo));
      expect(find.byType(DrillMediaHandoff), findsOneWidget);
      // Leave preparation, then pass two moves and their transition rests.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('skip')));
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byType(ExerciseVideo), findsOneWidget);
        expect(tester.state(find.byType(ExerciseVideo)), same(owner));
      }
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).exercise.id,
        'n-windshield',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
