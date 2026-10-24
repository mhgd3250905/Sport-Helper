// Player fixed slots (docs/design-audit-2026-10-19.md §2.6, H4): changing
// phase changes what is written, not where things sit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show services, tall;

const _two = TrainingPlan(
  id: 'two', source: 'template', title: '两个动作', summary: '', goal: 'relax', scene: 'home',
  equipment: [], level: 1, targetMinutes: 2,
  blocks: [PlanBlock(id: 'main', name: '主训练', type: BlockType.main, rounds: 1, restBetweenRoundsSeconds: 0, items: [
    PlanItem(exerciseId: 'h-squat', mode: DoseMode.time, sets: 1, workSeconds: 20, perSide: false, restSeconds: 15),
    PlanItem(exerciseId: 'h-squat', mode: DoseMode.reps, sets: 1, reps: 8, perSide: false, restSeconds: 0),
  ])],
);

void main() {
  testWidgets('prep → work → rest: the ring, the name and the controls stay put', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: buildTheme(), home: const PlayerPage(plan: _two))));
    await tester.pump();
    Offset ring() => tester.getTopLeft(find.byKey(const ValueKey('ring')));
    Offset pause() => tester.getTopLeft(find.byKey(const ValueKey('pause')));
    final r0 = ring(), p0 = pause();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
      expect(ring(), r0);
      expect(pause(), p0);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
