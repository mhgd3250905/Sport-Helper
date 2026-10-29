// Actual SmartFit entry points and SDK widgets. Native video is deliberately
// pending, so every media panel shows its genuine bundled standing fallback.
// The separate 24px footer labels this software evidence inside each image.
// SF_SCREENSHOT_DIR=<new delivery>/screenshots/training
// flutter test --no-pub --flavor internal
//   test_screens/training_ux_review_test.dart --update-goldens
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/posehub_ui_support.dart' show PoseHubUiRepository;
import '../test/support.dart';
import '../test/support/coach_v2_fixtures.dart';

class _Images extends CachingAssetBundle {
  _Images(this.images);
  final Map<String, ByteData> images;
  @override
  Future<ByteData> load(String key) => images.containsKey(key)
      ? SynchronousFuture(images[key]!)
      : rootBundle.load(key);
}

const _wholePlan = TrainingPlan(
  id: 'software-training-ux-plan',
  source: 'manual',
  title: '居家核心训练',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: ['mat'],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-forearm-plank',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 12,
          perSide: false,
          restSeconds: 0,
        ),
        PlanItem(
          exerciseId: 's-butterfly',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 12,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

Future<void> _fonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  for (final (family, bytes) in [
    ('NotoSansSC', rootBundle.load('assets/fonts/NotoSansSC.ttf')),
    (
      'MaterialIcons',
      Future.value(
        ByteData.sublistView(
          File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    ),
    (
      'packages/cupertino_icons/CupertinoIcons',
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    ),
  ]) {
    await (FontLoader(family)..addFont(bytes)).load();
  }
}

Widget _app({
  required AppServices services,
  required SfPalette palette,
  required AssetBundle images,
  required Widget home,
}) => DefaultAssetBundle(
  bundle: images,
  child: AppScope(
    services: services,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(palette),
      builder: (context, child) => Column(
        children: [
          SizedBox(
            height: 844,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: const Size(390, 844)),
              child: SfPaletteScope(
                child: SfAlphaCardsScope(enabled: true, child: child!),
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: ColoredBox(
              color: palette.background,
              child: Center(
                child: Text(
                  '软件静帧 · SDK站立首帧（非视频）',
                  style: SfType.caption.copyWith(
                    fontFamily: sfFontFamily,
                    color: palette.muted,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      home: home,
    ),
  ),
);

Future<void> _shot(WidgetTester tester, _Images images, String name) async {
  await tester.runAsync(() async {
    final host = tester.element(find.byType(MaterialApp));
    for (final key in images.images.keys) {
      await precacheImage(
        AssetImage(key, bundle: images),
        host,
      ).timeout(const Duration(seconds: 10));
    }
    for (final element in tester.allElements.toList()) {
      if (element.widget case final Image image) {
        await precacheImage(
          image.image,
          element,
        ).timeout(const Duration(seconds: 10));
      }
    }
  });
  await tester.pump();
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      Uri.file('${Platform.environment['SF_SCREENSHOT_DIR']}/$name.png'),
    ),
  );
}

Future<void> _advance(WidgetTester tester, int milliseconds) async {
  for (var elapsed = 0; elapsed < milliseconds; elapsed += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SF_SCREENSHOT_DIR'];
  late CoachV2Fixtures fixture;
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubMediaRepository imageRepository;
  late _Images images;
  setUpAll(() async {
    if (output == null) return;
    await _fonts();
    fixture = await CoachV2Fixtures.load();
    catalog = await trainer.PoseHubActionLibrary.load();
    final bundled = await PoseHubBundledImages.load(
      catalogRevision: trainer.PoseHubActionLibrary.catalogSha256,
    );
    imageRepository = await PoseHubMediaRepository.create(
      catalog: catalog,
      catalogRevision: trainer.PoseHubActionLibrary.catalogSha256,
      mediaBaseUrls: const [],
      rootDirectory: '$output/image-cache',
      bundledFileLoader: bundled.loadFile,
    );
    final production = PoseHubAssetBundle(
      catalog: catalog,
      installation: imageRepository,
    );
    final bytes = <String, ByteData>{};
    for (final id in ['s-butterfly', 'h-forearm-plank']) {
      for (final role in ['cover', 'thumbnail']) {
        final key = 'posehub-r1/$id/$role';
        bytes[key] = await production.load(key);
      }
    }
    images = _Images(bytes);
  });
  tearDownAll(() {
    if (output != null) imageRepository.dispose();
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'real single preview, training, completion and feeling ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2604);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final pending = Completer<Uri>();
        final media = PoseHubUiRepository(
          mediaBaseUri: Uri.file('/software-standing-frame-only/'),
          onEnsureAction: (_) => pending.future,
        );
        addTearDown(media.dispose);
        final storage = MemoryStorage();
        final store = AppStore(storage)
          ..starfield = false
          ..voice = const VoiceSettings(voice: false, chimes: false);
        await store.acceptSafety(blocked: false);
        final services = AppServices(
          library: fixture.library,
          catalog: loadCatalog(),
          store: store,
          voiceLibrary: VoiceLibrary.empty,
          voiceOutput: const MutedVoiceOutput(),
          poseHubCatalog: catalog,
          poseHubMedia: media,
          chatReplyDelay: Duration.zero,
        );
        addTearDown(services.dispose);
        addTearDown(store.dispose);
        final theme = palette.brightness.name;

        // Library's real action handler enters the same preview as recommendations.
        await tester.pumpWidget(
          _app(
            services: services,
            palette: palette,
            images: images,
            home: const LibraryPage(),
          ),
        );
        await tester.pump();
        final action = catalog.tryGet('s-butterfly')!;
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          action.nameZh,
        );
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('posehub-action-${action.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(trainer.PoseHubSinglePracticePage), findsOneWidget);
        expect(find.byKey(const ValueKey('start-training')), findsOneWidget);
        expect(store.sessionResults, isEmpty);
        await _shot(tester, images, '10-single-preview-$theme');

        await tester.tap(find.byKey(const ValueKey('start-training')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await _shot(tester, images, '11-start-morph-150ms-$theme');
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('start-training')), findsNothing);
        await _shot(tester, images, '12-single-preparation-$theme');
        await _advance(tester, 11000);
        expect(find.byKey(const ValueKey('pause')), findsOneWidget);
        await _shot(tester, images, '13-single-training-$theme');

        // The official action carries 40 seconds work and 10 seconds preparation.
        await _advance(tester, 45000);
        expect(find.byKey(const ValueKey('finish')), findsOneWidget);
        for (final feeling in trainer.TrainingFeeling.values) {
          expect(
            find.byKey(ValueKey('completion-feeling-${feeling.name}')),
            findsOneWidget,
          );
        }
        await _shot(tester, images, '14-completion-unselected-$theme');
        await tester.ensureVisible(
          find.byKey(const ValueKey('completion-feeling-justRight')),
        );
        await tester.tap(
          find.byKey(const ValueKey('completion-feeling-justRight')),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await _shot(tester, images, '15-completion-justRight-$theme');
        await tester.tap(find.byKey(const ValueKey('finish')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        expect(store.sessionResults, hasLength(1));
        expect(store.history, hasLength(1));
        expect(
          store.sessionResults.single.feeling,
          trainer.TrainingFeeling.justRight,
        );
        expect(store.history.single.feeling, trainer.TrainingFeeling.justRight);
        final restored = AppStore(storage);
        await restored.load();
        addTearDown(restored.dispose);
        expect(
          restored.sessionResults.single.feeling,
          trainer.TrainingFeeling.justRight,
        );
        expect(
          restored.history.single.feeling,
          trainer.TrainingFeeling.justRight,
        );
        await tester.runAsync(
          () => File('$output/feedback-$theme.json').writeAsString(
            '${jsonEncode({'schema': 'smartfit-training-ux-widget-feedback@1', 'source': 'actual App library to SDK preview/training/completion flow', 'nativeDevice': false, 'mediaPlaybackVerified': false, 'mediaFrame': 'bundled SDK standing fallback; video remains pending', 'theme': theme, 'feeling': store.sessionResults.single.feeling!.name, 'sessionCount': store.sessionResults.length, 'historyCount': store.history.length, 'sameSessionId': store.sessionResults.single.sessionId == store.history.single.sessionId, 'restoredFeeling': restored.history.single.feeling!.name, 'session': store.sessionResults.single.toJson()})}\n',
          ),
        );

        // The actual full-plan host explicitly enters training, without preview.
        await tester.pumpWidget(
          _app(
            services: services,
            palette: palette,
            images: images,
            home: const PlayerPage(plan: _wholePlan),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byKey(const ValueKey('start-training')), findsNothing);
        await _shot(tester, images, '16-whole-plan-preparation-$theme');
        await _advance(tester, 11000);
        await _shot(tester, images, '17-whole-plan-training-$theme');
        await _advance(tester, 45000);
        expect(find.byKey(const ValueKey('finish')), findsOneWidget);
        expect(find.byKey(const ValueKey('completion-item-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('completion-item-1')), findsOneWidget);
        await _shot(tester, images, '18-whole-plan-completion-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        pending.complete(media.mediaBaseUri);
      },
      skip: output == null,
    );
  }
}
