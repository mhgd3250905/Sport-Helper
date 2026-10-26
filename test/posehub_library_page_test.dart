import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_pack_installation.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
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
  final base = Uri.parse('file:///verified-posehub-pack/');

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
    'library waits for one shared installation, then uses SDK browser',
    (tester) async {
      final ready = Completer<Uri>();
      var calls = 0;
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () {
          calls++;
          return ready.future;
        },
      );
      final services = poseHubUiServices(
        catalog: catalog,
        installation: installation,
      );
      final app = poseHubUiApp(
        palette: SfPalette.light,
        services: services,
        home: const LibraryPage(),
      );
      await tester.pumpWidget(app);
      expect(find.byKey(const ValueKey('posehub-preparing')), findsOneWidget);
      expect(find.byType(PoseHubActionBrowser), findsNothing);
      await tester.pumpWidget(app);
      await tester.pump();
      expect(calls, 1);
      ready.complete(base);
      await tester.pumpAndSettle();
      final browser = tester.widget<PoseHubActionBrowser>(
        find.byType(PoseHubActionBrowser),
      );
      expect(browser.catalog, same(catalog));
      expect(browser.mediaBaseUri, base);
      expect(browser.theme!.background, SfPalette.light.background);
      expect(find.text('动作库 · 219'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      installation.dispose();
    },
  );

  testWidgets('failed preparation retries without the old media resolver', (
    tester,
  ) async {
    var calls = 0;
    final installation = PoseHubPackInstallation.forTesting(
      enabled: true,
      install: () async {
        if (++calls == 1) throw StateError('test installation failure');
        return base;
      },
    );
    await tester.pumpWidget(
      poseHubUiApp(
        palette: SfPalette.dark,
        home: PoseHubLibraryPage(catalog: catalog, media: installation),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('posehub-prepare-error')), findsOneWidget);
    expect(find.byType(PoseHubActionBrowser), findsNothing);
    await tester.tap(find.byKey(const ValueKey('posehub-prepare-retry')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(PoseHubActionBrowser), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    installation.dispose();
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'SDK browse/search/pending/manual practice, ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final installation = PoseHubPackInstallation.forTesting(
          enabled: true,
          install: () async => base,
        );
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            home: PoseHubLibraryPage(catalog: catalog, media: installation),
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
        installation.dispose();
      },
    );
  }

  testWidgets(
    'pack media waits, preserves controls and exposes no invented position',
    (tester) async {
      final ready = Completer<Uri>();
      final installation = PoseHubPackInstallation.forTesting(
        enabled: true,
        install: () => ready.future,
      );
      final action = catalog.allActions.first;
      final second = catalog.allActions[1];
      final handle = DrillMediaPlaybackHandle();
      final services = poseHubUiServices(
        catalog: catalog,
        installation: installation,
      );
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
      expect(
        find.byKey(const ValueKey('posehub-media-preparing')),
        findsOneWidget,
      );
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
      final media = tester.widget<PoseHubPackMedia>(
        find.byType(PoseHubPackMedia),
      );
      expect(media.paused, isTrue);
      expect(platform.commands, contains((1, 'pause', null)));
      expect(find.byType(Transform), findsWidgets);
      await tester.pumpWidget(show(selected: second, playing: false));
      await tester.pump();
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
      installation.dispose();
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
