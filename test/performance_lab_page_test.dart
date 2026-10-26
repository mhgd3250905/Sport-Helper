import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_report.dart';
import 'package:smartfit/ui/performance_lab_page.dart';
import 'package:smartfit/ui/theme.dart';

void main() {
  testWidgets(
    'ten fixed real-workload cells retain normal appearance and no experiment switches',
    (tester) async {
      final recorder = FrameRecorder(enabled: true);
      addTearDown(recorder.stop);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(SfPalette.light),
          home: PerformanceLabPage(
            service: PerformanceReportService(recorder: recorder),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('performance-case-light-planCardScroll')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('performance-case-dark-trainingPlayback')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('performance-case-dark-trainingPlayback')),
        findsOneWidget,
      );
      expect(recorder.status()['caseIds'], isEmpty);
    },
  );
  testWidgets('production has no diagnostic page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PerformanceLabPage(
          service: PerformanceReportService(
            recorder: FrameRecorder(enabled: false),
          ),
        ),
      ),
    );
    expect(find.text('实色界面性能采样'), findsNothing);
  });
  test('scroll protocol remains the existing fixed 32 second workload', () {
    expect(
      PerformanceScrollProtocol.sampleDuration,
      const Duration(seconds: 32),
    );
    expect(PerformanceScrollProtocol.legDuration, const Duration(seconds: 4));
    expect(PerformanceScrollProtocol.distance, 3200);
    expect(
      PerformanceScrollProtocol.tailDeliveryDelay,
      const Duration(milliseconds: 1200),
    );
    expect(
      performanceScenarios.keys.toList(),
      FrameRecorder.acceptanceScenarios,
    );
  });
}
