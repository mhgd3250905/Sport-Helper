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
import 'package:smartfit/ui/plan_presentation.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/polish_card.dart';
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

String _standing(String id) =>
    'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/$id.webp';

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
    expect(enabled.cutout, _standing(e.id));
    expect(enabled.stillCutout, _standing(e.id));
    expect(enabled.stage.mediaStage, Colors.transparent);
    final old = plain['h-catcow-quad'];
    final retained = toCoachExercise(old, alphaCards: true);
    expect(retained.poster, old.media.lightPoster);
    expect(retained.cutout, isNull);
    expect(retained.stage.mediaStage, SfPalette.light.mediaStage);
  });

  test(
    'routine metadata displays admitted equipment and executable duration',
    () {
      final data = _plan().toJson()
        ..['equipment'] = ['chair', 'wall', 'mat']
        ..['targetMinutes'] = 10;
      final routine = toCoachRoutine(TrainingPlan.fromJson(data), library);
      expect(routine.gearLabel, '椅子、墙、瑜伽垫');
      // These three 30-second entries and their transitions take about two
      // minutes. The requested target of ten must not replace the actual dose.
      expect(routine.durationLabel, '约 2 分钟');
      expect(routine.metaLabel, contains('约 2 分钟'));
      expect(planDurationLabel(TrainingPlan.fromJson(data), library), '约 2 分钟');
      expect(routine.metaLabel, contains('椅子、墙、瑜伽垫'));

      final bodyweight = toCoachRoutine(_plan(), library);
      expect(bodyweight.gearLabel, '徒手');
    },
  );

  test(
    'SDK-bound plan stills resolve bundled transparent first frames',
    () async {
      for (final exercise in library.all) {
        final key = toCoachExercise(exercise, alphaCards: true).stillCutout;
        expect(key, _standing(exercise.id), reason: exercise.id);
        final bytes = await rootBundle.load(key!);
        expect(bytes.lengthInBytes, greaterThan(0), reason: exercise.id);
      }
    },
  );

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'alpha plan keeps SDK height and anchored controls in ${palette.brightness.name}',
      (tester) async {
        var starts = 0;
        var saves = 0;
        var opens = 0;
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
                onOpen: () => opens++,
              ),
            ),
          ),
        );
        await pump(tester, card(), enabled: false, palette: palette);
        final colors = smartfitCoachUiStyle().colors;
        expect(colors.background, palette.background);
        final expectedFill = palette.isDark
            ? const Color(0xFF1A2324)
            : const Color(0xFFFFFFFF);
        final expectedEdge = palette.isDark
            ? const Color(0xFFFFFFFF).withValues(alpha: .08)
            : const Color(0xFFE3E8E6);
        expect(colors.surface, expectedFill);
        expect(colors.surfaceRaised, palette.surfaceHigh);
        expect(colors.outline, expectedEdge);
        expect(colors.shadow, palette.shadow);
        expect(colors.mediaLabelSurface, palette.surfaceHigh);
        expect(colors.surfaceRaised.a, 1);
        expect(colors.mediaLabelSurface.a, 1);
        final start = find.byKey(const ValueKey('plan-start-alpha-static'));
        final expand = find.byKey(const ValueKey('plan-expand-alpha-static'));
        final oldStart = tester.getRect(start);
        final oldExpand = tester.getRect(expand);
        final oldCard = tester.getRect(find.byType(PlanCard));
        final oldBody = tester.getRect(find.byType(CoachCardSurface));
        expect(oldCard.height, CoachPlanCard.setHeight);
        // Only SDK cutout layout changes. Both states use the same approved
        // card face; there is no separate lowered or elevated image surface.
        expect(find.byKey(const ValueKey('alpha-card-face')), findsNothing);

        await pump(tester, card(), palette: palette);
        // The SDK reserves 58dp above its 300dp upright-cutout card body.
        // That SDK-owned reservation remains separate from the flat card face.
        const uprightOverhang = 58.0;
        expect(find.byType(CoachPlanCard), findsOneWidget);
        final cardRect = tester.getRect(find.byType(PlanCard));
        final body = tester.getRect(find.byType(CoachCardSurface));
        expect(cardRect.width, oldCard.width);
        expect(
          cardRect.height,
          CoachPlanCard.cutoutSetHeight + uprightOverhang,
        );
        expect(body.height, CoachPlanCard.cutoutSetHeight);
        expect(body.top - cardRect.top, uprightOverhang);
        final alphaStart = tester.getRect(start);
        expect(alphaStart.size, oldStart.size);
        expect(alphaStart.right, oldStart.right);
        expect(
          alphaStart.bottom - cardRect.bottom,
          oldStart.bottom - oldCard.bottom,
        );
        expect(alphaStart.width, greaterThanOrEqualTo(48));
        expect(alphaStart.height, greaterThanOrEqualTo(48));
        // Controls retain their anchors within the body, which now sits below
        // the SDK-owned overhang reservation.
        final alphaExpand = tester.getRect(expand);
        expect(alphaExpand.top - body.top, oldExpand.top - oldBody.top);
        expect(alphaExpand.right, oldExpand.right);
        expect(alphaExpand.height, oldExpand.height);
        expect(_images(tester), contains(_standing('h-squat')));
        expect(_images(tester), contains(_standing('w-bird-dog')));
        final face = find.byType(SfPolishCard);
        expect(face, findsOneWidget);
        expect(tester.getRect(face), body);
        final faceContainer = tester.widget<Container>(
          find.descendant(of: face, matching: find.byType(Container)).first,
        );
        final decoration = faceContainer.decoration! as BoxDecoration;
        expect(decoration.color, expectedFill);
        expect(decoration.boxShadow, isNull);
        final edge = faceContainer.foregroundDecoration! as BoxDecoration;
        expect(edge.borderRadius, BorderRadius.circular(20));
        expect(edge.border, Border.all(color: expectedEdge, width: 1));
        final clip = tester.widget<ClipRRect>(
          find.byKey(const ValueKey('plan-clip-alpha-static')),
        );
        expect(clip.borderRadius, BorderRadius.circular(20));
        expect(clip.clipBehavior, Clip.antiAlias);
        void expectToggle(bool expanded) {
          final toggle = find.byType(SfPlanToggleButton);
          expect(toggle, findsOneWidget);
          expect(tester.widget<SfPlanToggleButton>(toggle).expanded, expanded);
          final button = tester.widget<SfPressable>(
            find.descendant(of: toggle, matching: find.byType(SfPressable)),
          );
          expect(button.semanticLabel, expanded ? '收起详情' : '展开详情');
          expect(button.expanded, expanded);
          final padding = tester.widget<Padding>(
            find.descendant(of: toggle, matching: find.byType(Padding)),
          );
          expect(padding.padding, const EdgeInsets.symmetric(horizontal: 12));
          final face = find.descendant(
            of: toggle,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).color ==
                      SfColors.surfaceHigh,
            ),
          );
          expect(face, findsOneWidget);
          // The SDK keeps its 44dp header slot. The colored button face must
          // still be precisely 32dp in both states, even under that constraint.
          expect(tester.getSize(face).height, 32);
          final decoration = tester.widget<DecoratedBox>(face);
          expect(
            (decoration.decoration as BoxDecoration).borderRadius,
            BorderRadius.circular(16),
          );
          final label = tester.widget<Text>(
            find.descendant(of: toggle, matching: find.byType(Text)),
          );
          expect(label.style!.fontSize, 13);
          expect(
            find.descendant(
              of: toggle,
              matching: find.text(expanded ? '收起' : '展开'),
            ),
            findsOneWidget,
          );
        }

        expectToggle(false);
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(const ValueKey('plan-cutout-overhang-hit')),
        );
        expect(opens, 1);
        expect(starts, 0);
        await tester.tap(start);
        expect(starts, 1);
        await tester.tap(expand);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byKey(const ValueKey('fly-hero')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final expandedFace = tester.getRect(find.byType(SfPolishCard));
        final title = tester.getRect(
          find.byKey(const ValueKey('plan-header-title')),
        );
        // The header is measured from the single card face, with no 14dp
        // offset retained from the old raised-alpha treatment.
        expect(title.top - expandedFace.top, 23);
        expect(title.left - expandedFace.left, 23);
        expectToggle(true);
        await tester.tap(find.byKey(const ValueKey('plan-save-alpha-static')));
        expect(saves, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the unified face ignores the old alpha scope without shifting controls or flyers',
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
      expect(find.byType(SfPolishCard), findsOneWidget);
      expect(find.byType(SfAlphaCardSurface), findsNothing);
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
      expect(find.byType(SfPolishCard), findsOneWidget);
      expect(find.byType(SfAlphaCardSurface), findsNothing);
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
    'legacy library uses the SDK recommendation renderer and trusted standing assets',
    (tester) async {
      final services = makeServices();
      addTearDown(services.dispose);
      await pump(tester, const LibraryPage(), services: services);
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(find.byType(CoachRecommendCard), findsOneWidget);
      expect(find.byType(SfPolishCard), findsNothing);
      expect(_images(tester), contains(_standing('h-squat')));
      expect(_images(tester), contains(_standing('w-bird-dog')));
      expect(
        _images(tester),
        contains(plain['h-catcow-quad'].media.lightPoster),
      );
      expect(find.byType(SfAlphaArtwork), findsNothing);
      expect(
        find.byKey(const ValueKey('alpha-artwork-face-h-squat')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await pump(
        tester,
        const LibraryPage(),
        enabled: false,
        services: services,
      );
      expect(find.byType(SfAlphaArtwork), findsNothing);
      expect(_images(tester), contains(_standing('h-squat')));
      expect(tester.takeException(), isNull);
    },
  );
}
