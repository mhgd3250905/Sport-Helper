import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/guide_media.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'app_flow_test.dart' show services;
import 'posehub_ui_support.dart';

class _MissingImages extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (RegExp(r'\.(?:webp|png|jpe?g)$').hasMatch(key)) {
      return Future.error(FlutterError('Intentionally unavailable poster.'));
    }
    return rootBundle.load(key);
  }
}

class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.files);
  final Map<String, List<int>> files;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(files[key]!));
}

class _LocalCache extends PoseHubUiRepository
    implements PoseHubVideoCacheAccess {
  _LocalCache(this.cached, {Future<Uri> Function(String)? prepare})
    : super(
        mediaBaseUri: Uri.parse('file:///unused/'),
        onEnsureAction: prepare,
      );
  Uri? cached;
  final queries = <String>[];
  final events = <String>[];
  var pins = 0;

  @override
  Future<Uri?> cachedVideo(String actionId) async {
    queries.add(actionId);
    events.add('query');
    return cached;
  }

  @override
  VoidCallback retainVideo(String actionId) {
    pins++;
    events.add('pin');
    var released = false;
    return () {
      if (released) return;
      released = true;
      pins--;
      events.add('release');
    };
  }
}

class _NoDecoder extends PackedAlphaPlatform implements PackedAlphaUriPlatform {
  var creations = 0;
  var allowPlayback = false;
  final operations = <String>[];
  final stream = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => stream.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      createUri(Uri(scheme: 'asset', path: '/$asset'));
  @override
  Future<({int playerId, int textureId})> createUri(Uri source) async {
    creations++;
    if (allowPlayback) return (playerId: creations, textureId: creations + 100);
    throw StateError('A missing poster must not create a decoder.');
  }

  @override
  Future<Object?> command(int playerId, String type, [Object? value]) async {
    operations.add(type);
    return type == 'position' ? .25 : null;
  }

  void ready() {
    stream.add({'playerId': creations, 'type': 'ready'});
    stream.add({'playerId': creations, 'type': 'first-frame'});
  }
}

void _androidTest(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

String? _filePath(ImageProvider provider) => switch (provider) {
  FileImage(:final file) => file.path,
  ResizeImage(:final imageProvider) => _filePath(imageProvider),
  _ => null,
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartfit/guide_poster');
  late coach.PoseHubAppTestCatalog catalog;
  late Directory temporary;
  late File poster;
  late File video;
  late Uri mediaBase;
  late _NoDecoder platform;
  late List<MethodCall> calls;
  late Future<String?> Function(MethodCall) extract;
  final applications = <AppServices>{};

  setUpAll(() async {
    catalog = await PoseHubActionLibrary.load();
    temporary = await Directory.systemTemp.createTemp('smartfit-guide-poster-');
    final bytes = await rootBundle.load(
      'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/'
      '${catalog.semanticCompleteActions.first.id}.webp',
    );
    poster = await File('${temporary.path}/cached-frame.webp').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    mediaBase = Directory('${temporary.path}/verified-pack').uri;
    video = File.fromUri(
      catalog.semanticCompleteActions.first.video.resolve(mediaBase),
    );
    await video.parent.create(recursive: true);
    await video.writeAsBytes([0, 0, 0, 8, 102, 116, 121, 112]);
  });

  tearDownAll(() => temporary.delete(recursive: true));

  setUp(() {
    calls = [];
    extract = (_) async => poster.path;
    platform = _NoDecoder();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return extract(call);
    });
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    await platform.stream.close();
    SfColors.palette = SfPalette.dark;
  });

  Future<void> show(
    WidgetTester tester,
    AppServices app,
    Exercise exercise, {
    bool missing = true,
  }) async {
    if (applications.add(app)) {
      addTearDown(() async {
        if (applications.remove(app)) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await app.dispose();
        }
      });
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final coordinator = GuidePreviewCoordinator();
    addTearDown(coordinator.dispose);
    Widget media = SizedBox(
      width: 320,
      height: 240,
      child: GuideMedia(
        exercise: exercise,
        slot: 'fixture',
        coordinator: coordinator,
      ),
    );
    if (missing) {
      media = DefaultAssetBundle(bundle: _MissingImages(), child: media);
    }
    await tester.pumpWidget(
      AppScope(
        services: app,
        child: MaterialApp(
          theme: buildTheme(SfPalette.light),
          themeAnimationDuration: Duration.zero,
          builder: (_, child) => SfPaletteScope(child: child!),
          home: Scaffold(body: Center(child: media)),
        ),
      ),
    );
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester, AppServices app) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await app.dispose();
    applications.remove(app);
  }

  Future<(TrainingMediaRepository, File)> legacyRepository({
    required bool hit,
  }) async {
    const root = 'assets/training_media/v0.3.0-app/';
    final bytes = await video.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final package = utf8.encode(
      jsonEncode({
        'files': [
          {
            'path': '../v0.3.0/realistic/light/h-catcow-quad.mp4',
            'bytes': bytes.length,
            'sha256': digest,
          },
        ],
      }),
    );
    final files = <String, List<int>>{
      '${root}packages/realistic-light.json': package,
      '${root}app-manifest.json': utf8.encode(
        jsonEncode({
          'version': '0.3.0',
          'actions': [
            {'id': 'h-catcow-quad', 'nameZh': '猫牛式', 'releaseEligible': true},
          ],
          'packages': {
            'realistic-light': {
              'kind': 'video',
              'actionIds': ['h-catcow-quad'],
              'totalBytes': bytes.length,
              'fileCount': 1,
              'manifest': {
                'path': 'packages/realistic-light.json',
                'bytes': package.length,
                'sha256': sha256.convert(package).toString(),
              },
            },
          },
        }),
      ),
    };
    final cache = await Directory(
      '${temporary.path}/legacy-${hit ? 'hit' : 'miss'}',
    ).create();
    final cached = File('${cache.path}/training-media/0.3.0/$digest');
    if (hit) {
      await cached.parent.create(recursive: true);
      await cached.writeAsBytes(bytes);
    }
    final repository = await TrainingMediaRepository.create(
      manifestAsset: '${root}app-manifest.json',
      baseUrls: const [],
      bundle: _ManifestBundle(files),
      bundledAssetKeys: files.keys,
      cacheDirectory: cache.path,
      networkProbe: () async => TrainingMediaNetwork.offline,
    );
    return (repository, cached);
  }

  _androidTest(
    'normal 219 frame performs no query extraction or decoder work',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final cache = _LocalCache(video.uri);
      final app = poseHubUiServices(catalog: catalog, media: cache);
      await show(tester, app, poseHubUiExercise(action), missing: false);
      expect(calls, isEmpty);
      expect(cache.queries, isEmpty);
      expect(cache.pins, 0);
      expect(cache.actionRequests, isEmpty);
      expect(platform.creations, 0);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      await close(tester, app);
      expect(tester.takeException(), isNull);
    },
  );

  _androidTest(
    'all missing covers use pinned local frame-zero cache without decoding',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final cache = _LocalCache(video.uri);
      final app = poseHubUiServices(catalog: catalog, media: cache);
      extract = (call) async {
        expect(
          cache.pins,
          1,
          reason: 'Native extraction retains its input file.',
        );
        return poster.path;
      };
      await show(tester, app, poseHubUiExercise(action));
      expect(calls, hasLength(1));
      final arguments = calls.single.arguments as Map;
      expect(calls.single.method, 'frameZero');
      expect(arguments['source'], video.uri.toString());
      expect(arguments['width'], 720);
      expect(arguments['timeUs'], 0);
      expect(arguments['packedAlpha'], isTrue);
      expect(cache.events, ['pin', 'query', 'release']);
      final firstImages = tester.widgetList<Image>(find.byType(Image));
      expect(
        firstImages.map((image) => _filePath(image.image)),
        contains(poster.path),
      );
      expect(cache.actionRequests, isEmpty);
      expect(cache.fileRequests, isEmpty);
      expect(platform.creations, 0);
      // A fresh widget rechecks the same native disk cache key and reuses the
      // same local WebP, without preparing the pack or constructing a player.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await show(tester, app, poseHubUiExercise(action));
      expect(calls, hasLength(2));
      expect((calls.last.arguments as Map)['cacheKey'], arguments['cacheKey']);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => _filePath(image.image)),
        contains(poster.path),
      );
      expect(cache.pins, 0);
      expect(cache.actionRequests, isEmpty);
      expect(platform.creations, 0);
      await close(tester, app);
      expect(tester.takeException(), isNull);
    },
  );

  _androidTest(
    'missing covers and a cache miss never start an implicit download',
    (tester) async {
      final cache = _LocalCache(null);
      final app = poseHubUiServices(catalog: catalog, media: cache);
      await show(
        tester,
        app,
        poseHubUiExercise(catalog.semanticCompleteActions.first),
      );
      expect(cache.queries, hasLength(1));
      expect(cache.events, ['pin', 'query', 'release']);
      expect(cache.pins, 0);
      expect(cache.actionRequests, isEmpty);
      expect(cache.fileRequests, isEmpty);
      expect(calls, isEmpty);
      expect(platform.creations, 0);
      await close(tester, app);
      expect(tester.takeException(), isNull);
    },
  );

  _androidTest(
    'cache miss recovers a frame after explicit download and keeps it after retire',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final gate = Completer<Uri>();
      late _LocalCache cache;
      cache = _LocalCache(
        null,
        prepare: (_) async {
          final base = await gate.future;
          cache.cached = video.uri;
          return base;
        },
      );
      final app = poseHubUiServices(catalog: catalog, media: cache);
      await show(tester, app, poseHubUiExercise(action));
      expect(cache.queries, hasLength(1));
      expect(calls, isEmpty);
      expect(cache.actionRequests, isEmpty);
      expect(platform.creations, 0);
      platform.allowPlayback = true;
      await tester.tap(
        find.byKey(const ValueKey('guide-media-control-fixture')),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump();
      }
      expect(cache.actionRequests, [action.id]);
      gate.complete(mediaBase);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump();
      }
      expect(platform.creations, 1);
      expect(calls, hasLength(1));
      expect((calls.single.arguments as Map)['source'], video.uri.toString());
      platform.ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump(const Duration(milliseconds: 200));
      final guide = tester.widget<GuideMedia>(find.byType(GuideMedia));
      final stopping = guide.coordinator.stop();
      await tester.pump();
      await tester.pump();
      await stopping;
      expect(guide.coordinator.activeSlot, isNull);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      expect(platform.operations, contains('dispose'));
      expect(cache.pins, 0);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('cached-media-poster-fixture')),
            )
            .opacity,
        1,
      );
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => _filePath(image.image)),
        contains(poster.path),
      );
      expect(calls, hasLength(1));
      await close(tester, app);
      expect(tester.takeException(), isNull);
    },
  );

  _androidTest(
    'legacy missing covers extract the local asset without a player',
    (tester) async {
      final app = services();
      final exercise = app.library['h-catcow-quad'];
      await show(tester, app, exercise);
      expect(calls, hasLength(1));
      final arguments = calls.single.arguments as Map;
      expect(
        arguments['source'],
        Uri(
          scheme: 'asset',
          host: '',
          path: '/${exercise.media.lightVideo}',
        ).toString(),
      );
      expect(arguments['packedAlpha'], isFalse);
      expect(arguments['width'], 720);
      expect(arguments['timeUs'], 0);
      expect(platform.creations, 0);
      expect(find.byType(DrillMediaView), findsNothing);
      await close(tester, app);
      expect(tester.takeException(), isNull);
    },
  );

  for (final hit in [true, false]) {
    _androidTest(
      'legacy repository ${hit ? 'hit uses verified cache' : 'miss never uses deleted asset'}',
      (tester) async {
        final fixture = await tester.runAsync(() => legacyRepository(hit: hit));
        final (repository, cached) = fixture!;
        final base = services();
        final app = AppServices(
          library: base.library,
          catalog: base.catalog,
          store: base.store,
          voiceLibrary: base.voiceLibrary,
          voiceOutput: base.voiceOutput,
          media: repository,
        );
        await show(tester, app, app.library['h-catcow-quad']);
        for (var frame = 0; frame < 12; frame++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        if (hit) {
          expect(calls, hasLength(1));
          expect(
            (calls.single.arguments as Map)['source'],
            cached.uri.toString(),
          );
          expect((calls.single.arguments as Map)['packedAlpha'], isFalse);
        } else {
          expect(calls, isEmpty);
        }
        expect(platform.creations, 0);
        expect(find.byType(DrillMediaView), findsNothing);
        await close(tester, app);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
