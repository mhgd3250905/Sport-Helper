import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/packs/drill_pack.dart';
import 'package:smartfit/ui/chat/cosmos.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'support.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Output extends MutedVoiceOutput {
  final spoken = <List<String>>[];
  final chimes = <String>[];
  @override
  Future<void> speak(List<String> assets) async => spoken.add([...assets]);
  @override
  Future<void> chime(String asset) async => chimes.add(asset);
}

TrainingPlan _plan({String id = 'h-forearm-plank', bool reps = false}) =>
    TrainingPlan(
      id: 'trainer-integration-$id',
      source: 'template',
      title: '接入验收训练',
      summary: '',
      goal: 'mixed',
      scene: 'home',
      equipment: const [],
      level: 1,
      targetMinutes: 1,
      blocks: [
        PlanBlock(
          id: 'main',
          name: '主训练',
          type: BlockType.main,
          rounds: 1,
          restBetweenRoundsSeconds: 0,
          items: [
            PlanItem(
              exerciseId: id,
              mode: reps ? DoseMode.reps : DoseMode.time,
              sets: 1,
              reps: reps ? 3 : null,
              workSeconds: reps ? null : 2,
              perSide: false,
              restSeconds: 0,
            ),
          ],
        ),
      ],
    );

AppServices _services({
  required _Storage storage,
  ExerciseLibrary? library,
  _Output? output,
}) => AppServices(
  library: library ?? loadLibrary(),
  catalog: loadCatalog(),
  store: AppStore(storage)..starfield = false,
  voiceLibrary: loadVoices(),
  voiceOutput: output ?? _Output(),
  chatReplyDelay: Duration.zero,
);

Future<void> _open(
  WidgetTester tester,
  AppServices services,
  TrainingPlan plan, {
  SfPalette palette = SfPalette.dark,
  List<trainer.SessionResult>? returned,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  addTearDown(() => SfColors.palette = SfPalette.dark);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(palette),
        builder: (context, child) => SfPaletteScope(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .push<trainer.SessionResult>(
                      MaterialPageRoute(builder: (_) => PlayerPage(plan: plan)),
                    );
                if (result != null) returned?.add(result);
              },
              child: const Text('打开训练'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开训练'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _advance(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets(
    'missing repSeconds counts automatically with trainer default pacing',
    (tester) async {
      final packs = loadPacksSync();
      final squat = packs.exercises.firstWhere((p) => p.id == 'h-squat');
      // Missing pacing metadata uses the SDK's default 3 seconds per rep.
      // The video's loop length must not become a repetition duration.
      final media = Map<String, dynamic>.from(squat.json['media'] as Map)
        ..remove('repSeconds');
      final withoutRhythm = DrillPack.fromJson({
        ...squat.json,
        'media': media,
      }, folder: squat.folder);
      final library = ExerciseLibrary.fromPacks(
        PackSet(packs.common, [withoutRhythm]),
      );
      expect(library['h-squat'].repSeconds, isNull);
      final s = _services(storage: _Storage(), library: library);
      await _open(tester, s, _plan(id: 'h-squat', reps: true));
      await _advance(
        tester,
        15,
      ); // 10 seconds prep, then part of 3 × 3 seconds.
      expect(find.byKey(const ValueKey('complete-set-button')), findsNothing);
      expect(find.text('练完了！'), findsNothing);
      expect(s.store.sessionResults, isEmpty);
      expect(s.store.history, isEmpty);
      await _advance(tester, 6);
      expect(find.text('练完了！'), findsOneWidget);
      final result = s.store.sessionResults.single;
      expect(result.full, isTrue);
      expect(result.items.single.completedSets, 1);
      expect(result.items.single.status, trainer.ItemStatus.completed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordered segments play their own media and save one completed parent set',
    (tester) async {
      final base = _plan(id: 'h-squat', reps: true);
      final plan = base.copyWith(
        blocks: [
          base.blocks.single.copyWith(
            items: [
              PlanItem(
                exerciseId: 'h-squat',
                mode: DoseMode.reps,
                sets: 1,
                perSide: false,
                restSeconds: 0,
                segments: const [
                  coach.PlanSegment(
                    id: 'plank',
                    exerciseId: 'h-forearm-plank',
                    mode: coach.DoseMode.time,
                    workSeconds: 10,
                  ),
                  coach.PlanSegment(
                    id: 'wall',
                    exerciseId: 'w-wall-sit',
                    mode: coach.DoseMode.time,
                    workSeconds: 10,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final storage = _Storage();
      final s = _services(storage: storage);
      await s.store.rememberPlan(plan);
      await _open(tester, s, plan);
      await _advance(tester, 11);
      expect(
        tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).exercise.id,
        'h-forearm-plank',
      );
      await _advance(tester, 10);
      expect(
        tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).exercise.id,
        'w-wall-sit',
      );
      expect(s.store.sessionResults, isEmpty);
      await _advance(tester, 11);
      final result = s.store.sessionResults.single;
      expect(result.full, isTrue);
      expect(result.items, hasLength(1));
      expect(result.items.single.exerciseId, 'h-squat');
      expect(result.items.single.completedSets, 1);
      expect(result.items.single.activeSeconds, closeTo(20, .1));
      expect(s.store.lastPlan!.items.single.segments, hasLength(2));
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(
        reloaded.lastPlan!.items.single.segments.map(
          (segment) => segment.exerciseId,
        ),
        ['h-forearm-plank', 'w-wall-sit'],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'natural completion returns and reloads the same saved session id',
    (tester) async {
      final storage = _Storage();
      final s = _services(storage: storage);
      final returned = <trainer.SessionResult>[];
      await _open(tester, s, _plan(), returned: returned);
      await _advance(tester, 15); // Default preparation + timed work.
      expect(find.text('练完了！'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('completion-celebration')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<trainer.TrainerPlayer>(find.byType(trainer.TrainerPlayer))
            .feedbackBuilder,
        isNull,
      );
      final result = s.store.sessionResults.single;
      expect(result.full, isTrue);
      expect(result.endedEarly, isFalse);
      expect(result.completedExercises, 1);
      expect(s.store.history.single.sessionId, result.sessionId);
      await tester.tap(find.byKey(const ValueKey('finish')));
      await tester.pumpAndSettle();
      expect(returned.single.sessionId, result.sessionId);
      expect(s.store.history, hasLength(1));
      // The same result can safely reach the App callback again.
      await s.store.saveSession(result);
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(reloaded.history, hasLength(1));
      expect(reloaded.sessionResults, hasLength(1));
      expect(reloaded.history.single.sessionId, result.sessionId);
      expect(reloaded.sessionResults.single.toJson(), result.toJson());
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final palette in [SfPalette.dark, SfPalette.light]) {
    testWidgets(
      'retains ${palette.brightness.name} SDK styling with brand accent, media and language',
      (tester) async {
        final output = _Output();
        final s = _services(storage: _Storage(), output: output);
        s.store.voice = const VoiceSettings(
          language: VoiceLanguage.en,
          volume: .4,
        );
        await _open(tester, s, _plan(), palette: palette);
        final player = tester.widget<trainer.TrainerPlayer>(
          find.byType(trainer.TrainerPlayer),
        );
        final defaults = palette.isDark
            ? trainer.TrainerTheme.dark
            : trainer.TrainerTheme.light;
        expect(player.theme.brightness, palette.brightness);
        expect(player.theme.background, defaults.background);
        expect(player.theme.surface, defaults.surface);
        expect(player.theme.surfaceHigh, defaults.surfaceHigh);
        expect(player.theme.border, defaults.border);
        expect(player.theme.shadow, defaults.shadow);
        expect(player.theme.track, defaults.track);
        expect(player.theme.track.a, 1);
        expect(player.theme.ringKnob, defaults.ringKnob);
        expect(player.theme.cardSurface, defaults.cardSurface);
        expect(player.theme.cardBorder, defaults.cardBorder);
        expect(player.theme.primaryForeground, const Color(0xFFFFFFFF));
        expect(player.theme.accent, palette.accent);
        expect(player.theme.accentSubtle, palette.accentSoft);
        expect(player.theme.pausedColor, palette.accent);
        expect(player.theme.onPaused, palette.onAccent);
        expect(player.theme.fontFamily, sfFontFamily);
        expect(player.voice!.source, same(s.voiceLibrary));
        expect(player.voice!.output, same(output));
        expect(player.voice!.settings.language, 'en');
        expect(player.voice!.settings.volume, .4);
        expect(player.strings.completeSet, '完成本组');
        expect(player.startMode, trainer.TrainerStartMode.training);
        expect(find.byKey(const ValueKey('start-training')), findsNothing);
        expect(player.feedbackBuilder, isNull);
        expect(player.onCompleted, isNotNull);
        expect(
          player.drillOf('h-forearm-plank')!.name,
          s.library['h-forearm-plank'].name,
        );
        final drill = player.drillOf('h-forearm-plank')!;
        final exercise = s.library['h-forearm-plank'];
        expect(drill.cues, exercise.cues);
        expect(drill.precautions, exercise.cautions);
        expect(drill.targetMuscles, exercise.muscles.join('、'));
        expect(
          drill.thumbnailAsset,
          palette.isDark
              ? exercise.media.poster
              : exercise.media.lightPoster ?? exercise.media.poster,
        );
        // The shared next-up card reads TrainerDrill.media directly,
        // independently of the App's main mediaBuilder slot.
        final media = player.drillOf('h-forearm-plank')!.media!;
        final source = s.library['h-forearm-plank'].media;
        expect(media.videoAsset, source.video);
        expect(media.posterAsset, source.poster);
        expect(media.lightVideoAsset, source.lightVideo);
        expect(media.lightPosterAsset, source.lightPoster);
        expect(media.duration, source.loopSeconds);
        expect(media.posterTime, source.posterSeconds);
        expect(
          media.posterFor(light: !palette.isDark),
          palette.isDark ? source.poster : source.lightPoster ?? source.poster,
        );
        expect(find.byType(CosmosBackground), findsNothing);
        final video = tester.widget<ExerciseVideo>(find.byType(ExerciseVideo));
        expect(
          video.exercise.media.video,
          s.library['h-forearm-plank'].media.video,
        );
        expect(video.paused, isFalse);
        await tester.tap(find.byKey(const ValueKey('pause')));
        await tester.pump();
        expect(
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).paused,
          isTrue,
        );
        await tester.tap(find.byKey(const ValueKey('pause')));
        await _advance(tester, 15);
        expect(find.text('练完了！'), findsOneWidget);
        expect(output.spoken, isEmpty, reason: 'No English clips are bundled.');
        expect(output.chimes, isNotEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
