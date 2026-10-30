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
  setUp(() async {
    now = 1000;
    clipboard = null;
    recorder = TrainingTransitionTimings(
      enabled: true,
      storage: _Storage(),
      attachScheduler: false,
      settleDelay: Duration.zero,
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
      (_) async => <String, Object?>{
        'renderer': 'unverified',
        'rendererVerified': false,
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

  Future<void> show(WidgetTester tester, {bool disabled = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(SfPalette.light),
        home: TrainingTransitionTimingsPage(recorder: recorder),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty viewer cannot invent performance values', (tester) async {
    await show(tester);
    expect(find.text('训练进出帧耗时'), findsOneWidget);
    expect(find.textContaining('尚未收到已结束的真实过渡帧'), findsOneWidget);
    expect(clipboard, isNull);
    expect(find.textContaining('0.00ms'), findsNothing);
  });

  testWidgets(
    'viewer exposes actual sample values and copies complete JSON with one tap',
    (tester) async {
      await show(tester);
      final token = recorder.begin(
        TrainingTransitionKind.entry,
        theme: 'light',
      );
      now = 3000;
      recorder.finish(token);
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
      expect(find.text('进入 · 本次启动第1次（首次）'), findsOneWidget);
      expect(find.text('Build：P90 5.00ms / 最大 5.00ms'), findsOneWidget);
      expect(find.text('Raster：P90 8.00ms / 最大 8.00ms'), findsOneWidget);
      expect(find.text('渲染后端：未验证'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transition-timings-copy')));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      final copied = jsonDecode(clipboard!) as Map;
      expect((copied['results'] as List).length, 1);
      expect((copied['results'] as List).single['buildP90Ms'], 5);
      expect(find.text('已复制最近10次训练过渡JSON'), findsOneWidget);
    },
  );

  testWidgets('disabled formal build viewer has no tools or copy action', (
    tester,
  ) async {
    recorder.dispose();
    recorder = TrainingTransitionTimings(enabled: false, storage: _Storage());
    await show(tester);
    expect(find.text('训练进出帧耗时'), findsNothing);
    expect(find.byKey(const ValueKey('transition-timings-copy')), findsNothing);
  });
}
