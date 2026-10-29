// Matched real App entry-point screenshots for the +41 supplement.
// Before source is d6bd79cd8dc6c5439f67779bd6e894af7981faa3.
// SF_SCREENSHOT_DIR=<delivery>/screenshots/<before|after>
// SF_PLAN_EXPAND_CAPTURE=1 adds final SDK475 expansion/details/scroll checks.
// Archived before images use the original capture harness and same initial
// three-plan fixture; only the separate scroll scenario adds six more plans.
// flutter test --no-pub --flavor internal
//   test_screens/supplement_review_test.dart --update-goldens
// Software widgets/fonts/assets only; no device/performance acceptance.
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
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachPlanExpanded;
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
  final captureExpansion =
      Platform.environment['SF_PLAN_EXPAND_CAPTURE'] == '1';
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
        if (captureExpansion) {
          // The initial four captures retain the original three-plan fixture.
          // New interactions use the SDK's actual public expanded component.
          expect(find.byType(SavedPlansPage), findsOneWidget);
          final first = store.savedPlans.singleWhere((p) => p.name == '晨间舒展');
          final second = store.savedPlans.singleWhere((p) => p.name == '核心练习');
          bool expanded(String savedId) => tester
              .widget<CoachPlanExpanded>(
                find.byKey(ValueKey('saved-expanded-$savedId')),
              )
              .expanded;
          int expandedCount() => tester
              .widgetList<CoachPlanExpanded>(find.byType(CoachPlanExpanded))
              .where((widget) => widget.expanded)
              .length;
          expect(expanded(first.id), isTrue);
          expect(expanded(second.id), isFalse);
          expect(expandedCount(), 1);
          expect(find.text('查看详情').hitTestable(), findsOneWidget);

          await tester.tap(
            find.byKey(ValueKey('saved-${second.id}')).hitTestable(),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          expect(expanded(first.id), isFalse);
          expect(expanded(second.id), isTrue);
          expect(expandedCount(), 1);
          await _shot(tester, images, 'saved-second-exclusive-$theme');

          await tester.tap(
            find.byKey(ValueKey('plan-expand-${second.plan.id}')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          expect(expandedCount(), 0);
          await _shot(tester, images, 'saved-all-collapsed-$theme');

          await tester.tap(
            find.byKey(ValueKey('saved-${first.id}')).hitTestable(),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          final details = find.byKey(ValueKey('plan-save-${first.plan.id}'));
          await tester.ensureVisible(details);
          await tester.tap(details);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          expect(find.byType(PlanPage), findsOneWidget);
          final detailContext = tester.element(find.byType(PlanPage));
          expect(ModalRoute.of(detailContext)!.settings.name, 'plan');
          await _shot(tester, images, 'saved-details-top-$theme');
          final detailPosition = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          for (var layout = 0; layout < 4; layout++) {
            detailPosition.jumpTo(detailPosition.maxScrollExtent);
            await tester.pump(const Duration(milliseconds: 100));
          }
          await _shot(tester, images, 'saved-details-bottom-$theme');
          expect(detailPosition.extentAfter, lessThanOrEqualTo(1));
          Navigator.of(detailContext).pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 800));
          expect(find.byType(SavedPlansPage), findsOneWidget);

          // Only the separate scrolling scenario adds six more saved fixtures;
          // these are not part of the matched three-plan before/after images.
          for (var index = 0; index < 6; index++) {
            await store.savePlan(
              TrainingPlan.fromJson({
                ..._plan.toJson(),
                'id': 'supplement-scroll-$index',
                'title': '滚动练习 ${index + 1}',
              }),
              now: DateTime(2026, 10, 29, 10, 0, store.savedPlans.length),
            );
          }
          await tester.pump();
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('saved-entry-${first.id}')),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump(const Duration(milliseconds: 800));
          expect(expanded(first.id), isTrue);
          expect(expandedCount(), 1);
          await _shot(tester, images, 'saved-scroll-expanded-$theme');
          await tester.runAsync(
            () => File('$output/interaction-proof-$theme.json').writeAsString(
              '${jsonEncode({'schema': 'smartfit-plus41-expanded-plan-widget-proof@1', 'evidence': 'actual App navigation and public SDK expanded widget', 'nativeDevice': false, 'firstExpanded': true, 'secondExpandedWithFirstCollapsed': true, 'collapseLeavesNoExpandedItem': true, 'detailsRoute': 'plan', 'detailsAtActualBottom': true, 'expandedStatePreservedAfterScroll': true, 'savedCountForMatchedViews': 3, 'savedCountForScrollOnly': store.savedPlans.length, 'oneExpandedVisibleAfterScroll': true})}\n',
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
      skip: output == null,
    );
  }
}
