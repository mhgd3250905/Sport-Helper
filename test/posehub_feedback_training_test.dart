import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_media_progress.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';
import 'support/widget_test_timeout.dart';

class _Voice extends MutedVoiceOutput {
  var begins = 0;
  @override
  Future<void> begin() async => begins++;
}

class _TrainingRepository extends PoseHubUiRepository
    implements PoseHubTrainingVideoPreparation {
  _TrainingRepository(
    this.catalog, {
    required super.mediaBaseUri,
    super.onEnsureFile,
  });
  final coach.PoseHubAppTestCatalog catalog;
  @override
  Future<Uri> ensureVideo(String actionId, {bool priority = false}) =>
      ensureFile(catalog.tryGet(actionId)!.video);
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

/// r2-v1 ships no definition-incomplete action, so the pending legacy case is
/// built from a copy of the real catalogue with its first action marked
/// incomplete (the shape r1-v3 used for 训练说明待补 actions).
coach.PoseHubAppTestCatalog _withPendingFirst(
  coach.PoseHubAppTestCatalog source,
) {
  final raw = jsonDecode(jsonEncode(source.raw)) as Map<String, dynamic>;
  final actions = (raw['actions'] as List).cast<Map<String, dynamic>>();
  final first = actions.first;
  final id = first['id'] as String;
  first['trainingDefinitionComplete'] = false;
  first['availableForTraining'] = false;
  final semantics = first['trainingSemantics'] as Map<String, dynamic>;
  semantics['definitionComplete'] = false;
  semantics['status'] = 'partial-unreviewed';
  semantics['missingRequiredFields'] = ['defaultDose'];
  final summary = raw['trainingSemantics'] as Map<String, dynamic>;
  final complete = (summary['definitionCompleteIds'] as List)..remove(id);
  summary['definitionCompleteCount'] = complete.length;
  summary['incompleteActionIds'] = [
    ...(summary['incompleteActionIds'] as List? ?? const []),
    id,
  ];
  return coach.PoseHubAppTestCatalog.fromJson(raw);
}

void main() {
  configureWidgetTestTimeout();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubUiVideoPlatform platform;
  final base = Uri.parse('file:///ui-contract-pack/');
  setUpAll(
    () async => catalog = _withPendingFirst(await PoseHubActionLibrary.load()),
  );
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
          for (final action in actions) action.video.path: Completer<Uri>(),
        };
        final repo = _TrainingRepository(
          catalog,
          mediaBaseUri: base,
          onEnsureFile: (file) => pending[file.path]!.future,
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
        expect(repo.actionRequests, isEmpty);
        expect(repo.fileRequests, [actions.first.video]);
        final player = tester.widget<TrainerPlayer>(find.byType(TrainerPlayer));
        final video = tester.widget<ExerciseVideo>(find.byType(ExerciseVideo));
        expect(player.poseHubActionOf!(actions.first.id), same(actions.first));
        expect(player.poseHubMediaPreparer, isA<TrainingVideoPreparer>());
        expect(
          player.poseHubMediaPreparer,
          isNot(same(services.poseHubPreparer)),
        );
        expect(video.mediaPreparer, isA<PoseHubMediaPrefetcher>());
        expect(video.mediaPreparer, isNot(same(services.poseHubPreparer)));
        expect(find.byType(ExerciseFrameZero), findsOneWidget);
        expect(find.byType(CachedExerciseMedia), findsOneWidget);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        expect(video.training, isTrue);
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
        pending[actions.first.video.path]!.completeError(
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
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        expect(find.byType(ExerciseFrameZero), findsOneWidget);
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

  testWidgets(
    'non-training playback keeps the original whole-action preparer',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final pending = Completer<Uri>();
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) => pending.future,
      );
      final services = poseHubUiServices(
        catalog: catalog,
        media: repo,
        library: ExerciseLibrary([poseHubUiExercise(action)]),
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: Scaffold(
            body: SizedBox.square(
              dimension: 240,
              child: ExerciseVideo(exercise: poseHubUiExercise(action)),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      final media = tester.widget<CachedExerciseMedia>(
        find.byType(CachedExerciseMedia),
      );
      expect(media.mediaPreparer, same(services.poseHubPreparer));
      expect(repo.actionRequests, [action.id]);
      expect(repo.fileRequests, isEmpty);
      expect(media.training, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(base);
      await tester.pump();
      repo.dispose();
      services.store.dispose();
    },
  );
}
