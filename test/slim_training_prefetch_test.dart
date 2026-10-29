import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'posehub_ui_support.dart';

TrainingPlan _plan(List<String> ids) => TrainingPlan(
  id: 'prefetch-order',
  source: 'template',
  title: '训练',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: const [],
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
        for (final id in ids)
          PlanItem(
            exerciseId: id,
            mode: DoseMode.time,
            sets: 1,
            workSeconds: 1,
            perSide: false,
            restSeconds: 0,
          ),
      ],
    ),
  ],
);

Future<void> _flush() async {
  for (var tick = 0; tick < 5; tick++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());

  test(
    'training prefetch starts the first action first, at most two at once',
    () async {
      final ids = catalog.semanticCompleteActions
          .take(4)
          .map((a) => a.id)
          .toList();
      final pending = {for (final id in ids) id: Completer<Uri>()};
      var active = 0;
      var peak = 0;
      final base = Uri.parse('file:///prefetch-test/');
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (id) {
          active++;
          if (active > peak) peak = active;
          return pending[id]!.future.whenComplete(() => active--);
        },
      );
      final services = poseHubUiServices(catalog: catalog, media: repo);
      addTearDown(repo.dispose);
      addTearDown(services.store.dispose);
      final plan = _plan([...ids, ids.first]);
      services.prefetchPlan(plan);
      expect(repo.actionRequests, ids.take(2).toList());
      services.prefetchPlan(plan);
      expect(repo.actionRequests, hasLength(2));
      pending[ids[0]]!.complete(base);
      await _flush();
      expect(repo.actionRequests, ids.take(3).toList());
      pending[ids[1]]!.complete(base);
      await _flush();
      expect(repo.actionRequests, ids);
      pending[ids[2]]!.complete(base);
      pending[ids[3]]!.complete(base);
      await _flush();
      expect(active, 0);
      expect(peak, 2);
    },
  );

  test(
    'failed prefetch does not block later actions or prevent a later retry',
    () async {
      final ids = catalog.semanticCompleteActions
          .take(3)
          .map((a) => a.id)
          .toList();
      final first = Completer<Uri>();
      final base = Uri.parse('file:///prefetch-test/');
      var fail = true;
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (id) {
          if (fail && id == ids.first) return first.future;
          return Future.value(base);
        },
      );
      final services = poseHubUiServices(catalog: catalog, media: repo);
      addTearDown(repo.dispose);
      addTearDown(services.store.dispose);
      final plan = _plan(ids);
      services.prefetchPlan(plan);
      await _flush();
      expect(repo.actionRequests, ids);
      first.completeError(StateError('offline'));
      await _flush();
      fail = false;
      services.prefetchPlan(plan);
      await _flush();
      expect(repo.actionRequests, [...ids, ...ids]);
    },
  );
}
