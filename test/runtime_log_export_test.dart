import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/log_export.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/ui/runtime_log_settings.dart';
import 'package:smartfit/ui/theme.dart';

class _Exporter implements RuntimeLogExporter {
  final pending = Completer<LogExportResult>();
  String? filename;
  String? contents;
  int calls = 0;

  @override
  Future<LogExportResult> save({
    required String filename,
    required String contents,
  }) {
    this.filename = filename;
    this.contents = contents;
    calls++;
    return pending.future;
  }
}

Future<void> _show(
  WidgetTester tester,
  RuntimeLog log,
  RuntimeLogExporter exporter,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(SfPalette.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: RuntimeLogSettings(log: log, exporter: exporter),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('smartfit/runtime_log_export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native save awaits the platform write and preserves cancellation',
    () async {
      final platformWrite = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) {
        expect(call.method, 'save');
        expect(call.arguments, {
          'filename': 'SmartFit-runtime-test.json',
          'contents': '{"schema":1}',
        });
        return platformWrite.future;
      });
      var completed = false;
      final result = const PlatformRuntimeLogExporter()
          .save(
            filename: 'SmartFit-runtime-test.json',
            contents: '{"schema":1}',
          )
          .then((value) {
            completed = true;
            return value;
          });
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      platformWrite.complete(true);
      expect(await result, LogExportResult.saved);
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(
        await const PlatformRuntimeLogExporter().save(
          filename: 'a',
          contents: 'b',
        ),
        LogExportResult.cancelled,
      );
    },
  );

  test('platform errors and invalid results never become saved', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      const PlatformRuntimeLogExporter().save(filename: 'a', contents: 'b'),
      throwsA(isA<PlatformException>()),
    );
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'export_write_failed');
    });
    await expectLater(
      const PlatformRuntimeLogExporter().save(filename: 'a', contents: 'b'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('export filenames use UTC and contain no path characters', () {
    final filename = runtimeLogFilename(
      DateTime.parse('2026-10-23T16:17:18.901+08:00'),
    );
    expect(filename, 'SmartFit-runtime-20261023T081718901Z.json');
  });

  testWidgets('saving exports diagnostics once and waits before success', (
    tester,
  ) async {
    final log = RuntimeLog(enabled: true);
    log.record('ai.started', fields: {'route': 'sdk', 'prompt': 'private'});
    final exporter = _Exporter();
    await _show(tester, log, exporter);
    await tester.tap(find.byKey(const ValueKey('runtime-log-save')));
    await tester.pump();
    expect(exporter.calls, 1);
    expect(find.text('正在保存…'), findsOneWidget);
    expect(find.textContaining('日志已保存：'), findsNothing);
    final report = jsonDecode(exporter.contents!) as Map;
    expect(report['events'], isNotEmpty);
    expect(exporter.contents, isNot(contains('private')));
    expect(exporter.filename, startsWith('SmartFit-runtime-'));
    exporter.pending.complete(LogExportResult.saved);
    await tester.pumpAndSettle();
    expect(find.text('日志已保存：${exporter.filename}'), findsOneWidget);
  });

  testWidgets('cancel and failure keep logs available and allow retry', (
    tester,
  ) async {
    final log = RuntimeLog(enabled: true)..record('app.started');
    final cancelled = _Exporter();
    await _show(tester, log, cancelled);
    await tester.tap(find.byKey(const ValueKey('runtime-log-save')));
    await tester.pump();
    cancelled.pending.complete(LogExportResult.cancelled);
    await tester.pumpAndSettle();
    expect(find.text('已取消保存；日志仍保存在 App 中。'), findsOneWidget);
    expect(log.entryCount, greaterThan(0));
    final failed = _Exporter();
    await _show(tester, log, failed);
    await tester.tap(find.byKey(const ValueKey('runtime-log-save')));
    await tester.pump();
    failed.pending.completeError(StateError('sensitive native failure detail'));
    await tester.pumpAndSettle();
    expect(find.text('日志保存失败，请换一个文件夹后重试。'), findsOneWidget);
    expect(find.textContaining('sensitive'), findsNothing);
    expect(log.exportJson(), isNot(contains('sensitive')));
    expect(
      tester
          .widget<SfPrimaryButton>(
            find.byKey(const ValueKey('runtime-log-save')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('disabled logs expose no export control', (tester) async {
    await _show(tester, RuntimeLog(enabled: false), _Exporter());
    expect(find.byKey(const ValueKey('runtime-log-save')), findsNothing);
    expect(find.text('内测运行日志已开启'), findsNothing);
  });
}
