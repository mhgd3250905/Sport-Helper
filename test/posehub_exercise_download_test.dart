import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/posehub_download_status.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

/// UI contract fake. Cache integrity and download de-duplication belong to the
/// repository tests; no dummy bytes are admitted under actual SDK checksums.
class _Repo extends Fake implements PoseHubMediaRepository {
  _Repo([String root = 'file:///ui-contract-pack/'])
    : mediaBaseUri = Uri.parse(root);
  @override
  final Uri mediaBaseUri;
  final actionRequests = <String>[];
  final fileRequests = <coach.PoseHubPackFile>[];
  final _actions = <String, Completer<Uri>>{};
  final _files = <String, Completer<Uri>>{};
  final _states = <String, ValueNotifier<PoseHubDownloadState>>{};
  final _fileStates = <String, ValueNotifier<PoseHubDownloadState>>{};

  @override
  ValueNotifier<PoseHubDownloadState> watchAction(String id) =>
      _states.putIfAbsent(
        id,
        () => ValueNotifier(
          const PoseHubDownloadState(phase: PoseHubDownloadPhase.idle),
        ),
      );
  @override
  ValueNotifier<PoseHubDownloadState> watchFile(coach.PoseHubPackFile file) =>
      _fileStates.putIfAbsent(
        file.sha256,
        () => ValueNotifier(
          const PoseHubDownloadState(phase: PoseHubDownloadPhase.idle),
        ),
      );
  @override
  Future<Uri> ensureAction(String id) {
    actionRequests.add(id);
    final previous = _actions[id];
    if (previous == null || previous.isCompleted) {
      _actions[id] = Completer<Uri>();
    }
    return _actions[id]!.future;
  }

  @override
  Future<Uri> ensureFile(coach.PoseHubPackFile file) {
    fileRequests.add(file);
    final previous = _files[file.sha256];
    if (previous == null || previous.isCompleted) {
      _files[file.sha256] = Completer<Uri>();
    }
    return _files[file.sha256]!.future;
  }

  void state(
    String id,
    PoseHubDownloadPhase phase, {
    int bytes = 0,
    int total = 0,
  }) => watchAction(id).value = PoseHubDownloadState(
    phase: phase,
    receivedBytes: bytes,
    totalBytes: total,
    error: phase == PoseHubDownloadPhase.failed
        ? StateError('test transfer failure')
        : null,
  );
  void completeAction(String id) {
    state(id, PoseHubDownloadPhase.ready);
    _actions[id]!.complete(mediaBaseUri);
  }

  void failAction(String id) {
    state(id, PoseHubDownloadPhase.failed);
    _actions[id]!.completeError(StateError('test transfer failure'));
  }

  void completeFile(coach.PoseHubPackFile file) =>
      _files[file.sha256]!.complete(file.resolve(mediaBaseUri));
  void failFile(String id, coach.PoseHubPackFile file) {
    state(id, PoseHubDownloadPhase.failed);
    _files[file.sha256]!.completeError(StateError('test cover failure'));
  }

  @override
  void dispose() {
    for (final notifier in [..._states.values, ..._fileStates.values]) {
      notifier.dispose();
    }
  }
}

class _Storage implements LocalStateStorage {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _VideoPlatform extends PackedAlphaPlatform
    implements PackedAlphaUriPlatform {
  final uris = <Uri>[];
  final commands = <(int, String, Object?)>[];
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('No old asset source');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    uris.add(uri);
    return (playerId: uris.length, textureId: uris.length + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    commands.add((id, type, value));
    return null;
  }

  void ready(int id) => eventsController.add({'playerId': id, 'type': 'ready'});
}

Exercise _exercise(coach.PoseHubPackAction action) => Exercise(
  id: action.id,
  name: action.nameZh,
  muscles: const [],
  unilateral: false,
  category: ExerciseCategory.core,
  equipment: const [],
  position: 'supine',
  level: 1,
  scenes: const ['home'],
  dose: const Dose(mode: DoseMode.time, sets: 1, seconds: 30, restSeconds: 0),
  repSeconds: null,
  cues: const [],
  cautions: const [],
  alternative: null,
  media: ExerciseMedia(
    id: action.id,
    video: 'assets/old-video-must-not-load.mp4',
    poster: 'assets/old-poster-must-not-load.webp',
    loopSeconds: 8,
    posterSeconds: 0,
    source: 'UI contract fixture',
  ),
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late _Repo repo;
  late _VideoPlatform platform;
  late DrillMediaPlaybackHandle handle;

  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    repo = _Repo();
    platform = _VideoPlatform();
    handle = DrillMediaPlaybackHandle();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SfColors.palette = SfPalette.dark;
    handle.dispose();
    repo.dispose();
    await platform.eventsController.close();
  });

  Widget show({
    coach.PoseHubPackAction? action,
    _Repo? source,
    bool playing = true,
    bool paused = false,
    bool covered = false,
  }) {
    final services = AppServices(
      library: ExerciseLibrary([]),
      catalog: TemplateCatalog([]),
      store: AppStore(_Storage()),
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
      poseHubCatalog: catalog,
      poseHubMedia: source ?? repo,
    );
    return AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(),
        builder: (_, child) => SfPaletteScope(child: child!),
        home: Scaffold(
          body: TickerMode(
            enabled: !covered,
            child: SizedBox.square(
              dimension: 280,
              child: ExerciseVideo(
                exercise: _exercise(action ?? catalog.allActions.first),
                playing: playing,
                paused: paused,
                playbackHandle: handle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'download bytes, progress and retry use scoped tokens ${palette.brightness.name}',
      (tester) async {
        final id = catalog.allActions.first.id;
        var pageBuilds = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(palette),
            builder: (_, child) => SfPaletteScope(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (_) {
                  pageBuilds++;
                  return Center(
                    child: SizedBox(
                      width: 240,
                      child: PoseHubDownloadStatus(repo: repo, actionId: id),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final initialBuilds = pageBuilds;
        repo.state(id, PoseHubDownloadPhase.downloading, bytes: 50, total: 100);
        await tester.pump();
        final progress = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('posehub-download-progress')),
        );
        expect(progress.value, .5);
        expect(progress.color, palette.accent);
        expect(find.text('50 B / 100 B'), findsOneWidget);
        expect(pageBuilds, initialBuilds);
        repo.state(id, PoseHubDownloadPhase.failed);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('posehub-download-error')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-download-retry')));
        expect(repo.actionRequests, [id]);
        repo.completeAction(id);
        await tester.pump();
        expect(find.text('动作素材已准备好'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'preview prepares only cover; playback then prepares current action',
    (tester) async {
      final action = catalog.allActions.first;
      await tester.pumpWidget(show(playing: false));
      expect(repo.fileRequests, [action.cover]);
      expect(repo.actionRequests, isEmpty);
      expect(find.byType(DrillMediaView), findsNothing);
      repo.completeFile(action.cover);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).playing,
        isFalse,
      );
      expect(platform.uris, isEmpty);
      await tester.pumpWidget(show());
      expect(repo.actionRequests, [action.id]);
      expect(find.byType(PoseHubPackMedia), findsNothing);
      repo.completeAction(action.id);
      await tester.pumpAndSettle();
      expect(platform.uris, [action.video.resolve(repo.mediaBaseUri)]);
      platform.ready(1);
      await tester.pump();
      await tester.pumpWidget(show(paused: true));
      await tester.pump();
      expect(
        tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).paused,
        isTrue,
      );
      expect(platform.commands, contains((1, 'pause', null)));
      final snapshot = await handle.capture();
      expect(snapshot!.mediaId, action.id);
      expect(snapshot.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed preview retry still requests no video', (tester) async {
    final action = catalog.allActions.first;
    await tester.pumpWidget(show(playing: false));
    repo.failFile(action.id, action.cover);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('posehub-download-retry')));
    await tester.pump();
    expect(repo.fileRequests, [action.cover, action.cover]);
    expect(repo.actionRequests, isEmpty);
    repo.completeFile(action.cover);
    await tester.pumpAndSettle();
    expect(find.byType(PoseHubPackMedia), findsOneWidget);
    expect(platform.uris, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed action retries current ID without falling back', (
    tester,
  ) async {
    final action = catalog.allActions.first;
    await tester.pumpWidget(show());
    repo.failAction(action.id);
    await tester.pumpAndSettle();
    expect(find.byType(DrillMediaView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('posehub-download-retry')));
    await tester.pump();
    expect(repo.actionRequests, [action.id, action.id]);
    repo.completeAction(action.id);
    await tester.pumpAndSettle();
    expect(platform.uris, [action.video.resolve(repo.mediaBaseUri)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late previous action cannot build or play after a switch', (
    tester,
  ) async {
    final first = catalog.allActions[0];
    final second = catalog.allActions[1];
    await tester.pumpWidget(show(action: first));
    await tester.pumpWidget(show(action: second));
    expect(repo.actionRequests, [first.id, second.id]);
    repo.completeAction(first.id);
    await tester.pumpAndSettle();
    expect(find.byType(PoseHubPackMedia), findsNothing);
    expect(platform.uris, isEmpty);
    repo.completeAction(second.id);
    await tester.pumpAndSettle();
    expect(platform.uris, [second.video.resolve(repo.mediaBaseUri)]);
    final snapshot = await handle.capture();
    expect(snapshot!.mediaId, second.id);
    expect(snapshot.videoSeconds, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await handle.capture(), isNull);
  });

  testWidgets('late previous repository cannot play after source changes', (
    tester,
  ) async {
    final replacement = _Repo('file:///replacement-ui-pack/');
    final action = catalog.allActions.first;
    await tester.pumpWidget(show());
    await tester.pumpWidget(show(source: replacement));
    repo.completeAction(action.id);
    await tester.pumpAndSettle();
    expect(platform.uris, isEmpty);
    replacement.completeAction(action.id);
    await tester.pumpAndSettle();
    expect(platform.uris, [action.video.resolve(replacement.mediaBaseUri)]);
    await tester.pumpWidget(const SizedBox.shrink());
    replacement.dispose();
  });

  testWidgets('download completion in background does not start video', (
    tester,
  ) async {
    final action = catalog.allActions.first;
    await tester.pumpWidget(show());
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    repo.completeAction(action.id);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).playing,
      isFalse,
    );
    expect(platform.uris, isEmpty);
    await tester.pumpWidget(show(paused: true));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    platform.ready(1);
    await tester.pump();
    expect(platform.commands.where((entry) => entry.$2 == 'play'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a newly mounted background view never starts its completed download',
    (tester) async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final action = catalog.allActions.first;
      await tester.pumpWidget(show());
      repo.completeAction(action.id);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).playing,
        isFalse,
      );
      expect(platform.uris, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'download completion under a covered route does not start video',
    (tester) async {
      final action = catalog.allActions.first;
      await tester.pumpWidget(show(covered: true));
      repo.completeAction(action.id);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).playing,
        isFalse,
      );
      expect(platform.uris, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
