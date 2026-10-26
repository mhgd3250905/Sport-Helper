import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

class _Voice extends MutedVoiceOutput {
  var begins = 0;
  @override
  Future<void> begin() async => begins++;
}

TrainingPlan _plan(List<coach.PoseHubPackAction> actions) => TrainingPlan(
  id: 'immediate-training',
  source: 'test',
  title: '测试训练',
  summary: '',
  goal: 'core',
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
        for (final action in actions)
          PlanItem(
            exerciseId: action.id,
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubUiVideoPlatform platform;
  final base = Uri.parse('file:///ui-contract-pack/');
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    platform = PoseHubUiVideoPlatform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.close();
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'pending legacy action clocks and audio start without preparation ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2100);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        final actions = [
          catalog.pendingActions.first,
          ...catalog.semanticCompleteActions.take(2),
        ];
        final pending = {
          for (final action in actions) action.id: Completer<Uri>(),
        };
        final repo = PoseHubUiRepository(
          mediaBaseUri: base,
          onEnsureAction: (id) => pending[id]!.future,
        );
        final voice = _Voice();
        final services = poseHubUiServices(
          catalog: catalog,
          media: repo,
          voiceOutput: voice,
          library: ExerciseLibrary(actions.map(poseHubUiExercise).toList()),
        );
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: PlayerPage(plan: _plan(actions)),
          ),
        );
        await tester.pump();
        expect(find.byType(TrainerPlayer), findsOneWidget);
        expect(find.text('准备训练'), findsNothing);
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(voice.begins, 1);
        expect(repo.actionRequests.toSet(), {actions[0].id, actions[1].id});
        final player = tester.widget<TrainerPlayer>(find.byType(TrainerPlayer));
        final video = tester.widget<ExerciseVideo>(find.byType(ExerciseVideo));
        expect(player.poseHubActionOf!(actions.first.id), same(actions.first));
        expect(player.poseHubMediaPreparer, same(services.poseHubPreparer));
        expect(video.mediaPreparer, isA<PoseHubMediaPrefetcher>());
        expect(video.mediaPreparer, isNot(same(services.poseHubPreparer)));
        expect(find.byType(PoseHubStandingImage), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('skip')));
        await tester.pump();
        String counter() => tester
            .widget<TrainerRollingNumber>(find.byKey(const ValueKey('counter')))
            .value;
        final before = int.parse(counter());
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(int.parse(counter()), lessThan(before));
        pending[actions.first.id]!.completeError(
          StateError('UI transport failure'),
        );
        await tester.pump();
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(find.textContaining('准备失败'), findsNothing);
        final afterFailure = int.parse(counter());
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(int.parse(counter()), lessThan(afterFailure));
        await tester.tap(find.byKey(const ValueKey('pause')));
        await tester.pump();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        final paused = counter();
        await tester.pump(const Duration(seconds: 2));
        expect(counter(), paused);
        expect(
          tester
              .widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia))
              .playing,
          isFalse,
        );
        expect(
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
          isTrue,
        );
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('pause')));
        await tester.pump();
        expect(
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
          isFalse,
        );
        expect(platform.uris, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        for (final ready in pending.values) {
          if (!ready.isCompleted) ready.complete(base);
        }
        repo.dispose();
      },
    );
  }
}
