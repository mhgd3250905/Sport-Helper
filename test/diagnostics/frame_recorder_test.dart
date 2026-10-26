import 'dart:convert';
import 'dart:ui' show FrameTiming;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';

// Synthetic engine inputs test the recorder; these are never device results.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FrameRecorder recorder;
  var key = 0, timestamp = 1000000, monotonic = 0;
  FrameRecorder make({
    bool enabled = true,
    int maxRawFrames = 60000,
    int maxFramesPerCase = 12000,
  }) {
    final value = FrameRecorder(
      enabled: enabled,
      currentFrameNumber: () => key,
      monotonicMicros: () => monotonic,
      maxRawFrames: maxRawFrames,
      maxFramesPerCase: maxFramesPerCase,
    );
    value.setRenderConditions(
      starfield: true,
      renderer: 'Impeller',
      rendererBackend: 'vulkan',
      rendererVerified: true,
      theme: 'dark',
      viewportWidth: 390,
      viewportHeight: 844,
      devicePixelRatio: 3,
      textScale: 1,
    );
    value.setRefreshRateHz(120);
    return value;
  }

  void boundary() {
    key++;
    timestamp += 100000;
    binding.handleBeginFrame(Duration(microseconds: timestamp));
    binding.handleDrawFrame();
  }

  FrameTiming timing(int number, int start, int raster, {int build = 1000}) =>
      FrameTiming(
        frameNumber: number,
        vsyncStart: start,
        buildStart: start + 100,
        buildFinish: start + 100 + build,
        rasterStart: start + 100 + build,
        rasterFinish: start + 100 + build + raster,
        rasterFinishWallTime: start + 100 + build + raster,
      );
  void report(List<FrameTiming> timings) =>
      binding.platformDispatcher.onReportTimings!(timings);
  Map total() => recorder.snapshot()['total'] as Map;
  Map cell(String id) => recorder.caseSnapshot(id)!;
  void startEntry() {
    recorder.setPage('action_library');
    recorder.start();
    expect(
      recorder.beginCase(theme: 'dark', scenario: FrameScenario.pageEntry),
      isTrue,
    );
    boundary();
  }

  setUp(() {
    key = 0;
    timestamp = 1000000;
    monotonic = 0;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    recorder = make();
  });
  tearDown(() {
    recorder.stop();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('disabled diagnostics do not record or arm a workload', () {
    recorder.stop();
    recorder = make(enabled: false);
    recorder.start();
    expect(
      recorder.armCase(theme: 'dark', scenario: FrameScenario.pageEntry),
      isFalse,
    );
    expect(recorder.snapshot()['recordedFrameCount'], 0);
    expect(recorder.isCollecting, isFalse);
  });
  test(
    'exact integer nearest-rank and original phase timestamps are retained',
    () {
      recorder.setPage('chat');
      recorder.start();
      boundary();
      report([
        for (var i = 1; i <= 100; i++)
          timing(key + i, timestamp + i * 1000, i * 100),
      ]);
      final raster = total()['raster'] as Map;
      expect(raster['p50Us'], 5000);
      expect(raster['p90Us'], 9000);
      expect(raster['p99Us'], 9900);
      expect(raster['maxUs'], 10000);
      expect(raster['over8_33msCount'], 17);
      final raw = (recorder.snapshot()['rawFrames'] as List).first as Map;
      expect((raw['phasesUs'] as Map)['vsyncStart'], timestamp + 1000);
      expect(raw['rasterUs'], 100);
      expect(jsonEncode(recorder.snapshot()), isNot(contains('histogram')));
    },
  );
  for (final value in [8329, 8330, 8331]) {
    test('strict 120Hz P99 boundary at $value us', () {
      startEntry();
      report([timing(key, timestamp, value)]);
      monotonic = 3000000;
      recorder.endCase();
      boundary();
      final data = cell('dark__pageEntry');
      expect(data['comparisonReady'], isTrue);
      final full = recorder.snapshot();
      final compactCell = (full['cases'] as Map)['dark__pageEntry'] as Map;
      expect(compactCell.containsKey('rawFrames'), isFalse);
      final rawIndex = (compactCell['rawFrameIndices'] as List).single as int;
      expect(((full['rawFrames'] as List)[rawIndex] as Map)['rasterUs'], value);
      expect(data['rasterP99Pass'], value < 8330);
      final raster = (data['allFrames'] as Map)['raster'] as Map;
      expect(raster['over8_33msCount'], value > 8330 ? 1 : 0);
      expect(raster['overExact120HzPeriodCount'], 0);
    });
  }
  test(
    '60Hz keeps the literal 8.33ms P99 gate and identifies its actual period separately',
    () {
      recorder.setRefreshRateHz(60);
      startEntry();
      report([timing(key, timestamp, 12000)]);
      monotonic = 3000000;
      recorder.endCase();
      boundary();
      final data = cell('dark__pageEntry');
      expect(data['rasterP99Pass'], isFalse);
      expect(data['is120HzDeviceSample'], isFalse);
      expect(data['acceptanceBudgetUs'], 8330);
      final raster = (data['allFrames'] as Map)['raster'] as Map;
      expect(raster['overBudgetFrames'], 0);
      expect(raster['over8_33msCount'], 1);
    },
  );
  test(
    'delayed batches keep the page label at their exact engine frame number',
    () {
      recorder.setPage('chat');
      recorder.start();
      boundary();
      final a = timing(key, timestamp, 1000);
      recorder.setPage('action_library');
      boundary();
      final b = timing(key, timestamp, 2000);
      report([a, b]);
      final pages = recorder.snapshot()['pages'] as Map;
      expect((pages['chat'] as Map)['frameCount'], 1);
      expect((pages['action_library'] as Map)['frameCount'], 1);
    },
  );
  test('reset rejects delayed timings from the previous round', () {
    recorder.start();
    boundary();
    final before = timing(key, timestamp, 1000);
    recorder.reset();
    boundary();
    report([before, timing(key, timestamp, 2000)]);
    expect(total()['frameCount'], 1);
    expect(recorder.snapshot()['beforeSessionFrameCount'], 1);
  });
  test('raw retention overflow never becomes an approximate percentile', () {
    recorder.stop();
    recorder = make(maxRawFrames: 2);
    recorder.start();
    boundary();
    report([
      timing(key, timestamp, 1000),
      timing(key + 1, timestamp + 1000, 2000),
      timing(key + 2, timestamp + 2000, 3000),
    ]);
    expect(total()['rawSampleOverflowFrameCount'], 1);
    expect((total()['raster'] as Map)['p99Us'], isNull);
    expect(recorder.snapshot()['rawFramesTruncated'], isTrue);
  });
  test(
    'mixed render conditions invalidate an otherwise complete real entry',
    () {
      startEntry();
      report([timing(key, timestamp, 1000)]);
      recorder.setRenderConditions(
        starfield: false,
        renderer: 'impeller',
        rendererBackend: 'vulkan',
        rendererVerified: true,
        theme: 'dark',
        viewportWidth: 390,
        viewportHeight: 844,
        devicePixelRatio: 3,
        textScale: 1,
      );
      boundary();
      report([timing(key, timestamp, 1000)]);
      monotonic = 3000000;
      recorder.endCase();
      boundary();
      expect(
        cell('dark__pageEntry')['comparisonIssues'],
        contains('mixed_or_missing_render_conditions'),
      );
      expect(cell('dark__pageEntry')['rasterP99Pass'], isFalse);
    },
  );
  test(
    'case raw overflow and duplicate engine frame keys are explicit failures',
    () {
      recorder.stop();
      recorder = make(maxFramesPerCase: 2);
      startEntry();
      report([
        timing(key, timestamp, 1000),
        timing(key, timestamp + 1000, 1000),
        timing(key + 1, timestamp + 2000, 1000),
      ]);
      monotonic = 3000000;
      recorder.endCase();
      boundary();
      final issues = cell('dark__pageEntry')['comparisonIssues'] as List;
      expect(issues, contains('raw_frame_limit_reached'));
      expect(issues, contains('duplicate_frame_numbers'));
      expect(cell('dark__pageEntry')['rasterP99Pass'], isFalse);
    },
  );
  test('an interrupted lifecycle cannot pass a case', () {
    startEntry();
    report([timing(key, timestamp, 1000)]);
    recorder.didChangeAppLifecycleState(AppLifecycleState.paused);
    recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
    boundary();
    monotonic = 3000000;
    recorder.endCase();
    boundary();
    expect(
      cell('dark__pageEntry')['comparisonIssues'],
      contains('lifecycle_interrupted'),
    );
  });
  test(
    'ten IDs are theme times real workload, without runtime material variants',
    () {
      for (final theme in ['light', 'dark']) {
        for (final scenario in FrameRecorder.acceptanceScenarios) {
          expect(recorder.beginCase(theme: theme, scenario: scenario), isTrue);
          recorder.endCase();
        }
      }
      final data = recorder.snapshot();
      expect((data['cases'] as Map).length, 10);
      expect(data['material'], 'solid');
      expect(data['schema'], 3);
      expect((data['cases'] as Map).keys, contains('light__bottomBarSwitch'));
      expect(jsonEncode(data), isNot(contains('prewarm')));
    },
  );
  test(
    'armed entry begins on the real target route, and can be cancelled safely',
    () {
      recorder.setPage('chat');
      expect(
        recorder.armCase(theme: 'dark', scenario: FrameScenario.pageEntry),
        isTrue,
      );
      expect(recorder.currentCaseId, isNull);
      recorder.setPage('action_library');
      expect(recorder.currentCaseId, 'dark__pageEntry');
      recorder.endCase(completed: false);
      recorder.armCase(theme: 'dark', scenario: FrameScenario.trainingPlayback);
      recorder.cancelArmedCase();
      recorder.setPage('training');
      expect(recorder.currentCaseId, isNull);
    },
  );
  test(
    'bottom-bar workload requires actual chat and library route traffic',
    () {
      recorder.setPage('chat');
      recorder.start();
      recorder.beginCase(
        theme: 'dark',
        scenario: FrameScenario.bottomBarSwitch,
      );
      boundary();
      report([timing(key, timestamp, 1000)]);
      monotonic = 20000000;
      recorder.endCase();
      boundary();
      expect(
        cell('dark__bottomBarSwitch')['comparisonIssues'],
        contains('real_bottom_bar_flow_not_observed'),
      );
    },
  );
  test(
    'safe metadata allowlist excludes content and endpoint-shaped values',
    () {
      recorder.setMetadata({
        'appSource': 'a' * 40,
        'token': 'secret',
        'chat': 'private',
        'deviceModel': 'ws://127.0.0.1/private',
        'material': 'solid',
      });
      final metadata = recorder.snapshot()['metadata'] as Map;
      expect(metadata['material'], 'solid');
      expect(metadata['appSource'], 'a' * 40);
      expect(metadata.containsKey('token'), isFalse);
      expect(metadata.containsKey('chat'), isFalse);
      expect(metadata.containsKey('deviceModel'), isFalse);
    },
  );
}
