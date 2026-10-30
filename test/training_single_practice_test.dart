import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/gated_posehub_media_preparer.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/training_transition_timings.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/single_practice_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

class _Voice extends MutedVoiceOutput {
  int begins = 0;
  @override
  Future<void> begin() async => begins++;
}

class _Preparer implements PoseHubMediaPreparer {
  final requests = <String>[];
  @override
  Stream<PoseHubMediaPreparationEvent> prepareAction(
    coach.PoseHubPackAction action,
  ) {
    requests.add(action.id);
    return const Stream<PoseHubMediaPreparationEvent>.empty();
  }
}

class _MediaProbe extends StatefulWidget {
  const _MediaProbe({required this.fixture, required this.request});
  final _Fixture fixture;
  final TrainerMediaRequest request;
  @override
  State<_MediaProbe> createState() => _MediaProbeState();
}

class _MediaProbeState extends State<_MediaProbe> {
  @override
  void initState() {
    super.initState();
    widget.fixture.mediaCreated++;
    widget.fixture.mediaPaused = widget.request.paused;
  }

  @override
  void didUpdateWidget(_MediaProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.fixture.mediaPaused = widget.request.paused;
  }

  @override
  void dispose() {
    widget.fixture.mediaDisposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('single-practice-custom-media'));
}

class _Fixture {
  _Fixture(
    this.catalog, {
    this.palette = SfPalette.light,
    this.mode = TrainerStartMode.training,
    this.originalGate,
    this.customMedia = true,
    this.emptyLibrary = false,
    this.failures = 0,
    this.finishFailures = 0,
  });
  final coach.PoseHubAppTestCatalog catalog;
  final SfPalette palette;
  final TrainerStartMode mode;
  final Completer<void>? originalGate;
  final bool customMedia;
  final bool emptyLibrary;
  int failures;
  int finishFailures;
  final nav = GlobalKey<NavigatorState>();
  final voice = _Voice();
  final preparer = _Preparer();
  final receipts = <SessionResult>[];
  final requests = <TrainerMediaRequest>[];
  final base = Uri.parse('file:///single-practice-preserved-origin/');
  int starts = 0, finished = 0, completed = 0, successfulSaves = 0;
  int exitNotifications = 0, beforePops = 0;
  int mediaCreated = 0, mediaDisposed = 0;
  bool mediaPaused = false;
  Completer<void>? saving, beforePop;
  late final action = catalog.semanticCompleteActions.first;
  late final exercise = poseHubUiExercise(action);
  late final theme = (palette.isDark ? TrainerTheme.dark : TrainerTheme.light)
      .copyWith(
        radius: 19,
        accent: const Color(0xff368f85),
        mediaStage: const Color(0xff394857),
      );
  late final AppServices services = poseHubUiServices(
    catalog: catalog,
    media: null,
    library: ExerciseLibrary(emptyLibrary ? [] : [exercise]),
    voiceOutput: voice,
  );
  late final voiceConfig = services.trainerVoice();
  late final original = PoseHubSinglePracticePage(
    key: const ValueKey('original-sdk-single-practice'),
    action: action,
    mediaBaseUri: base,
    theme: theme,
    mediaPreparer: preparer,
    voice: voiceConfig,
    startMode: mode,
    startGate: originalGate?.future,
    onStartTraining: () => starts++,
    onFinished: (_) {
      finished++;
      if (finishFailures > 0) {
        finishFailures--;
        throw StateError('original synchronous finished callback failure');
      }
    },
    onCompleted: (_) async {
      completed++;
      await saving?.future;
      if (failures > 0) {
        failures--;
        throw StateError('original completion callback failure');
      }
      successfulSaves++;
    },
    onExitStarted: () => exitNotifications++,
    beforeExitPop: () async {
      beforePops++;
      await beforePop?.future;
    },
    mediaBuilder: customMedia
        ? (context, request) {
            requests.add(request);
            return _MediaProbe(fixture: this, request: request);
          }
        : null,
  );
  late TrainingRoute<SessionResult> route;

  void open(BuildContext context) {
    route = TrainingRoute<SessionResult>(
      context: context,
      sourceEntry: 'single-practice-test',
      trainerTheme: original.theme,
      builder: (_) => SinglePracticePage(page: original),
    );
    unawaited(
      nav.currentState!.push(route).then((result) async {
        await route.completed;
        if (result != null) receipts.add(result);
      }),
    );
  }
}

Future<_Fixture> _mount(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  await tester.pumpWidget(
    poseHubUiApp(
      palette: fixture.palette,
      services: fixture.services,
      navigatorKey: fixture.nav,
      home: Builder(
        builder: (context) => Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => fixture.open(context),
            child: const SizedBox(
              width: 240,
              height: 60,
              child: Text('open practice'),
            ),
          ),
        ),
      ),
    ),
  );
  final source = tester.element(find.byType(Scaffold));
  await tester.runAsync(
    () => TrainingPosterImages.precacheAsset(
      source,
      'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${fixture.action.id}.webp',
    ),
  );
  await tester.tap(find.text('open practice'));
  await _frames(tester);
  return fixture;
}

Future<void> _frames(WidgetTester tester, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump();
  }
}

Future<void> _enter(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(microseconds: 1));
  await _frames(tester);
}

Future<void> _exitTime(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 280));
  await tester.pump(const Duration(microseconds: 1));
  await _frames(tester);
}

Future<void> _confirmExit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('close')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('close-confirm')));
  await _frames(tester);
}

void _expectPosterColor(WidgetTester tester, Finder poster, Color expected) {
  expect(tester.widget<TrainingPoster>(poster).stageColor, expected);
  final box = find.descendant(of: poster, matching: find.byType(ColoredBox));
  expect(tester.widget<ColoredBox>(box.first).color, expected);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late PoseHubUiVideoPlatform platform;
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    final oldTimings = TrainingTransitionTimings.instance;
    final oldFrames = FrameRecorder.instance;
    TrainingTransitionTimings.instance = TrainingTransitionTimings(
      enabled: false,
    );
    FrameRecorder.instance = FrameRecorder(enabled: false);
    platform = PoseHubUiVideoPlatform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
    addTearDown(() async {
      TrainingTransitionTimings.instance.dispose();
      FrameRecorder.instance.stop();
      TrainingTransitionTimings.instance = oldTimings;
      FrameRecorder.instance = oldFrames;
      UgkPackedAlphaVideo.debugPlatform = null;
      UgkPackedAlphaVideo.debugFilterBuilder = null;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SfColors.palette = SfPalette.dark;
      await platform.close();
    });
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name}: original SDK preview fields survive; media waits for route, preview exit saves nothing',
      (tester) async {
        final f = await _mount(
          tester,
          _Fixture(
            catalog,
            palette: palette,
            mode: TrainerStartMode.preview,
            originalGate: Completer<void>(),
          ),
        );
        final copy = tester.widget<PoseHubSinglePracticePage>(
          find.byType(PoseHubSinglePracticePage),
        );
        expect(copy.key, f.original.key);
        expect(copy.action, same(f.action));
        expect(copy.mediaBaseUri, f.base);
        expect(copy.theme, same(f.theme));
        expect(f.theme.mediaStage, isNot(palette.mediaStage));
        expect(copy.mediaPreparer, isA<GatedPoseHubMediaPreparer>());
        expect(
          (copy.mediaPreparer! as GatedPoseHubMediaPreparer).delegate,
          same(f.preparer),
        );
        expect(f.preparer.requests, isEmpty);
        expect(copy.voice, same(f.voiceConfig));
        expect(copy.startMode, TrainerStartMode.preview);
        expect(copy.onStartTraining, same(f.original.onStartTraining));
        expect(copy.startGate, isNotNull);
        expect(copy.mediaBuilder, isNotNull);
        expect(
          tester
              .widget<TrainerPlayer>(find.byType(TrainerPlayer))
              .chromeAnimation,
          isNull,
        );
        expect(
          find.byKey(const ValueKey('single-practice-poster')),
          findsOneWidget,
        );
        _expectPosterColor(
          tester,
          find.byKey(const ValueKey('single-practice-poster')),
          f.theme.mediaStage,
        );
        expect(
          tester
              .widget<ColoredBox>(
                find.byKey(const ValueKey('training-route-background')),
              )
              .color,
          f.theme.mediaStage,
        );
        expect(find.byKey(const ValueKey('preview-labels')), findsOneWidget);
        expect(f.mediaCreated, 0);
        expect(f.voice.begins, 0);
        await tester.pump(const Duration(milliseconds: 150));
        expect(f.mediaCreated, 0);
        expect(f.voice.begins, 0);
        expect(f.preparer.requests, isEmpty);
        _expectPosterColor(
          tester,
          find.byKey(const ValueKey('single-practice-poster')),
          f.theme.mediaStage,
        );
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(microseconds: 1));
        await _frames(tester);
        expect(f.route.control.entered, isTrue);
        // The original SDK preview ignores its pending training-only startGate.
        expect(f.mediaCreated, 1);
        expect(f.preparer.requests, isNotEmpty);
        expect(f.requests.last.drill.id, f.action.id);
        expect(f.requests.last.paused, isFalse);
        // SDK deliberately sets its edge-to-edge media stage radius to zero.
        // The original page's custom theme itself is still preserved above.
        expect(f.requests.last.theme.radius, 0);
        expect(f.voice.begins, 0);
        expect(f.starts, 0);

        await tester.tap(find.byKey(const ValueKey('close')));
        await _frames(tester);
        expect(f.route.animation!.status, AnimationStatus.reverse);
        expect(f.mediaPaused, isTrue);
        expect(f.mediaDisposed, 0);
        await _exitTime(tester);
        expect(f.mediaDisposed, 1);
        expect(f.finished, 0);
        expect(f.completed, 0);
        expect(f.exitNotifications, 0);
        expect(f.beforePops, 0);
        expect(f.receipts, isEmpty);
      },
    );
  }

  testWidgets(
    'training combines original startGate with route gate instead of discarding it',
    (tester) async {
      final gate = Completer<void>();
      final f = await _mount(tester, _Fixture(catalog, originalGate: gate));
      await _enter(tester);
      expect(f.route.control.entered, isTrue);
      expect(f.voice.begins, 0);
      expect(f.mediaCreated, 0);
      expect(f.preparer.requests, isEmpty);
      expect(
        find.byKey(const ValueKey('single-practice-poster')),
        findsOneWidget,
      );
      gate.complete();
      await _frames(tester, 5);
      expect(f.voice.begins, 1);
      expect(f.mediaCreated, 1);
      expect(f.preparer.requests, isNotEmpty);
      expect(f.starts, 0);
    },
  );

  testWidgets(
    'slow original completion callback runs once while slide retires media at 280ms',
    (tester) async {
      final f = await _mount(tester, _Fixture(catalog));
      f.saving = Completer<void>();
      await _enter(tester);
      expect(f.mediaCreated, 1);
      await _confirmExit(tester);
      expect(f.exitNotifications, 1);
      expect(f.route.animation!.status, AnimationStatus.reverse);
      expect(f.finished, 1);
      expect(f.completed, 1);
      expect(f.mediaPaused, isTrue);
      await tester.pump(const Duration(milliseconds: 279));
      expect(f.mediaDisposed, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await _frames(tester);
      expect(f.mediaDisposed, 1);
      expect(f.route.isActive, isTrue);
      expect(f.receipts, isEmpty);
      f.saving!.complete();
      await _frames(tester, 6);
      expect(f.finished, 1);
      expect(f.completed, 1);
      expect(f.successfulSaves, 1);
      expect(f.beforePops, 1);
      expect(f.receipts, hasLength(1));
      expect(f.receipts.single.endedEarly, isTrue);
    },
  );

  testWidgets(
    'original completion failure restores SDK retry; successful retry does not duplicate the finished callback',
    (tester) async {
      final f = await _mount(tester, _Fixture(catalog, failures: 1));
      await _enter(tester);
      await _confirmExit(tester);
      await _frames(tester, 6);
      await tester.pump(const Duration(milliseconds: 301));
      await _frames(tester);
      expect(f.route.control.saveFailed, isTrue);
      expect(
        find.byKey(const ValueKey('save-retry')).hitTestable(),
        findsOneWidget,
      );
      expect(f.finished, 1);
      expect(f.completed, 1);
      expect(f.successfulSaves, 0);
      expect(f.receipts, isEmpty);
      await tester.tap(find.byKey(const ValueKey('save-retry')));
      await _frames(tester);
      // Retry saves without leaving. The existing SDK finish action closes.
      expect(f.route.control.exiting, isFalse);
      expect(f.exitNotifications, 1);
      expect(f.finished, 1);
      expect(f.completed, 2);
      expect(f.successfulSaves, 1);
      expect(f.beforePops, 0);
      expect(f.receipts, isEmpty);
      expect(f.route.animation!.value, 1);
      expect(
        find.byKey(const ValueKey('finish')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('finish')));
      await _frames(tester);
      expect(f.route.control.exiting, isTrue);
      await _exitTime(tester);
      expect(f.completed, 2);
      expect(f.successfulSaves, 1);
      expect(f.beforePops, 1);
      expect(f.receipts, hasLength(1));
    },
  );

  testWidgets(
    'synchronous original onFinished failure restores retry and delegates the same SDK save attempt',
    (tester) async {
      final f = await _mount(tester, _Fixture(catalog, finishFailures: 1));
      await _enter(tester);
      await _confirmExit(tester);
      await _frames(tester, 6);
      await tester.pump(const Duration(milliseconds: 301));
      await _frames(tester);
      expect(f.route.control.saveFailed, isTrue);
      expect(
        find.byKey(const ValueKey('save-retry')).hitTestable(),
        findsOneWidget,
      );
      expect(f.finished, 1);
      expect(f.completed, 0);
      expect(f.receipts, isEmpty);
      await tester.tap(find.byKey(const ValueKey('save-retry')));
      await _frames(tester);
      expect(f.route.control.exiting, isFalse);
      expect(f.exitNotifications, 1);
      expect(f.finished, 2);
      expect(f.completed, 0);
      expect(f.receipts, isEmpty);
      expect(f.route.animation!.value, 1);
      expect(
        find.byKey(const ValueKey('finish')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('finish')));
      await _frames(tester);
      expect(f.route.control.exiting, isTrue);
      await _exitTime(tester);
      expect(f.finished, 2);
      expect(f.completed, 1);
      expect(f.successfulSaves, 1);
      expect(f.receipts, hasLength(1));
    },
  );

  testWidgets(
    'original beforeExitPop hook is awaited as well as host visual completion',
    (tester) async {
      final f = await _mount(tester, _Fixture(catalog));
      f.beforePop = Completer<void>();
      await _enter(tester);
      await _confirmExit(tester);
      await _exitTime(tester);
      expect(f.beforePops, 1);
      expect(f.route.isActive, isTrue);
      expect(f.receipts, isEmpty);
      f.beforePop!.complete();
      await _frames(tester, 6);
      expect(f.receipts, hasLength(1));
      expect(f.successfulSaves, 1);
    },
  );

  testWidgets(
    'default SDK practice media uses host ExerciseVideo after the slide and preserves its poster geometry',
    (tester) async {
      final f = await _mount(
        tester,
        _Fixture(catalog, mode: TrainerStartMode.preview, customMedia: false),
      );
      final poster = tester.widget<TrainingPoster>(
        find.byKey(const ValueKey('single-practice-poster')),
      );
      expect(poster.asset, endsWith('/standing/${f.action.id}.webp'));
      expect(poster.radius, 0);
      _expectPosterColor(
        tester,
        find.byKey(const ValueKey('single-practice-poster')),
        f.theme.mediaStage,
      );
      expect(find.byType(ExerciseVideo), findsNothing);
      await _enter(tester);
      final video = tester.widget<ExerciseVideo>(find.byType(ExerciseVideo));
      expect(video.exercise, same(f.exercise));
      expect(video.radius, poster.radius);
      expect(video.mirrored, poster.mirrored);
      expect(video.stageColor, f.theme.mediaStage);
      final cached = find.byType(CachedExerciseMedia);
      expect(
        tester.widget<CachedExerciseMedia>(cached).stageColor,
        f.theme.mediaStage,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find
                  .descendant(of: cached, matching: find.byType(ColoredBox))
                  .first,
            )
            .color,
        f.theme.mediaStage,
      );
      expect(video.training, isTrue);
      expect(video.paused, isFalse);
      f.route.control.beginExit();
      await _frames(tester);
      expect(
        tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
        isTrue,
      );
      await _exitTime(tester);
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(
        find.byKey(const ValueKey('single-practice-poster')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'standalone SDK preview with no App exercise retains its decoded still through loading and failure',
    (tester) async {
      final f = await _mount(
        tester,
        _Fixture(
          catalog,
          mode: TrainerStartMode.preview,
          customMedia: false,
          emptyLibrary: true,
        ),
      );
      expect(f.services.library.all, isEmpty);
      final poster = tester.widget<TrainingPoster>(
        find.byKey(const ValueKey('single-practice-poster')),
      );
      expect(poster.asset, endsWith('/standing/${f.action.id}.webp'));
      _expectPosterColor(
        tester,
        find.byKey(const ValueKey('single-practice-poster')),
        f.theme.mediaStage,
      );
      expect(find.byType(PoseHubPackMedia), findsNothing);
      await _enter(tester);
      final media = tester.widget<PoseHubPackMedia>(
        find.byType(PoseHubPackMedia),
      );
      expect(media.action, same(f.action));
      expect(media.baseUri, f.base);
      final fade = find.byKey(
        const ValueKey('single-practice-sdk-poster-fade'),
      );
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      expect(
        find.byKey(const ValueKey('single-practice-sdk-poster')),
        findsOneWidget,
      );
      _expectPosterColor(
        tester,
        find.byKey(const ValueKey('single-practice-sdk-poster')),
        f.theme.mediaStage,
      );
      media.onStatus!(PoseHubPackPlaybackStatus.error);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      // Exercise the SDK's public composed-frame status contract. Actual
      // native first-frame delivery is covered by the media platform tests.
      media.onStatus!(PoseHubPackPlaybackStatus.playing);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
      expect(
        tester.widget<AnimatedOpacity>(fade).duration,
        const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(milliseconds: 200));
      media.onStatus!(PoseHubPackPlaybackStatus.loading);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
      expect(tester.widget<AnimatedOpacity>(fade).duration, Duration.zero);
      _expectPosterColor(
        tester,
        find.byKey(const ValueKey('single-practice-sdk-poster')),
        f.theme.mediaStage,
      );
      expect(f.voice.begins, 0);
      expect(f.completed, 0);
    },
  );

  testWidgets(
    'preview start action remains the original SDK action and delegates its callback once after entry',
    (tester) async {
      final f = await _mount(
        tester,
        _Fixture(catalog, mode: TrainerStartMode.preview),
      );
      expect(f.starts, 0);
      expect(f.voice.begins, 0);
      await _enter(tester);
      await tester.tap(find.byKey(const ValueKey('start-training')));
      await _frames(tester);
      await tester.pump(const Duration(milliseconds: 301));
      await _frames(tester);
      expect(f.starts, 1);
      expect(f.voice.begins, 1);
    },
  );
}
