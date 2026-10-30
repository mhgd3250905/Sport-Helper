import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/gated_posehub_media_preparer.dart';
import 'package:smartfit/app/training_transition_activity.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/exercise.dart' show DoseMode;
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/training_poster_flight.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_transition_freeze.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'support.dart';
import 'app_flow_test.dart' show services;

class _Pixels extends CachingAssetBundle {
  _Pixels(this.bytes);
  final ByteData bytes;
  var imageLoads = 0;
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    if (RegExp(r'\.(webp|png|jpe?g)$').hasMatch(key)) {
      imageLoads++;
      return bytes;
    }
    return rootBundle.load(key);
  }
}

class _Prepared implements PoseHubMediaPreparer {
  var calls = 0;
  @override
  Stream<PoseHubMediaPreparationEvent> prepareAction(
    coach.PoseHubPackAction action,
  ) {
    calls++;
    return Stream.value(
      PoseHubMediaReady(mediaBaseUri: Uri.parse('file:///verified/')),
    );
  }
}

class _LatePixels extends _Pixels {
  _LatePixels(super.bytes);
  final ready = Completer<ByteData>();
  @override
  Future<ByteData> load(String key) =>
      RegExp(r'\.(webp|png|jpe?g)$').hasMatch(key)
      ? ready.future
      : super.load(key);
}

const _plan = TrainingPlan(
  id: 'precache-lifecycle',
  source: 'test',
  title: '测试训练',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-forearm-plank',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 60,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ByteData bytes;
  setUpAll(() async {
    final recording = ui.PictureRecorder();
    final canvas = Canvas(recording);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 20, 40),
      Paint()..color = Colors.red,
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 20, 20, 20),
      Paint()..color = Colors.blue,
    );
    final picture = recording.endRecording();
    final image = await picture.toImage(20, 40);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    picture.dispose();
  });

  testWidgets(
    'flight retains decoded pixels and fixed layout while its actual paint rect and circular clip move',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bundle = _Pixels(bytes);
      final exercise = loadLibrary()['h-forearm-plank'];
      final animation = AnimationController(
        vsync: tester,
        duration: const Duration(milliseconds: 560),
      );
      late BuildContext imageContext;
      final flight = TrainingPosterFlight(
        key: const ValueKey('flight'),
        animation: animation,
        exercise: exercise,
        canvasSize: const Size(390, 390),
        from: const Rect.fromLTWH(20, 70, 200, 150),
        to: const Rect.fromLTWH(0, 0, 390, 390),
        durationMs: 560,
        morphMs: 420,
        beginRadius: 20,
        endRadius: 0,
        cacheWidth: 390,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: bundle,
            child: Builder(
              builder: (context) {
                imageContext = context;
                return Center(
                  child: SizedBox(
                    width: 390,
                    height: 390,
                    child: Stack(
                      children: [
                        Positioned.fill(child: flight),
                        Positioned(
                          width: 50,
                          height: 50,
                          child: DecodedTrainingPoster(
                            exercise: exercise,
                            cacheWidth: 390,
                            builder: (_, pixels, _) => pixels,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => TrainingPosterImages.precache(imageContext, exercise),
      );
      await tester.pump();
      final flightFinder = find.byKey(const ValueKey('flight'));
      final rawFinder = find.descendant(
        of: flightFinder,
        matching: find.byType(RawImage),
      );
      final initial = tester.widget<RawImage>(rawFinder);
      final images = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .toList();
      expect(images, hasLength(2));
      expect(images[0].image!.isCloneOf(images[1].image!), isTrue);
      expect(bundle.imageLoads, 1);
      final imageBox = tester.renderObject<RenderImage>(rawFinder);
      final fixedSize = imageBox.size;
      final clipFinder = find.descendant(
        of: flightFinder,
        matching: find.byType(ClipRRect),
      );
      final rootBox = tester.renderObject<RenderBox>(flightFinder);
      final origin = rootBox.localToGlobal(Offset.zero);
      for (final value in [0.0, .125, .375, .5, .75, 1.0]) {
        animation.value = value;
        await tester.pump();
        expect(identical(tester.widget<RawImage>(rawFinder), initial), isTrue);
        expect(imageBox.size, fixedSize);
        final clip = tester.renderObject<RenderClipRRect>(clipFinder);
        final actual = MatrixUtils.transformRect(
          clip.getTransformTo(null),
          Offset.zero & clip.size,
        ).shift(-origin);
        final t = Curves.easeInOutCubicEmphasized.transform(
          (value * 560 / 420).clamp(0.0, 1.0),
        );
        final expected = Rect.lerp(
          const Rect.fromLTWH(20, 70, 200, 150),
          const Rect.fromLTWH(0, 0, 390, 390),
          t,
        )!;
        expect(actual.left, closeTo(expected.left, 1e-5));
        expect(actual.top, closeTo(expected.top, 1e-5));
        expect(actual.width, closeTo(expected.width, 1e-5));
        expect(actual.height, closeTo(expected.height, 1e-5));
        final radius = tester
            .widget<ClipRRect>(clipFinder)
            .borderRadius
            .resolve(TextDirection.ltr)
            .topLeft;
        expect(radius.x * actual.width / 390, closeTo(20 * (1 - t), 1e-5));
        expect(radius.y * actual.height / 390, closeTo(20 * (1 - t), 1e-5));
        final pixelMatrix = imageBox.getTransformTo(null).storage;
        expect(
          pixelMatrix[0].abs(),
          closeTo(pixelMatrix[5].abs(), 1e-5),
          reason: 'person remains uniformly scaled, with contain fitting',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      animation.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source subtree buffers notifications and rebuilds once after transition',
    (tester) async {
      final data = ValueNotifier<int>(0);
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingTransitionFreeze(
            listenable: data,
            builder: (_) {
              builds++;
              return Text('value=${data.value}');
            },
          ),
        ),
      );
      final initialBuilds = builds;
      final release = TrainingTransitionActivity.instance.hold();
      await tester.pump();
      for (var i = 1; i <= 100; i++) {
        data.value = i;
      }
      await tester.pump();
      expect(builds, initialBuilds);
      expect(find.text('value=0'), findsOneWidget);
      release();
      await tester.pump();
      expect(builds, initialBuilds + 1);
      expect(find.text('value=100'), findsOneWidget);
      release();
      expect(TrainingTransitionActivity.instance.active, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      data.dispose();
    },
  );

  testWidgets(
    'background during image prewarm leaves article retryable without starting a session',
    (tester) async {
      final s = services();
      await s.store.acceptSafety(blocked: false);
      final bundle = _LatePixels(bytes);
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            home: DefaultAssetBundle(
              bundle: bundle,
              child: const PlanPage(plan: _plan),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      bundle.ready.complete(bytes);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(PlayerPage, skipOffstage: false), findsNothing);
      expect(s.store.sessionResults, isEmpty);
      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(TrainingTransitionActivity.instance.active, isFalse);
      expect(s.store.sessionResults, isEmpty);
      await s.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'overlapping short windows release work only when both are finished',
    () async {
      final activity = TrainingTransitionActivity();
      final first = activity.hold(), second = activity.hold();
      var idle = false;
      unawaited(activity.waitUntilIdle().then((_) => idle = true));
      first();
      first();
      await Future<void>.delayed(Duration.zero);
      expect(idle, isFalse);
      second();
      await Future<void>.delayed(Duration.zero);
      expect(idle, isTrue);
      activity.dispose();
    },
  );

  test(
    'public SDK prefetch cannot cross gate or active paint window; canceled gate never prepares',
    () async {
      final catalog = await PoseHubActionLibrary.load();
      final action = catalog.allActions.first;
      final delegate = _Prepared();
      final gate = Completer<void>();
      final release = TrainingTransitionActivity.instance.hold();
      final events = <PoseHubMediaPreparationEvent>[];
      final done = Completer<void>();
      final subscription = GatedPoseHubMediaPreparer(
        delegate,
        gate.future,
      ).prepareAction(action).listen(events.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      expect(delegate.calls, 0);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(delegate.calls, 0);
      release();
      await done.future;
      expect(delegate.calls, 1);
      expect(events.single, isA<PoseHubMediaReady>());
      await subscription.cancel();
      final canceledGate = Completer<void>();
      final canceled = GatedPoseHubMediaPreparer(
        delegate,
        canceledGate.future,
      ).prepareAction(action).listen((_) {});
      await canceled.cancel();
      canceledGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(delegate.calls, 1);
    },
  );
}
