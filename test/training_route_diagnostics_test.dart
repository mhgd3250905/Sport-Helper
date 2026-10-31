import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/training_transition_activity.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/training_transition_timings.dart';
import 'package:smartfit/diagnostics/training_transition_timings_storage.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

class _TimingStorage implements TrainingTransitionTimingsStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String json) async {}
}

Future<TrainingTransitionTimings> _enableDiagnostics(
  WidgetTester tester,
) async {
  final previousTimings = TrainingTransitionTimings.instance;
  final previousFrames = FrameRecorder.instance;
  final timings = TrainingTransitionTimings.instance =
      TrainingTransitionTimings(
        enabled: true,
        storage: _TimingStorage(),
        attachScheduler: false,
        clock: tester.binding.clock.now,
        monotonicMicros: () =>
            tester.binding.clock.now().microsecondsSinceEpoch,
        currentFrameNumber: () => -1,
        currentFrameInProgress: () => false,
        settleDelay: Duration.zero,
        summarize: (data) async => summarizeTransitionTimings(data),
        encode: (data) async => jsonEncode(data),
      );
  final frames = FrameRecorder.instance = FrameRecorder(enabled: true);
  await timings.initialize();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    timings.dispose();
    frames.stop();
    TrainingTransitionTimings.instance = previousTimings;
    FrameRecorder.instance = previousFrames;
  });
  return timings;
}

class _RouteFixture {
  _RouteFixture({
    this.brightness = Brightness.light,
    this.reducedMotion = false,
  });

  final Brightness brightness;
  final bool reducedMotion;
  final navigator = GlobalKey<NavigatorState>();
  late TrainingRoute<void> route;
  TrainerSlideRouteControl? pageControl;
  bool gateOpened = false;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                route = TrainingRoute<void>(
                  context: context,
                  sourceEntry: 'diagnostic-entry',
                  builder: (context) {
                    pageControl = TrainerSlideRouteScope.maybeOf(context);
                    return const Scaffold(body: Text('SDK route page'));
                  },
                );
                unawaited(navigator.currentState!.push(route));
                unawaited(
                  route.control.startGate.then((_) => gateOpened = true),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump();
  }

  Future<void> finishExit(WidgetTester tester, Future<void> exiting) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(microseconds: 1));
    await tester.pump();
    await exiting;
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name}: SDK control drives only host activity and diagnostic windows',
      (tester) async {
        final timings = await _enableDiagnostics(tester);
        final fixture = _RouteFixture(brightness: brightness);
        await fixture.open(tester);
        expect(fixture.route, isA<TrainerSlideRoute<void>>());
        expect(fixture.pageControl, same(fixture.route.control));
        expect(TrainingTransitionActivity.instance.active, isTrue);
        expect(
          FrameRecorder.instance.currentScenario,
          FrameScenario.trainingRouteEntry,
        );

        await fixture.enter(tester);
        expect(fixture.gateOpened, isTrue);
        expect(TrainingTransitionActivity.instance.active, isFalse);
        expect(FrameRecorder.instance.currentScenario, isNull);

        fixture.route.control.beginExit();
        expect(TrainingTransitionActivity.instance.active, isTrue);
        expect(
          FrameRecorder.instance.currentScenario,
          FrameScenario.trainingRouteExit,
        );
        await fixture.finishExit(tester, fixture.route.control.beforeExitPop());
        expect(TrainingTransitionActivity.instance.active, isFalse);
        expect(FrameRecorder.instance.currentScenario, isNull);
        fixture.navigator.currentState!.pop();
        await tester.pump();
        await tester.pump();

        expect(timings.results, hasLength(2));
        for (final result in timings.results) {
          expect(result['sourceEntry'], 'diagnostic-entry');
          expect(result['theme'], brightness.name);
          expect(result['outcome'], 'completed');
          // No engine frames are supplied by this integration test.
          expect(result['hasMeasuredFrames'], isFalse);
        }
      },
    );
  }

  testWidgets('failed-save retry gets a separate host exit timing window', (
    tester,
  ) async {
    final timings = await _enableDiagnostics(tester);
    final fixture = _RouteFixture();
    await fixture.open(tester);
    await fixture.enter(tester);
    fixture.route.control.beginExit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    fixture.route.control.exitSaveFailed();
    expect(TrainingTransitionActivity.instance.active, isFalse);
    expect(FrameRecorder.instance.currentScenario, isNull);
    await fixture.enter(tester);
    expect(fixture.route.control.mediaRetired, isTrue);

    final retryExit = fixture.route.control.beforeExitPop();
    expect(TrainingTransitionActivity.instance.active, isTrue);
    expect(
      FrameRecorder.instance.currentScenario,
      FrameScenario.trainingRouteExit,
    );
    await fixture.finishExit(tester, retryExit);
    expect(TrainingTransitionActivity.instance.active, isFalse);
    expect(FrameRecorder.instance.currentScenario, isNull);
    final exits = timings.results.where((result) => result['kind'] == 'exit');
    expect(exits, hasLength(2));
    expect(
      exits.map((result) => result['outcome']),
      unorderedEquals(['save_failed', 'completed']),
    );
  });

  testWidgets('route disposal closes host entry diagnostics as aborted', (
    tester,
  ) async {
    final timings = await _enableDiagnostics(tester);
    final fixture = _RouteFixture();
    await fixture.open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(microseconds: 1));
    expect(fixture.gateOpened, isFalse);
    expect(TrainingTransitionActivity.instance.active, isFalse);
    expect(FrameRecorder.instance.currentScenario, isNull);
    expect(timings.results.single['kind'], 'entry');
    expect(timings.results.single['outcome'], 'aborted');
  });

  testWidgets('host diagnostics retain the SDK reduced-motion setting', (
    tester,
  ) async {
    final timings = await _enableDiagnostics(tester);
    final fixture = _RouteFixture(reducedMotion: true);
    await fixture.open(tester);
    await fixture.enter(tester);
    expect(fixture.gateOpened, isTrue);
    expect(TrainingTransitionActivity.instance.active, isFalse);
    expect(timings.results.single['reducedMotion'], isTrue);
    expect(timings.results.single['outcome'], 'completed');
  });
}
