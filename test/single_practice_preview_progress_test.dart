import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/posehub_library_page.dart';
import 'package:smartfit/ui/single_practice_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' hide TrainingPosterImages;

import 'posehub_ui_support.dart';
import 'support/widget_test_timeout.dart';

class _PreviewRepository extends PoseHubUiRepository
    implements
        PoseHubTrainingVideoPreparation,
        PoseHubMediaEntryPreparation,
        PoseHubVideoCacheAccess {
  _PreviewRepository(this.catalog)
    : super(mediaBaseUri: Uri.parse('file:///preview-progress/'));
  final coach.PoseHubAppTestCatalog catalog;
  final entries = <String>[];
  final requests = <(String, String, bool)>[];
  final downloads = <Completer<Uri>>[];
  final cached = <String, Uri>{};
  final _jobs = <String, Future<Uri>>{};

  @override
  void markMediaEntry(String entry) => entries.add(entry);
  @override
  Future<Uri> ensureVideo(String actionId, {bool priority = false}) =>
      ensureVideoForEntry(actionId, entry: 'training', priority: priority);
  @override
  Future<Uri> ensureVideoForEntry(
    String actionId, {
    required String entry,
    bool priority = false,
  }) {
    requests.add((actionId, entry, priority));
    if (cached[actionId] case final uri?) return Future.value(uri);
    return _jobs.putIfAbsent(actionId, () {
      final file = catalog.tryGet(actionId)!.video;
      fileRequests.add(file);
      setFileState(
        file,
        PoseHubDownloadState(
          phase: PoseHubDownloadPhase.downloading,
          totalBytes: file.bytes,
        ),
      );
      final gate = Completer<Uri>();
      downloads.add(gate);
      final job = gate.future.then(
        (uri) {
          cached[actionId] = uri;
          setFileState(
            file,
            PoseHubDownloadState(
              phase: PoseHubDownloadPhase.ready,
              receivedBytes: file.bytes,
              totalBytes: file.bytes,
            ),
          );
          return uri;
        },
        onError: (Object error, StackTrace stack) {
          setFileState(
            file,
            PoseHubDownloadState(
              phase: PoseHubDownloadPhase.failed,
              totalBytes: file.bytes,
              error: error,
            ),
          );
          Error.throwWithStackTrace(error, stack);
        },
      );
      unawaited(
        job.then<void>(
          (_) => _jobs.remove(actionId),
          onError: (Object _, StackTrace _) {
            _jobs.remove(actionId);
          },
        ),
      );
      return job;
    });
  }

  void seed(coach.PoseHubPackAction action) {
    cached[action.id] = action.video.resolve(mediaBaseUri);
    setFileState(
      action.video,
      PoseHubDownloadState(
        phase: PoseHubDownloadPhase.ready,
        receivedBytes: action.video.bytes,
        totalBytes: action.video.bytes,
      ),
    );
  }

  @override
  Future<Uri?> cachedVideo(String actionId) async => cached[actionId];
  @override
  VoidCallback retainVideo(String actionId) => () {};
}

class _Voice extends MutedVoiceOutput {
  var begins = 0;
  @override
  Future<void> begin() async => begins++;
}

class _Platform extends PackedAlphaPlatform implements PackedAlphaUriPlatform {
  final stream = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final sources = <Uri>[];
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => stream.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('Expected verified URI');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    sources.add(uri);
    return (playerId: sources.length, textureId: sources.length + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async => null;
  void frame(int id) {
    stream.add({'playerId': id, 'type': 'ready'});
    stream.add({'playerId': id, 'type': 'first-frame'});
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

void main() {
  configureWidgetTestTimeout();
  TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late _Platform platform;
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    platform = _Platform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    await platform.stream.close();
  });

  Future<(AppServices, _Voice)> open(
    WidgetTester tester,
    String entry,
    _PreviewRepository repository,
  ) async {
    final action = catalog.semanticCompleteActions.first;
    final exercise = poseHubUiExercise(action);
    final voice = _Voice();
    final services = poseHubUiServices(
      catalog: catalog,
      media: repository,
      voiceOutput: voice,
      library: ExerciseLibrary([exercise]),
    );
    await tester.pumpWidget(
      poseHubUiApp(
        palette: SfPalette.dark,
        services: services,
        home: entry == 'action_library'
            ? PoseHubLibraryPage(catalog: catalog, media: repository)
            : Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const ValueKey('open-recommendation'),
                    onPressed: () =>
                        unawaited(showExerciseDetails(context, exercise)),
                    child: const Text('动作详情'),
                  ),
                ),
              ),
      ),
    );
    final source = tester.element(find.byType(Scaffold).first);
    await tester.runAsync(
      () => TrainingPosterImages.precacheAsset(
        source,
        '${PoseHubActionLibrary.standingAssetRoot}${action.id}.webp',
      ),
    );
    await tester.pump();
    final trigger = entry == 'action_library'
        ? find.byKey(ValueKey('posehub-action-${action.id}'))
        : find.byKey(const ValueKey('open-recommendation'));
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await _frames(tester);
    expect(find.byType(SinglePracticePage), findsOneWidget);
    final wrapper = tester.widget<SinglePracticePage>(
      find.byType(SinglePracticePage),
    );
    expect(wrapper.sourceEntry, entry);
    expect(wrapper.page.startMode, TrainerStartMode.preview);
    expect(
      TrainingMediaPolicyScope.maybeOf(
        tester.element(find.byType(TrainerPlayer)),
      ),
      isNotNull,
    );
    await tester.pump(const Duration(milliseconds: 350));
    await _frames(tester);
    return (services, voice);
  }

  for (final entry in ['action_library', 'recommendation']) {
    testWidgets(
      '$entry preview current video, delayed native HUD, retry and reuse',
      (tester) async {
        final repository = _PreviewRepository(catalog);
        final action = catalog.semanticCompleteActions.first;
        final (services, voice) = await open(tester, entry, repository);
        expect(repository.downloads, hasLength(1));
        expect(
          repository.requests.every((r) => r.$1 == action.id && r.$3),
          isTrue,
        );
        expect(repository.requests.map((r) => r.$2).toSet(), {
          '${entry}_preview',
        });
        expect(repository.entries, ['${entry}_preview']);
        expect(voice.begins, 0);
        expect(
          find.byKey(const ValueKey('media-download-indicator')),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 401));
        await _frames(tester);
        final hud = find.byKey(const ValueKey('media-download-indicator'));
        expect(hud, findsOneWidget);
        final rect = tester.getRect(hud);
        expect(
          rect.overlaps(
            tester.getRect(find.byKey(const ValueKey('info-card'))),
          ),
          isFalse,
        );
        expect(
          rect.overlaps(
            tester.getRect(find.byKey(const ValueKey('preview-labels'))),
          ),
          isFalse,
        );
        expect(
          rect.overlaps(
            tester.getRect(find.byKey(const ValueKey('start-training'))),
          ),
          isFalse,
        );
        repository.downloads.first.completeError(
          StateError('fixture download failure'),
        );
        await _frames(tester);
        expect(
          find.byKey(const ValueKey('media-download-retry')),
          findsOneWidget,
        );
        await tester.tap(hud);
        await _frames(tester);
        expect(repository.downloads, hasLength(2));
        repository.downloads.last.complete(
          action.video.resolve(repository.mediaBaseUri),
        );
        await _frames(tester);
        expect(platform.sources, hasLength(1));
        expect(
          find.byKey(const ValueKey('media-download-ready')),
          findsNothing,
        );
        expect(hud, findsOneWidget);
        platform.frame(1);
        await _frames(tester);
        final player = tester.element(find.byType(TrainerPlayer));
        final policy = TrainingMediaPolicyScope.maybeOf(player);
        await tester.tap(find.byKey(const ValueKey('start-training')));
        await _frames(tester);
        await tester.pump(const Duration(milliseconds: 350));
        await _frames(tester);
        expect(
          TrainingMediaPolicyScope.maybeOf(
            tester.element(find.byType(TrainerPlayer)),
          ),
          same(policy),
        );
        expect(
          repository.downloads,
          hasLength(2),
          reason: 'Starting training must reuse the verified preview video',
        );
        expect(repository.entries, ['${entry}_preview']);
        expect(voice.begins, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _frames(tester);
        repository.dispose();
        services.store.dispose();
      },
    );

    testWidgets('$entry cached preview never flashes a download ring', (
      tester,
    ) async {
      final action = catalog.semanticCompleteActions.first;
      final repository = _PreviewRepository(catalog)..seed(action);
      final (services, voice) = await open(tester, entry, repository);
      expect(platform.sources, hasLength(1));
      platform.frame(1);
      await _frames(tester);
      expect(
        repository.downloads,
        isEmpty,
        reason: 'Cache-only access must not call the fake HTTP transport',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey('media-download-indicator')),
        findsNothing,
      );
      expect(voice.begins, 0);
      expect(repository.entries, ['${entry}_preview']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
      repository.dispose();
      services.store.dispose();
    });
  }
}
