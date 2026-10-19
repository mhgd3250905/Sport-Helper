import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'support.dart';

class _Storage implements LocalStateStorage {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

AppServices _services() => AppServices(
  library: loadLibrary(),
  catalog: loadCatalog(),
  store: AppStore(_Storage()),
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
);

const _plan = TrainingPlan(
  id: 'core',
  source: 'template',
  title: '核心',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: [],
  level: 2,
  targetMinutes: 5,
  blocks: [
    PlanBlock(
      id: 'b',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-russian-twist',
          mode: DoseMode.reps,
          sets: 1,
          reps: 10,
          perSide: false,
          restSeconds: 20,
        ),
      ],
    ),
  ],
);

Future<void> _show(
  WidgetTester tester,
  AppServices services,
  Widget home,
  Size size,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('manual replacement cannot add unavailable equipment', (
    tester,
  ) async {
    final services = _services();
    await services.store.rememberPlan(_plan);
    await _show(
      tester,
      services,
      const PlanPage(plan: _plan),
      const Size(430, 1500),
    );
    await tester.ensureVisible(find.byTooltip('换一个'));
    await tester.tap(find.byTooltip('换一个'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需要弹力带'), findsOneWidget);
    expect(services.store.lastPlan!.exerciseIds, ['h-russian-twist']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual replacement works when the required equipment is available',
    (tester) async {
      final services = _services();
      final plan = TrainingPlan.fromJson({
        ..._plan.toJson(),
        'equipment': ['band'],
      });
      await _show(
        tester,
        services,
        PlanPage(
          plan: plan,
          request: const ScenarioRequest(level: 2, equipment: {Equipment.band}),
        ),
        const Size(430, 1500),
      );
      await tester.ensureVisible(find.byTooltip('换一个'));
      await tester.tap(find.byTooltip('换一个'));
      await tester.pumpAndSettle();
      expect(services.store.lastPlan!.exerciseIds, ['h-band-pallof']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('manual replacement preserves protected body parts', (
    tester,
  ) async {
    final services = _services();
    final plan = _plan.copyWith(
      blocks: [
        _plan.blocks.first.copyWith(
          items: [
            _plan.items.first.copyWith(
              exerciseId: 'h-chair-step-up',
              perSide: true,
            ),
          ],
        ),
      ],
    );
    await services.store.rememberPlan(plan);
    await _show(
      tester,
      services,
      PlanPage(
        plan: plan,
        request: ScenarioRequest(level: 2, avoid: const {'膝'}),
      ),
      const Size(430, 1500),
    );
    await tester.ensureVisible(find.byTooltip('换一个'));
    await tester.tap(find.byTooltip('换一个'));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂不能替换'), findsOneWidget);
    expect(services.store.lastPlan!.exerciseIds, ['h-chair-step-up']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('exercise details scroll without overflow in landscape', (
    tester,
  ) async {
    await _show(tester, _services(), const LibraryPage(), const Size(844, 390));
    await tester.scrollUntilVisible(
      find.text('徒手深蹲'),
      500,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('徒手深蹲'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.textContaining('注意：'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
