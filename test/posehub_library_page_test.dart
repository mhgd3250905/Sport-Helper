import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/posehub_library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/trainer_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

void main() {
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
        expect(find.textContaining('待补'), findsNothing);
        expect(find.textContaining('219'), findsNothing);
        expect(
          find.text(catalog.semanticCompleteActions.first.id),
          findsNothing,
        );
        expect(repo.actionRequests, isEmpty);
        expect(repo.fileRequests, isEmpty);

        await tester.tap(find.byKey(const ValueKey('posehub-器械-徒手')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('posehub-部位-胸')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('posehub-类型-力量')));
        await tester.pumpAndSettle();
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
        expect(count(tester), expected);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('posehub-器械-徒手')))
              .selected,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-clear-filters')));
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
          last.id,
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
        await tester.tap(find.byKey(ValueKey('posehub-action-${action.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
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
        expect(player.prepSeconds, 0);
        expect(player.poseHubActionOf!(action.id), same(action));
        expect(player.poseHubMediaPreparer, same(services.poseHubPreparer));
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

  testWidgets(
    'coach action opens SDK training, not the legacy production sheet',
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
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TrainerPlayer), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
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
      await tester.tap(find.byKey(ValueKey('posehub-action-${action.id}')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
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

  test('SmartFit shared SDK theme maps both palettes', () {
    for (final palette in [SfPalette.light, SfPalette.dark]) {
      final theme = SmartFitTrainerTheme.fromPalette(palette);
      expect(theme.background, palette.background);
      expect(theme.surface, palette.surface);
      expect(theme.surfaceHigh, palette.surfaceHigh);
      expect(theme.accent, palette.accent);
      expect(theme.mediaStage, palette.mediaStage);
      expect(theme.fontFamily, sfFontFamily);
    }
  });
}
