import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/posehub_download_status.dart';
import 'package:smartfit/ui/posehub_library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/trainer_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.close();
  });

  testWidgets(
    'library first frame shows metadata while an action is still preparing',
    (tester) async {
      final ready = Completer<Uri>();
      final media = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) => ready.future,
      );
      final preparing = media.ensureAction(catalog.allActions.first.id);
      final services = poseHubUiServices(catalog: catalog, media: media);
      final app = poseHubUiApp(
        palette: SfPalette.light,
        services: services,
        home: const LibraryPage(),
      );
      await tester.pumpWidget(app);
      expect(ready.isCompleted, isFalse);
      expect(find.byType(PoseHubActionBrowser), findsOneWidget);
      final browser = tester.widget<PoseHubActionBrowser>(
        find.byType(PoseHubActionBrowser),
      );
      expect(browser.catalog, same(catalog));
      expect(browser.mediaBaseUri, base);
      expect(browser.theme!.background, SfPalette.light.background);
      expect(find.text('动作库 · 219'), findsOneWidget);
      ready.complete(base);
      await preparing;
      await tester.pumpWidget(const SizedBox.shrink());
      media.dispose();
    },
  );

  testWidgets(
    'failed action preparation never blocks library scroll or search',
    (tester) async {
      final media = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) async => throw StateError('UI transfer failure'),
      );
      await expectLater(
        media.ensureAction(catalog.allActions.first.id),
        throwsStateError,
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          home: PoseHubLibraryPage(catalog: catalog, media: media),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PoseHubActionBrowser), findsOneWidget);
      final list = find.byKey(const ValueKey('posehub-action-list'));
      final before = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      final after = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      expect(after, greaterThan(before));
      await tester.enterText(
        find.byKey(const ValueKey('posehub-search')),
        catalog.allActions.last.id,
      );
      await tester.pumpAndSettle();
      expect(find.text('显示 1 个动作'), findsOneWidget);
      expect(
        find.byKey(ValueKey('posehub-action-${catalog.allActions.last.id}')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      media.dispose();
    },
  );

  // SDK 0.4.1 navigation/control regression only. Its provider hook is pending;
  // these interactions do not claim that SDK pages initiate Repo downloads.
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'SDK browse/search/pending/manual practice, ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final media = PoseHubUiRepository(mediaBaseUri: base);
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            home: PoseHubLibraryPage(catalog: catalog, media: media),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('显示 219 个动作'), findsOneWidget);
        final list = find.descendant(
          of: find.byKey(const ValueKey('posehub-action-list')),
          matching: find.byType(Scrollable),
        );
        final last = catalog.allActions.last;
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('posehub-action-${last.id}')),
          1000,
          scrollable: list,
          maxScrolls: 50,
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
        expect(find.text('显示 1 个动作'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          '',
        );
        await tester.tap(
          find.byKey(const ValueKey('posehub-filter-semanticComplete')),
        );
        await tester.pumpAndSettle();
        expect(find.text('显示 211 个动作'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('posehub-filter-pending')));
        await tester.pumpAndSettle();
        expect(find.text('显示 8 个动作'), findsOneWidget);
        final pending = catalog.tryGet('h-towel-isometric-curl')!;
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          pending.id,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('posehub-action-${pending.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(PoseHubActionDetail), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('posehub-pending-label')),
          300,
        );
        expect(find.textContaining('原始建议：'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('posehub-practice')),
          300,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-practice')));
        await tester.pumpAndSettle();
        expect(find.byType(PoseHubSinglePracticePage), findsOneWidget);
        expect(find.text('训练说明待补'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('posehub-practice-toggle')),
          300,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-practice-toggle')));
        await tester.pump();
        expect(platform.uris, [pending.video.resolve(base)]);
        platform.ready(1);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('posehub-practice-toggle')));
        await tester.pump();
        expect(find.text('继续'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('posehub-practice-toggle')));
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(find.text('继续'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('posehub-practice-finish')),
          100,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-practice-finish')));
        await tester.pump();
        expect(find.text('单练已结束'), findsOneWidget);
        expect(find.textContaining('原始建议：'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        media.dispose();
      },
    );
  }

  testWidgets(
    'pack media waits, preserves controls and exposes no invented position',
    (tester) async {
      final ready = Completer<Uri>();
      final media = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) => ready.future,
      );
      final action = catalog.allActions.first;
      final second = catalog.allActions[1];
      final handle = DrillMediaPlaybackHandle();
      final services = poseHubUiServices(catalog: catalog, media: media);
      Widget show({
        coach.PoseHubPackAction? selected,
        bool playing = true,
        bool paused = false,
        bool mirrored = false,
      }) => poseHubUiApp(
        palette: SfPalette.dark,
        services: services,
        home: Scaffold(
          body: SizedBox.square(
            dimension: 240,
            child: ExerciseVideo(
              exercise: poseHubUiExercise(selected ?? action),
              playing: playing,
              paused: paused,
              mirrored: mirrored,
              playbackHandle: handle,
            ),
          ),
        ),
      );
      await tester.pumpWidget(show());
      expect(find.byType(PoseHubDownloadStatus), findsOneWidget);
      expect(find.byType(DrillMediaView), findsNothing);
      var snapshot = await handle.capture();
      expect(snapshot!.mediaId, action.id);
      expect(snapshot.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      ready.complete(base);
      await tester.pumpAndSettle();
      expect(platform.uris, [action.video.resolve(base)]);
      platform.ready(1);
      await tester.pump();
      await tester.pumpWidget(show(paused: true, mirrored: true));
      await tester.pump();
      final playback = tester.widget<PoseHubPackMedia>(
        find.byType(PoseHubPackMedia),
      );
      expect(playback.paused, isTrue);
      expect(platform.commands, contains((1, 'pause', null)));
      expect(find.byType(Transform), findsWidgets);
      await tester.pumpWidget(show(selected: second, playing: false));
      await tester.pumpAndSettle();
      snapshot = await handle.capture();
      expect(snapshot!.mediaId, second.id);
      expect(snapshot.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      expect(
        tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).playing,
        isFalse,
      );
      expect(platform.uris, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(await handle.capture(), isNull);
      handle.dispose();
      media.dispose();
    },
  );

  test(
    'SmartFit shared SDK theme maps both palettes without opaque role changes',
    () {
      for (final palette in [SfPalette.light, SfPalette.dark]) {
        final theme = SmartFitTrainerTheme.fromPalette(palette);
        expect(theme.background, palette.background);
        expect(theme.surface, palette.surface);
        expect(theme.surfaceHigh, palette.surfaceHigh);
        expect(theme.accent, palette.accent);
        expect(theme.mediaStage, palette.mediaStage);
        expect(theme.fontFamily, sfFontFamily);
      }
    },
  );
}
