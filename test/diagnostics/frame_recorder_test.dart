import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FrameRecorder recorder;
  var nextTimestamp = 1000000;

  int frame() {
    final timestamp = nextTimestamp;
    nextTimestamp += 100000;
    binding.handleBeginFrame(Duration(microseconds: timestamp));
    binding.handleDrawFrame();
    return timestamp;
  }

  int frameNumber() =>
      binding.currentSystemFrameTimeStamp.inMicroseconds ~/ 10000;

  FrameTiming timing(
    int startUs,
    int buildUs,
    int rasterUs, {
    int? frameNumber,
  }) => FrameTiming(
    vsyncStart: startUs - 100,
    buildStart: startUs,
    buildFinish: startUs + buildUs,
    rasterStart: startUs + buildUs,
    rasterFinish: startUs + buildUs + rasterUs,
    rasterFinishWallTime: startUs + buildUs + rasterUs,
    frameNumber: frameNumber ?? startUs ~/ 10000,
  );

  void report(List<FrameTiming> timings) {
    binding.platformDispatcher.onReportTimings!(timings);
  }

  Map total() => recorder.snapshot()['total'] as Map;

  void conditions({
    bool glass = true,
    bool stars = true,
    String quality = 'high',
    String phase = 'stable',
    bool frost = true,
    String renderer = 'Impeller',
    String backend = 'vulkan',
    double budget = 1000 / 60,
  }) => recorder.setRenderConditions(
    glassEnabled: glass,
    starfield: stars,
    glassQuality: quality,
    glassPhase: phase,
    glassFrost: frost,
    renderer: renderer,
    rendererBackend: backend,
    adaptiveTargetFrameMs: budget,
    theme: 'dark',
    viewportWidth: 412,
    viewportHeight: 915,
    devicePixelRatio: 2.625,
    textScale: 1,
  );

  bool beginCase({
    String variant = 'glass_on_stars_on',
    FrameScenario scenario = FrameScenario.longChatScroll,
    String fixtureId = 'chat_fixture_v1',
    int messageCount = 64,
  }) => recorder.beginCase(
    variant: variant,
    scenario: scenario,
    fixtureId: fixtureId,
    messageCount: messageCount,
  );

  Map currentCase() =>
      (recorder.snapshot()['cases'] as Map)[recorder.currentCaseId] as Map;

  int count(Map caseStats, String window) =>
      (caseStats[window] as Map)['frameCount'] as int;

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    recorder = FrameRecorder(enabled: true, currentFrameNumber: frameNumber);
  });

  tearDown(() {
    recorder.stop();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    frame();
  });

  test(
    'production default is off and disabled recorder registers nothing',
    () {
      expect(FrameRecorder.buildEnabled, isFalse);
      recorder = FrameRecorder(enabled: false);
      final initialCallbacks = binding.transientCallbackCount;
      recorder.setPage('action_library');
      recorder.beginScenario(FrameScenario.actionListScroll);
      recorder.setRefreshRateHz(120);
      recorder.setMetadata({'deviceModel': 'Phone'});
      conditions();
      expect(beginCase(), isFalse);
      recorder.endCase();
      recorder.start();
      recorder.reset();
      expect(recorder.isRunning, isFalse);
      expect(recorder.isCollecting, isFalse);
      expect(binding.transientCallbackCount, initialCallbacks);
      report([timing(nextTimestamp - 100000, 20000, 40000)]);
      final snapshot = recorder.snapshot();
      expect(snapshot['receivedFrameCount'], 0);
      expect(snapshot['metadata'], isEmpty);
      expect(snapshot['currentRefreshRateHz'], 60);
      expect(snapshot['cases'], isEmpty);
      expect(snapshot['currentCaseId'], isNull);
      expect(
        (snapshot['currentRenderConditions'] as Map)['glassEnabled'],
        isNull,
      );
    },
    skip: FrameRecorder.buildEnabled,
  );

  test(
    'averages, histogram quantiles and worst frames have stated precision',
    () {
      recorder.setPage('action_library');
      recorder.start();
      final start = frame();
      report([
        for (var i = 1; i <= 100; i++) timing(start + i, i * 1000, i * 2000),
      ]);
      final stats = total();
      final ui = stats['uiBuild'] as Map;
      final raster = stats['raster'] as Map;
      expect(stats['frameCount'], 100);
      expect(ui['averageMs'], 50.5);
      expect(raster['averageMs'], 101);
      expect(ui['worstMs'], 100);
      expect(raster['worstMs'], 200);
      expect(ui['p90Ms'], inInclusiveRange(90, 90 * 1.0625 + .001));
      expect(ui['p99Ms'], inInclusiveRange(99, 99 * 1.0625 + .001));
      expect(raster['p90Ms'], inInclusiveRange(180, 180 * 1.0625 + .001));
      expect(raster['p99Ms'], inInclusiveRange(198, 198 * 1.0625 + .001));
      expect(ui['overBudgetFrames'], 84);
      expect(raster['overBudgetFrames'], 92);
      expect(stats['eitherThreadOverBudgetFrames'], 92);
      final expectedMissed = List.generate(
        100,
        (i) => math.max(0, ((i + 1) * 2000 / (1000000 / 60)).ceil() - 1),
      ).reduce((a, b) => a + b);
      expect(stats['estimatedMissedVsyncs'], expectedMissed);
    },
  );

  test(
    '120 Hz strict budget, union and missed-vsync estimate do not double count',
    () {
      recorder.setRefreshRateHz(120);
      recorder.start();
      final start = frame();
      report([
        timing(start, 8333, 8333),
        timing(start + 1, 8334, 1000),
        timing(start + 2, 1000, 9000),
        timing(start + 3, 17000, 25000),
      ]);
      final stats = total();
      expect((stats['uiBuild'] as Map)['overBudgetFrames'], 2);
      expect((stats['raster'] as Map)['overBudgetFrames'], 2);
      expect(stats['eitherThreadOverBudgetFrames'], 3);
      expect(stats['estimatedMissedVsyncs'], 4);
      expect(stats['refreshRatesHz'], [120]);
    },
  );

  test('start and lifecycle resume are idempotent; stop removes callbacks', () {
    recorder.start();
    recorder.start();
    recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
    final start = frame();
    report([timing(start, 20000, 5000)]);
    expect(total()['frameCount'], 1);
    recorder.stop();
    recorder.stop();
    report([timing(start + 1, 20000, 5000)]);
    expect(total()['frameCount'], 1);
    expect(recorder.isCollecting, isFalse);
    recorder.start();
    final restarted = frame();
    report([timing(restarted, 20000, 5000)]);
    expect(total()['frameCount'], 2);
  });

  test(
    'batched frames retain page, scenario and refresh rate at frame start',
    () {
      recorder.setPage('action_library');
      recorder.beginScenario(FrameScenario.actionListScroll);
      recorder.start();
      final first = frame();
      recorder.setPage('chat');
      recorder.beginScenario(FrameScenario.longChatScroll);
      recorder.setRefreshRateHz(120);
      final second = frame();
      recorder.setPage('settings'); // Must not backdate to the previous frame.
      report([
        timing(first, 12000, 3000),
        timing(second - 1, 12000, 3000),
        timing(second, 12000, 3000),
      ]);
      final snapshot = recorder.snapshot();
      final pages = snapshot['pages'] as Map;
      expect((pages['action_library'] as Map)['frameCount'], 2);
      expect((pages['chat'] as Map)['frameCount'], 1);
      expect(pages.containsKey('settings'), isFalse);
      final scenarios = snapshot['scenarios'] as Map;
      expect((scenarios['actionListScroll'] as Map)['frameCount'], 2);
      expect((scenarios['longChatScroll'] as Map)['frameCount'], 1);
      expect(total()['eitherThreadOverBudgetFrames'], 1);
      recorder.endScenario(FrameScenario.actionListScroll);
      expect(recorder.snapshot()['currentScenario'], 'longChatScroll');
      recorder.endScenario(FrameScenario.longChatScroll);
      final third = frame();
      report([timing(third, 1000, 1000)]);
      expect(total()['frameCount'], 4);
      expect((recorder.snapshot()['scenarios'] as Map).length, 2);
    },
  );

  test('reset rejects old batches and preserves safe measurement context', () {
    recorder.setPage('training');
    recorder.beginScenario(FrameScenario.trainingActionSwitch);
    recorder.setRefreshRateHz(120);
    recorder.setMetadata({'appVersion': '0.1.0', 'appBuild': 15});
    recorder.start();
    final old = frame();
    report([timing(old, 1000, 1000)]);
    recorder.reset();
    final current = frame();
    report([timing(old, 90000, 90000), timing(current, 9000, 1000)]);
    final snapshot = recorder.snapshot();
    expect(snapshot['recordedFrameCount'], 1);
    expect(snapshot['ignoredBeforeSessionFrameCount'], 1);
    expect(snapshot['currentPage'], 'training');
    expect(snapshot['currentScenario'], 'trainingActionSwitch');
    expect(snapshot['currentRefreshRateHz'], 120);
    expect(snapshot['metadata'], {'appVersion': '0.1.0', 'appBuild': 15});
    expect((total()['uiBuild'] as Map)['worstMs'], 9);
  });

  test('settings frames do not contaminate a manually selected scenario', () {
    recorder.setPage('action_library');
    recorder.beginScenario(FrameScenario.actionListScroll);
    expect(recorder.currentPage, 'action_library');
    expect(recorder.currentScenario, FrameScenario.actionListScroll);
    recorder.start();
    final library = frame();
    recorder.setPage('settings');
    final settings = frame();
    recorder.setPage('performance_settings');
    final performanceSettings = frame();
    recorder.setPage('action_library');
    final returnedLibrary = frame();
    report([
      timing(library, 1000, 2000),
      timing(settings, 90000, 90000),
      timing(performanceSettings, 80000, 80000),
      timing(returnedLibrary, 3000, 4000),
    ]);
    final snapshot = recorder.snapshot();
    final scenarios = snapshot['scenarios'] as Map;
    final scenario = scenarios['actionListScroll'] as Map;
    expect(scenario['frameCount'], 2);
    expect((scenario['uiBuild'] as Map)['averageMs'], 2);
    expect((scenario['uiBuild'] as Map)['worstMs'], 3);
    expect(total()['frameCount'], 4);
    expect((total()['uiBuild'] as Map)['worstMs'], 90);
    final pages = snapshot['pages'] as Map;
    expect((pages['settings'] as Map)['frameCount'], 1);
    expect((pages['performance_settings'] as Map)['frameCount'], 1);
    expect(recorder.currentScenario, FrameScenario.actionListScroll);
    recorder.endScenario();
    expect(recorder.currentScenario, isNull);
  });

  test('frame keys win over vsync and presentation timestamp offsets', () {
    recorder.setPage('action_library');
    recorder.start();
    final old = frame();
    final oldNumber = frameNumber();
    recorder.setPage('chat');
    final current = frame();
    final currentNumber = frameNumber();
    report([
      // The old frame may build late, after the next presentation timestamp.
      timing(current + 500000, 1000, 2000, frameNumber: oldNumber),
      // The new frame may build before its future presentation target.
      timing(old - 500000, 3000, 4000, frameNumber: currentNumber),
    ]);
    final pages = recorder.snapshot()['pages'] as Map;
    expect(
      ((pages['action_library'] as Map)['uiBuild'] as Map)['averageMs'],
      1,
    );
    expect(((pages['chat'] as Map)['uiBuild'] as Map)['averageMs'], 3);
    expect(recorder.snapshot()['recordedFrameCount'], 2);
  });

  test('missing engine frame keys are explicit rather than guessed', () {
    recorder = FrameRecorder(enabled: true, currentFrameNumber: () => -1);
    recorder.start();
    final start = frame();
    report([
      timing(start, 1000, 1000, frameNumber: -1),
      timing(start + 1, 1000, 1000),
    ]);
    final snapshot = recorder.snapshot();
    expect(snapshot['recordedFrameCount'], 0);
    expect(snapshot['unattributedFrameCount'], 2);
    expect(snapshot['unavailableFrameKeyBoundaryCount'], 1);
  });

  test(
    'inactive frames are excluded even when returned in a resumed batch',
    () {
      recorder.start();
      final active = frame();
      recorder.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(recorder.isCollecting, isFalse);
      recorder.didChangeAppLifecycleState(AppLifecycleState.hidden);
      recorder.didChangeAppLifecycleState(AppLifecycleState.paused);
      recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final resumed = frame();
      report([
        timing(active, 1000, 1000),
        timing(active + 10000, 90000, 90000),
        timing(resumed, 2000, 2000),
      ]);
      expect(total()['frameCount'], 2);
      expect(recorder.snapshot()['ignoredInactiveFrameCount'], 1);
    },
  );

  test(
    'history eviction and page cardinality stay bounded without guessing',
    () {
      recorder = FrameRecorder(
        enabled: true,
        maxPages: 3,
        maxLabelTransitions: 4,
        currentFrameNumber: frameNumber,
      );
      recorder.start();
      final old = frame();
      for (var i = 0; i < 30; i++) {
        recorder.setPage('page_$i');
        final start = frame();
        report([timing(start, 1000, 2000)]);
      }
      report([timing(old, 90000, 90000)]);
      final snapshot = recorder.snapshot();
      expect((snapshot['pages'] as Map).length, 3);
      expect((snapshot['otherPages'] as Map)['frameCount'], 27);
      expect(snapshot['recordedFrameCount'], 30);
      expect(snapshot['unattributedFrameCount'], 1);
      final retention = snapshot['retention'] as Map;
      expect(retention['retainedLabelTransitions'], 4);
      expect(retention['evictedLabelTransitions'], 27);
      expect(retention['perFrameSamplesStored'], 0);
      expect((total()['uiBuild'] as Map)['worstMs'], 1);
    },
  );

  test('histogram memory stays fixed across large batches and long frames', () {
    recorder.start();
    final start = frame();
    report([
      for (var i = 0; i < 20000; i++) timing(start + i, i % 16, 1000),
      timing(start + 20000, 15000000, 1000000),
    ]);
    final snapshot = recorder.snapshot();
    expect(snapshot['recordedFrameCount'], 20001);
    expect((total()['uiBuild'] as Map)['worstMs'], 15000);
    expect((total()['uiBuild'] as Map)['p99Ms'], 15 / 1000);
    expect((snapshot['retention'] as Map)['histogramBucketsPerThread'], 1024);
    expect((snapshot['retention'] as Map)['perFrameSamplesStored'], 0);
    expect(jsonEncode(snapshot).length, lessThan(10000));
  });

  test(
    'empty, zero durations and invalid timing do not fabricate statistics',
    () {
      expect((total()['uiBuild'] as Map)['averageMs'], isNull);
      expect((total()['raster'] as Map)['p99Ms'], isNull);
      recorder.start();
      // The callback has not established its first scheduler boundary yet.
      report([timing(nextTimestamp, 1000, 1000)]);
      final start = frame();
      report([timing(start, 0, 0), timing(start + 1, -1, 0)]);
      final snapshot = recorder.snapshot();
      expect(snapshot['unattributedFrameCount'], 1);
      expect(snapshot['invalidTimingFrameCount'], 1);
      expect(snapshot['recordedFrameCount'], 1);
      expect((total()['uiBuild'] as Map)['p99Ms'], 0);
      expect((total()['raster'] as Map)['worstMs'], 0);
      expect(total()['estimatedMissedVsyncs'], 0);
    },
  );

  test('report only accepts fixed labels and allowlisted bounded metadata', () {
    recorder.setPage('private chat message');
    recorder.setRefreshRateHz(double.nan);
    recorder.setRefreshRateHz(0);
    recorder.setMetadata({
      'deviceModel': 'Pixel 9 Pro',
      'systemVersion': 'Android 15',
      'isEmulator': false,
      'secret': 'PRIVATE_KEY',
      'chat': 'PRIVATE_KEY',
      'platform': 'https://PRIVATE_KEY',
      'deviceManufacturer': 'x' * 129,
      'appBuild': double.infinity,
    });
    final snapshot = recorder.snapshot();
    expect(snapshot['currentPage'], 'unknown');
    expect(snapshot['invalidPageLabelCount'], 1);
    expect(snapshot['currentRefreshRateHz'], 60);
    expect(snapshot['metadata'], {
      'deviceModel': 'Pixel 9 Pro',
      'systemVersion': 'Android 15',
      'isEmulator': false,
    });
    expect(jsonEncode(snapshot), isNot(contains('PRIVATE_KEY')));
  });

  test('measurement metadata retains fixed app and device context fields', () {
    final metadata = <String, Object?>{
      'sdkRef': 'f684e02f38e652633c23fa8946a53d02b6aa3ea2',
      'appSource': 'performance_baseline',
      'appBuildNumber': 15,
      'measurementKind': 'baseline_profile',
      'appearance': 'dark',
      'starfield': true,
      'glassQuality': 'medium',
      'deviceApiLevel': 35,
      'metadataStatus': 'available',
      'contentActionCount': 120,
      'chatMessageCount': 250,
      'theme': 'dark',
      'appBaseCommit': 'abcdef012345',
    };
    recorder.setMetadata(metadata);
    final snapshot = recorder.snapshot();
    expect(snapshot['metadata'], metadata);
    final definitions = snapshot['definitions'] as Map;
    expect(definitions['coverage'], contains('WebView'));
    expect(definitions['coverage'], contains('no screen-present FPS'));
  });

  test(
    'condition changes are visible without counting initial device metadata',
    () {
      recorder.setMetadata({'theme': 'dark', 'starfield': true});
      recorder.setMetadata({
        'theme': 'light',
      }); // Before capture: no change count.
      recorder.start();
      frame();
      recorder.setRefreshRateHz(120); // First explicit rate: no change count.
      recorder.setMetadata({
        'glassQuality': 'medium',
        'deviceModel': 'Pixel 9 Pro',
        'metadataStatus': 'available',
      });
      expect(recorder.snapshot()['conditionChangesDuringCapture'], 0);
      recorder.setMetadata({'theme': 'dark', 'starfield': false});
      recorder.setMetadata({'glassQuality': 'low', 'metadataStatus': 'ready'});
      recorder.setRefreshRateHz(60);
      recorder.setRefreshRateHz(60); // Repeated assignment is not a change.
      recorder.setMetadata({'theme': 'dark'});
      expect(recorder.snapshot()['conditionChangesDuringCapture'], 4);
      recorder.reset();
      expect(recorder.snapshot()['conditionChangesDuringCapture'], 0);
      recorder.setMetadata({'theme': 'light'});
      expect(recorder.snapshot()['conditionChangesDuringCapture'], 1);
      recorder.stop();
      recorder.setMetadata({'theme': 'dark'});
      recorder.setRefreshRateHz(120);
      expect(recorder.snapshot()['conditionChangesDuringCapture'], 1);
    },
  );

  test('actual conditions retain frame attribution across delayed batches', () {
    recorder.setPage('chat');
    conditions();
    expect(beginCase(), isTrue);
    recorder.start();
    final first = frame();
    conditions(
      stars: false,
      quality: 'low',
      phase: 'motion',
      frost: false,
      renderer: 'Skia',
      backend: 'opengl',
      budget: 1000 / 120,
    );
    recorder.setRefreshRateHz(120);
    final second = frame();
    // This assignment has not reached its scheduled boundary: it must never
    // overwrite either frame's actual conditions in a delayed engine batch.
    conditions(quality: 'medium');
    report([timing(first, 1000, 7000), timing(second, 2000, 12000)]);
    final measurement = currentCase();
    final groups = measurement['conditions'] as List;
    expect(groups.length, 2);
    final original = groups[0] as Map;
    final changed = groups[1] as Map;
    expect(original['condition'], {
      'glassEnabled': true,
      'starfield': true,
      'glassQuality': 'high',
      'glassPhase': 'stable',
      'glassFrost': true,
      'renderer': 'Impeller',
      'rendererBackend': 'vulkan',
      'refreshRateHz': 60.0,
      'frameBudgetMs': 1000 / 60,
      'adaptiveTargetFrameMs': 1000 / 60,
      'theme': 'dark',
      'viewportWidth': 412.0,
      'viewportHeight': 915.0,
      'devicePixelRatio': 2.625,
      'textScale': 1.0,
    });
    final changedCondition = changed['condition'] as Map;
    expect(changedCondition['starfield'], false);
    expect(changedCondition['glassQuality'], 'low');
    expect(changedCondition['glassPhase'], 'motion');
    expect(changedCondition['glassFrost'], false);
    expect(changedCondition['renderer'], 'Skia');
    expect(changedCondition['rendererBackend'], 'opengl');
    expect(changedCondition['refreshRateHz'], 120);
    expect(count(original, 'allFrames'), 1);
    expect(count(changed, 'allFrames'), 1);
    expect(
      measurement['comparisonIssues'],
      containsAll([
        'mixed_render_conditions',
        'variant_switches_do_not_match_actual_conditions',
      ]),
    );
    final perScenario = recorder.snapshot()['scenarioConditions'] as Map;
    expect((perScenario['longChatScroll'] as Map)['groups'], hasLength(2));
  });

  test('case warmup uses real vsync and exact two second boundary', () {
    recorder.setPage('chat');
    recorder.setRefreshRateHz(120);
    conditions(stars: false, budget: 1000 / 120);
    beginCase(variant: 'glass_on_stars_off');
    recorder.start();
    frame();
    final key = frameNumber();
    // Scheduler time differs by many seconds; only the actual engine vsync
    // clock determines both warmup and observed case duration.
    report([
      timing(100000000, 1000, 40000, frameNumber: key),
      timing(101999999, 1000, 20000, frameNumber: key),
      timing(102000000, 1000, 7000, frameNumber: key),
      timing(132000000, 1000, 8000, frameNumber: key),
    ]);
    final id = recorder.currentCaseId;
    recorder.endCase();
    final measurement = (recorder.snapshot()['cases'] as Map)[id] as Map;
    expect(recorder.snapshot()['schema'], 2);
    expect(count(measurement, 'allFrames'), 4);
    expect(count(measurement, 'warmupFirst2Seconds'), 2);
    expect(count(measurement, 'steadyState'), 2);
    expect(count(measurement, 'firstPageEntryFirst2Seconds'), 2);
    expect(measurement['observedDurationSeconds'], 32);
    expect(measurement['comparisonReady'], true);
    expect(measurement['comparisonIssues'], isEmpty);
    final steady = measurement['steadyState'] as Map;
    expect((steady['raster'] as Map)['averageMs'], 7.5);
    expect((steady['raster'] as Map)['worstMs'], 8);
    expect((steady['raster'] as Map)['overBudgetRatio'], 0);
    final warmup = measurement['warmupFirst2Seconds'] as Map;
    expect((warmup['raster'] as Map)['overBudgetRatio'], 1);
    final group = (measurement['conditions'] as List).single as Map;
    expect(count(group, 'warmupFirst2Seconds'), 2);
    expect(count(group, 'steadyState'), 2);
  });

  test('page first entry is independent of case warmup and page reentry', () {
    recorder.setPage('chat');
    conditions();
    recorder.start();
    frame();
    report([timing(10000000, 1000, 30000, frameNumber: frameNumber())]);
    beginCase();
    frame();
    report([timing(15000000, 1000, 5000, frameNumber: frameNumber())]);
    final measurement = currentCase();
    expect(count(measurement, 'warmupFirst2Seconds'), 1);
    expect(count(measurement, 'firstPageEntryFirst2Seconds'), 0);
    final entries = recorder.snapshot()['pageEntries'] as Map;
    final chatEntry = entries['chat'] as Map;
    expect((chatEntry['first2Seconds'] as Map)['frameCount'], 1);
    expect(
      ((chatEntry['first2Seconds'] as Map)['raster'] as Map)['worstMs'],
      30,
    );
    recorder.endCase();
    recorder.setPage('plan');
    frame();
    report([timing(20000000, 1000, 5000, frameNumber: frameNumber())]);
    recorder.setPage('chat');
    beginCase(variant: 'glass_on_stars_off');
    frame();
    report([timing(25000000, 1000, 5000, frameNumber: frameNumber())]);
    expect(count(currentCase(), 'firstPageEntryFirst2Seconds'), 0);
  });

  test('ending, changing and resampling cells never mixes delayed frames', () {
    recorder.setPage('chat');
    conditions();
    beginCase();
    final firstId = recorder.currentCaseId;
    recorder.start();
    final first = frame();
    recorder.endCase();
    conditions(stars: false);
    beginCase(variant: 'glass_on_stars_off');
    final secondId = recorder.currentCaseId;
    final second = frame();
    report([timing(first, 1000, 5000), timing(second, 1000, 9000)]);
    var measurements = recorder.snapshot()['cases'] as Map;
    expect(count(measurements[firstId] as Map, 'allFrames'), 1);
    expect((measurements[firstId] as Map)['completed'], true);
    expect(count(measurements[secondId] as Map, 'allFrames'), 1);
    expect((measurements[secondId] as Map)['completed'], false);
    recorder.endCase();
    conditions();
    beginCase();
    final resample = frame();
    // A still-pending frame from the old object cannot enter the new same-key
    // cell. Other matrix cells retain their earlier results.
    report([timing(first + 1, 1000, 90000), timing(resample, 1000, 3000)]);
    measurements = recorder.snapshot()['cases'] as Map;
    expect(measurements, hasLength(2));
    expect(count(measurements[firstId] as Map, 'allFrames'), 1);
    expect(
      (((measurements[firstId] as Map)['allFrames'] as Map)['raster']
          as Map)['worstMs'],
      3,
    );
    expect(count(measurements[secondId] as Map, 'allFrames'), 1);
  });

  test('settings and no-case frames never leak into comparison cells', () {
    recorder.setPage('chat');
    conditions();
    beginCase();
    final id = recorder.currentCaseId;
    recorder.start();
    final first = frame();
    recorder.setPage('performance_settings');
    final settings = frame();
    recorder.endCase();
    recorder.setPage('chat');
    final after = frame();
    report([
      timing(first, 1000, 3000),
      timing(settings, 90000, 90000),
      timing(after, 90000, 90000),
    ]);
    final measurement = (recorder.snapshot()['cases'] as Map)[id] as Map;
    expect(count(measurement, 'allFrames'), 1);
    expect(total()['frameCount'], 3);
  });

  test(
    'invalid requests retain active cell and short or unknown data is gated',
    () {
      recorder.setPage('chat');
      recorder.start();
      beginCase(messageCount: 17);
      final originalId = recorder.currentCaseId;
      expect(beginCase(variant: 'arbitrary_name'), isFalse);
      expect(beginCase(scenario: FrameScenario.planExpand), isFalse);
      expect(beginCase(fixtureId: 'private chat text'), isFalse);
      expect(beginCase(messageCount: -1), isFalse);
      expect(beginCase(messageCount: 10001), isFalse);
      expect(recorder.currentCaseId, originalId);
      final first = frame();
      report([timing(first, 1000, 40000)]);
      final measurement = currentCase();
      expect(measurement['comparisonReady'], false);
      expect(
        measurement['comparisonIssues'],
        containsAll([
          'incomplete',
          'observed_span_less_than_30_seconds',
          'no_steady_state_frames',
          'renderer_unknown',
          'actual_render_condition_unknown',
          'long_chat_has_fewer_than_60_messages',
        ]),
      );
      expect(recorder.snapshot()['invalidCaseRequestCount'], 5);
      recorder.endCase(completed: false);
      expect(recorder.currentCaseId, isNull);
    },
  );

  test('actual conditions reject placeholders and invalid budgets', () {
    conditions(
      quality: 'adaptive_initial',
      phase: 'private message',
      renderer: 'requested_impeller',
      backend: 'https://private',
      budget: double.nan,
    );
    final actual = recorder.snapshot()['currentRenderConditions'] as Map;
    expect(actual['glassQuality'], 'unknown');
    expect(actual['glassPhase'], 'unknown');
    expect(actual['renderer'], 'unknown');
    expect(actual['rendererBackend'], 'unknown');
    expect(actual['adaptiveTargetFrameMs'], isNull);
    expect(jsonEncode(actual), isNot(contains('private')));
    recorder.setPage('chat');
    conditions(budget: 16);
    beginCase();
    recorder.setRefreshRateHz(120);
    recorder.start();
    final first = frame();
    report([timing(first, 1000, 40000)]);
    expect(
      currentCase()['comparisonIssues'],
      contains('adaptive_budget_does_not_match_refresh_rate'),
    );
  });

  test('all eight fixed cells and resets keep bounded storage', () {
    const variants = [
      'glass_on_stars_on',
      'glass_on_stars_off',
      'glass_off_stars_on',
      'glass_off_stars_off',
    ];
    const scenarios = [
      FrameScenario.longChatScroll,
      FrameScenario.planCardScroll,
    ];
    recorder = FrameRecorder(
      enabled: true,
      maxConditionGroupsPerCase: 2,
      currentFrameNumber: frameNumber,
    );
    recorder.setPage('chat');
    recorder.start();
    for (final variant in variants) {
      for (final scenario in scenarios) {
        conditions(
          glass: variant.startsWith('glass_on_'),
          stars: variant.endsWith('_stars_on'),
        );
        beginCase(variant: variant, scenario: scenario);
        for (final quality in ['high', 'medium', 'low', 'low']) {
          conditions(
            glass: variant.startsWith('glass_on_'),
            stars: variant.endsWith('_stars_on'),
            quality: quality,
          );
          final timestamp = frame();
          report([timing(timestamp, 1000, 10000)]);
        }
        recorder.endCase();
      }
    }
    final snapshot = recorder.snapshot();
    final measurements = snapshot['cases'] as Map;
    expect(measurements, hasLength(8));
    for (final measurement in measurements.values.cast<Map>()) {
      expect(measurement['conditions'], hasLength(2));
      expect(count(measurement, 'allFrames'), 4);
      expect(measurement['overflowConditionFrameCount'], 2);
      expect(
        measurement['comparisonIssues'],
        contains('condition_groups_overflow'),
      );
    }
    final manual = snapshot['scenarioConditions'] as Map;
    for (final value in manual.values.cast<Map>()) {
      expect(value['groups'], hasLength(2));
      expect(value['overflowFrameCount'], greaterThan(0));
    }
    final retention = snapshot['retention'] as Map;
    expect(retention['maxCases'], 8);
    expect(retention['maxConditionGroupsPerCase'], 2);
    expect(retention['perFrameSamplesStored'], 0);
    recorder.reset();
    expect(recorder.snapshot()['cases'], isEmpty);
    expect(recorder.snapshot()['scenarioConditions'], isEmpty);
    expect(recorder.currentCaseId, isNull);
    expect(recorder.snapshot()['invalidCaseRequestCount'], 0);
  });

  test('non-monotonic vsync times explicitly invalidate window comparison', () {
    recorder.setPage('chat');
    conditions();
    beginCase();
    recorder.start();
    frame();
    final key = frameNumber();
    report([
      timing(100000000, 1000, 5000, frameNumber: key),
      timing(132000000, 1000, 5000, frameNumber: key),
      timing(99999999, 1000, 5000, frameNumber: key),
    ]);
    expect(
      currentCase()['comparisonIssues'],
      contains('out_of_order_vsync_timestamps'),
    );
    expect(count(currentCase(), 'allFrames'), 3);
    expect(count(currentCase(), 'warmupFirst2Seconds'), 1);
    expect(count(currentCase(), 'steadyState'), 1);
  });

  test(
    'pausing an active cell cannot turn a sparse sample into a full run',
    () {
      recorder.setPage('chat');
      conditions();
      beginCase();
      recorder.start();
      frame();
      report([timing(100000000, 1000, 5000, frameNumber: frameNumber())]);
      recorder.didChangeAppLifecycleState(AppLifecycleState.inactive);
      recorder.didChangeAppLifecycleState(AppLifecycleState.resumed);
      frame();
      report([timing(132000000, 1000, 5000, frameNumber: frameNumber())]);
      expect(
        currentCase()['comparisonIssues'],
        contains('lifecycle_interrupted'),
      );
      expect(currentCase()['comparisonReady'], false);
    },
  );

  test(
    'interrupted tail invalidates an ended cell while preserving late frames',
    () {
      recorder.setPage('chat');
      conditions();
      beginCase();
      final firstId = recorder.currentCaseId!;
      recorder.start();
      frame();
      final firstKey = frameNumber();
      report([
        timing(100000000, 1000, 5000, frameNumber: firstKey),
        timing(132000000, 1000, 6000, frameNumber: firstKey),
      ]);
      recorder.endCase();
      var first = (recorder.snapshot()['cases'] as Map)[firstId] as Map;
      expect(first['completed'], true);
      expect(first['comparisonReady'], true);
      recorder.invalidateCase(firstId);
      // Invalidation must not reactivate the ended case or relabel its tail.
      expect(recorder.currentCaseId, isNull);
      expect(recorder.currentScenario, isNull);
      conditions(stars: false);
      beginCase(variant: 'glass_on_stars_off');
      final secondId = recorder.currentCaseId!;
      frame();
      final secondKey = frameNumber();
      report([
        timing(132000001, 1000, 7000, frameNumber: firstKey),
        timing(140000000, 1000, 9000, frameNumber: secondKey),
      ]);
      final measurements = recorder.snapshot()['cases'] as Map;
      first = measurements[firstId] as Map;
      expect(count(first, 'allFrames'), 3);
      expect(first['completed'], false);
      expect(first['comparisonReady'], false);
      expect(first['invalidationReason'], 'interrupted_tail_delivery');
      expect(
        first['comparisonIssues'],
        containsAll(['case_invalidated', 'interrupted_tail_delivery']),
      );
      final second = measurements[secondId] as Map;
      expect(count(second, 'allFrames'), 1);
      expect(second['invalidationReason'], isNull);
      recorder.invalidateCase('unknown_cell', reason: 'private message');
      expect(recorder.snapshot()['cases'] as Map, hasLength(2));
      recorder.invalidateCase(firstId, reason: 'private message');
      first = (recorder.snapshot()['cases'] as Map)[firstId] as Map;
      expect(first['invalidationReason'], 'invalidated');
      expect(
        jsonEncode(recorder.snapshot()),
        isNot(contains('private message')),
      );
    },
  );
}
