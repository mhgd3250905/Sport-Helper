import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_report.dart';
import 'package:smartfit/ui/performance_settings.dart';
import 'package:smartfit/ui/theme.dart';

const _channel = MethodChannel('smartfit/performance');
const _device = <String, Object?>{
  'model': 'Test phone',
  'manufacturer': 'Test manufacturer',
  'osVersion': '15',
  'apiLevel': 35,
  'appVersion': '0.1.0',
  'appBuildNumber': 2016,
  'refreshRateHz': 120.0,
  'isEmulator': true,
};

class _ReportPlatform implements PerformanceReportPlatform {
  int deviceCalls = 0;
  final exports = <({String filename, String contents})>[];
  Future<Map<String, Object?>> Function()? readDevice;

  @override
  Future<Map<String, Object?>> deviceInfo() async {
    deviceCalls++;
    return readDevice == null ? _device : await readDevice!();
  }

  @override
  Future<void> share({
    required String filename,
    required String contents,
  }) async {
    exports.add((filename: filename, contents: contents));
  }
}

class _ControlledService extends PerformanceReportService {
  _ControlledService(FrameRecorder recorder) : super(recorder: recorder);
  final attempts = <Completer<void>>[];

  @override
  Future<void> share() {
    final result = Completer<void>();
    attempts.add(result);
    return result.future;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final recorders = <FrameRecorder>[];
  var nextTimestamp = 1000000;

  FrameRecorder createRecorder({bool enabled = true}) {
    final recorder = FrameRecorder(
      enabled: enabled,
      currentFrameNumber: () => 42,
      clock: () => DateTime.utc(2026, 10, 23, 12, 34, 56),
    );
    recorders.add(recorder);
    return recorder;
  }

  // Unit-test input only. These synthetic timings never represent measured
  // device performance and are never written to the delivery artifacts.
  void reportTestFrame() {
    binding.platformDispatcher.onReportTimings!([
      FrameTiming(
        vsyncStart: 1000,
        buildStart: 1000,
        buildFinish: 13000,
        rasterStart: 13000,
        rasterFinish: 33000,
        rasterFinishWallTime: 33000,
        frameNumber: 42,
      ),
    ]);
  }

  void seedUnitFrame(FrameRecorder recorder) {
    recorder.setPage('action_library');
    recorder.beginScenario(FrameScenario.actionListScroll);
    recorder.start();
    binding.handleBeginFrame(Duration(microseconds: nextTimestamp));
    binding.handleDrawFrame();
    nextTimestamp += 100000;
    reportTestFrame();
    expect(recorder.snapshot()['recordedFrameCount'], 1);
  }

  Future<void> showPage(
    WidgetTester tester,
    PerformanceReportService service,
  ) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(SfPalette.light),
        home: PerformanceSettingsPage(service: service),
      ),
    );
  }

  Future<void> seedWidgetFrame(
    WidgetTester tester,
    FrameRecorder recorder,
  ) async {
    recorder.setPage('action_library');
    recorder.start();
    await tester.pump();
    reportTestFrame();
    expect(recorder.snapshot()['recordedFrameCount'], 1);
  }

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    for (final recorder in recorders) {
      recorder.stop();
    }
    recorders.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  group('Android performance report channel', () {
    const platform = AndroidPerformanceReportPlatform();

    test(
      'device metadata keeps native types and actual package build code',
      () async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
          call,
        ) async {
          expect(call.method, 'deviceInfo');
          expect(call.arguments, isNull);
          return _device;
        });
        expect(await platform.deviceInfo(), _device);
      },
    );

    test('missing device metadata is a failure', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (_) async => null,
      );
      await expectLater(platform.deviceInfo(), throwsStateError);
    });

    test('native device failure remains retryable by the caller', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        _,
      ) async {
        throw PlatformException(code: 'device_info_unavailable');
      });
      await expectLater(
        platform.deviceInfo(),
        throwsA(isA<PlatformException>()),
      );
    });

    test(
      'share true means chooser opened and passes exact JSON arguments',
      () async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
          call,
        ) async {
          expect(call.method, 'share');
          expect(call.arguments, {
            'filename': 'SmartFit-performance-20261023T123456Z.json',
            'contents': '{"schema":1}',
          });
          return true;
        });
        await platform.share(
          filename: 'SmartFit-performance-20261023T123456Z.json',
          contents: '{"schema":1}',
        );
      },
    );

    for (final opened in <bool?>[false, null]) {
      test('share $opened does not claim that the chooser opened', () async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          (_) async => opened,
        );
        await expectLater(
          platform.share(filename: 'report.json', contents: '{}'),
          throwsStateError,
        );
      });
    }

    test('share platform errors propagate without a success result', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        _,
      ) async {
        throw PlatformException(code: 'share_write_failed');
      });
      await expectLater(
        platform.share(filename: 'report.json', contents: '{}'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'share_write_failed',
          ),
        ),
      );
    });
  });

  group('Performance report service', () {
    test('disabled diagnostics never access a platform channel', () async {
      var channelCalls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        _,
      ) async {
        channelCalls++;
        return _device;
      });
      final recorder = createRecorder(enabled: false);
      final service = PerformanceReportService(recorder: recorder);
      await service.initialize();
      await service.refreshDeviceInfo();
      await expectLater(service.share(), throwsStateError);
      expect(channelCalls, 0);
      expect(recorder.snapshot()['metadata'], isEmpty);
    });

    test(
      'initialization coalesces concurrent device metadata requests',
      () async {
        final nativeReply = Completer<Map<String, Object?>>();
        final platform = _ReportPlatform()
          ..readDevice = () => nativeReply.future;
        final recorder = createRecorder();
        final service = PerformanceReportService(
          recorder: recorder,
          platform: platform,
        );
        final first = service.initialize();
        final second = service.initialize();
        expect(platform.deviceCalls, 1);
        nativeReply.complete(_device);
        await Future.wait([first, second]);
        expect(platform.deviceCalls, 1);
        expect(recorder.snapshot()['currentRefreshRateHz'], 120);
        final metadata = recorder.snapshot()['metadata'] as Map;
        expect(metadata['appBuildNumber'], 2016);
        expect(metadata['metadataStatus'], 'available');
      },
    );

    test(
      'metadata failures can retry during export and encode a real snapshot',
      () async {
        final platform = _ReportPlatform();
        platform.readDevice = () async {
          if (platform.deviceCalls == 1) {
            throw StateError('temporary native failure');
          }
          return _device;
        };
        final recorder = createRecorder();
        final service = PerformanceReportService(
          recorder: recorder,
          platform: platform,
        );
        await service.initialize();
        expect(
          (recorder.snapshot()['metadata'] as Map)['metadataStatus'],
          'unavailable',
        );
        seedUnitFrame(recorder);
        await service
            .share(); // Uses the actual compute encoder in another isolate.
        expect(platform.deviceCalls, 2);
        expect(platform.exports, hasLength(1));
        final export = platform.exports.single;
        expect(
          export.filename,
          matches(RegExp(r'^SmartFit-performance-[A-Za-z0-9_-]+\.json$')),
        );
        expect(export.filename.length, lessThanOrEqualTo(96));
        final decoded = jsonDecode(export.contents) as Map<String, dynamic>;
        expect(decoded, recorder.snapshot());
        expect(decoded['reportType'], 'solid_frame_performance');
        expect(decoded['material'], 'solid');
        expect(decoded['recordedFrameCount'], 1);
        expect((decoded['metadata'] as Map)['deviceModel'], 'Test phone');
        expect((decoded['metadata'] as Map)['appBuildNumber'], 2016);
        expect((decoded['metadata'] as Map)['metadataStatus'], 'available');
        expect(((decoded['total'] as Map)['uiBuild'] as Map)['averageMs'], 12);
        expect(((decoded['total'] as Map)['raster'] as Map)['worstMs'], 20);
        expect((decoded['scenarios'] as Map)['actionListScroll'], isNotNull);
        expect(recorder.snapshot()['recordedFrameCount'], 1);
      },
    );

    test('zero attributed frames cannot be exported or shared', () async {
      final platform = _ReportPlatform();
      final recorder = createRecorder();
      recorder.start();
      reportTestFrame(); // No scheduler boundary, so this frame is unattributed.
      expect(recorder.snapshot()['receivedFrameCount'], 1);
      expect(recorder.snapshot()['recordedFrameCount'], 0);
      final service = PerformanceReportService(
        recorder: recorder,
        platform: platform,
      );
      await expectLater(service.share(), throwsA(isA<NoPerformanceFrames>()));
      expect(platform.exports, isEmpty);
    });

    test('only a verified native renderer updates actual conditions', () async {
      final platform = _ReportPlatform()
        ..readDevice = () async => {
          ..._device,
          'renderer': 'impeller',
          'rendererBackend': 'vulkan',
          'rendererSource': 'android_engine_startup_log_own_pid',
          'rendererVerified': true,
        };
      final recorder = createRecorder();
      final service = PerformanceReportService(
        recorder: recorder,
        platform: platform,
      );
      var changed = 0;
      service.addListener(() => changed++);
      await service.initialize();
      expect(service.renderer, 'impeller');
      expect(service.rendererBackend, 'vulkan');
      expect(service.rendererVerified, isTrue);
      expect(
        (recorder.snapshot()['metadata'] as Map)['rendererVerified'],
        isTrue,
      );
      expect(changed, 1);
      platform.readDevice = () async => {
        ..._device,
        'renderer': 'skia',
        'rendererVerified': false,
      };
      await service.refreshDeviceInfo();
      expect(service.renderer, 'unverified');
      expect(service.rendererVerified, isFalse);
      expect(
        (recorder.snapshot()['metadata'] as Map)['renderer'],
        'unverified',
      );
      service.dispose();
    });

    test('filename is ASCII, UTC and safe for the native allowlist', () {
      expect(
        performanceReportFilename(
          DateTime.parse('2026-10-23T20:34:56.123+08:00'),
        ),
        'SmartFit-performance-20261023T123456123Z.json',
      );
    });
  });

  test(
    'compact UTF-8 export size guard preserves raw frames and skips native sharing',
    () async {
      final recorder = createRecorder();
      final normal = _ReportPlatform()
        ..readDevice = () async => {..._device, 'model': '示例手机'};
      final service = PerformanceReportService(
        recorder: recorder,
        platform: normal,
      );
      await service.initialize();
      seedUnitFrame(recorder);
      await service.share();
      final contents = normal.exports.single.contents;
      expect(contents, isNot(contains('\n')));
      final data = jsonDecode(contents) as Map;
      expect(data['schema'], 3);
      expect((data['rawFrames'] as List).length, 1);
      final limited = _ReportPlatform()..readDevice = normal.readDevice;
      final restricted = PerformanceReportService(
        recorder: recorder,
        platform: limited,
        maxExportBytes: contents.length,
      );
      await expectLater(
        restricted.share(),
        throwsA(isA<PerformanceReportTooLarge>()),
      );
      expect(limited.exports, isEmpty);
      expect((recorder.snapshot()['rawFrames'] as List).length, 1);
      expect(PerformanceReportService.maximumExportBytes, 64 * 1024 * 1024);
    },
  );

  group('Performance settings', () {
    const exportKey = ValueKey('performance-export');
    testWidgets('disabled recorder renders no controls or platform access', (
      tester,
    ) async {
      final platform = _ReportPlatform();
      await showPage(
        tester,
        PerformanceReportService(
          recorder: createRecorder(enabled: false),
          platform: platform,
        ),
      );
      expect(find.byKey(exportKey), findsNothing);
      expect(platform.deviceCalls, 0);
      expect(platform.exports, isEmpty);
    });
    testWidgets(
      'generic VM scenario survives opening the new ten-cell settings',
      (tester) async {
        final recorder = createRecorder()
          ..beginScenario(FrameScenario.mediaVerifyScroll);
        await showPage(tester, _ControlledService(recorder));
        expect(
          find.byKey(const ValueKey('performance-open-lab')),
          findsOneWidget,
        );
        expect(find.byType(SwitchListTile), findsNothing);
        expect(tester.takeException(), isNull);
        expect(recorder.currentScenario, FrameScenario.mediaVerifyScroll);
      },
    );
    testWidgets(
      'export disables duplicate requests and preserves the raw round',
      (tester) async {
        final recorder = createRecorder();
        // The page and exporter must share the same recorder.
        final actual = _ControlledService(recorder);
        await showPage(tester, actual);
        await seedWidgetFrame(tester, recorder);
        final before = recorder.snapshot();
        await tester.tap(find.byKey(exportKey));
        await tester.pump();
        expect(
          tester.widget<SfPrimaryButton>(find.byKey(exportKey)).onPressed,
          isNull,
        );
        await tester.pump(const Duration(milliseconds: 1200));
        expect(actual.attempts, hasLength(1));
        actual.attempts.single.complete();
        await tester.pumpAndSettle();
        expect(find.text('系统分享已打开；取消分享不会清空统计。'), findsOneWidget);
        expect(recorder.snapshot(), before);
      },
    );
    testWidgets('export failure retains samples and permits a retry', (
      tester,
    ) async {
      final recorder = createRecorder();
      final actual = _ControlledService(recorder);
      await showPage(tester, actual);
      await seedWidgetFrame(tester, recorder);
      final before = recorder.snapshot();
      await tester.tap(find.byKey(exportKey));
      await tester.pump(const Duration(milliseconds: 1200));
      actual.attempts.single.completeError(
        StateError('fixture export failure'),
      );
      await tester.pump();
      expect(find.text('导出未完成，请稍后重试；已有统计仍保留。'), findsOneWidget);
      expect(recorder.snapshot(), before);
      await tester.tap(find.byKey(exportKey));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(actual.attempts, hasLength(2));
      actual.attempts.last.complete();
      await tester.pumpAndSettle();
    });
    testWidgets('empty samples never create a performance claim', (
      tester,
    ) async {
      final service = _ControlledService(createRecorder());
      await showPage(tester, service);
      await tester.tap(find.byKey(exportKey));
      await tester.pump(const Duration(milliseconds: 1200));
      service.attempts.single.completeError(const NoPerformanceFrames());
      await tester.pump();
      expect(find.text('还没有收到真实帧，未生成性能结论。'), findsOneWidget);
      expect(
        tester.widget<SfPrimaryButton>(find.byKey(exportKey)).onPressed,
        isNotNull,
      );
    });
  });
}
