// Actual Flutter component screenshots for UI polish batch 1.
// Same fixture, viewport and capture time on the before/after worktrees.
// SF_SCREENSHOT_DIR=<absolute output> flutter test --no-pub --flavor internal
// test_screens/ui_polish_review_test.dart --update-goldens
// This renders production widgets. It is not native-device acceptance.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/alpha_artwork.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' hide CoachTaskBubble;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/posehub_ui_support.dart' show poseHubUiApp;
import '../test/support.dart';
import '../test/support/coach_v2_fixtures.dart';

const _plan = TrainingPlan(
  id: 'ui-polish-review-plan',
  source: 'manual',
  title: '居家舒展训练',
  summary: '居家舒展训练',
  goal: 'fullbody',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 15,
  blocks: [
    PlanBlock(
      id: 'warmup',
      name: 'warmup',
      type: BlockType.warmup,
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
      ],
    ),
    PlanBlock(
      id: 'main',
      name: 'main',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-banana',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 30,
          perSide: true,
          restSeconds: 10,
        ),
      ],
    ),
    PlanBlock(
      id: 'cooldown',
      name: 'cooldown',
      type: BlockType.cooldown,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
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

coach.CoachTaskState _task() => coach.CoachTaskState.fromJson({
  'type': 'plan',
  'reused': false,
  'nodes': [
    {'id': 'understand', 'status': 'done', 'stamp': '准备推荐动作', 'doneAtTurn': 1},
    {
      'id': 'parameters',
      'status': 'done',
      'stamp': '居家 · 拉伸 · 徒手',
      'doneAtTurn': 1,
    },
    {'id': 'actions', 'status': 'done', 'stamp': '选了 3 个动作', 'doneAtTurn': 1},
    {'id': 'planning', 'status': 'current', 'stamp': '编排训练'},
    {'id': 'review', 'status': 'pending', 'stamp': ''},
    {'id': 'output', 'status': 'pending', 'stamp': ''},
  ],
});

coach.CoachSessionState _session() => coach.CoachSessionState(
  task: _task(),
  params: {
    'scene': coach.CoachParamValue(
      value: 'home',
      source: 'user',
      quote: '在家',
      turn: 1,
    ),
    'goal': coach.CoachParamValue(
      value: ['purpose.stretch'],
      source: 'user',
      quote: '拉伸',
      turn: 1,
    ),
    'equipment': coach.CoachParamValue(
      value: <String>[],
      source: 'user',
      quote: '徒手',
      turn: 1,
    ),
    'level': coach.CoachParamValue(value: 3, source: 'default', turn: 1),
    'limits': coach.CoachParamValue(
      value: <String>[],
      source: 'default',
      turn: 1,
    ),
  },
  picks: const ['s-butterfly', 'h-adductor-rock', 's-figure4'],
);

// Preload the production bundle's verified bytes outside the fake widget
// clock. Rendering still uses the original component and original images.
class _ReviewImages extends CachingAssetBundle {
  _ReviewImages(this.images);
  final Map<String, ByteData> images;
  @override
  Future<ByteData> load(String key) => images.containsKey(key)
      ? SynchronousFuture(images[key]!)
      : rootBundle.load(key);
}

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

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final host = tester.element(find.byType(MaterialApp));
    final bundle = DefaultAssetBundle.of(host);
    if (bundle is _ReviewImages) {
      // Decode future carousel frames too; a finite pump can advance to a
      // frame that was not mounted when screenshot preparation began.
      for (final key in bundle.images.keys) {
        await precacheImage(
          AssetImage(key, bundle: bundle),
          host,
        ).timeout(const Duration(seconds: 10));
      }
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
  // Finite clock increment also works with the generation card's looping arc.
  await tester.pump(const Duration(milliseconds: 600));
  expect(tester.takeException(), isNull);
  final output = Platform.environment['SF_SCREENSHOT_DIR']!;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(Uri.file('$output/$name.png')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SF_SCREENSHOT_DIR'];
  late CoachV2Fixtures fixture;
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubMediaRepository media;
  late AssetBundle reviewImages;
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
      rootDirectory: '$output/media-cache',
      bundledFileLoader: bundled.loadFile,
    );
    final productionBundle = PoseHubAssetBundle(
      catalog: catalog,
      installation: media,
    );
    final images = <String, ByteData>{};
    for (final id in [
      'h-catcow-quad',
      'h-banana',
      'n-windshield',
      's-butterfly',
      'h-adductor-rock',
      's-figure4',
    ]) {
      for (final role in ['cover', 'thumbnail']) {
        final key = 'posehub-r1/$id/$role';
        images[key] = await productionBundle.load(key);
      }
    }
    reviewImages = _ReviewImages(images);
  });
  tearDownAll(() {
    if (output != null) media.dispose();
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets('actual batch 1 surfaces ${palette.brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = AppStore(MemoryStorage())..starfield = false;
      await store.acceptSafety(blocked: false);
      await store.setAppearance(palette.brightness.name);
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
      final theme = palette.brightness.name;

      Future<void> show(Widget child) async {
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: reviewImages,
            child: poseHubUiApp(
              palette: palette,
              services: services,
              home: SfAlphaCardsScope(enabled: true, child: child),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }

      Widget planCard() => PlanCard(
        plan: _plan,
        library: fixture.library,
        saved: false,
        onStart: () {},
        onSave: () {},
        onOpen: () {},
      );

      // 0: Real recommendation/plan SDK cards in one shared App theme.
      tester.view.physicalSize = const Size(1170, 3600);
      await show(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Builder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  withSmartfitRecommendUi(
                    context,
                    CoachRecommendCard(
                      actionIds: const ['s-butterfly', 'h-adductor-rock'],
                      note: '',
                      library: CoachExerciseLibrary([
                        for (final id in ['s-butterfly', 'h-adductor-rock'])
                          toCoachRecommendationExercise(fixture.library[id]),
                      ]),
                      onOpenAction: (_) {},
                      onPlanFromActions: (_) {},
                    ),
                  ),
                  const SizedBox(height: 12),
                  planCard(),
                ],
              ),
            ),
          ),
        ),
      );
      await _shot(tester, '00-card-surfaces-$theme');
      tester.view.physicalSize = const Size(1170, 2532);

      // 1: Same SDK progress snapshot, presented by App generation widget.
      final generation =
          Function.apply(CoachTaskBubble.new, [], {
                #task: _task(),
                #waiting: true,
                #onCancel: () {},
                if (Platform.environment['SF_SCREENSHOT_AFTER'] == '1') ...{
                  #sessionState: _session(),
                  #library: fixture.library,
                },
              })
              as Widget;
      await show(
        Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: generation),
        ),
      );
      await _shot(tester, '01-generation-$theme');

      // 2: SDK plan fold and expand states; no card facsimile.
      await show(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: planCard(),
          ),
        ),
      );
      await _shot(tester, '02-plan-collapsed-$theme');
      await tester.tap(
        find.byKey(const ValueKey('plan-expand-ui-polish-review-plan')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await _shot(tester, '02-plan-expanded-$theme');

      // 3: Production chat and composer, including panel-to-dock junction.
      final chat = ChatController(
        engine: services.chatEngine,
        store: store,
        replyDelay: Duration.zero,
        clock: () => DateTime(2026, 10, 29, 10),
      );
      addTearDown(chat.dispose);
      await show(ChatHomePage(controller: chat));
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '今天想轻松练一会儿',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await _shot(tester, '03-composer-$theme');

      // 4: Production PoseHub library browser, including SDK cards.
      await show(const LibraryPage());
      await _shot(tester, '04-library-$theme');

      // 5: Production saved plan entry; before tap opens chat, after expands.
      await store.savePlan(
        _plan,
        name: _plan.title,
        now: DateTime(2026, 10, 29, 10),
      );
      await show(
        SavedPlansPage(
          store: store,
          library: fixture.library,
          onShow: (_) {},
          onStart: (_, _) {},
        ),
      );
      await _shot(tester, '05-saved-collapsed-$theme');
      final saved = store.savedPlans.single;
      await tester.tap(find.byKey(ValueKey('saved-${saved.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await _shot(tester, '05-saved-expanded-$theme');

      // 6: Production article top and final body clearance under floating CTA.
      await show(const PlanPage(plan: _plan));
      await _shot(tester, '06-details-top-$theme');
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      // Lazy variable-height children refine their maximum after layout.
      for (var frame = 0; frame < 4; frame++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _shot(tester, '06-details-bottom-$theme');
      expect(position.extentAfter, lessThanOrEqualTo(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }, skip: output == null);
  }
}
