import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_report.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/performance_settings.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

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

class _MemoryStorage implements LocalStateStorage {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
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
        expect(decoded['reportType'], 'frame_performance');
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

  group('Performance settings', () {
    const exportKey = ValueKey('performance-export');

    testWidgets(
      'VM-selected hidden scenario opens settings with a valid dropdown value',
      (tester) async {
        final recorder = createRecorder();
        // The profile VM extension accepts every fixed enum, including the
        // verification-only scenario that the manual combined window omits.
        recorder.beginScenario(FrameScenario.mediaVerifyScroll);
        await showPage(tester, _ControlledService(recorder));
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<DropdownButtonFormField<FrameScenario>>(
                find.byKey(const ValueKey('performance-scenario')),
              )
              .initialValue,
          FrameScenario.actionListScroll,
        );
        expect(recorder.currentScenario, FrameScenario.mediaVerifyScroll);
      },
    );

    testWidgets(
      'disabled recorder renders no controls and does not access the platform',
      (tester) async {
        final platform = _ReportPlatform();
        await showPage(
          tester,
          PerformanceReportService(
            recorder: createRecorder(enabled: false),
            platform: platform,
          ),
        );
        expect(find.byKey(exportKey), findsNothing);
        expect(find.text('性能报告'), findsNothing);
        expect(platform.deviceCalls, 0);
        expect(platform.exports, isEmpty);
      },
    );

    testWidgets(
      'production settings contains no performance entry',
      (tester) async {
        expect(FrameRecorder.buildEnabled, isFalse);
        final store = AppStore(_MemoryStorage());
        addTearDown(store.dispose);
        final services = AppServices(
          library: ExerciseLibrary([]),
          catalog: TemplateCatalog([]),
          store: store,
          voiceLibrary: VoiceLibrary.empty,
          voiceOutput: const MutedVoiceOutput(),
        );
        tester.view.physicalSize = const Size(1080, 9000);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          AppScope(
            services: services,
            child: MaterialApp(
              theme: buildTheme(SfPalette.light),
              home: const AboutPage(),
            ),
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('performance-report-open')),
          findsNothing,
        );
        expect(find.text('导出性能报告'), findsNothing);
      },
      skip: FrameRecorder.buildEnabled,
    );

    testWidgets(
      'export disables edits and duplicate taps; success or later cancel preserves statistics',
      (tester) async {
        final recorder = createRecorder();
        final service = _ControlledService(recorder);
        await showPage(tester, service);
        await seedWidgetFrame(tester, recorder);
        final before = recorder.snapshot();
        await tester.tap(find.byKey(exportKey));
        await tester.tap(find.byKey(exportKey));
        await tester.pump();
        expect(find.text('正在准备报告…'), findsOneWidget);
        for (final key in [
          'performance-export',
          'performance-reset',
          'performance-start-scenario',
        ]) {
          expect(
            tester.widget<SfPrimaryButton>(find.byKey(ValueKey(key))).onPressed,
            isNull,
          );
        }
        expect(
          tester
              .widget<SfTextAction>(
                find.byKey(const ValueKey('performance-end-scenario')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<DropdownButtonFormField<FrameScenario>>(
                find.byKey(const ValueKey('performance-scenario')),
              )
              .onChanged,
          isNull,
        );
        expect(service.attempts, isEmpty);
        await tester.pump(const Duration(milliseconds: 1200));
        expect(service.attempts, hasLength(1));
        await tester.tap(find.byKey(exportKey));
        await tester.pump();
        expect(service.attempts, hasLength(1));
        service.attempts.single.complete();
        await tester.pumpAndSettle();
        expect(find.text('已打开系统分享，请选择接收方。统计仍保留。'), findsOneWidget);
        expect(
          tester.widget<SfPrimaryButton>(find.byKey(exportKey)).onPressed,
          isNotNull,
        );
        // The chooser may later be cancelled; opening it must never clear a round.
        expect(recorder.snapshot(), before);
      },
    );

    testWidgets('export failure preserves the round and permits retry', (
      tester,
    ) async {
      final recorder = createRecorder();
      final service = _ControlledService(recorder);
      await showPage(tester, service);
      await seedWidgetFrame(tester, recorder);
      final before = recorder.snapshot();
      await tester.tap(find.byKey(exportKey));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(service.attempts, hasLength(1));
      service.attempts.single.completeError(StateError('write failed'));
      await tester.pump();
      expect(find.text('报告导出失败；统计仍保留，请重试。'), findsOneWidget);
      expect(recorder.snapshot(), before);
      await tester.tap(find.byKey(exportKey));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(service.attempts, hasLength(2));
      service.attempts.last.complete();
      await tester.pump();
      expect(find.text('已打开系统分享，请选择接收方。统计仍保留。'), findsOneWidget);
      expect(recorder.snapshot(), before);
    });

    testWidgets(
      'empty-round error gives actionable feedback and enables export again',
      (tester) async {
        final service = _ControlledService(createRecorder());
        await showPage(tester, service);
        await tester.tap(find.byKey(exportKey));
        await tester.pump(const Duration(milliseconds: 1200));
        service.attempts.single.completeError(const NoPerformanceFrames());
        await tester.pump();
        expect(find.text('尚未收到有效帧数据，请返回页面操作后再导出。'), findsOneWidget);
        expect(
          tester.widget<SfPrimaryButton>(find.byKey(exportKey)).onPressed,
          isNotNull,
        );
      },
    );
  });
}
