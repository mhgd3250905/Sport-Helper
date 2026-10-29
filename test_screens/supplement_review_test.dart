// Matched real App entry-point screenshots for the +41 supplement.
// Before source is d6bd79cd8dc6c5439f67779bd6e894af7981faa3.
// SF_SCREENSHOT_DIR=<delivery>/screenshots/<before|after>
// flutter test --no-pub --flavor internal
//   test_screens/supplement_review_test.dart --update-goldens
// Software widgets/fonts/assets only; no device/performance acceptance.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/posehub_ui_support.dart' show poseHubUiApp;
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

const _plan = TrainingPlan(
  id: 'supplement-plan',
  source: 'manual',
  title: '晨间舒展',
  summary: '',
  goal: 'mixed',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 15,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-catcow-quad',
          mode: DoseMode.reps,
          sets: 1,
          reps: 8,
          perSide: false,
          restSeconds: 10,
        ),
        PlanItem(
          exerciseId: 'h-banana',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: true,
          restSeconds: 10,
        ),
        PlanItem(
          exerciseId: 'n-windshield',
          mode: DoseMode.reps,
          sets: 1,
          reps: 6,
          perSide: false,
          restSeconds: 10,
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
  await tester.pump(const Duration(milliseconds: 500));
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      Uri.file('${Platform.environment['SF_SCREENSHOT_DIR']}/$name.png'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SF_SCREENSHOT_DIR'];
  late CoachV2Fixtures fixture;
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubMediaRepository media;
  late _Images images;
  setUpAll(() async {
    if (output == null) return;
    await _fonts();
    fixture = await CoachV2Fixtures.load();
    catalog = await PoseHubActionLibrary.load();
    final bundled = await PoseHubBundledImages.load(
      catalogRevision: PoseHubActionLibrary.catalogSha256,
    );
    media = await PoseHubMediaRepository.create(
      catalog: catalog,
      catalogRevision: PoseHubActionLibrary.catalogSha256,
      mediaBaseUrls: const [],
      rootDirectory: '$output/image-cache',
      bundledFileLoader: bundled.loadFile,
    );
    final production = PoseHubAssetBundle(
      catalog: catalog,
      installation: media,
    );
    final bytes = <String, ByteData>{};
    for (final id in ['h-catcow-quad', 'h-banana', 'n-windshield']) {
      for (final role in ['cover', 'thumbnail']) {
        final key = 'posehub-r1/$id/$role';
        bytes[key] = await production.load(key);
      }
    }
    images = _Images(bytes);
  });
  tearDownAll(() {
    if (output != null) media.dispose();
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'real supplement saved plans and menu ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final store = AppStore(MemoryStorage())..starfield = false;
        await store.acceptSafety(blocked: false);
        await store.setAppearance(palette.brightness.name);
        for (final (id, title) in [
          ('evening', '晚间放松'),
          ('core', '核心练习'),
          ('morning', '晨间舒展'),
        ]) {
          await store.savePlan(
            TrainingPlan.fromJson({
              ..._plan.toJson(),
              'id': 'supplement-$id',
              'title': title,
            }),
          now: DateTime(2026, 10, 29, 9, 0, store.savedPlans.length),
          );
        }
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
        final chat = ChatController(
          engine: services.chatEngine,
          store: store,
          replyDelay: Duration.zero,
          clock: () => DateTime(2026, 10, 29, 10),
        );
        addTearDown(chat.dispose);
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: images,
            child: poseHubUiApp(
              palette: palette,
              services: services,
              home: SfAlphaCardsScope(
                enabled: true,
                child: ChatHomePage(controller: chat),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final theme = palette.brightness.name;
        await _shot(tester, images, 'menu-closed-$theme');
        await tester.tap(find.byTooltip('打开功能面板'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await _shot(tester, images, 'menu-open-$theme');
        await tester.tap(find.byKey(const ValueKey('panel-plans')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(SavedPlansPage), findsOneWidget);
        await _shot(tester, images, 'saved-list-$theme');
        await tester.tap(find.text('晨间舒展').first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await _shot(tester, images, 'saved-first-tap-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      skip: output == null,
    );
  }
}
