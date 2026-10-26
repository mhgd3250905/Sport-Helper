import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_preparer.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/posehub_library_page.dart';
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

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'SDK manual practice gates start, retries and pauses ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 4200);
        tester.view.devicePixelRatio = 2.5;
        addTearDown(tester.view.reset);
        final first = Completer<Uri>();
        final retry = Completer<Uri>();
        var attempts = 0;
        final repo = PoseHubUiRepository(
          mediaBaseUri: base,
          onEnsureAction: (_) => ++attempts == 1 ? first.future : retry.future,
        );
        final services = poseHubUiServices(catalog: catalog, media: repo);
        final action = catalog.pendingActions.first;
        final platform = PoseHubUiVideoPlatform();
        UgkPackedAlphaVideo.debugPlatform = platform;
        UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
        addTearDown(() async {
          UgkPackedAlphaVideo.debugPlatform = null;
          UgkPackedAlphaVideo.debugFilterBuilder = null;
          await platform.close();
          repo.dispose();
        });
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            home: PoseHubSinglePracticePage(
              action: action,
              mediaBaseUri: base,
              mediaPreparer: services.poseHubPreparer,
            ),
          ),
        );
        await tester.pump();
        final start = find.byKey(const ValueKey('posehub-practice-toggle'));
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        await tester.pump(const Duration(seconds: 4));
        expect(find.text('0:00'), findsOneWidget);
        first.completeError(StateError('UI test failure'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('posehub-media-preparation-retry')),
        );
        await tester.pump();
        expect(tester.widget<FilledButton>(start).onPressed, isNull);
        retry.complete(base);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
        expect(find.text('0:00'), findsOneWidget);
        expect(platform.uris, isEmpty);
        await tester.tap(start);
        await tester.pump();
        expect(find.text('暂停'), findsOneWidget);
        expect(platform.uris, [action.video.resolve(base)]);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump();
        expect(find.text('继续'), findsOneWidget);
        expect(
          tester.widget<PoseHubPackMedia>(find.byType(PoseHubPackMedia)).paused,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'local small-image readiness gates the first browser, not videos',
    (tester) async {
      final images = Completer<void>();
      final repo = PoseHubUiRepository(mediaBaseUri: base);
      final services = poseHubUiServices(
        catalog: catalog,
        media: repo,
        imagesReady: images.future,
      );
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.light,
          services: services,
          home: const LibraryPage(),
        ),
      );
      expect(
        find.byKey(const ValueKey('posehub-images-preparing')),
        findsOneWidget,
      );
      images.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PoseHubActionBrowser), findsOneWidget);
      final provider = tester
          .widget<PoseHubActionBrowser>(find.byType(PoseHubActionBrowser))
          .mediaPreparer;
      expect(provider, same(services.poseHubPreparer));
      expect(repo.actionRequests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets('failed local images still allow catalog navigation', (
    tester,
  ) async {
    final images = Completer<void>();
    final repo = PoseHubUiRepository(mediaBaseUri: base);
    final services = poseHubUiServices(
      catalog: catalog,
      media: repo,
      imagesReady: images.future,
    );
    await tester.pumpWidget(
      poseHubUiApp(
        palette: SfPalette.dark,
        services: services,
        home: const LibraryPage(),
      ),
    );
    images.completeError(StateError('UI images failure'));
    await tester.pumpAndSettle();
    expect(find.byType(PoseHubActionBrowser), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    repo.dispose();
  });

  testWidgets(
    'missing cache always supplies a failed gate and disables practice',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final services = poseHubUiServices(catalog: catalog, media: null);
      expect(services.poseHubPreparer, isNotNull);
      expect(services.poseHubPreparer, same(services.poseHubPreparer));
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          home: PoseHubLibraryPage(catalog: catalog),
        ),
      );
      final browser = tester.widget<PoseHubActionBrowser>(
        find.byType(PoseHubActionBrowser),
      );
      expect(browser.mediaPreparer, isNotNull);
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          home: PoseHubSinglePracticePage(
            action: catalog.pendingActions.first,
            mediaBaseUri: base,
            mediaPreparer: browser.mediaPreparer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本机动作缓存暂不可用，请重试。'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('posehub-practice-toggle')),
            )
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('0:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'multi-action clock mounts only after all referenced actions Ready',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final a = catalog.allActions[0];
      final b = catalog.allActions[1];
      final first = Completer<Uri>();
      final second = Completer<Uri>();
      final retry = Completer<Uri>();
      var secondAttempts = 0;
      final repo = PoseHubUiRepository(
        mediaBaseUri: base,
        onEnsureAction: (id) => id == a.id
            ? first.future
            : (++secondAttempts == 1 ? second.future : retry.future),
      );
      final services = poseHubUiServices(
        catalog: catalog,
        media: repo,
        library: ExerciseLibrary([poseHubUiExercise(a), poseHubUiExercise(b)]),
      );
      final plan = TrainingPlan(
        id: 'preflight',
        source: 'test',
        title: '测试训练',
        summary: '',
        goal: 'core',
        scene: 'home',
        equipment: const [],
        level: 1,
        targetMinutes: 2,
        blocks: [
          PlanBlock(
            id: 'main',
            name: '主训练',
            type: BlockType.main,
            rounds: 1,
            restBetweenRoundsSeconds: 0,
            items: [
              for (final id in [a.id, b.id])
                PlanItem(
                  exerciseId: id,
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
      await tester.pumpWidget(
        poseHubUiApp(
          palette: SfPalette.dark,
          services: services,
          home: PlayerPage(plan: plan),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(TrainerPlayer), findsNothing);
      expect(repo.actionRequests, [a.id]);
      first.complete(base);
      await tester.pump();
      expect(repo.actionRequests, [a.id, b.id]);
      expect(find.byType(TrainerPlayer), findsNothing);
      second.completeError(StateError('UI action failure'));
      await tester.pumpAndSettle();
      expect(find.byType(TrainerPlayer), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('posehub-media-preparation-retry')),
      );
      await tester.pump();
      expect(repo.actionRequests, [a.id, b.id, b.id]);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      retry.complete(base);
      await tester.pump();
      expect(find.byType(TrainerPlayer), findsNothing);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(TrainerPlayer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      repo.dispose();
    },
  );
}
