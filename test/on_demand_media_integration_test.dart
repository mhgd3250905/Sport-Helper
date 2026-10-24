import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/training_media_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_media_settings.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'support.dart';

class _Storage implements LocalStateStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

class _Output extends MutedVoiceOutput {
  final spoken = <List<String>>[];
  final chimes = <String>[];
  @override
  Future<void> speak(List<String> assets) async => spoken.add([...assets]);
  @override
  Future<void> chime(String asset) async => chimes.add(asset);
}

Future<trainer.TrainingMediaRepository> _repository({
  bool pending = true,
  trainer.TrainingMediaNetworkProbe? probe,
  void Function(Directory directory)? onCacheDirectory,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'smartfit-media-app-',
  );
  onCacheDirectory?.call(directory);
  addTearDown(() => directory.delete(recursive: true));
  final media = await trainer.TrainingMediaRepository.create(
    manifestAsset: TrainingMediaConfig.manifestAsset,
    baseUrls: const [],
    allowPending: pending,
    cacheDirectory: directory.path,
    networkProbe: probe ?? () async => trainer.TrainingMediaNetwork.offline,
  );
  addTearDown(media.dispose);
  return media;
}

PlanTemplate _template(String exerciseId, [String? secondExerciseId]) =>
    PlanTemplate(
      id: 'media-app-test',
      name: '素材接缝测试',
      summary: '',
      goal: 'mobility',
      scenes: const ['home', 'office'],
      equipment: const [],
      minutes: 5,
      minLevel: 1,
      maxLevel: 3,
      keywords: const [],
      blocks: [
        PlanBlock(
          id: 'main',
          name: '主训练',
          type: BlockType.main,
          rounds: 1,
          restBetweenRoundsSeconds: 0,
          items: [
            for (final id in [exerciseId, ?secondExerciseId])
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

Exercise _exercise(
  String id, {
  List<Equipment> equipment = const [],
  List<String> cautions = const [],
  String position = 'standing',
  int level = 1,
}) => Exercise(
  id: id,
  name: id,
  muscles: const ['髋屈肌'],
  unilateral: false,
  category: ExerciseCategory.mobility,
  equipment: equipment,
  position: position,
  level: level,
  scenes: const ['home', 'office'],
  dose: const Dose(mode: DoseMode.time, sets: 1, seconds: 30, restSeconds: 0),
  repSeconds: null,
  cues: const [],
  cautions: cautions,
  alternative: null,
  media: ExerciseMedia(
    id: id,
    video: 'unused/$id.mp4',
    poster: 'unused/$id.webp',
    loopSeconds: 8,
    posterSeconds: 0,
    source: 'test',
  ),
);

Future<void> _open(
  WidgetTester tester,
  AppServices services,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  addTearDown(() => SfColors.palette = SfPalette.dark);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: trainer.TrainingMediaScope(
        repository: services.media!,
        child: MaterialApp(theme: buildTheme(SfPalette.dark), home: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default content excludes pending actions from both App and AI catalogs',
    () async {
      final (library, _, _, catalog) = await AppServices.loadContent();
      expect(TrainingMediaConfig.includePending, isFalse);
      // This release intentionally has no approved actions yet. Keeping the
      // production gate closed must not leave them in the coach's AI catalog.
      expect(library.all, isEmpty);
      expect(catalog.drills, isEmpty);

      final media = await _repository(pending: false);
      final (withRepository, _, _, coachCatalog) =
          await AppServices.loadContent(media: media);
      expect(media.visibleActions, isEmpty);
      expect(withRepository.all, isEmpty);
      expect(coachCatalog.drills, isEmpty);
      expect(await media.availableActionIds(), isEmpty);
    },
  );

  test(
    'debug pending preview keeps all 93 App actions with new media paths',
    () async {
      final media = await _repository();
      final (library, _, _, catalog) = await AppServices.loadContent(
        media: media,
      );
      final expectedIds = loadPacksSync().exercises.map((e) => e.id).toSet();
      expect(expectedIds, hasLength(93));
      expect(library.all.map((e) => e.id).toSet(), expectedIds);
      expect(catalog.ids.toSet(), expectedIds);
      for (final exercise in library.all) {
        expect(
          exercise.media.video,
          '${TrainingMediaConfig.videoRoot}/${exercise.id}.mp4',
        );
        expect(
          exercise.media.poster,
          '${TrainingMediaConfig.assetRoot}/common-lossy/covers/${exercise.id}.webp',
        );
        expect(exercise.media.lightVideo, isNull);
        expect(exercise.media.lightPoster, isNull);
      }
      final ready = await media.availableActionIds();
      expect(ready, hasLength(32));
      expect(
        (await media.availableVideo('h-squat'))!.assetKey,
        '${TrainingMediaConfig.videoRoot}/h-squat.mp4',
      );
      expect(await media.availableVideo('n-pelvis-circle'), isNull);
    },
  );

  test('offline App generator prefers a bundled demonstration', () async {
    final media = await _repository();
    await media.canDownload();
    final (library, _, voices, _) = await AppServices.loadContent(media: media);
    final services = AppServices(
      library: library,
      catalog: TemplateCatalog([_template('n-pelvis-circle')]),
      store: AppStore(_Storage()),
      voiceLibrary: voices,
      voiceOutput: const MutedVoiceOutput(),
      media: media,
    );
    expect(media.isOffline, isTrue);
    expect(media.readyActionIds, isNot(contains('n-pelvis-circle')));
    final result = await services.generator.generate(
      const ScenarioRequest(scene: 'office', minutes: 5),
    );
    expect(result.issues, isEmpty);
    expect(result.plan, isNotNull);
    expect(result.plan!.items.single.exerciseId, isIn(media.readyActionIds));
    expect(result.plan!.items.single.replacedFrom, 'n-pelvis-circle');
    expect(
      PlanValidator(library).validate(
        result.plan!,
        const ScenarioRequest(scene: 'office', minutes: 5),
      ),
      isEmpty,
    );
  });

  group('offline preference preserves scenario constraints', () {
    final request = const ScenarioRequest(
      scene: 'office',
      minutes: 5,
      avoid: {'膝'},
    );
    final blocked = [
      _exercise('local-band', equipment: [Equipment.band]),
      _exercise('local-knee', cautions: ['膝']),
      _exercise('local-floor', position: 'supine'),
      _exercise('local-hard', level: 3),
    ];
    for (final candidate in blocked) {
      test(
        'rejects preferred ${candidate.id} and keeps a safe remote action',
        () async {
          final library = ExerciseLibrary([_exercise('remote'), candidate]);
          final generator = TemplatePlanGenerator(
            lib: library,
            catalog: TemplateCatalog([_template('remote')]),
            preferredExerciseIds: () => {candidate.id},
          );
          final result = await generator.generate(request);
          expect(result.issues, isEmpty);
          expect(result.plan!.items.single.exerciseId, 'remote');
          expect(
            PlanValidator(library).validate(result.plan!, request),
            isEmpty,
          );
        },
      );
    }

    test(
      'chooses a safe local action ahead of unsafe local candidates',
      () async {
        final library = ExerciseLibrary([
          _exercise('remote'),
          ...blocked,
          _exercise('local-safe'),
        ]);
        final generator = TemplatePlanGenerator(
          lib: library,
          catalog: TemplateCatalog([_template('remote')]),
          preferredExerciseIds: () => {
            for (final e in blocked) e.id,
            'local-safe',
          },
        );
        final result = await generator.generate(request);
        expect(result.issues, isEmpty);
        expect(result.plan!.items.single.exerciseId, 'local-safe');
        expect(PlanValidator(library).validate(result.plan!, request), isEmpty);
      },
    );
  });

  test(
    'non-chat generation prefetches every plan action without awaiting media',
    () async {
      final downloadPolicy = Completer<trainer.TrainingMediaNetwork>();
      var holdDownloads = false;
      var pendingProbes = 0;
      final media = await _repository(
        probe: () async {
          if (!holdDownloads) return trainer.TrainingMediaNetwork.wifi;
          pendingProbes++;
          return downloadPolicy.future;
        },
      );
      final (library, _, voices, _) = await AppServices.loadContent(
        media: media,
      );
      final remoteIds = library.all
          .where(
            (exercise) =>
                exercise.category == ExerciseCategory.mobility &&
                !exercise.unilateral &&
                exercise.scenes.contains('home') &&
                exercise.level <= 2 &&
                !media.readyActionIds.contains(exercise.id),
          )
          .map((e) => e.id)
          .take(2)
          .toList();
      expect(remoteIds, hasLength(2));
      final services = AppServices(
        library: library,
        catalog: TemplateCatalog([_template(remoteIds.first, remoteIds.last)]),
        store: AppStore(_Storage()),
        voiceLibrary: voices,
        voiceOutput: const MutedVoiceOutput(),
        media: media,
      );
      addTearDown(() async {
        if (!downloadPolicy.isCompleted) {
          downloadPolicy.complete(trainer.TrainingMediaNetwork.offline);
        }
        await media.prefetchActions(remoteIds);
      });
      holdDownloads = true;
      // Do not initialize chat or attach a chat listener. This is the custom
      // form's generator seam and must schedule all downloads on its own.
      final result = await services.generator
          .generate(const ScenarioRequest(minutes: 5))
          .timeout(const Duration(seconds: 2));
      expect(result.issues, isEmpty);
      expect(
        result.plan!.items.map((item) => item.exerciseId).toSet(),
        remoteIds.toSet(),
      );
      for (var i = 0; i < 100 && pendingProbes < remoteIds.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(downloadPolicy.isCompleted, isFalse);
      expect(pendingProbes, greaterThanOrEqualTo(remoteIds.length));
      for (final id in remoteIds) {
        expect(
          media.stateFor(id).phase,
          trainer.TrainingMediaPhase.queued,
          reason: '$id must be prefetched while the network is still pending',
        );
      }
    },
  );

  test('chat plan prefetch includes ordered segment media', () async {
    final downloadPolicy = Completer<trainer.TrainingMediaNetwork>();
    var holdDownloads = false;
    var pendingProbes = 0;
    final media = await _repository(
      probe: () async {
        if (!holdDownloads) return trainer.TrainingMediaNetwork.wifi;
        pendingProbes++;
        return downloadPolicy.future;
      },
    );
    final (library, catalog, voices, _) = await AppServices.loadContent(
      media: media,
    );
    final ids = library.all
        .where((exercise) => !media.readyActionIds.contains(exercise.id))
        .map((exercise) => exercise.id)
        .take(2)
        .toList();
    expect(ids, hasLength(2));
    final plan = TrainingPlan(
      id: 'segment-media',
      source: 'template',
      title: '分段预取',
      summary: '',
      goal: 'mobility',
      scene: 'home',
      equipment: const [],
      level: 1,
      targetMinutes: 5,
      blocks: [
        PlanBlock(
          id: 'main',
          name: '主训练',
          type: BlockType.main,
          rounds: 1,
          restBetweenRoundsSeconds: 0,
          items: [
            PlanItem(
              exerciseId: ids.first,
              mode: DoseMode.time,
              sets: 1,
              perSide: false,
              restSeconds: 0,
              segments: [
                coach.PlanSegment(
                  id: 'part',
                  exerciseId: ids.last,
                  mode: coach.DoseMode.time,
                  workSeconds: 10,
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final services = AppServices(
      library: library,
      catalog: catalog,
      store: AppStore(_Storage()),
      voiceLibrary: voices,
      voiceOutput: const MutedVoiceOutput(),
      media: media,
    );
    addTearDown(() async {
      if (!downloadPolicy.isCompleted) {
        downloadPolicy.complete(trainer.TrainingMediaNetwork.offline);
      }
      await media.prefetchActions(ids);
    });
    holdDownloads = true;
    services.prefetchPlan(plan);
    for (var i = 0; i < 100 && pendingProbes < ids.length; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(pendingProbes, greaterThanOrEqualTo(ids.length));
    for (final id in ids) {
      expect(media.stateFor(id).phase, trainer.TrainingMediaPhase.queued);
    }
  });

  testWidgets('pending then failed prefetch never blocks plan, timer or speech', (
    tester,
  ) async {
    final downloadPolicy = Completer<trainer.TrainingMediaNetwork>();
    addTearDown(() {
      if (!downloadPolicy.isCompleted) {
        downloadPolicy.complete(trainer.TrainingMediaNetwork.offline);
      }
    });
    var probes = 0;
    int? holdFromProbe;
    final media = (await tester.runAsync(
      () => _repository(
        probe: () async {
          probes++;
          return holdFromProbe == null || probes < holdFromProbe
              ? trainer.TrainingMediaNetwork.wifi
              : downloadPolicy.future;
        },
      ),
    ))!;
    final content = (await tester.runAsync(
      () => AppServices.loadContent(media: media),
    ))!;
    final holdAfter = probes + 2; // Refresh for the reply, then hold prefetch.
    holdFromProbe = holdAfter;
    final output = _Output();
    final services = AppServices(
      library: content.$1,
      catalog: TemplateCatalog([_template('n-pelvis-circle')]),
      store: AppStore(_Storage())..starfield = false,
      voiceLibrary: content.$3,
      voiceOutput: output,
      media: media,
      chatReplyDelay: Duration.zero,
    );
    addTearDown(services.chat.dispose);
    await services.store.acceptSafety(blocked: false);
    services.chat.start();
    await tester.runAsync(() async {
      await services.chat.send('在家 5 分钟练灵活，徒手，新手');
      for (var i = 0; i < 100 && probes < holdAfter; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    final plan = services.chat.currentPlan;
    expect(plan, isNotNull);
    expect(plan!.items.single.exerciseId, 'n-pelvis-circle');
    expect(probes, greaterThanOrEqualTo(holdAfter));
    expect(
      downloadPolicy.isCompleted,
      isFalse,
      reason: 'The plan is available while background prefetch is pending.',
    );
    await _open(tester, services, PlayerPage(plan: plan));
    expect(find.text('正在加载动作视频'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                '${TrainingMediaConfig.assetRoot}/common-lossy/covers/n-pelvis-circle.webp',
      ),
      findsOneWidget,
    );
    final initialCounter = tester
        .widget<trainer.TrainerCountdownDigits>(
          find.byType(trainer.TrainerCountdownDigits),
        )
        .value;
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(
      tester
          .widget<trainer.TrainerCountdownDigits>(
            find.byType(trainer.TrainerCountdownDigits),
          )
          .value,
      isNot(initialCounter),
    );
    expect(output.spoken, isNotEmpty);

    downloadPolicy.complete(trainer.TrainingMediaNetwork.offline);
    await tester.runAsync(() => media.prefetchActions(['n-pelvis-circle']));
    await tester.pump();
    expect(
      media.stateFor('n-pelvis-circle').phase,
      trainer.TrainingMediaPhase.offline,
    );
    expect(find.text('正在加载动作视频'), findsNothing);
    expect(find.text('示范暂时加载不了，计时和语音仍可继续'), findsOneWidget);
    final spokenBefore = output.spoken.length;
    final chimesBefore = output.chimes.length;
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(output.spoken.length, greaterThan(spokenBefore));
    expect(output.chimes.length, greaterThan(chimesBefore));
    expect(find.byKey(const ValueKey('pause')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'media settings persist Wi-Fi policy and preserve user data on clear',
    (tester) async {
      late Directory cacheDirectory;
      final media = (await tester.runAsync(
        () => _repository(
          onCacheDirectory: (directory) => cacheDirectory = directory,
        ),
      ))!;
      // Orphaned bytes from an older download still occupy disk space.
      // Exercise actual removal rather than clearing an already empty cache.
      final staleBlob = File(
        '${cacheDirectory.path}/training-media/${media.manifest.version}/'
        '${List.filled(64, '0').join()}',
      );
      await tester.runAsync(() async {
        await staleBlob.parent.create(recursive: true);
        await staleBlob.writeAsBytes(List.filled(1000000, 0));
      });
      expect(await tester.runAsync(media.cacheBytes), 1000000);
      final content = (await tester.runAsync(
        () => AppServices.loadContent(media: media),
      ))!;
      final storage = _Storage();
      final store = AppStore(storage);
      final services = AppServices(
        library: content.$1,
        catalog: content.$2,
        store: store,
        voiceLibrary: content.$3,
        voiceOutput: const MutedVoiceOutput(),
        media: media,
      );
      final plan = (await services.generator.generate(
        const ScenarioRequest(templateId: 'office-relax', scene: 'office'),
      )).plan!;
      await store.savePlan(plan);
      await store.rememberPlan(plan);
      await store.addHistory(
        HistoryEntry(
          title: plan.title,
          at: DateTime.utc(2026, 10, 22),
          minutes: 8,
          completed: 1,
          total: 2,
        ),
      );
      await _open(
        tester,
        services,
        const Scaffold(
          body: SingleChildScrollView(child: TrainingMediaSettings()),
        ),
      );
      final usage = find.text('已用缓存 1.0 MB');
      for (var i = 0; i < 1000 && usage.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(usage, findsOneWidget);
      final toggle = find.byKey(const ValueKey('media-wifi-only'));
      expect(tester.widget<SfSwitchRow>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(media.wifiOnly, isFalse);
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(reloaded.mediaWifiOnly, isFalse);
      await tester.tap(find.byKey(const ValueKey('media-clear-cache')));
      final cleared = find.text('缓存已清理，内置动作、计划和训练记录保留');
      for (var i = 0; i < 1000 && cleared.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(cleared, findsOneWidget);
      expect(await tester.runAsync(media.cacheBytes), 0);
      expect(await tester.runAsync(staleBlob.exists), isFalse);
      expect(media.readyActionIds, hasLength(32));
      await reloaded.load();
      expect(reloaded.savedPlans.single.plan.id, plan.id);
      expect(reloaded.lastPlan!.id, plan.id);
      expect(reloaded.history.single.completed, 1);
      expect(reloaded.mediaWifiOnly, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
