import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/gated_posehub_media_preparer.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/posehub_library_page.dart';
import 'package:smartfit/ui/single_practice_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/trainer_theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' hide TrainingPosterImages;

import 'posehub_ui_support.dart';
import 'support/widget_test_timeout.dart';

void main() {
  configureWidgetTestTimeout();
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubUiVideoPlatform platform;
  final base = Uri.parse('file:///ui-contract-pack/');
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    platform = PoseHubUiVideoPlatform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.close();
  });

  int count(WidgetTester tester) =>
      (tester
                  .widget<GridView>(
                    find.byKey(const ValueKey('posehub-action-list')),
                  )
                  .childrenDelegate
              as SliverChildBuilderDelegate)
          .childCount!;

  Future<TrainingRouteControl> openPreview(
    WidgetTester tester,
    coach.PoseHubPackAction action,
    Finder trigger, {
    PoseHubUiRepository? repository,
  }) async {
    final library = find.byType(PoseHubLibraryPage);
    final source = tester.element(
      library.evaluate().isNotEmpty ? library : find.byType(Scaffold).first,
    );
    await tester.runAsync(
      () => TrainingPosterImages.precacheAsset(
        source,
        'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${action.id}.webp',
      ),
    );
    await tester.pump();
    await tester.tap(trigger);
    final host = find.byType(SinglePracticePage, skipOffstage: false);
    for (var i = 0; i < 12 && host.evaluate().isEmpty; i++) {
      await tester.pump();
    }
    await tester.pump();
    expect(host, findsOneWidget);
    final control = TrainingRouteScope.maybeOf(tester.element(host))!;
    void expectGated() {
      expect(control.entered, isFalse);
      expect(find.byType(TrainingPoster, skipOffstage: false), findsOneWidget);
      expect(find.byType(ExerciseVideo, skipOffstage: false), findsNothing);
      expect(find.byType(PoseHubPackMedia, skipOffstage: false), findsNothing);
      expect(platform.uris, isEmpty);
      if (repository != null) expect(repository.actionRequests, isEmpty);
      expect(find.byKey(const ValueKey('start-training')), findsOneWidget);
      expect(find.byKey(const ValueKey('info-card')), findsOneWidget);
    }

    expectGated();
    await tester.pump(const Duration(milliseconds: 150));
    expectGated();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump();
    expect(control.entered, isTrue);
    expect(
      find.byType(ExerciseVideo).evaluate().length +
          find.byType(PoseHubPackMedia).evaluate().length,
      1,
      reason: 'The real media surface is mounted only after the slide',
    );
    return control;
  }

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'SDK complete-only two-column library and combinable filters ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2100);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        final repo = PoseHubUiRepository(mediaBaseUri: base);
        final services = poseHubUiServices(catalog: catalog, media: repo);
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: const LibraryPage(),
          ),
        );
        expect(find.byType(PoseHubActionBrowser), findsOneWidget);
        expect(
          find.byKey(const ValueKey('posehub-images-preparing')),
          findsNothing,
        );
        expect(count(tester), 211);
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          2,
        );
        final firstAction = catalog.semanticCompleteActions.first;
        final sdkTheme = palette.isDark
            ? TrainerTheme.dark
            : TrainerTheme.light;
        final surface = tester.widget<DecoratedBox>(
          find.byKey(ValueKey('posehub-card-surface-${firstAction.id}')),
        );
        final decoration = surface.decoration as BoxDecoration;
        expect(decoration.color, sdkTheme.cardSurface);
        expect(decoration.border, Border.all(color: sdkTheme.cardBorder));
        expect(decoration.borderRadius, BorderRadius.circular(20));
        expect(decoration.gradient, isNull);
        expect(decoration.boxShadow, isNull);
        final title = tester.widget<Text>(find.text(firstAction.nameZh));
        expect(title.style!.fontSize, 15);
        expect(title.style!.fontWeight, FontWeight.w600);
        expect(title.style!.height, 1.35);
        expect(
          tester
              .widget<AspectRatio>(
                find.byKey(ValueKey('posehub-image-area-${firstAction.id}')),
              )
              .aspectRatio,
          1,
        );
        expect(find.textContaining('待补'), findsNothing);
        expect(find.textContaining('219'), findsNothing);
        expect(
          find.text(catalog.semanticCompleteActions.first.id),
          findsNothing,
        );
        expect(repo.actionRequests, isEmpty);
        expect(repo.fileRequests, isEmpty);

        await tester.tap(find.byKey(const ValueKey('posehub-quick-胸')));
        await tester.pumpAndSettle();
        final chestCount = catalog.semanticCompleteActions
            .where(
              (action) => PoseHubActionFacets.matches(action, bodyPart: '胸'),
            )
            .length;
        expect(chestCount, greaterThan(0));
        expect(count(tester), chestCount);
        await tester.tap(find.byKey(const ValueKey('posehub-quick-全部')));
        await tester.pumpAndSettle();
        expect(count(tester), 211);

        // SDK v0.6.0: facet chips live in the filter sheet.
        Future<void> tapChip(String key) async {
          final chip = find.byKey(ValueKey(key));
          await tester.ensureVisible(chip);
          await tester.tap(chip);
          await tester.pumpAndSettle();
        }

        await tester.tap(find.byKey(const ValueKey('posehub-filter-button')));
        await tester.pumpAndSettle();
        await tapChip('posehub-器械-徒手');
        await tapChip('posehub-部位-胸');
        await tapChip('posehub-类型-力量');
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('posehub-器械-徒手')))
              .selected,
          isTrue,
        );
        final expected = catalog.semanticCompleteActions
            .where(
              (action) => PoseHubActionFacets.matches(
                action,
                equipment: '徒手',
                bodyPart: '胸',
                type: '力量',
              ),
            )
            .length;
        expect(expected, greaterThan(0));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('posehub-filter-apply')),
            matching: find.text('查看 $expected 个动作'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-filter-apply')));
        await tester.pumpAndSettle();
        expect(count(tester), expected);
        expect(
          find.byKey(const ValueKey('posehub-filter-badge')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-filter-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('posehub-filter-reset')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('posehub-filter-apply')));
        await tester.pumpAndSettle();
        expect(count(tester), 211);
        final last = catalog.semanticCompleteActions.last;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('posehub-action-${last.id}')),
          500,
          scrollable: find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          ),
          maxScrolls: 100,
        );
        expect(
          find.byKey(ValueKey('posehub-action-${last.id}')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          '__missing_action__',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('posehub-empty-state')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-empty-clear')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          last.nameZh,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('posehub-action-${last.id}')),
          findsOneWidget,
        );
        expect(repo.actionRequests, isEmpty);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final browserState = tester.state(find.byType(TrainingLibraryBrowser));
        final position = tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(GridView),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        final offset = position.pixels;
        await openPreview(
          tester,
          last,
          find.byKey(ValueKey('posehub-action-${last.id}')),
          repository: repo,
        );
        await tester.tap(find.byKey(const ValueKey('close')));
        await tester.pumpAndSettle();
        expect(find.byType(TrainerPlayer), findsNothing);
        expect(
          tester.state(find.byType(TrainingLibraryBrowser)),
          same(browserState),
        );
        expect(position.pixels, offset);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('posehub-search')))
              .controller!
              .text,
          last.nameZh,
        );
        expect(services.store.history, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.dispose();
      },
    );

    testWidgets(
      'one card opens shared Trainer immediately while download is pending ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2100);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        final pending = Completer<Uri>();
        final repo = PoseHubUiRepository(
          mediaBaseUri: base,
          onEnsureAction: (_) => pending.future,
        );
        final services = poseHubUiServices(catalog: catalog, media: repo);
        final action = catalog.semanticCompleteActions.first;
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: const LibraryPage(),
          ),
        );
        await openPreview(
          tester,
          action,
          find.byKey(ValueKey('posehub-action-${action.id}')),
          repository: repo,
        );
        expect(find.byType(PoseHubSinglePracticePage), findsOneWidget);
        expect(find.byType(TrainerPlayer), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PoseHubPackMedia),
            matching: find.byType(PoseHubStandingImage),
          ),
          findsOneWidget,
        );
        expect(platform.uris, isEmpty);
        expect(repo.actionRequests, [action.id]);
        final player = tester.widget<TrainerPlayer>(find.byType(TrainerPlayer));
        expect(player.startMode, TrainerStartMode.preview);
        expect(player.prepSeconds, 10);
        expect(
          tester
              .widget<SinglePracticePage>(find.byType(SinglePracticePage))
              .page
              .onCompleted,
          services.recordTrainingCompletion,
        );
        expect(player.poseHubActionOf!(action.id), same(action));
        expect(player.poseHubMediaPreparer, isA<GatedPoseHubMediaPreparer>());
        expect(
          (player.poseHubMediaPreparer! as GatedPoseHubMediaPreparer).delegate,
          same(services.poseHubPreparer),
        );
        expect(
          tester
              .widget<SinglePracticePage>(find.byType(SinglePracticePage))
              .page
              .mediaPreparer,
          same(services.poseHubPreparer),
        );
        expect(find.byKey(const ValueKey('pause')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('progress')), findsNothing);
        expect(services.store.history, isEmpty);
        final mediaState = tester.state(find.byType(PoseHubPackMedia));
        await tester.pump(const Duration(seconds: 15));
        expect(services.store.history, isEmpty);
        expect(find.byKey(const ValueKey('start-training')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('start-training')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.state(find.byType(PoseHubPackMedia)), same(mediaState));
        expect(find.byKey(const ValueKey('progress')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('pause')));
        await tester.pump();
        expect(
          tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).paused,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        pending.complete(base);
        repo.dispose();
      },
    );
  }

  testWidgets('library copy follows the host locale without losing its scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2100);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final locale = ValueNotifier(const Locale('zh', 'CN'));
    addTearDown(locale.dispose);
    final repo = PoseHubUiRepository(mediaBaseUri: base);
    final services = poseHubUiServices(catalog: catalog, media: repo);
    final search = find.byKey(const ValueKey('posehub-search'));
    final filter = find.byKey(const ValueKey('posehub-filter-button'));
    final apply = find.byKey(const ValueKey('posehub-filter-apply'));
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (_, value, child) => poseHubUiApp(
          palette: SfPalette.light,
          services: services,
          locale: value,
          home: const LibraryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(count(tester), 211);
    expect(
      tester.widget<TextField>(search).decoration!.hintText,
      '搜动作，中文或英文都行',
    );
    expect(
      find.descendant(of: filter, matching: find.text('筛选')),
      findsOneWidget,
    );
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: apply, matching: find.text('查看 211 个动作')),
      findsOneWidget,
    );
    await tester.tap(apply);
    await tester.pumpAndSettle();
    final browserState = tester.state(find.byType(TrainingLibraryBrowser));

    locale.value = const Locale('en');
    await tester.pumpAndSettle();
    expect(
      tester.state(find.byType(TrainingLibraryBrowser)),
      same(browserState),
    );
    expect(count(tester), 211);
    expect(
      tester.widget<TextField>(search).decoration!.hintText,
      'Search moves in English or Chinese',
    );
    expect(
      find.descendant(of: filter, matching: find.text('Filter')),
      findsOneWidget,
    );
    final action = catalog.semanticCompleteActions.first;
    await tester.enterText(search, action.id);
    await tester.pumpAndSettle();
    expect(count(tester), 1);
    expect(find.byKey(ValueKey('posehub-action-${action.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('posehub-search-clear')));
    await tester.pumpAndSettle();
    expect(count(tester), 211);
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: apply, matching: find.text('Show 211 moves')),
      findsOneWidget,
    );
    expect(find.text('Reset'), findsOneWidget);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(repo.actionRequests, isEmpty);
    expect(repo.fileRequests, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    repo.dispose();
  });

  testWidgets(
    'coach action opens SDK preview and leaving it never saves a workout',
    (tester) async {
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) => Completer<Uri>().future,
      );
      final services = poseHubUiServices(catalog: catalog, media: repo);
      final action = catalog.semanticCompleteActions.first;
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showExerciseDetails(context, poseHubUiExercise(action)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      final source = tester.element(find.byType(Scaffold));
      await openPreview(tester, action, find.text('open'), repository: repo);
      expect(find.byType(TrainerPlayer), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final preview = tester.widget<TrainerPlayer>(find.byType(TrainerPlayer));
      final single = tester.widget<PoseHubSinglePracticePage>(
        find.byType(PoseHubSinglePracticePage),
      );
      expect(single.startMode, TrainerStartMode.preview);
      expect(preview.startMode, TrainerStartMode.preview);
      expect(preview.prepSeconds, 10);
      expect(
        tester
            .widget<SinglePracticePage>(find.byType(SinglePracticePage))
            .page
            .onCompleted,
        services.recordTrainingCompletion,
      );
      expect(services.store.history, isEmpty);
      await tester.pump(const Duration(seconds: 15));
      await tester.tap(find.byKey(const ValueKey('close')));
      await tester.pumpAndSettle();
      expect(find.byType(TrainerPlayer), findsNothing);
      expect(services.store.history, isEmpty);
      expect(tester.element(find.byType(Scaffold)), same(source));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.dispose();
    },
  );

  testWidgets(
    'missing cache still opens library and training with standing art',
    (tester) async {
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          home: PoseHubLibraryPage(catalog: catalog),
        ),
      );
      final browser = tester.widget<PoseHubActionBrowser>(
        find.byType(PoseHubActionBrowser),
      );
      expect(browser.mediaPreparer, isNotNull);
      final action = catalog.semanticCompleteActions.first;
      await openPreview(
        tester,
        action,
        find.byKey(ValueKey('posehub-action-${action.id}')),
      );
      expect(find.byType(TrainerPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PoseHubPackMedia),
          matching: find.byType(PoseHubStandingImage),
        ),
        findsOneWidget,
      );
      expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
      expect(find.textContaining('缓存暂不可用'), findsNothing);
      expect(platform.uris, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  test('SDK shared surfaces remain defaults with SmartFit brand accents', () {
    for (final palette in [SfPalette.light, SfPalette.dark]) {
      final theme = SmartFitTrainerTheme.fromPalette(palette);
      final defaults = palette.isDark ? TrainerTheme.dark : TrainerTheme.light;
      expect(theme.background, defaults.background);
      expect(theme.surface, defaults.surface);
      expect(theme.surfaceHigh, defaults.surfaceHigh);
      expect(theme.accent, palette.accent);
      expect(theme.mediaStage, defaults.mediaStage);
      expect(theme.cardSurface, defaults.cardSurface);
      expect(theme.cardBorder, defaults.cardBorder);
      expect(theme.primaryForeground, defaults.primaryForeground);
      expect(theme.fontFamily, sfFontFamily);
    }
  });
}
