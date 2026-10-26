import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/action_issue.dart';
import 'package:smartfit/diagnostics/action_issue_store.dart';

import 'app_flow_test.dart' show MemoryStorage;

ActionIssueContext capture() => ActionIssueContext(
  actionId: 'fixture',
  revision: 'r1',
  videoSeconds: null,
  videoPositionUnavailableReason: ActionIssueVideoUnavailableReason.notReady,
);

void main() {
  test(
    'bad preference preserves valid historical exports and can be repaired',
    () async {
      final storage = MemoryStorage();
      final initial = LocalActionIssueStore(storage, enabled: true);
      await initial.add(capture(), note: 'preserved');
      final records = storage.data[LocalActionIssueStore.storageKey];
      storage.data[LocalActionIssueStore.recordingKey] = 'broken';
      final restarted = LocalActionIssueStore(storage, enabled: true);
      await restarted.loadRecordingPreference();
      expect(restarted.enabled, isFalse);
      expect((await restarted.snapshot()).single.note, 'preserved');
      expect(storage.data[LocalActionIssueStore.recordingKey], 'broken');
      expect(storage.data[LocalActionIssueStore.storageKey], records);
      await restarted.setRecordingEnabled(false);
      expect(storage.data[LocalActionIssueStore.recordingKey], 'false');
      await restarted.setRecordingEnabled(true);
      expect(restarted.enabled, isTrue);
      expect(storage.data[LocalActionIssueStore.storageKey], records);
    },
  );

  test(
    'recording preference persists without altering records or user data',
    () async {
      final storage = MemoryStorage();
      storage.data['unrelated'] = 'keep';
      final store = LocalActionIssueStore(storage, enabled: true);
      await store.add(capture(), note: 'existing');
      final records = storage.data[LocalActionIssueStore.storageKey];
      await store.setRecordingEnabled(false);
      expect(store.available, isTrue);
      expect(store.enabled, isFalse);
      expect((await store.snapshot()).single.note, 'existing');
      await expectLater(store.add(capture()), throwsStateError);
      final restarted = LocalActionIssueStore(storage, enabled: true);
      await restarted.load();
      expect(restarted.enabled, isFalse);
      expect(storage.data[LocalActionIssueStore.storageKey], records);
      expect(storage.data['unrelated'], 'keep');
      await restarted.setRecordingEnabled(true);
      await restarted.add(capture());
      expect((await restarted.snapshot()).length, 2);
    },
  );

  test(
    'preference cannot enable a build without the internal capability',
    () async {
      final storage = MemoryStorage();
      final store = LocalActionIssueStore(storage, enabled: false);
      await expectLater(store.setRecordingEnabled(true), throwsStateError);
      await expectLater(store.snapshot(), throwsStateError);
      expect(store.enabled, isFalse);
      expect(storage.data, isEmpty);
    },
  );
}
