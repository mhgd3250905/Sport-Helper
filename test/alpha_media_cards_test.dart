import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/alpha_bounds.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

Exercise _withMedia(Exercise e, ExerciseMedia media) => Exercise(
  id: e.id,
  name: e.name,
  muscles: e.muscles,
  unilateral: e.unilateral,
  category: e.category,
  equipment: e.equipment,
  position: e.position,
  level: e.level,
  scenes: e.scenes,
  dose: e.dose,
  repSeconds: e.repSeconds,
  cues: e.cues,
  cautions: e.cautions,
  alternative: e.alternative,
  media: media,
);

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

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('SMARTFIT_CAPTURE_ALPHA_CARDS')) return;
  // pumpAndSettle alone can end before asynchronous asset decoding finishes.
  // A visual-review capture must contain real decoded figures, not an empty slot.
  final assets = _images(tester).toSet();
  final context = tester.element(find.byType(PlanCard));
  await tester.runAsync(() async {
    await SfAlphaBounds.load(DefaultAssetBundle.of(context));
    await Future.wait([
      for (final asset in assets) precacheImage(AssetImage(asset), context),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('alpha-preview-page')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      final face = tester.getRect(
        find.byKey(const ValueKey('alpha-card-face')),
      );
      final card = tester.getRect(find.byType(PlanCard));
      int? firstForegroundY;
      var foregroundPixels = 0;
      for (var y = (card.top * 2).ceil(); y < (face.top * 2).floor(); y++) {
        final background = (y * image.width) * 4;
        for (
          var x = ((card.left + 30) * 2).ceil();
          x < ((card.right - 90) * 2).floor();
          x++
        ) {
          final pixel = (y * image.width + x) * 4;
          final delta =
              (rgba[pixel] - rgba[background]).abs() +
              (rgba[pixel + 1] - rgba[background + 1]).abs() +
              (rgba[pixel + 2] - rgba[background + 2]).abs();
          if (delta > 35) {
            firstForegroundY ??= y;
            foregroundPixels++;
          }
        }
      }
      expect(
        foregroundPixels,
        greaterThan(10),
        reason: 'Decoded figure must actually paint above the card face',
      );
      expect(face.top - firstForegroundY! / 2, inInclusiveRange(12, 16));
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('.buildlog/alpha-static-cards/$name.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  late ExerciseLibrary plain;
  late ExerciseLibrary library;

  setUpAll(() async {
    if (const bool.fromEnvironment('SMARTFIT_CAPTURE_ALPHA_CARDS')) {
      await (FontLoader(
        sfFontFamily,
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
    }
    plain = loadLibrary();
    final pack = (await AppTestPack.load(
      (path) => File(path).readAsString(),
      enabled: true,
    ))!;
    library = ExerciseLibrary([
      for (final e in plain.all)
        _withMedia(e, pack.actions[e.id]?.applyTo(e.media) ?? e.media),
    ]);
    expect(library['h-squat'].media.alphaCover, isNotNull);
    expect(library['w-bird-dog'].media.alphaThumbnail, isNotNull);
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
    Widget app = SfAlphaCardsScope(
      enabled: enabled,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        home: child,
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
      'alpha plan uses a lower face and unchanged controls in ${palette.brightness.name}',
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
        final oldSize = tester.getSize(find.byType(PlanCard));
        expect(
          _images(tester),
          isNot(contains(library['h-squat'].media.alphaCover)),
        );

        await pump(tester, card(), palette: palette);
        expect(tester.getSize(find.byType(PlanCard)), oldSize);
        expect(tester.getRect(start), oldStart);
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
        final cardRect = tester.getRect(find.byType(PlanCard));
        expect(face.top - cardRect.top, SfAlphaCards.rise);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'plan-${palette.brightness.name}-decoded');

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

  testWidgets(
    'alpha popup cover starts the existing player with its frame-zero poster',
    (tester) async {
      final services = makeServices();
      addTearDown(services.dispose);
      final e = library['h-squat'];
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExerciseDetails(context, e),
              child: const Text('查看示范'),
            ),
          ),
        ),
        services: services,
      );
      await tester.tap(find.text('查看示范'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(_images(tester), contains(e.media.alphaCover));
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('播放${e.name}示范'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library-alpha-play')));
      await tester.pumpAndSettle();
      final video = tester.widget<ExerciseVideo>(find.byType(ExerciseVideo));
      final view = tester.widget<trainer.DrillMediaView>(
        find.byType(trainer.DrillMediaView),
      );
      expect(video.exercise.id, e.id);
      expect(view.media.packedAlphaPosterAsset, e.media.alphaPlaybackPoster);
      expect(view.media.packedAlphaPosterAsset, isNot(e.media.alphaCover));
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
