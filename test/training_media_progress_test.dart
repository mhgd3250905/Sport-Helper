import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/single_practice_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_media_progress.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as sdk;

import 'posehub_ui_support.dart';
import 'support/widget_test_timeout.dart';

class _Repository extends PoseHubUiRepository
    implements PoseHubTrainingVideoPreparation {
  _Repository(this.catalog, {super.onEnsureFile})
    : super(mediaBaseUri: Uri.parse('file:///training-progress/'));
  final coach.PoseHubAppTestCatalog catalog;
  final videos = <(String, bool)>[];
  @override
  Future<Uri> ensureVideo(String actionId, {bool priority = false}) {
    videos.add((actionId, priority));
    return ensureFile(catalog.tryGet(actionId)!.video);
  }
}

class _Voice extends MutedVoiceOutput {
  var begins = 0;
  @override
  Future<void> begin() async => begins++;
}

class _Platform extends sdk.PackedAlphaPlatform
    implements sdk.PackedAlphaUriPlatform {
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final uris = <Uri>[];
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('Expected the verified file URI');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    uris.add(uri);
    return (playerId: uris.length, textureId: uris.length + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async => null;
  void emit(int id, String type) =>
      eventsController.add({'playerId': id, 'type': type});
}

TrainingPlan _plan(List<String> ids) => TrainingPlan(
  id: 'media-progress',
  source: 'template',
  title: '训练',
  summary: '',
  goal: 'mixed',
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
        for (final id in ids)
          PlanItem(
            exerciseId: id,
            mode: DoseMode.time,
            sets: 1,
            workSeconds: 60,
            perSide: false,
            restSeconds: 0,
          ),
      ],
    ),
  ],
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump();
  }
}

void main() {
  configureWidgetTestTimeout();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late _Platform platform;
  setUpAll(() async => catalog = await sdk.PoseHubActionLibrary.load());
  setUp(() {
    platform = _Platform();
    sdk.UgkPackedAlphaVideo.debugPlatform = platform;
    sdk.UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    sdk.UgkPackedAlphaVideo.debugPlatform = null;
    sdk.UgkPackedAlphaVideo.debugFilterBuilder = null;
    await platform.eventsController.close();
  });

  test(
    'all file phases, bytes and errors map without inventing total bytes',
    () {
      final error = StateError('safe fixture');
      for (final phase in PoseHubDownloadPhase.values) {
        final mapped = trainingDownloadState(
          PoseHubDownloadState(
            phase: phase,
            receivedBytes: 42,
            totalBytes: 100,
            error: error,
          ),
        );
        expect(mapped.phase.name, phase.name);
        expect(mapped.progress, .42);
        expect(mapped.error, same(error));
      }
      expect(
        trainingDownloadState(
          const PoseHubDownloadState(
            phase: PoseHubDownloadPhase.downloading,
            receivedBytes: 42,
          ),
        ).progress,
        isNull,
      );
    },
  );

  testWidgets('selecting a new action never carries the previous ready state', (
    tester,
  ) async {
    final actions = catalog.semanticCompleteActions.take(2).toList();
    final host = _Repository(catalog);
    final repository = TrainingMediaRepositoryBridge(
      catalog: catalog,
      host: host,
    );
    final current = CurrentTrainingDownload(repository);
    host.setFileState(
      actions[0].video,
      const PoseHubDownloadState(phase: PoseHubDownloadPhase.ready),
    );
    var selected = actions[0];
    Widget view() => MaterialApp(
      home: Builder(
        builder: (_) {
          current.select(selected);
          return ValueListenableBuilder<sdk.CatalogMediaDownloadState>(
            key: ValueKey(selected.id),
            valueListenable: current,
            builder: (_, value, _) => Text(value.phase.name),
          );
        },
      ),
    );
    await tester.pumpWidget(view());
    expect(find.text('ready'), findsOneWidget);
    selected = actions[1];
    await tester.pumpWidget(view());
    expect(find.text('idle'), findsOneWidget);
    host.setFileState(
      actions[0].video,
      const PoseHubDownloadState(phase: PoseHubDownloadPhase.failed),
    );
    host.setFileState(
      actions[1].video,
      const PoseHubDownloadState(phase: PoseHubDownloadPhase.queued),
    );
    await tester.pump();
    expect(find.text('queued'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    current.dispose();
    repository.dispose();
    host.dispose();
  });

  testWidgets(
    'training requests current during preparation and next only after ready; clock and audio continue',
    (tester) async {
      final actions = catalog.semanticCompleteActions.take(3).toList();
      final pending = {for (final a in actions) a.video.path: Completer<Uri>()};
      final host = _Repository(
        catalog,
        onEnsureFile: (file) => pending[file.path]!.future,
      );
      final voice = _Voice();
      final services = poseHubUiServices(
        catalog: catalog,
        media: host,
        voiceOutput: voice,
        library: ExerciseLibrary(actions.map(poseHubUiExercise).toList()),
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: PlayerPage(plan: _plan(actions.map((a) => a.id).toList())),
        ),
      );
      await _frames(tester);
      expect(host.videos, [(actions[0].id, true)]);
      expect(host.actionRequests, isEmpty);
      expect(voice.begins, 1);
      final before = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('counter')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join();
      await tester.pump(const Duration(seconds: 1));
      final after = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('counter')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .join();
      expect(after, isNot(before));
      expect(host.videos, [(actions[0].id, true)]);
      pending[actions[0].video.path]!.complete(
        actions[0].video.resolve(host.mediaBaseUri),
      );
      await _frames(tester);
      expect(host.videos, [(actions[0].id, true), (actions[1].id, false)]);
      expect(platform.uris, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pending[actions[1].video.path]!.complete(
        actions[1].video.resolve(host.mediaBaseUri),
      );
      await _frames(tester);
      host.dispose();
      services.store.dispose();
    },
  );

  testWidgets(
    'native HUD retry re-requests the current video and replaces a failed decoder',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final host = _Repository(catalog);
      final services = poseHubUiServices(
        catalog: catalog,
        media: host,
        library: ExerciseLibrary([poseHubUiExercise(action)]),
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: PlayerPage(plan: _plan([action.id])),
        ),
      );
      await _frames(tester);
      expect(platform.uris, hasLength(1));
      platform.emit(1, 'ready');
      platform.emit(1, 'first-frame');
      await _frames(tester);
      platform.emit(1, 'error');
      await _frames(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const ValueKey('media-download-retry')),
        findsOneWidget,
      );
      final requests = host.videos.length;
      await tester.tap(find.byKey(const ValueKey('media-download-indicator')));
      await _frames(tester);
      expect(host.videos.length, requests + 1);
      expect(host.videos.last, (action.id, true));
      expect(platform.uris, hasLength(2));
      platform.emit(2, 'ready');
      platform.emit(2, 'first-frame');
      await _frames(tester);
      expect(find.byKey(const ValueKey('media-download-retry')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      host.dispose();
      services.store.dispose();
    },
  );

  testWidgets(
    'one decoder binds issue and download handles without owning them',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final host = _Repository(catalog);
      final services = poseHubUiServices(
        catalog: catalog,
        media: host,
        library: ExerciseLibrary([poseHubUiExercise(action)]),
      );
      final repository = TrainingMediaRepositoryBridge(
        catalog: catalog,
        host: host,
      );
      final current = CurrentTrainingDownload(repository)..select(action);
      final issue = sdk.DrillMediaPlaybackHandle();
      final download = sdk.DrillMediaPlaybackHandle();
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: Scaffold(
            body: SizedBox.square(
              dimension: 240,
              child: ExerciseVideo(
                exercise: poseHubUiExercise(action),
                training: true,
                trainingProgress: true,
                mediaPreparer: TrainingVideoPreparer(repository, current),
                playbackHandle: issue,
                downloadPlaybackHandle: download,
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(platform.uris, hasLength(1));
      platform.emit(1, 'ready');
      platform.emit(1, 'first-frame');
      await _frames(tester);
      for (final handle in [issue, download]) {
        expect(handle.isBound, isTrue);
        expect(handle.hasFrame, isTrue);
        expect((await handle.capture())?.mediaId, action.id);
      }
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
      for (final handle in [issue, download]) {
        expect(handle.isBound, isFalse);
        final owner = Object();
        handle.bind(owner: owner, mediaId: 'still-usable', controller: null);
        expect(
          handle.isBound,
          isTrue,
          reason: 'The view must not dispose caller handles',
        );
        handle.unbind(owner);
        handle.dispose();
      }
      current.dispose();
      repository.dispose();
      host.dispose();
      services.store.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single training uses the native policy HUD while non-playing detail stays offline',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final pending = Completer<Uri>();
      final host = _Repository(catalog, onEnsureFile: (_) => pending.future);
      final exercise = poseHubUiExercise(action);
      final services = poseHubUiServices(
        catalog: catalog,
        media: host,
        library: ExerciseLibrary([exercise]),
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: Scaffold(
            body: ExerciseVideo(exercise: exercise, playing: false),
          ),
        ),
      );
      await _frames(tester);
      expect(host.fileRequests, isEmpty);
      expect(platform.uris, isEmpty);
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: SinglePracticePage(
            exercise: exercise,
            page: sdk.PoseHubSinglePracticePage(
              action: action,
              mediaBaseUri: host.mediaBaseUri,
            ),
          ),
        ),
      );
      await _frames(tester);
      final player = tester.widget<sdk.TrainerPlayer>(
        find.byType(sdk.TrainerPlayer),
      );
      expect(player.showMediaDownloadIndicator, isTrue);
      expect(player.poseHubMediaPreparer, isNull);
      expect(host.videos.every((v) => v == (action.id, true)), isTrue);
      expect(host.videos, isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(ValueKey('media-download-${action.id}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      pending.complete(action.video.resolve(host.mediaBaseUri));
      await _frames(tester);
      host.dispose();
      services.store.dispose();
    },
  );
}
