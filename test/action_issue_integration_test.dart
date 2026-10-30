import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/training_media_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/action_issue.dart';
import 'package:smartfit/diagnostics/action_issue_export.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/action_issue_actions.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show DrillMediaPlaybackSnapshot;

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

// Synthetic review fixtures have no dependency on any export/sample directory.
Exercise _exercise(
  String id, {
  bool videoAvailable = false,
  String? revision,
}) => Exercise(
  id: id,
  name: id == 'test-a' ? '测试抬手' : '测试转身',
  muscles: const ['肩部'],
  unilateral: false,
  category: ExerciseCategory.mobility,
  equipment: const [],
  position: 'standing',
  level: 1,
  scenes: const ['home'],
  dose: const Dose(mode: DoseMode.time, sets: 1, seconds: 30, restSeconds: 0),
  repSeconds: null,
  cues: const ['自然呼吸'],
  cautions: const [],
  alternative: null,
  media: ExerciseMedia(
    id: id,
    video: '',
    poster: '',
    loopSeconds: 8,
    posterSeconds: 0,
    source: 'synthetic fixture',
    videoAvailable: videoAvailable,
    lightVideoAvailable: videoAvailable,
    revision: revision,
  ),
);

class _Library extends ExerciseLibrary {
  _Library() : super([_exercise('test-a'), _exercise('test-b')]);
  String? lookedUp;
  @override
  Exercise? tryGet(String id) {
    lookedUp = id;
    return super.tryGet(id);
  }
}

AppServices _services(_Storage storage, {bool enabled = true}) => AppServices(
  library: ExerciseLibrary([_exercise('test-a'), _exercise('test-b')]),
  catalog: TemplateCatalog([]),
  store: AppStore(storage, actionIssueEnabled: enabled)..starfield = false,
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
);

TrainingPlan _plan() => const TrainingPlan(
  id: 'test-plan',
  source: 'template',
  title: '测试训练',
  summary: '',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '活动开',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'test-a',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 0,
        ),
        PlanItem(
          exerciseId: 'test-b',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 30,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

Future<void> _show(
  WidgetTester tester,
  AppServices services,
  Widget page,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(SfPalette.light),
        builder: (context, child) => SfPaletteScope(child: child!),
        home: page,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(
      AndroidActionIssueExporter.channel,
      null,
    );
    SfColors.palette = SfPalette.dark;
  });

  test(
    'snapshot identity and timestamp win over the current action after a switch',
    () async {
      final library = _Library();
      final captured = Completer<DrillMediaPlaybackSnapshot?>();
      final result = captureActionIssueContext(
        actionIdAtTap: 'test-b',
        library: library,
        capturePlayback: () => captured.future,
        light: false,
        capturedAt: DateTime.utc(2026, 10, 25, 8),
      );
      final actual = DateTime.utc(2026, 10, 25, 8, 0, 0, 30);
      captured.complete(
        DrillMediaPlaybackSnapshot(
          mediaId: 'test-a',
          videoSeconds: 2.75,
          ready: true,
          capturedAt: actual,
        ),
      );
      final context = await result;
      expect(library.lookedUp, 'test-a');
      expect(context.actionId, 'test-a');
      expect(context.videoSeconds, 2.75);
      expect(context.capturedAt, actual);
    },
  );

  test(
    'unbound playback records null position with not-ready reason',
    () async {
      final at = DateTime.utc(2026, 10, 25, 8);
      final context = await captureActionIssueContext(
        actionIdAtTap: 'test-a',
        library: ExerciseLibrary([_exercise('test-a', videoAvailable: true)]),
        capturePlayback: () async => null,
        light: true,
        capturedAt: at,
      );
      expect(context.videoSeconds, isNull);
      expect(
        context.videoPositionUnavailableReason,
        ActionIssueVideoUnavailableReason.notReady,
      );
      expect(context.capturedAt, at);
      expect(context.revision, isNull);
      expect(context.revisionUnavailableReason, 'metadata_not_available');
    },
  );

  test(
    'real media revision follows the captured action into persistence',
    () async {
      final context = await captureActionIssueContext(
        actionIdAtTap: 'test-b',
        library: ExerciseLibrary([
          _exercise('test-a', revision: 'fixture-action-a-r3'),
          _exercise('test-b', revision: 'fixture-action-b-r8'),
        ]),
        capturePlayback: () async => DrillMediaPlaybackSnapshot(
          mediaId: 'test-a',
          videoSeconds: 3.25,
          ready: true,
          capturedAt: DateTime.utc(2026, 10, 25, 8),
        ),
        light: false,
      );
      expect(context.actionId, 'test-a');
      expect(context.revision, 'fixture-action-a-r3');
      expect(context.revisionUnavailableReason, isNull);
      final store = AppStore(
        _Storage(),
        actionIssueEnabled: true,
      ).actionIssueStore;
      final saved = await store.add(context);
      expect(saved.toJson()['revision'], 'fixture-action-a-r3');
      expect(saved.toJson()['revisionUnavailableReason'], isNull);
    },
  );

  testWidgets(
    'internal player marker uses its media handle and avoids training controls',
    (tester) async {
      addTearDown(tester.view.reset);
      final storage = _Storage();
      final services = _services(storage);
      await _show(tester, services, PlayerPage(plan: _plan()));
      final marker = find.byKey(const ValueKey('player-action-issue'));
      final rect = tester.getRect(marker);
      for (final key in [
        'pause',
        'discomfort',
        'prev',
        'skip',
        'top-hud',
        'counter',
      ]) {
        expect(
          rect.overlaps(tester.getRect(find.byKey(ValueKey(key)))),
          isFalse,
          reason: key,
        );
      }
      final handle = tester
          .widget<ExerciseVideo>(find.byType(ExerciseVideo))
          .playbackHandle;
      expect(handle, isNotNull);
      await tester.tap(marker);
      await tester.pumpAndSettle();
      expect(find.text('动作：test-a'), findsOneWidget);
      expect(find.text('视频时间：未记录（这个动作没有视频）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('action-issue-tag-clipping')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('action-issue-save')),
      );
      await tester.tap(find.byKey(const ValueKey('action-issue-save')));
      await tester.pumpAndSettle();
      expect(
        services.store.actionIssueStore.records.single.capture.actionId,
        'test-a',
      );
      final restarted = AppStore(storage, actionIssueEnabled: true);
      await restarted.actionIssueStore.load();
      expect(restarted.actionIssueStore.count, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await handle!.capture(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'internal library popup owns and disposes a separate review handle',
    (tester) async {
      addTearDown(tester.view.reset);
      final services = _services(_Storage());
      await _show(tester, services, const LibraryPage());
      await tester.tap(find.text('测试抬手'));
      await tester.pumpAndSettle();
      final handle = tester
          .widget<ExerciseVideo>(find.byType(ExerciseVideo))
          .playbackHandle;
      expect(handle, isNotNull);
      final marker = find.byKey(const ValueKey('library-action-issue'));
      await tester.ensureVisible(marker);
      await tester.tap(marker);
      await tester.pumpAndSettle();
      expect(find.text('动作：test-a'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('action-issue-note')),
        '名称需要复核',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('action-issue-save')),
      );
      await tester.tap(find.byKey(const ValueKey('action-issue-save')));
      await tester.pumpAndSettle();
      expect(services.store.actionIssueStore.records.single.note, '名称需要复核');
      Navigator.of(tester.element(find.byType(LibraryPage))).pop();
      await tester.pumpAndSettle();
      expect(await handle!.capture(), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('production hides player, library and settings review entries', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final services = _services(_Storage(), enabled: false);
    expect(
      AppStore(_Storage()).actionIssueStore.enabled,
      actionIssueBuildEnabled,
    );
    await _show(tester, services, PlayerPage(plan: _plan()));
    expect(find.byKey(const ValueKey('player-action-issue')), findsNothing);
    expect(
      tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).playbackHandle,
      isNull,
    );
    await _show(tester, services, const LibraryPage());
    await tester.tap(find.text('测试抬手'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('library-action-issue')), findsNothing);
    await _show(tester, services, const AboutPage());
    expect(find.byKey(const ValueKey('action-issues-export')), findsNothing);
    expect(find.text('动作问题标记（内测）'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'settings saves directly to Downloads and permits retry after failure',
    (tester) async {
      addTearDown(tester.view.reset);
      final services = _services(_Storage());
      await services.store.actionIssueStore.add(
        ActionIssueContext(
          actionId: 'test-a',
          revision: 'fixture-r2',
          videoSeconds: 4.5,
        ),
      );
      var attempts = 0;
      messenger.setMockMethodCallHandler(AndroidActionIssueExporter.channel, (
        call,
      ) async {
        expect(call.method, 'saveToDownloads');
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final report = jsonDecode(args['contents'] as String) as Map;
        expect((report['issues'] as List).single['actionId'], 'test-a');
        if (++attempts == 1) throw PlatformException(code: 'write_failed');
        return {
          'uri': 'content://media/external/downloads/123',
          'displayName': args['filename'],
        };
      });
      await _show(tester, services, const AboutPage());
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('action-issues-open')), 250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('action-issues-open')));
      await tester.pumpAndSettle();
      final export = find.byKey(const ValueKey('action-issues-export'));
      await tester.ensureVisible(export);
      await tester.pumpAndSettle();
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.text('保存到下载失败，标记仍保存在本机，请重试。'), findsOneWidget);
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('已保存到下载：Download/SmartFit/SmartFit-action-issues-'),
        findsOneWidget,
      );
      expect(attempts, 2);
      expect(services.store.actionIssueStore.count, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !TrainingMediaConfig.isInternal,
  );
}
