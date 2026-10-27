import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';
import 'posehub_ui_support.dart' show PoseHubUiRepository;

/// Read the real installed-path bundle in setUpAll's real async zone. Widget
/// fake-async tests then decode those same bytes without stranding file handles.
class _InstalledImageFixture extends CachingAssetBundle {
  _InstalledImageFixture(this.delegate, this.images);
  final AssetBundle delegate;
  final Map<String, ByteData> images;

  @override
  Future<ByteData> load(String key) =>
      images.containsKey(key) ? Future.value(images[key]!) : delegate.load(key);
}

TrainingPlan _plan() => const TrainingPlan(
  id: 'alpha-static',
  source: 'test',
  title: '活动一下',
  summary: '',
  goal: 'mobility',
  scene: 'home',
  equipment: [],
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
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 0,
        ),
        PlanItem(
          exerciseId: 'w-bird-dog',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 0,
        ),
        PlanItem(
          exerciseId: 'h-catcow-quad',
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

Iterable<String> _images(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((image) => image.image)
    .whereType<AssetImage>()
    .map((asset) => asset.assetName);

Future<List<int>> _fixtureImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xff2d9672),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(4, 4);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ExerciseLibrary plain;
  late ExerciseLibrary library;
  late coach.PoseHubAppTestCatalog sdk;
  late Directory installed;
  late PoseHubUiRepository installation;
  late AssetBundle bundle;

  setUpAll(() async {
    plain = loadLibrary();
    sdk = await trainer.PoseHubActionLibrary.load();
    library = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(sdk),
      legacyLibrary: plain,
    ).library;
    installed = await Directory.systemTemp.createTemp('smartfit-alpha-cards-');
    final image = await _fixtureImage();
    for (final id in _plan().exerciseIds) {
      final action = sdk.tryGet(id)!;
      for (final file in [action.cover, action.thumbnail]) {
        final target = File.fromUri(file.resolve(installed.uri));
        await target.parent.create(recursive: true);
        await target.writeAsBytes(image);
      }
    }
    installation = PoseHubUiRepository(mediaBaseUri: installed.uri);
    final source = PoseHubAssetBundle(catalog: sdk, installation: installation);
    final images = <String, ByteData>{};
    for (final id in _plan().exerciseIds) {
      for (final role in ['cover', 'thumbnail']) {
        final key =
            '${PoseHubAssetBundle.prefix}${Uri.encodeComponent(id)}/$role';
        images[key] = await source.load(key);
      }
    }
    bundle = _InstalledImageFixture(source, images);
    expect(library['h-squat'].media.alphaCover, isNotNull);
    expect(library['w-bird-dog'].media.alphaThumbnail, isNotNull);
  });

  tearDownAll(() async {
    installation.dispose();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await installed.delete(recursive: true);
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool enabled = true,
    SfPalette palette = SfPalette.light,
    AppServices? services,
  }) async {
    SfColors.palette = palette;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app = DefaultAssetBundle(
      bundle: bundle,
      child: SfAlphaCardsScope(
        enabled: enabled,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(palette),
          home: child,
        ),
      ),
    );
    if (services != null) app = AppScope(services: services, child: app);
    await tester.pumpWidget(
      RepaintBoundary(key: const ValueKey('alpha-preview-page'), child: app),
    );
    await tester.pumpAndSettle();
  }

  AppServices makeServices() => AppServices(
    library: ExerciseLibrary([
      library['h-squat'],
      library['w-bird-dog'],
      plain['h-catcow-quad'],
    ]),
    catalog: loadCatalog(),
    store: AppStore(MemoryStorage())..starfield = false,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );

  test('alpha mapping is opt-in and leaves the old theme media unchanged', () {
    SfColors.palette = SfPalette.light;
    final e = library['h-squat'];
    final disabled = toCoachExercise(e, alphaCards: false);
    expect(disabled.poster, e.media.lightPoster);
    expect(disabled.cutout, isNull);
    expect(disabled.stage.mediaStage, SfPalette.light.mediaStage);

    final enabled = toCoachExercise(e, alphaCards: true);
    expect(enabled.poster, e.media.alphaThumbnail);
    expect(enabled.cutout, e.media.alphaCover);
    expect(enabled.stillCutout, e.media.alphaCover);
    expect(enabled.stage.mediaStage, Colors.transparent);
    final old = plain['h-catcow-quad'];
    final retained = toCoachExercise(old, alphaCards: true);
    expect(retained.poster, old.media.lightPoster);
    expect(retained.cutout, isNull);
    expect(retained.stage.mediaStage, SfPalette.light.mediaStage);
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'alpha plan keeps SDK height and anchored controls in ${palette.brightness.name}',
      (tester) async {
        var starts = 0;
        var saves = 0;
        Widget card() => Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PlanCard(
                plan: _plan(),
                library: library,
                saved: false,
                onStart: (_) => starts++,
                onSave: () => saves++,
                onOpen: () {},
              ),
            ),
          ),
        );
        await pump(tester, card(), enabled: false, palette: palette);
        final colors = smartfitCoachUiStyle().colors;
        expect(colors.background, palette.background);
        expect(colors.surface, palette.surface);
        expect(colors.surfaceRaised, palette.surfaceHigh);
        expect(colors.outline, palette.line);
        expect(colors.shadow, palette.shadow);
        expect(colors.mediaLabelSurface, palette.surfaceHigh);
        expect(colors.surfaceRaised.a, 1);
        expect(colors.mediaLabelSurface.a, 1);
        final start = find.byKey(const ValueKey('plan-start-alpha-static'));
        final expand = find.byKey(const ValueKey('plan-expand-alpha-static'));
        final oldStart = tester.getRect(start);
        final oldExpand = tester.getRect(expand);
        final oldCard = tester.getRect(find.byType(PlanCard));
        expect(oldCard.height, CoachPlanCard.setHeight);
        // The SDK cover is shared by both treatments; alpha mode changes the
        // painted face and cutout layout, not the identity of its image source.
        expect(find.byKey(const ValueKey('alpha-card-face')), findsNothing);

        await pump(tester, card(), palette: palette);
        // SDK 0.3.0 deliberately gives the multi-action cutout hero more room.
        // The App adopts that public folded-height contract; the 14dp painted
        // face offset must still leave the button's size and bottom anchor alone.
        expect(find.byType(CoachPlanCard), findsOneWidget);
        final cardRect = tester.getRect(find.byType(PlanCard));
        expect(cardRect.width, oldCard.width);
        expect(cardRect.height, CoachPlanCard.cutoutSetHeight);
        final alphaStart = tester.getRect(start);
        expect(alphaStart.size, oldStart.size);
        expect(alphaStart.right, oldStart.right);
        expect(
          alphaStart.bottom - cardRect.bottom,
          oldStart.bottom - oldCard.bottom,
        );
        expect(alphaStart.width, greaterThanOrEqualTo(48));
        expect(alphaStart.height, greaterThanOrEqualTo(48));
        // The SDK's established cutout style chooses a different dark face;
        // its top/right anchor and touch height stay fixed.
        final alphaExpand = tester.getRect(expand);
        expect(alphaExpand.top, oldExpand.top);
        expect(alphaExpand.right, oldExpand.right);
        expect(alphaExpand.height, oldExpand.height);
        expect(_images(tester), contains(library['h-squat'].media.alphaCover));
        expect(
          _images(tester),
          contains(library['w-bird-dog'].media.alphaThumbnail),
        );
        final face = tester.getRect(
          find.byKey(const ValueKey('alpha-card-face')),
        );
        expect(SfAlphaCards.rise, 14);
        expect(face.top - cardRect.top, SfAlphaCards.rise);
        expect(tester.takeException(), isNull);

        await tester.tap(start);
        expect(starts, 1);
        await tester.tap(expand);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byKey(const ValueKey('fly-hero')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('plan-save-alpha-static')));
        expect(saves, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'lowering only the painted alpha face leaves hitboxes and flyer measurements fixed',
    (tester) async {
      final plan = _plan();
      Widget card(bool lowerFace) => Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SfAlphaCardScope(
              active: lowerFace,
              child: Builder(
                builder: (context) => withSmartfitCoachUi(
                  context,
                  CoachPlanCard(
                    plan: toCoachRoutine(plan, library),
                    library: CoachExerciseLibrary([
                      for (final id in plan.exerciseIds)
                        toCoachExercise(library[id], alphaCards: true),
                    ]),
                    saved: false,
                    onStart: (_) {},
                    onSave: () {},
                    onOpen: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final expand = find.byKey(const ValueKey('plan-expand-alpha-static'));
      final start = find.byKey(const ValueKey('plan-start-alpha-static'));
      await pump(tester, card(false), palette: SfPalette.dark);
      final startBefore = tester.getRect(start);
      final expandBefore = tester.getRect(expand);
      await tester.tap(expand);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final flyerBefore = tester.getRect(
        find.byKey(const ValueKey('fly-hero')),
      );
      await tester.pumpAndSettle();
      await tester.tap(expand);
      await tester.pumpAndSettle();

      await pump(tester, card(true), palette: SfPalette.dark);
      expect(tester.getRect(start), startBefore);
      expect(tester.getRect(expand), expandBefore);
      await tester.tap(expand);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(
        tester.getRect(find.byKey(const ValueKey('fly-hero'))),
        flyerBefore,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'library thumbnails use alpha while an old tile keeps its stage',
    (tester) async {
      final services = makeServices();
      addTearDown(services.dispose);
      await pump(tester, const LibraryPage(), services: services);
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(
        _images(tester),
        contains(library['h-squat'].media.alphaThumbnail),
      );
      expect(
        _images(tester),
        contains(library['w-bird-dog'].media.alphaThumbnail),
      );
      expect(
        _images(tester),
        contains(plain['h-catcow-quad'].media.lightPoster),
      );
      final image = tester.getRect(
        find.byKey(const ValueKey('alpha-artwork-image-h-squat')),
      );
      final face = tester.getRect(
        find.byKey(const ValueKey('alpha-artwork-face-h-squat')),
      );
      expect(face.top - image.top, SfAlphaCards.rise);
      expect(tester.takeException(), isNull);

      await pump(
        tester,
        const LibraryPage(),
        enabled: false,
        services: services,
      );
      expect(find.byType(SfAlphaArtwork), findsNothing);
      expect(_images(tester), contains(library['h-squat'].media.lightPoster));
      expect(tester.takeException(), isNull);
    },
  );
}
