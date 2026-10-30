import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/training_transition_timings.dart';
import 'package:smartfit/diagnostics/training_transition_timings_storage.dart';
import 'package:smartfit/diagnostics/training_transition_timings_storage_io.dart';

class _Storage implements TrainingTransitionTimingsStorage {
  String? contents;
  int reads = 0, writes = 0;
  bool fail = false;
  @override
  Future<String?> read() async {
    reads++;
    return contents;
  }

  @override
  Future<void> write(String json) async {
    writes++;
    if (fail) throw const FileSystemException('Synthetic test write failure');
    contents = json;
  }
}

// Synthetic unit-test timings only; never exported as device evidence.
FrameTiming _frame(int number, int vsync, int buildUs, int rasterUs) =>
    FrameTiming(
      frameNumber: number,
      vsyncStart: vsync,
      buildStart: vsync,
      buildFinish: vsync + buildUs,
      rasterStart: vsync + buildUs,
      rasterFinish: vsync + buildUs + rasterUs,
      rasterFinishWallTime: vsync + buildUs + rasterUs,
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late int now, number;
  late bool inProgress;
  late _Storage storage;
  final recorders = <TrainingTransitionTimings>[];

  TrainingTransitionTimings create({
    bool enabled = true,
    bool attach = false,
    bool initialize = true,
  }) {
    final value = TrainingTransitionTimings(
      enabled: enabled,
      storage: storage,
      attachScheduler: attach,
      clock: () => DateTime.utc(2026, 10, 30).add(Duration(microseconds: now)),
      monotonicMicros: () => now,
      currentFrameNumber: () => number,
      currentFrameInProgress: () => inProgress,
      settleDelay: Duration.zero,
      summarize: (data) async => summarizeTransitionTimings(data),
      encode: (data) async => jsonEncode(data),
    );
    recorders.add(value);
    if (initialize) unawaited(value.initialize());
    return value;
  }

  setUp(() {
    now = 1500;
    number = 7;
    inProgress = true;
    storage = _Storage();
  });
  tearDown(() {
    for (final item in recorders) {
      item.dispose();
    }
    recorders.clear();
  });

  test(
    'no singleton-style collection or tail timer before explicit startup initialization',
    () async {
      final recorder = create(initialize: false);
      expect(recorder.begin(TrainingTransitionKind.entry), isNull);
      expect(storage.reads, 0);
      expect(recorder.pendingResultCount, 0);
      await recorder.initialize();
      final token = recorder.begin(TrainingTransitionKind.entry);
      expect(token, isNotNull);
      now += 1000;
      recorder.finish(token);
      await recorder.exportJson();
      expect(recorder.results.length, 1);
    },
  );

  test(
    'copy flushes a late correction already received inside its debounce window',
    () async {
      final recorder = create();
      final token = recorder.begin(TrainingTransitionKind.entry);
      now = 4000;
      number = 8;
      recorder.finish(token);
      recorder.acceptTimings([_frame(7, 1000, 1000, 2000)]);
      await recorder.exportJson();
      expect(recorder.results.single['frameCount'], 1);
      recorder.acceptTimings([_frame(8, 3000, 19000, 21000)]);
      expect(recorder.pendingResultCount, 1);
      final json = jsonDecode(await recorder.exportJson()) as Map;
      expect((json['results'] as List).single['frameCount'], 2);
      expect(recorder.results.single['rasterMaxMs'], 21);
      expect(recorder.pendingResultCount, 0);
    },
  );

  test(
    'late engine batch includes opening build frame and closing raster frame',
    () async {
      final recorder = create();
      await recorder.initialize();
      final token = recorder.begin(TrainingTransitionKind.entry);
      now = 3500;
      number = 8;
      recorder.finish(token);
      recorder.acceptTimings([
        _frame(6, 0, 100, 100),
        _frame(7, 1000, 500, 600),
        _frame(8, 2000, 600, 700),
        _frame(9, 3000, 20000, 20000),
      ]);
      await recorder.exportJson();
      final result = recorder.results.single;
      expect(result['frameCount'], 2);
      expect(result['buildMaxMs'], .6);
      expect(result['rasterMaxMs'], .7);
      expect(result['firstFrameNumber'], 7);
      expect(result['lastFrameNumber'], 8);
      expect(storage.writes, 1);
    },
  );

  test(
    'idle click starts with next frame; duplicate reports do not inflate counts',
    () async {
      final recorder = create();
      inProgress = false;
      final token = recorder.begin(TrainingTransitionKind.entry);
      now = 4000;
      number = 9;
      recorder.finish(token);
      final a = _frame(8, 2000, 8000, 10000), b = _frame(9, 3000, 9000, 11000);
      recorder.acceptTimings([_frame(7, 1000, 20000, 30000), a, b, a, b]);
      await recorder.exportJson();
      expect(recorder.results.single['frameCount'], 2);
      expect(recorder.results.single['buildMaxMs'], 9);
    },
  );

  test(
    'timestamp fallback correctly attributes late entry batch after exit starts',
    () async {
      number = -1;
      now = 1000;
      final recorder = create();
      final entry = recorder.begin(TrainingTransitionKind.entry);
      now = 3000;
      recorder.finish(entry);
      now = 4000;
      final exit = recorder.begin(TrainingTransitionKind.exit);
      now = 6000;
      recorder.finish(exit);
      recorder.acceptTimings([
        _frame(-1, 1500, 1000, 2000),
        _frame(-1, 4500, 3000, 4000),
      ]);
      await recorder.exportJson();
      final results = {for (final row in recorder.results) row['kind']: row};
      expect(results['entry']!['frameCount'], 1);
      expect(results['entry']!['rasterMaxMs'], 2);
      expect(results['exit']!['buildMaxMs'], 3);
    },
  );

  test(
    'nearest rank P90 and strict >16ms count keep exact 16ms within budget',
    () {
      final sample = summarizeTransitionTimings({
        'frames': [
          for (var i = 1; i <= 10; i++)
            {'buildUs': i * 1000, 'rasterUs': i == 10 ? 16001 : 16000},
        ],
        'outcome': 'completed',
        'truncated': false,
        'reducedMotion': false,
        'buildMode': 'profile',
      });
      expect(sample['buildP90Ms'], 9);
      expect(sample['rasterP90Ms'], 16);
      expect(sample['buildMaxMs'], 10);
      expect(sample['rasterMaxMs'], 16.001);
      expect(sample['buildOver16ms'], 0);
      expect(sample['rasterOver16ms'], 1);
      expect(sample['over16msFrames'], 1);
      expect(sample['sampleComplete'], isTrue);
      expect(sample.containsKey('eligibleForWarmTarget'), isFalse);
      expect(sample.containsKey('meetsNumericTarget'), isFalse);
    },
  );

  test(
    'empty interrupted sample stays unmeasured without an acceptance verdict',
    () async {
      final recorder = create();
      final token = recorder.begin(TrainingTransitionKind.entry);
      now += 500;
      recorder.finish(token, outcome: 'aborted');
      await recorder.exportJson();
      final result = recorder.results.single;
      expect(result['frameCount'], 0);
      expect(result['buildP90Ms'], isNull);
      expect(result['rasterMaxMs'], isNull);
      expect(result['sampleComplete'], isFalse);
      expect(result.containsKey('meetsNumericTarget'), isFalse);
    },
  );

  test(
    'run sequence and first marker are per direction and process, with latest ten retained',
    () async {
      final recorder = create();
      for (var i = 0; i < 6; i++) {
        for (final kind in TrainingTransitionKind.values) {
          now += 1000;
          final token = recorder.begin(kind);
          now += 500;
          recorder.finish(token);
        }
      }
      await recorder.exportJson();
      expect(recorder.results.length, 10);
      final entryRuns = recorder.results
          .where((r) => r['kind'] == 'entry')
          .toList();
      expect(entryRuns.map((r) => r['runInProcess']), [6, 5, 4, 3, 2]);
      expect(
        entryRuns.every((row) => row['firstAfterProcessStart'] == false),
        isTrue,
      );
      final restored = create();
      now += 10000;
      await restored.initialize();
      final token = restored.begin(TrainingTransitionKind.entry);
      now += 500;
      restored.finish(token);
      await restored.exportJson();
      expect(restored.results.first['runInProcess'], 1);
      expect(restored.results.first['firstAfterProcessStart'], isTrue);
      expect(restored.results.length, 10);
    },
  );

  test(
    'source entry and horizontal slide identity survive export and restore',
    () async {
      final recorder = create();
      for (final entry in [
        'chat',
        'saved_plan',
        'guide',
        'action_library',
        'recommendation',
      ]) {
        now += 1000;
        final token = recorder.begin(
          TrainingTransitionKind.entry,
          theme: 'dark',
          sourceEntry: entry,
        );
        now += 500;
        recorder.finish(token);
      }
      final report = jsonDecode(await recorder.exportJson()) as Map;
      final rows = (report['results'] as List).cast<Map>();
      expect(rows.map((row) => row['sourceEntry']), [
        'recommendation',
        'action_library',
        'guide',
        'saved_plan',
        'chat',
      ]);
      expect(
        rows.every((row) => row['transitionStyle'] == 'horizontal_slide'),
        isTrue,
      );
      expect(rows.every((row) => row['theme'] == 'dark'), isTrue);
      final restored = create();
      await restored.initialize();
      expect(restored.results.map((row) => row['sourceEntry']), [
        'recommendation',
        'action_library',
        'guide',
        'saved_plan',
        'chat',
      ]);
    },
  );

  test(
    'legacy stored frames survive without obsolete performance target verdicts',
    () async {
      storage.contents = jsonEncode({
        'schema': 'smartfit-training-transition-timings@1',
        'results': [
          {
            'id': 'legacy-entry',
            'startedAtUtc': '2026-10-29T00:00:00Z',
            'kind': 'entry',
            'frameCount': 1,
            'frames': [
              {'frameNumber': 1, 'buildUs': 5000, 'rasterUs': 8000},
            ],
            'buildP90Ms': 5.0,
            'warmAcceptanceRun': true,
            'eligibleForWarmTarget': true,
            'meetsNumericTarget': true,
          },
        ],
      });
      final recorder = create();
      await recorder.initialize();
      final row = recorder.results.single;
      expect(row['buildP90Ms'], 5);
      expect(row['frames'], hasLength(1));
      expect(row['transitionStyle'], isNull);
      expect(row.containsKey('warmAcceptanceRun'), isFalse);
      expect(row.containsKey('eligibleForWarmTarget'), isFalse);
      expect(row.containsKey('meetsNumericTarget'), isFalse);
    },
  );

  test('replacement and lifecycle interruption are idempotent', () async {
    final recorder = create();
    final first = recorder.begin(TrainingTransitionKind.entry);
    now += 1000;
    final second = recorder.begin(TrainingTransitionKind.exit);
    now += 1000;
    recorder.didChangeAppLifecycleState(AppLifecycleState.paused);
    recorder.finish(first);
    recorder.finish(second);
    await recorder.exportJson();
    expect(recorder.results.length, 2);
    expect(
      recorder.results.every((row) => row['outcome'] == 'interrupted'),
      isTrue,
    );
  });

  test(
    'disabled production recorder neither attaches nor reads/writes storage',
    () async {
      final recorder = create(enabled: false, attach: true);
      await recorder.initialize();
      expect(recorder.begin(TrainingTransitionKind.entry), isNull);
      recorder.acceptTimings([_frame(7, 1000, 20000, 30000)]);
      expect(storage.reads, 0);
      expect(storage.writes, 0);
      expect(recorder.results, isEmpty);
      await expectLater(recorder.exportJson(), throwsStateError);
    },
  );

  test(
    'scheduler callback receives actual engine event rather than guessed timings',
    () async {
      final recorder = create(attach: true);
      await recorder.initialize();
      final token = recorder.begin(TrainingTransitionKind.entry);
      binding.platformDispatcher.onReportTimings!([_frame(7, 1000, 500, 700)]);
      now += 1000;
      recorder.finish(token);
      await recorder.exportJson();
      expect(recorder.results.single['frameCount'], 1);
    },
  );

  test(
    'backend evidence must be verified; guessed flags remain unverified',
    () async {
      final recorder = create();
      recorder.setEnvironment(
        renderer: 'impeller',
        rendererBackend: 'vulkan',
        rendererVerified: false,
      );
      final a = recorder.begin(TrainingTransitionKind.entry);
      now += 1000;
      recorder.finish(a);
      await recorder.exportJson();
      expect(recorder.results.single['renderer'], 'unverified');
      recorder.setEnvironment(
        renderer: 'impeller',
        rendererBackend: 'vulkan',
        rendererVerified: true,
      );
      final b = recorder.begin(TrainingTransitionKind.exit);
      now += 1000;
      recorder.finish(b);
      await recorder.exportJson();
      expect(recorder.results.last['renderer'], 'impeller');
      expect(
        recorder.results.last['rendererVerifiedAfterSampleStarted'],
        isTrue,
      );
      expect(recorder.results.first['rendererBackend'], 'vulkan');
      expect(recorder.results.first['rendererVerified'], isTrue);
    },
  );

  test(
    'failed storage preserves copyable results and exposes failure without crashing transition',
    () async {
      storage.fail = true;
      final recorder = create();
      final token = recorder.begin(TrainingTransitionKind.entry);
      now += 500;
      recorder.finish(token);
      final report = jsonDecode(await recorder.exportJson()) as Map;
      expect(recorder.results.length, 1);
      expect(report['persistenceFailed'], isTrue);
    },
  );

  test(
    'raw frames are bounded, with truncation explicitly marking an incomplete sample',
    () async {
      number = -1;
      now = 1;
      final recorder = create();
      final token = recorder.begin(TrainingTransitionKind.entry);
      recorder.acceptTimings([
        for (var i = 0; i < 700; i++) _frame(i, 1000 + i, 1, 1),
      ]);
      now = 10000;
      recorder.finish(token);
      await recorder.exportJson();
      expect(recorder.results.single['frameCount'], 600);
      expect(recorder.results.single['truncated'], isTrue);
      expect(recorder.results.single['sampleComplete'], isFalse);
    },
  );

  test(
    'dedicated Application Support JSON replacement retains latest valid document',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'smartfit-transition-timings-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final files = FileTrainingTransitionTimingsStorage(directory: temporary);
      await files.write('{"sample":1}');
      await files.write('{"sample":2}');
      expect(await files.read(), '{"sample":2}');
      expect(
        await File(
          '${temporary.path}${Platform.pathSeparator}recent.json.writing',
        ).exists(),
        isFalse,
      );
    },
  );
}
