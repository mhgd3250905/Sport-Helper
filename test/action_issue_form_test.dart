import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/action_issue.dart';
import 'package:smartfit/diagnostics/action_issue_store.dart';
import 'package:smartfit/ui/action_issue_form.dart';
import 'package:smartfit/ui/theme.dart';

class _Storage implements LocalStateStorage {
  String? value;
  Completer<void>? gate;
  var failures = 0;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    if (gate case final pending?) await pending.future;
    if (failures > 0) {
      failures--;
      throw StateError('write failed');
    }
    this.value = value;
  }
}

Future<void> _show(
  WidgetTester tester, {
  required LocalActionIssueStore store,
  required List<ActionIssue> saved,
  bool dark = false,
  bool unavailable = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildTheme(dark ? SfPalette.dark : SfPalette.light),
    home: Scaffold(
      body: ActionIssueForm(
        store: store,
        capture: ActionIssueContext(
          actionId: 'test-action-01',
          revision: 'fixture-r2',
          videoSeconds: unavailable ? null : 4.25,
          videoPositionUnavailableReason: unavailable
              ? ActionIssueVideoUnavailableReason.notReady
              : null,
          capturedAt: DateTime.utc(2026, 10, 25, 8),
        ),
        onSaved: saved.add,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'light form saves optional tags and a note only after durable write',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<void>();
      final storage = _Storage()..gate = gate;
      final store = LocalActionIssueStore(storage, enabled: true);
      final saved = <ActionIssue>[];
      await _show(tester, store: store, saved: saved);
      expect(find.text('视频时间：4.25 秒'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('action-issue-tag-pose')));
      await tester.tap(find.byKey(const ValueKey('action-issue-tag-framing')));
      await tester.enterText(
        find.byKey(const ValueKey('action-issue-note')),
        '抬手时被裁切',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('action-issue-save')),
      );
      await tester.tap(find.byKey(const ValueKey('action-issue-save')));
      await tester.pump();
      expect(saved, isEmpty);
      expect(
        tester
            .widget<SfPrimaryButton>(
              find.byKey(const ValueKey('action-issue-save')),
            )
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(saved.single.tags, [ActionIssueTag.pose, ActionIssueTag.framing]);
      expect(saved.single.note, '抬手时被裁切');
      expect(saved.single.capture.videoSeconds, 4.25);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dark form explains null video time and retains content for retry',
    (tester) async {
      final storage = _Storage()..failures = 1;
      final store = LocalActionIssueStore(storage, enabled: true);
      final saved = <ActionIssue>[];
      await _show(
        tester,
        store: store,
        saved: saved,
        dark: true,
        unavailable: true,
      );
      expect(find.text('视频时间：未记录（视频尚未就绪）'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('action-issue-note')),
        '静帧名称不对',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('action-issue-save')),
      );
      await tester.tap(find.byKey(const ValueKey('action-issue-save')));
      await tester.pumpAndSettle();
      expect(find.text('保存失败，内容还在，请重试。'), findsOneWidget);
      expect(saved, isEmpty);
      expect(find.text('静帧名称不对'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('action-issue-save')));
      await tester.pumpAndSettle();
      expect(saved.single.tags, isEmpty);
      expect(saved.single.capture.videoSeconds, isNull);
      expect(
        saved.single.capture.videoPositionUnavailableReason,
        ActionIssueVideoUnavailableReason.notReady,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disabled review shows no form or action', (tester) async {
    await _show(
      tester,
      store: LocalActionIssueStore(_Storage(), enabled: false),
      saved: [],
    );
    expect(find.text('标记动作问题'), findsNothing);
    expect(find.byKey(const ValueKey('action-issue-save')), findsNothing);
  });
}
