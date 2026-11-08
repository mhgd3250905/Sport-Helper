import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/cached_exercise_media.dart'
    show GuideMedia, GuidePreviewCoordinator;
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/visible_video_progress.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as sdk;

import 'posehub_ui_support.dart';
import 'support.dart';
import 'support/widget_test_timeout.dart';

class _Videos extends PoseHubUiRepository
    implements
        PoseHubTrainingVideoPreparation,
        PoseHubMediaEntryPreparation,
        PoseHubVideoCacheAccess {
  _Videos(this.catalog, {super.onEnsureFile})
    : super(mediaBaseUri: Uri.parse('file:///visible-video-fixture/'));
  final coach.PoseHubAppTestCatalog catalog;
  final requests = <(String, bool, String?)>[];
  final entries = <String>[];
  var cached = false;
  var pins = 0;
  @override
  void markMediaEntry(String entry) => entries.add(entry);
  @override
  Future<Uri> ensureVideo(String id, {bool priority = false}) {
    requests.add((id, priority, null));
    return ensureFile(catalog.tryGet(id)!.video);
  }

  @override
  Future<Uri> ensureVideoForEntry(
    String id, {
    required String entry,
    bool priority = false,
  }) {
    requests.add((id, priority, entry));
    return ensureFile(catalog.tryGet(id)!.video);
  }

  @override
  Future<Uri?> cachedVideo(String id) async {
    if (!cached) return null;
    final video = catalog.tryGet(id)!.video;
    setFileState(
      video,
      PoseHubDownloadState(
        phase: PoseHubDownloadPhase.ready,
        receivedBytes: video.bytes,
        totalBytes: video.bytes,
      ),
    );
    return video.resolve(mediaBaseUri);
  }

  @override
  VoidCallback retainVideo(String id) {
    pins++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      pins--;
    };
  }
}

/// Widget transport only: no network, SHA validation or real decoder timings.
class _Platform extends sdk.PackedAlphaPlatform
    implements sdk.PackedAlphaUriPlatform {
  final controller = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final sources = <Uri>[];
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => controller.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('Expected verified URI');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    sources.add(uri);
    return (playerId: sources.length, textureId: sources.length + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async =>
      type == 'position' ? .1 : null;
  void emit(int id, String type) =>
      controller.add({'playerId': id, 'type': type});
}

/// Exercises the old public downloader contract, without another downloader.
class _Legacy extends ChangeNotifier implements sdk.TrainingMediaRepository {
  _Legacy(String id)
    : manifest = sdk.TrainingMediaManifest.fromJson({
        'version': '1.0.0',
        'actions': [
          {'id': id, 'nameZh': '兼容示范', 'releaseEligible': true},
        ],
        'packages': <String, Object?>{},
      });
  @override
  final sdk.TrainingMediaManifest manifest;
  @override
  bool get isOffline => false;
  @override
  bool get wifiOnly => false;
  @override
  List<sdk.TrainingMediaAction> get visibleActions => manifest.actions;
  final requests = <String>[];
  final pending = <Completer<sdk.TrainingMediaResource>>[];
  var state = const sdk.TrainingMediaState(sdk.TrainingMediaPhase.idle);
  @override
  int get cacheRevision => 0;
  @override
  sdk.TrainingMediaState stateFor(String id) => state;
  @override
  Future<sdk.TrainingMediaResource?> availableVideo(
    String id, {
    String skin = 'realistic',
    String theme = 'dark',
  }) async => null;
  @override
  Future<sdk.TrainingMediaResource> ensureVideo(
    String id, {
    String skin = 'realistic',
    String theme = 'dark',
  }) {
    requests.add(id);
    state = const sdk.TrainingMediaState(sdk.TrainingMediaPhase.queued);
    notifyListeners();
    final job = Completer<sdk.TrainingMediaResource>();
    pending.add(job);
    return job.future;
  }

  void fail() {
    state = const sdk.TrainingMediaState(sdk.TrainingMediaPhase.failed);
    notifyListeners();
    pending.last.completeError(StateError('fixture failure'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

void main() {
  configureWidgetTestTimeout();
  late coach.PoseHubAppTestCatalog catalog;
  late _Platform platform;
  setUpAll(() async => catalog = await sdk.PoseHubActionLibrary.load());
  setUp(() {
    platform = _Platform();
    sdk.UgkPackedAlphaVideo.debugPlatform = platform;
    sdk.UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    sdk.UgkPackedAlphaVideo.debugPlatform = null;
    sdk.UgkPackedAlphaVideo.debugFilterBuilder = null;
    await platform.controller.close();
  });

  Future<(AppServices, GuidePreviewCoordinator)> guide(
    WidgetTester tester,
    _Videos repo,
  ) async {
    final action = catalog.semanticCompleteActions.first;
    final services = poseHubUiServices(
      catalog: catalog,
      media: repo,
      library: ExerciseLibrary([poseHubUiExercise(action)]),
    );
    final coordinator = GuidePreviewCoordinator();
    await tester.pumpWidget(
      poseHubUiApp(
        palette: SfPalette.dark,
        services: services,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: GuideMedia(
                exercise: poseHubUiExercise(action),
                slot: 'visible',
                coordinator: coordinator,
              ),
            ),
          ),
        ),
      ),
    );
    await _frames(tester);
    return (services, coordinator);
  }

  testWidgets(
    'guide waits for user, requests only priority video and retries network failure',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final pending = <Completer<Uri>>[];
      final repo = _Videos(
        catalog,
        onEnsureFile: (_) {
          final job = Completer<Uri>();
          pending.add(job);
          return job.future;
        },
      );
      final (services, coordinator) = await guide(tester, repo);
      expect(repo.requests, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('guide-media-control-visible')),
      );
      await _frames(tester);
      expect(repo.requests, [(action.id, true, 'guide_preview')]);
      expect(repo.actionRequests, isEmpty);
      expect(repo.fileRequests, [action.video]);
      expect(repo.entries, ['guide_preview']);
      await tester.pump(const Duration(milliseconds: 401));
      await tester.pump(const Duration(milliseconds: 150));
      final hud = find.byKey(const ValueKey('media-download-indicator'));
      expect(hud, findsOneWidget);
      expect(
        tester
            .getRect(hud)
            .overlaps(
              tester.getRect(
                find.byKey(const ValueKey('guide-media-control-visible')),
              ),
            ),
        isFalse,
      );
      pending.first.completeError(StateError('fixture network failure'));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('media-download-retry')),
        findsOneWidget,
      );
      expect(repo.pins, 0);
      await tester.tap(hud);
      await _frames(tester);
      expect(repo.requests, hasLength(2));
      expect(repo.entries, ['guide_preview']);
      pending.last.complete(action.video.resolve(repo.mediaBaseUri));
      await _frames(tester);
      platform.emit(1, 'ready');
      platform.emit(1, 'first-frame');
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('media-download-ready')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
      repo.dispose();
      services.store.dispose();
    },
  );

  testWidgets(
    'guide cached video never flashes HUD; decoder failure has real retry',
    (tester) async {
      final repo = _Videos(catalog)..cached = true;
      final (services, coordinator) = await guide(tester, repo);
      await tester.tap(
        find.byKey(const ValueKey('guide-media-control-visible')),
      );
      await _frames(tester);
      platform.emit(1, 'ready');
      platform.emit(1, 'first-frame');
      await _frames(tester);
      await tester.pump(const Duration(milliseconds: 399));
      expect(
        find.byKey(const ValueKey('media-download-indicator')),
        findsNothing,
      );
      expect(repo.requests, isEmpty);
      platform.emit(1, 'error');
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('media-download-retry')),
        findsOneWidget,
      );
      expect(repo.pins, 0);
      final originalControl = find.byKey(
        const ValueKey('guide-media-control-visible'),
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: originalControl,
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label,
        '重试动作示范',
      );
      await tester.tap(originalControl);
      await _frames(tester);
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.$2, isTrue);
      expect(platform.sources, hasLength(2));
      expect(repo.entries, ['guide_preview']);
      await tester.pumpWidget(const SizedBox());
      coordinator.dispose();
      repo.dispose();
      services.store.dispose();
    },
  );

  test('legacy adapter keeps unknown bytes and observed blocked state', () {
    final unknown = legacyVideoDownloadState(
      const sdk.TrainingMediaState(
        sdk.TrainingMediaPhase.downloading,
        receivedBytes: 12,
      ),
    );
    expect(unknown.progress, isNull);
    expect(unknown.receivedBytes, 12);
    expect(
      legacyVideoDownloadState(
        const sdk.TrainingMediaState(sdk.TrainingMediaPhase.waitingForWifi),
      ).phase,
      sdk.CatalogMediaDownloadPhase.failed,
    );
  });

  testWidgets(
    'legacy sheet shares renderer handle, keeps failed HUD and retries old public API',
    (tester) async {
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog.instance = RuntimeLog(enabled: true);
      addTearDown(() => RuntimeLog.instance = previousLog);
      final exercise = loadLibrary().all.firstWhere(
        (e) =>
            !e.media.hasPackedAlpha && e.media.videoAvailableFor(light: false),
      );
      final repo = _Legacy(exercise.id);
      final services = AppServices(
        library: ExerciseLibrary([exercise]),
        catalog: TemplateCatalog([]),
        store: AppStore(PoseHubUiStorage()),
        voiceLibrary: VoiceLibrary.empty,
        voiceOutput: const sdk.MutedVoiceOutput(),
        media: repo,
      );
      late BuildContext source;
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                source = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      unawaited(showExerciseDetails(source, exercise));
      await _frames(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await _frames(tester);
      final play = find.byKey(const ValueKey('library-alpha-play'));
      if (play.evaluate().isNotEmpty) {
        expect(repo.requests, isEmpty);
        await tester.tap(play);
        await _frames(tester);
      }
      expect(repo.requests, [exercise.id]);
      final indicator = tester.widget<sdk.TrainerMediaDownloadIndicator>(
        find.byType(sdk.TrainerMediaDownloadIndicator),
      );
      final renderer = tester.widget<sdk.DrillMediaView>(
        find.byType(sdk.DrillMediaView),
      );
      expect(indicator.playbackHandle, same(renderer.playbackHandle));
      repo.fail();
      await _frames(tester);
      // Wait for the native indicator's delay and fade before a visible tap.
      await tester.pump(const Duration(milliseconds: 550));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('media-download-retry')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('media-download-indicator')));
      await _frames(tester);
      expect(repo.requests, [exercise.id, exercise.id]);
      final events = (jsonDecode(log.exportJson()) as Map)['events'] as List;
      final timing = events.where((e) => (e as Map)['event'] == 'media.timing');
      final fields = timing.map((e) => (e as Map)['fields'] as Map).toList();
      expect(
        fields.where(
          (f) => f['phase'] == 'entry' && f['entry'] == 'legacy_detail_preview',
        ),
        hasLength(1),
      );
      expect(
        fields.any(
          (f) =>
              f['phase'] == 'observed_queued' &&
              f['entry'] == 'legacy_detail_preview' &&
              f['source'] == 'legacy',
        ),
        isTrue,
      );
      expect(
        fields.any(
          (f) =>
              f.containsKey('firstByteAt') || f.containsKey('requestStartedAt'),
        ),
        isFalse,
      );
      repo.fail();
      await _frames(tester);
      await tester.pumpWidget(const SizedBox());
      await services.dispose();
      services.store.dispose();
    },
  );
}
