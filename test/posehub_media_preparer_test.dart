import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_preparer.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  final base = Uri.parse('file:///ui-preparation-contract/');
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    SfColors.palette = SfPalette.dark;
  });

  test('100 percent stays Progress until verified future completes', () async {
    final ready = Completer<Uri>();
    final repo = PoseHubUiRepository(
      mediaBaseUri: base,
      onEnsureAction: (_) => ready.future,
    );
    final action = catalog.allActions.first;
    final events = <PoseHubMediaPreparationEvent>[];
    final done = Completer<void>();
    SmartFitPoseHubMediaPreparer(
      repo,
    ).prepareAction(action).listen(events.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);
    final total = action.files.values.fold<int>(
      0,
      (sum, file) => sum + file.bytes,
    );
    repo.setActionState(
      action.id,
      PoseHubDownloadState(
        phase: PoseHubDownloadPhase.downloading,
        receivedBytes: total,
        totalBytes: total,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect((events.last as PoseHubMediaProgress).fraction, 1);
    expect(events.whereType<PoseHubMediaReady>(), isEmpty);
    ready.complete(base);
    await done.future;
    expect(events.whereType<PoseHubMediaReady>().single.mediaBaseUri, base);
    repo.dispose();
  });

  test(
    'cancel retires the consumer without cancelling shared preparation',
    () async {
      final ready = Completer<Uri>();
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (_) => ready.future,
      );
      final action = catalog.allActions.first;
      final events = <PoseHubMediaPreparationEvent>[];
      final subscription = SmartFitPoseHubMediaPreparer(
        repo,
      ).prepareAction(action).listen(events.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      final count = events.length;
      ready.complete(base);
      await Future<void>.delayed(Duration.zero);
      expect(events.length, count);
      expect(repo.actionRequests, [action.id]);
      repo.dispose();
    },
  );

  test('transport failure emits safe Chinese copy and no raw error', () async {
    final repo = PoseHubUiRepository(
      mediaBaseUri: base,
      onEnsureAction: (_) async => throw StateError('private transport trace'),
    );
    final events = await SmartFitPoseHubMediaPreparer(
      repo,
    ).prepareAction(catalog.allActions.first).toList();
    expect(events.last, isA<PoseHubMediaFailed>());
    expect((events.last as PoseHubMediaFailed).reason, '动作资源准备失败，请重试。');
    expect(events.whereType<PoseHubMediaReady>(), isEmpty);
    repo.dispose();
  });

  test(
    'replaced SDK preparation ignores the old action terminal result',
    () async {
      final first = Completer<Uri>();
      final second = Completer<Uri>();
      final a = catalog.allActions[0];
      final b = catalog.allActions[1];
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (id) => id == a.id ? first.future : second.future,
      );
      final preparer = SmartFitPoseHubMediaPreparer(repo);
      final gate = PoseHubMediaPreparationController();
      gate.start(preparer, a);
      gate.start(preparer, b);
      first.complete(base);
      await Future<void>.delayed(Duration.zero);
      expect(gate.state.status, PoseHubMediaPreparationStatus.preparing);
      second.complete(base);
      await Future<void>.delayed(Duration.zero);
      expect(gate.state.status, PoseHubMediaPreparationStatus.ready);
      gate.dispose();
      repo.dispose();
    },
  );
}
