import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

String _asset(Image image) {
  ImageProvider provider = image.image;
  while (provider is ResizeImage) {
    provider = provider.imageProvider;
  }
  return (provider as AssetImage).assetName;
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

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

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'bundled standing preview needs no preparation ${palette.brightness.name}',
      (tester) async {
        final repo = PoseHubUiRepository(mediaBaseUri: base);
        final services = poseHubUiServices(catalog: catalog, media: repo);
        final action = catalog.semanticCompleteActions.first;
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: Scaffold(
              body: SizedBox.square(
                dimension: 240,
                child: ExerciseVideo(
                  exercise: poseHubUiExercise(action),
                  playing: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ExerciseFrameZero), findsOneWidget);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        final image = tester.widget<Image>(
          find.byKey(ValueKey('exercise-frame-zero-${action.id}')),
        );
        expect(_asset(image), endsWith('/standing/${action.id}.webp'));
        expect(repo.fileRequests, isEmpty);
        expect(repo.actionRequests, isEmpty);
        expect(platform.uris, isEmpty);
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        repo.dispose();
      },
    );

    testWidgets(
      'pending and failed media stay silent with standing art ${palette.brightness.name}',
      (tester) async {
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
            home: Scaffold(
              body: SizedBox.square(
                dimension: 240,
                child: ExerciseVideo(exercise: poseHubUiExercise(action)),
              ),
            ),
          ),
        );
        await _frames(tester);
        expect(repo.actionRequests, [action.id]);
        expect(find.byType(ExerciseFrameZero), findsOneWidget);
        expect(platform.uris, isEmpty);
        pending.completeError(StateError('UI-only transport failure'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(find.textContaining('准备失败'), findsNothing);
        expect(find.textContaining('重试'), findsNothing);
        expect(find.byType(ExerciseFrameZero), findsOneWidget);
        expect(platform.uris, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        repo.dispose();
      },
    );
  }

  testWidgets(
    'late previous action never creates its decoder or invents issue position',
    (tester) async {
      final a = catalog.semanticCompleteActions[0];
      final b = catalog.semanticCompleteActions[1];
      final first = Completer<Uri>();
      final second = Completer<Uri>();
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (id) => id == a.id ? first.future : second.future,
      );
      final services = poseHubUiServices(catalog: catalog, media: repo);
      final handle = DrillMediaPlaybackHandle();
      Widget show(
        coach.PoseHubPackAction action, {
        bool paused = false,
        bool playing = true,
        bool covered = false,
      }) => poseHubUiApp(
        palette: SfPalette.dark,
        services: services,
        home: Scaffold(
          body: TickerMode(
            enabled: !covered,
            child: SizedBox.square(
              dimension: 240,
              child: ExerciseVideo(
                key: const ValueKey('media'),
                exercise: poseHubUiExercise(action),
                paused: paused,
                playing: playing,
                playbackHandle: handle,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(show(a));
      await _frames(tester);
      await tester.pumpWidget(show(b));
      await _frames(tester);
      first.complete(base);
      await tester.pump();
      expect(platform.uris, isEmpty);
      var snapshot = await handle.capture();
      expect(snapshot!.mediaId, b.id);
      expect(snapshot.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      second.complete(base);
      await _frames(tester);
      expect(platform.uris, [b.video.resolve(base)]);
      platform.ready(1);
      await tester.pump();
      await tester.pumpWidget(show(b, paused: true));
      await tester.pump();
      expect(platform.commands, contains((1, 'pause', null)));
      snapshot = await handle.capture();
      expect(snapshot!.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      await tester.pumpWidget(show(b, covered: true));
      await tester.pump();
      await _frames(tester);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      expect(platform.commands, contains((1, 'dispose', null)));
      expect(find.byType(ExerciseFrameZero), findsOneWidget);
      await tester.pumpWidget(show(b));
      await tester.pump();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _frames(tester);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      expect(find.byType(ExerciseFrameZero), findsOneWidget);
      snapshot = await handle.capture();
      expect(snapshot!.mediaId, b.id);
      expect(snapshot.ready, isFalse);
      expect(snapshot.videoSeconds, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(await handle.capture(), isNull);
      handle.dispose();
      repo.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
