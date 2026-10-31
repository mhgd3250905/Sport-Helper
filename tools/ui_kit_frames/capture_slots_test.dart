// Shared capture driver. Both checkouts run these exact bytes and input JSON.
// The tiny adapter only crosses the old/new public constructor boundary.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/alpha_bounds.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/open_training.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachFailureBubble;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'capture_adapter.dart';

const _dpr = 2.625;
const _size = Size(412, 915);
const _key = ValueKey('capture-bubble');
const _stageIds = [
  'understand',
  'parameters',
  'actions',
  'planning',
  'review',
  'output',
];

class _Memory implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Content {
  _Content(
    this.app,
    this.bundle,
    this.plan,
    this.repo,
    this.legacyLibrary,
    this.legacyManifest,
  );
  final AppServices app;
  final AssetBundle bundle;
  final TrainingPlan plan;
  final PoseHubMediaRepository repo;
  final ExerciseLibrary legacyLibrary;
  final Map<String, dynamic> legacyManifest;
}

/// Only the two immutable historical images and their original metadata are
/// served here. All current PoseHub/Flutter asset requests use the real bundle.
class _LegacyBundle extends CachingAssetBundle {
  _LegacyBundle(this.delegate, this.files);
  final AssetBundle delegate;
  final Map<String, ByteData> files;
  @override
  Future<ByteData> load(String key) {
    if (files[key] case final data?) {
      return SynchronousFuture(data);
    }
    return delegate.load(key);
  }
}

Exercise _legacyExercise(Exercise original, String thumbnail) {
  final m = original.media;
  return Exercise(
    id: original.id,
    name: original.name,
    muscles: original.muscles,
    unilateral: original.unilateral,
    category: original.category,
    equipment: original.equipment,
    equipmentIds: original.equipmentIds,
    position: original.position,
    level: original.level,
    scenes: original.scenes,
    dose: original.dose,
    repSeconds: original.repSeconds,
    trainingRhythm: original.trainingRhythm,
    cues: original.cues,
    cautions: original.cautions,
    alternative: original.alternative,
    media: ExerciseMedia(
      id: m.id,
      video: m.video,
      poster: m.poster,
      loopSeconds: m.loopSeconds,
      posterSeconds: m.posterSeconds,
      source: m.source,
      videoAvailable: m.videoAvailable,
      lightVideo: m.lightVideo,
      lightPoster: m.lightPoster,
      lightVideoAvailable: m.lightVideoAvailable,
      playbackPoster: m.playbackPoster,
      lightPlaybackPoster: m.lightPlaybackPoster,
      packedAlphaVideo: m.packedAlphaVideo,
      alphaPlaybackPoster: m.alphaPlaybackPoster,
      alphaCover: m.alphaCover,
      alphaThumbnail: thumbnail,
      revision: m.revision,
      appTestOnly: m.appTestOnly,
    ),
  );
}

enum _Scene { bubble, delivery, focus, failure, cancelled, card }

coach.CoachSessionState _session(
  Map<String, dynamic> input, {
  String stage = 'actions',
  bool complete = false,
  bool changed = false,
}) {
  final params = Map<String, dynamic>.from(input['params'] as Map);
  if (changed) params['level'] = {'value': 2, 'source': 'user'};
  return coach.CoachSessionState(
    params: {
      for (final entry in params.entries)
        entry.key: coach.CoachParamValue(
          value: (entry.value as Map)['value'],
          source: (entry.value as Map)['source'] as String,
          turn: 1,
        ),
    },
    picks: List<String>.from(input['picks'] as List),
    task: coach.CoachTaskState(
      type: 'plan',
      reused: false,
      nodes: [
        for (final (index, id) in _stageIds.indexed)
          coach.CoachNodeState(
            id: id,
            status: complete || index < _stageIds.indexOf(stage)
                ? 'done'
                : id == stage
                ? 'current'
                : 'pending',
            stamp: 'captured source fact',
          ),
      ],
    ),
  );
}

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.content,
    required this.palette,
    required this.input,
    required this.boundary,
  });
  final _Content content;
  final SfPalette palette;
  final Map<String, dynamic> input;
  final GlobalKey boundary;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final navigator = GlobalKey<NavigatorState>();
  _Scene scene = _Scene.cancelled;
  late coach.CoachSessionState session = _session(widget.input);
  bool waiting = true, complete = false, preparing = true;
  bool legacy = false;
  String? focusTitle;
  int epoch = 0;
  BuildContext? source;

  void mutate(VoidCallback callback) => setState(callback);
  void reset(_Scene next, {bool useLegacy = false}) => setState(() {
    scene = next;
    epoch++;
    legacy = useLegacy;
    session = _session(
      useLegacy
          ? {
              ...widget.input,
              'picks': (widget.input['legacyAlpha'] as Map)['picks'],
            }
          : widget.input,
    );
    waiting = true;
    complete = false;
    preparing = true;
    focusTitle = null;
  });

  ExerciseLibrary get imageLibrary =>
      legacy ? widget.content.legacyLibrary : widget.content.app.library;

  Widget bubble(BuildContext context) => buildCaptureBubble(
    context: context,
    key: _key,
    state: session,
    library: imageLibrary,
    waiting: waiting,
    visualComplete: complete,
    onCancel: () => mutate(() => scene = _Scene.cancelled),
  );

  Widget card(BuildContext context) => PlanCard(
    plan: widget.content.plan,
    library: widget.content.app.library,
    saved: false,
    onSave: () {},
    onOpen: () {},
    onStart: () => unawaited(
      openTraining(
        context,
        plan: widget.content.plan,
        sourceEntry: 'golden_card',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.content.app,
    child: DefaultAssetBundle(
      bundle: widget.content.bundle,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: buildTheme(widget.palette),
        themeAnimationDuration: Duration.zero,
        builder: (_, child) => RepaintBoundary(
          key: widget.boundary,
          child: SfPaletteScope(child: child!),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
            child: Builder(
              builder: (context) {
                source = context;
                return withSmartfitCoachUi(
                  context,
                  Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: ValueKey('scene-$epoch'),
                          child: switch (scene) {
                            _Scene.bubble => bubble(context),
                            _Scene.delivery => buildCaptureDelivery(
                              preparing: preparing,
                              successful: true,
                              child: preparing
                                  ? bubble(context)
                                  : card(context),
                            ),
                            _Scene.focus => buildCaptureFocus(
                              title: focusTitle,
                              onClear: () => mutate(() => focusTitle = null),
                            ),
                            _Scene.failure => CoachFailureBubble(
                              enabled: true,
                              onRetry: () async {},
                            ),
                            _Scene.cancelled => const SizedBox.shrink(),
                            _Scene.card => card(context),
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<Map<String, Object?>>> _fonts(WidgetTester tester) async {
  final result = <Map<String, Object?>>[];
  await tester.runAsync(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.cast<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List).cast<Map>()) {
        final asset = font['asset'] as String;
        final data = await rootBundle.load(asset);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        loader.addFont(Future.value(data));
        result.add({
          'family': family['family'],
          'asset': asset,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        });
      }
      await loader.load();
    }
  });
  expect(result.any((font) => font['family'] == 'NotoSansSC'), isTrue);
  return result;
}

Map<String, Object?> _runtimeSnapshot(WidgetTester tester, _HostState host) {
  final bubble = find.byKey(_key);
  int? boundaries;
  final images = <Map<String, Object?>>[];
  if (bubble.evaluate().isNotEmpty) {
    expect(bubble, findsOneWidget);
    boundaries = find
        .descendant(of: bubble, matching: find.byType(RepaintBoundary))
        .evaluate()
        .length;
    expect(
      boundaries,
      4,
      reason: 'Actual bubble subtree, excluding App/router',
    );
    final seen = <int>{};
    for (final id in host.session.picks) {
      final exercise = host.imageLibrary.tryGet(id);
      if (exercise == null) continue;
      final finder = find.bySemanticsLabel(exercise.name);
      for (var i = 0; i < finder.evaluate().length; i++) {
        final node = tester.getSemantics(finder.at(i));
        if (!seen.add(node.id)) continue;
        final data = node.getSemanticsData();
        images.add({
          'actionId': id,
          'label': data.label,
          'isImage': data.flagsCollection.isImage,
          'rect': [
            data.rect.left,
            data.rect.top,
            data.rect.right,
            data.rect.bottom,
          ],
        });
      }
    }
    images.sort(
      (a, b) => (a['actionId'] as String).compareTo(b['actionId'] as String),
    );
  }
  Map<String, Object?>? clear;
  final focus = find.bySemanticsLabel('取消讨论计划');
  if (focus.evaluate().isNotEmpty) {
    final data = tester.getSemantics(focus.first).getSemanticsData();
    clear = {
      'label': data.label,
      'isButton': data.flagsCollection.isButton,
      'hasTap': data.hasAction(ui.SemanticsAction.tap),
      'rect': [
        data.rect.left,
        data.rect.top,
        data.rect.right,
        data.rect.bottom,
      ],
    };
  }
  final cropPainters = host.legacy
      ? find
            .descendant(
              of: find.byType(SfAlphaAsset),
              matching: find.byType(CustomPaint),
            )
            .evaluate()
            .length
      : 0;
  return {
    'bubbleRepaintBoundaryCount': boundaries,
    'libraryKind': host.legacy ? 'historical-legacy-alpha' : 'current-posehub',
    'imageSemantics': images,
    'focusClearSemantics': clear,
    'legacyCropPainterCount': cropPainters,
  };
}

Future<_Content> _content(
  WidgetTester tester,
  Map<String, dynamic> config,
  Map<String, dynamic> input,
  String theme,
) async {
  late _Content result;
  await tester.runAsync(() async {
    final sdk = await PoseHubActionLibrary.load();
    final content = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(sdk),
      legacyLibrary: ExerciseLibrary([]),
    );
    final images = await PoseHubBundledImages.load(
      catalogRevision: PoseHubActionLibrary.catalogSha256,
    );
    final repo = await PoseHubMediaRepository.create(
      catalog: sdk,
      catalogRevision: PoseHubActionLibrary.catalogSha256,
      mediaBaseUrls: const [],
      rootDirectory: '${config['mediaCache']}/$theme',
      bundledFileLoader: images.loadFile,
    );
    final store = AppStore(_Memory())..starfield = false;
    await store.acceptSafety(blocked: false);
    final app = AppServices(
      library: content.library,
      catalog: TemplateCatalog.fromJson(
        jsonDecode(await rootBundle.loadString('assets/library/templates.json'))
            as Map<String, dynamic>,
      ),
      store: store,
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
      poseHubCatalog: sdk,
      testCatalog: content.catalog,
    );
    final fixtureRoot = config['legacyFixtureRoot'] as String;
    final manifestBytes = await File(
      '$fixtureRoot/manifest.json',
    ).readAsBytes();
    final legacyInput = input['legacyAlpha'] as Map;
    expect(
      sha256.convert(manifestBytes).toString(),
      legacyInput['manifestSha256'],
    );
    final legacyManifest =
        jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final metadataBytes = await File(
      '$fixtureRoot/alpha-bounds.json',
    ).readAsBytes();
    final indexBytes = await File('$fixtureRoot/index.json').readAsBytes();
    expect(
      sha256.convert(metadataBytes).toString(),
      legacyInput['boundsSha256'],
    );
    expect(sha256.convert(indexBytes).toString(), legacyInput['indexSha256']);
    final files = <String, ByteData>{
      '${SfAlphaBounds.root}/alpha-bounds.json': ByteData.sublistView(
        metadataBytes,
      ),
      '${SfAlphaBounds.root}/index.json': ByteData.sublistView(indexBytes),
    };
    final legacyAssets = <String, String>{};
    for (final row in (legacyManifest['images'] as List).cast<Map>()) {
      final data = await File('$fixtureRoot/${row['fixture']}').readAsBytes();
      expect(data.length, row['bytes']);
      expect(sha256.convert(data).toString(), row['sha256']);
      files[row['asset'] as String] = ByteData.sublistView(data);
      legacyAssets[row['actionId'] as String] = row['asset'] as String;
    }
    final bundle = _LegacyBundle(
      PoseHubAssetBundle(catalog: sdk, installation: repo),
      files,
    );
    final crop = await SfAlphaBounds.load(bundle);
    for (final row in (legacyManifest['images'] as List).cast<Map>()) {
      final bounds = (row['bounds'] as List).cast<num>();
      final width = row['width'] as num, height = row['height'] as num;
      expect(
        crop.entries[row['asset']],
        Rect.fromLTRB(
          bounds[0] / width,
          bounds[1] / height,
          bounds[2] / width,
          bounds[3] / height,
        ),
      );
      expect(
        crop.entries[row['asset']],
        isNot(const Rect.fromLTWH(0, 0, 1, 1)),
      );
    }
    final legacyLibrary = ExerciseLibrary([
      for (final exercise in content.library.all)
        if (legacyAssets[exercise.id] case final thumbnail?)
          _legacyExercise(exercise, thumbnail)
        else
          exercise,
    ]);
    result = _Content(
      app,
      bundle,
      TrainingPlan.fromJson(Map<String, dynamic>.from(input['plan'] as Map)),
      repo,
      legacyLibrary,
      legacyManifest,
    );
  });
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configPath = String.fromEnvironment('SMARTFIT_UI_KIT_CAPTURE_CONFIG');
  final config =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
  final inputBytes = File(config['inputs'] as String).readAsBytesSync();
  final input = jsonDecode(utf8.decode(inputBytes)) as Map<String, dynamic>;
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final theme = palette.brightness.name;
    testWidgets('ui kit same-driver frames $theme', (tester) async {
      tester.view.physicalSize = _size * _dpr;
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        SfCutouts.animate = false;
        stdout.writeln('CAPTURE_STAGE $theme fonts');
        final fonts = await _fonts(tester);
        stdout.writeln('CAPTURE_STAGE $theme content');
        final content = await _content(tester, config, input, theme);
        final hostKey = GlobalKey<_HostState>();
        final boundaryKey = GlobalKey();
        final frames = <Map<String, Object?>>[];
        final output = Directory('${config['output']}/$theme');
        output.createSync(recursive: true);
        stdout.writeln('CAPTURE_STAGE $theme mount-blank');
        await tester.pumpWidget(
          _Host(
            key: hostKey,
            content: content,
            palette: palette,
            input: input,
            boundary: boundaryKey,
          ),
        );
        await tester.pump();
        final host = hostKey.currentState!;
        stdout.writeln('CAPTURE_STAGE $theme precache');
        await tester.runAsync(() async {
          for (final id in content.plan.exerciseIds) {
            final exercise = content.app.library[id];
            for (final asset in [
              exercise.media.alphaCover,
              exercise.media.alphaThumbnail,
            ]) {
              if (asset != null) {
                await precacheImage(AssetImage(asset), host.source!);
              }
            }
          }
          await TrainingPosterImages.precache(
            host.source!,
            content.app.library[content.plan.items.first.exerciseId],
          );
          for (final id in (input['legacyAlpha'] as Map)['picks'] as List) {
            final exercise = content.legacyLibrary[id as String];
            await precacheImage(
              AssetImage(exercise.media.alphaThumbnail!),
              host.source!,
            );
          }
        });
        await tester.pump();
        stdout.writeln('CAPTURE_STAGE $theme ready');
        host.reset(_Scene.bubble);
        await tester.pump();

        Future<void> capture(
          String name, {
          int? elapsedUs,
          double? fraction,
          Map<String, Object?> extra = const {},
        }) async {
          stdout.writeln('CAPTURE_FRAME $theme/$name');
          await tester.pump();
          expect(tester.takeException(), isNull);
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          expect(boundary.size, _size);
          final runtime = _runtimeSnapshot(tester, host);
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: _dpr);
            try {
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final bytes = data!.buffer.asUint8List(
                data.offsetInBytes,
                data.lengthInBytes,
              );
              String? historicalSha;
              if (config['historicalBase'] case final String historical) {
                final historicalFile = File('$historical/$theme/$name.png');
                if (await historicalFile.exists()) {
                  historicalSha = sha256
                      .convert(await historicalFile.readAsBytes())
                      .toString();
                  if (config['variant'] == 'base') {
                    expect(
                      sha256.convert(bytes).toString(),
                      historicalSha,
                      reason:
                          'Original 58 frames must retain historical PNG bytes',
                    );
                  }
                }
              }
              final file = File('${output.path}/$name.png');
              if (await file.exists()) {
                expect(
                  sha256.convert(await file.readAsBytes()).toString(),
                  sha256.convert(bytes).toString(),
                  reason: 'Preserve existing captured bytes',
                );
              } else {
                await file.writeAsBytes(bytes, flush: true);
              }
              frames.add({
                'frame': '$theme/$name.png',
                'bytes': bytes.length,
                'sha256': sha256.convert(bytes).toString(),
                'width': image.width,
                'height': image.height,
                'elapsedUs': ?elapsedUs,
                'fraction': ?fraction,
                'runtime': runtime,
                'historicalOriginalFrameSha256': ?historicalSha,
                if (historicalSha != null)
                  'historicalOriginalFrameByteIdentical':
                      sha256.convert(bytes).toString() == historicalSha,
                ...extra,
              });
            } finally {
              image.dispose();
            }
          });
        }

        for (var i = 0; i <= 4; i++) {
          if (i > 0) await tester.pump(const Duration(milliseconds: 400));
          await capture('waiting-${i * 400}ms', elapsedUs: i * 400000);
        }
        await capture('parameters-before', elapsedUs: 1600000);
        host.mutate(() => host.session = _session(input, changed: true));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));
        await capture('parameters-after', elapsedUs: 1860000);

        host.mutate(() {
          host.session = _session(
            input,
            stage: 'output',
            complete: true,
            changed: true,
          );
          host.waiting = false;
          host.complete = true;
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));
        await capture('complete', elapsedUs: 260000);

        host.reset(_Scene.failure);
        await tester.pump();
        await capture('failure');
        host.reset(_Scene.bubble);
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('generation-cancel-target')),
        );
        await tester.pump();
        expect(host.scene, _Scene.cancelled);
        await capture('cancelled');

        host.reset(_Scene.delivery);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1600));
        host.mutate(() => host.preparing = false);
        await tester.pump();
        for (var i = 0; i <= 4; i++) {
          if (i > 0) await tester.pump(const Duration(microseconds: 222500));
          await capture(
            'delivery-${i * 25}pct',
            elapsedUs: i * 222500,
            fraction: i / 4,
          );
        }

        host.reset(_Scene.focus);
        await tester.pump();
        host.mutate(() => host.focusTitle = content.plan.title);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));
        await capture('focus-appearing', elapsedUs: 90000, fraction: .5);
        await tester.pump(const Duration(milliseconds: 90));
        await capture('focus-held', elapsedUs: 180000, fraction: 1);
        await tester.tap(find.byKey(const ValueKey('plan-focus-clear')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        await capture('focus-clearing', elapsedUs: 60000, fraction: .5);
        await tester.pump(const Duration(milliseconds: 60));
        await capture('focus-cleared', elapsedUs: 120000, fraction: 1);

        host.reset(_Scene.card);
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => TrainingPosterImages.precache(
            host.source!,
            content.app.library[content.plan.items.first.exerciseId],
          ),
        );
        await tester.tap(find.byKey(ValueKey('plan-start-${content.plan.id}')));
        for (
          var i = 0;
          i < 12 &&
              find.byType(PlayerPage, skipOffstage: false).evaluate().isEmpty;
          i++
        ) {
          await tester.pump();
        }
        await tester.pump();
        final player = find.byType(PlayerPage, skipOffstage: false);
        expect(player, findsOneWidget);
        final route = ModalRoute.of(tester.element(player))!;
        expect(route.settings.name, 'player');
        for (var i = 0; i <= 4; i++) {
          if (i > 0) await tester.pump(const Duration(milliseconds: 75));
          await capture(
            'training-entry-${i * 25}pct',
            elapsedUs: i * 75000,
            fraction: i / 4,
            extra: {
              'routeValue': route.animation!.value,
              'routeStatus': route.animation!.status.name,
            },
          );
        }
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        beginCaptureExit(tester.element(player));
        await tester.pump();
        for (var i = 0; i <= 4; i++) {
          if (i > 0) await tester.pump(const Duration(milliseconds: 70));
          await capture(
            'training-exit-${i * 25}pct',
            elapsedUs: i * 70000,
            fraction: i / 4,
            extra: {
              'routeValue': route.animation!.value,
              'routeStatus': route.animation!.status.name,
            },
          );
        }
        host.navigator.currentState!.pop();
        await tester.pumpAndSettle();

        final capturePlan = input['capturePlan'] as Map;
        Future<void> captureSilhouettes({required bool legacy}) async {
          final prefix = legacy ? 'legacy' : 'posehub';
          host.reset(_Scene.bubble, useLegacy: legacy);
          await tester.pump();
          var elapsedMs = 0;
          for (final (kind, samples) in [
            ('reveal', capturePlan['firstRevealMs'] as List),
            ('crossfade', capturePlan['crossfadeMs'] as List),
          ]) {
            for (final sample in samples.cast<int>()) {
              await tester.pump(Duration(milliseconds: sample - elapsedMs));
              elapsedMs = sample;
              final runtime = _runtimeSnapshot(tester, host);
              final imageSemantics = (runtime['imageSemantics'] as List)
                  .cast<Map<String, Object?>>();
              final expected = sample == 430
                  ? host.session.picks.take(1).toList()
                  : sample == 1025
                  ? host.session.picks.take(2).toList()
                  : <String>[];
              for (final id in expected) {
                expect(
                  imageSemantics.any(
                    (row) =>
                        row['actionId'] == id &&
                        row['isImage'] == true &&
                        row['label'] == host.imageLibrary[id].name,
                  ),
                  isTrue,
                  reason:
                      '$prefix/$kind/$sample must expose original image semantics for $id',
                );
              }
              if (legacy && expected.isNotEmpty) {
                expect(
                  runtime['legacyCropPainterCount'],
                  greaterThanOrEqualTo(expected.length),
                  reason:
                      'Real legacy renderer must apply the original alpha bounds',
                );
              }
              await capture(
                '$prefix-$kind-${sample}ms',
                elapsedUs: sample * 1000,
                extra: {'expectedImageSemantics': expected},
              );
            }
          }
        }

        await captureSilhouettes(legacy: false);
        await captureSilhouettes(legacy: true);

        host.reset(_Scene.focus);
        await tester.pump();
        host.mutate(() => host.focusTitle = content.plan.title);
        await tester.pump();
        var focusElapsedMs = 0;
        for (final sample
            in (capturePlan['focusEnterMs'] as List).cast<int>()) {
          await tester.pump(Duration(milliseconds: sample - focusElapsedMs));
          focusElapsedMs = sample;
          await capture('focus-enter-${sample}ms', elapsedUs: sample * 1000);
        }
        final clear =
            _runtimeSnapshot(tester, host)['focusClearSemantics'] as Map?;
        expect(clear, isNotNull);
        expect(clear!['hasTap'], isTrue);
        expect(clear['isButton'], isTrue);
        await tester.tap(find.byKey(const ValueKey('plan-focus-clear')));
        await tester.pump();
        focusElapsedMs = 0;
        for (final sample in (capturePlan['focusExitMs'] as List).cast<int>()) {
          await tester.pump(Duration(milliseconds: sample - focusElapsedMs));
          focusElapsedMs = sample;
          await capture('focus-exit-${sample}ms', elapsedUs: sample * 1000);
        }

        expect(frames, hasLength(capturePlan['framesPerTheme'] as int));
        final boundaryCounts =
            frames
                .map(
                  (frame) =>
                      (frame['runtime'] as Map)['bubbleRepaintBoundaryCount'],
                )
                .whereType<int>()
                .toSet()
                .toList()
              ..sort();
        expect(boundaryCounts, [4]);
        final originalRegression = frames
            .where(
              (frame) =>
                  frame.containsKey('historicalOriginalFrameByteIdentical'),
            )
            .toList();
        expect(originalRegression, hasLength(29));
        if (config['variant'] == 'base') {
          expect(
            originalRegression.every(
              (frame) => frame['historicalOriginalFrameByteIdentical'] == true,
            ),
            isTrue,
          );
        }
        await tester.runAsync(() async {
          final manifest = File('${output.path}/capture-manifest.json');
          expect(await manifest.exists(), isFalse);
          await manifest.writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({
              'schema': 'smartfit-ui-kit-slots-frames@2',
              'variant': config['variant'],
              'source': config['source'],
              'publicInputsSha256': config['publicInputsSha256'],
              'driverSha256': config['driverSha256'],
              'adapterSha256': config['adapterSha256'],
              'focusImplementation': config['focusImplementation'],
              'inputsSha256': sha256.convert(inputBytes).toString(),
              'logicalSize': {'width': 412, 'height': 915},
              'dpr': _dpr,
              'physicalSizeRounding': 'ceil in RenderRepaintBoundary.toImage',
              'theme': theme,
              'fonts': fonts,
              'frames': frames,
              'capturePlan': capturePlan,
              'originalCaptureInputSha256': input['originalCaptureInputSha256'],
              'historicalOriginalFrameCount': originalRegression.length,
              'historicalOriginalFramesByteIdentical': originalRegression.every((frame) => frame['historicalOriginalFrameByteIdentical'] == true),
              'bubbleRepaintBoundaryCounts': boundaryCounts,
              'legacyAlpha': content.legacyManifest,
              'isPhoneScreenshot': false,
              'isPerformanceMeasurement': false,
              'container': {'left': 20, 'top': 64, 'right': 20, 'bottom': 20},
              'media': 'production PoseHubAssetBundle + verified bundled images; genuine historical legacy alpha bytes, index and bounds served by immutable test AssetBundle',
              'routeExitTrigger': 'production public control.beginExit; no copied animation',
              'focusSampleTimesMs': {'appearing': 90, 'held': 180, 'clearing': 60, 'cleared': 120},
              'deliveryDurationUs': 890000,
            })}\n',
            flush: true,
          );
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await content.app.dispose();
        content.repo.dispose();
        SfColors.palette = SfPalette.dark;
      } finally {
        semantics.dispose();
      }
    });
  }
}
