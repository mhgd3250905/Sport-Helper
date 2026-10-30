import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/training_transition_timings.dart';
import 'package:smartfit/diagnostics/training_transition_timings_storage.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_transition_timings_page.dart';

class _Storage implements TrainingTransitionTimingsStorage {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String json) async {}
}

void main() {
  var now = 1000;
  late TrainingTransitionTimings recorder;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  String? clipboard;
  String? sharedFilename, sharedContents;
  var shareCalls = 0, deviceCalls = 0;
  Future<bool> Function()? shareResponse;
  setUp(() async {
    now = 1000;
    clipboard = null;
    sharedFilename = sharedContents = null;
    shareCalls = deviceCalls = 0;
    shareResponse = null;
    recorder = TrainingTransitionTimings(
      enabled: true,
      storage: _Storage(),
      attachScheduler: false,
      settleDelay: Duration.zero,
      clock: () => DateTime.utc(2026, 10, 30),
      monotonicMicros: () => now,
      currentFrameNumber: () => -1,
      summarize: (data) async => summarizeTransitionTimings(data),
      encode: (data) async => jsonEncode(data),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('smartfit/performance'),
      (call) async {
        if (call.method == 'share') {
          shareCalls++;
          final args = call.arguments as Map;
          sharedFilename = args['filename'] as String;
          sharedContents = args['contents'] as String;
          return shareResponse == null ? true : await shareResponse!();
        }
        deviceCalls++;
        return <String, Object?>{
          'renderer': 'unverified',
          'rendererVerified': false,
        };
      },
    );
    // Let setup's platform futures settle before the widget fake-clock zone.
    await Future<void>.value();
  });
  tearDown(() {
    recorder.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('smartfit/performance'),
      null,
    );
  });

  Future<void> show(WidgetTester tester, {bool dark = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(dark ? SfPalette.dark : SfPalette.light),
        home: TrainingTransitionTimingsPage(recorder: recorder),
      ),
    );
    await tester.pump();
  }

  Future<void> seedSample(WidgetTester tester, {bool dark = false}) async {
    final token = recorder.begin(
      TrainingTransitionKind.entry,
      theme: dark ? 'dark' : 'light',
      sourceEntry: 'guide',
    );
    now = 3000;
    recorder.finish(token);
    // Synthetic widget-test input only; never physical performance evidence.
    recorder.acceptTimings([
      FrameTiming(
        frameNumber: 7,
        vsyncStart: 2000,
        buildStart: 2000,
        buildFinish: 7000,
        rasterStart: 7000,
        rasterFinish: 15000,
        rasterFinishWallTime: 15000,
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('empty viewer cannot invent performance values', (tester) async {
    await show(tester);
    expect(find.text('训练进出帧耗时'), findsOneWidget);
    expect(find.textContaining('尚未收到已结束的真实过渡帧'), findsOneWidget);
    expect(clipboard, isNull);
    expect(find.textContaining('0.00ms'), findsNothing);
    expect(
      tester
          .widget<SfPrimaryButton>(
            find.byKey(const ValueKey('transition-timings-copy')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<SfSecondaryButton>(
            find.byKey(const ValueKey('transition-timings-share')),
          )
          .onPressed,
      isNull,
    );
    expect(shareCalls, 0);
  });

  testWidgets(
    'viewer exposes actual sample values and copies complete JSON with one tap',
    (tester) async {
      await show(tester);
      await seedSample(tester);
      expect(find.text('进入 · 本次启动第1次（首次）'), findsOneWidget);
      expect(find.text('Build：P90 5.00ms / 最大 5.00ms'), findsOneWidget);
      expect(find.text('Raster：P90 8.00ms / 最大 8.00ms'), findsOneWidget);
      expect(find.text('渲染后端：未验证'), findsOneWidget);
      expect(find.text('入口：图文详情'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transition-timings-copy')));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      final copied = jsonDecode(clipboard!) as Map;
      expect((copied['results'] as List).length, 1);
      expect((copied['results'] as List).single['buildP90Ms'], 5);
      expect((copied['results'] as List).single['sourceEntry'], 'guide');
      expect(find.text('已复制最近10次训练过渡JSON'), findsOneWidget);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'system share exports exact recent JSON in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        await show(tester, dark: dark);
        await seedSample(tester, dark: dark);
        await tester.tap(
          find.byKey(const ValueKey('transition-timings-share')),
        );
        await tester.pumpAndSettle();
        expect(shareCalls, 1);
        expect(
          sharedFilename,
          matches(RegExp(r'^SmartFit-performance-[A-Za-z0-9_-]+\.json$')),
        );
        expect(jsonDecode(sharedContents!), recorder.report);
        expect(clipboard, isNull);
        expect(find.text('系统分享已打开，可选择飞书；取消分享不会清空统计。'), findsOneWidget);
        expect(recorder.results, hasLength(1));
        expect(find.textContaining('已发送'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'pending share blocks duplicate share and copy until chooser result',
    (tester) async {
      await show(tester);
      await seedSample(tester);
      final pending = Completer<bool>();
      shareResponse = () => pending.future;
      final share = tester
          .widget<SfSecondaryButton>(
            find.byKey(const ValueKey('transition-timings-share')),
          )
          .onPressed!;
      share();
      share();
      await tester.pump();
      await tester.pump();
      expect(shareCalls, 1);
      expect(
        tester
            .widget<SfPrimaryButton>(
              find.byKey(const ValueKey('transition-timings-copy')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<SfSecondaryButton>(
              find.byKey(const ValueKey('transition-timings-share')),
            )
            .onPressed,
        isNull,
      );
      expect(clipboard, isNull);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SfPrimaryButton>(
              find.byKey(const ValueKey('transition-timings-copy')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('failed system share preserves results and permits retry', (
    tester,
  ) async {
    await show(tester);
    await seedSample(tester);
    shareResponse = () async => false;
    await tester.tap(find.byKey(const ValueKey('transition-timings-share')));
    await tester.pumpAndSettle();
    expect(find.text('分享未打开，请重试；已有采样保留。'), findsOneWidget);
    expect(recorder.results, hasLength(1));
    expect(find.textContaining('系统分享已打开'), findsNothing);
    shareResponse = () async => true;
    await tester.tap(find.byKey(const ValueKey('transition-timings-share')));
    await tester.pumpAndSettle();
    expect(shareCalls, 2);
    expect(find.textContaining('系统分享已打开'), findsOneWidget);
    expect(recorder.results, hasLength(1));
  });

  testWidgets(
    'instructions require export after each three-run entry/theme group',
    (tester) async {
      await show(tester);
      expect(find.textContaining('共6组。每组进出3次'), findsOneWidget);
      expect(find.textContaining('每组测完立即分享'), findsOneWidget);
      expect(find.textContaining('第2–5次'), findsNothing);
      expect(find.textContaining('达到目标'), findsNothing);
    },
  );

  testWidgets(
    'disabled formal build viewer has no tools or native export actions',
    (tester) async {
      recorder.dispose();
      recorder = TrainingTransitionTimings(enabled: false, storage: _Storage());
      await show(tester);
      expect(find.text('训练进出帧耗时'), findsNothing);
      expect(
        find.byKey(const ValueKey('transition-timings-copy')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('transition-timings-share')),
        findsNothing,
      );
      expect(shareCalls, 0);
      expect(deviceCalls, 0);
    },
  );
}
