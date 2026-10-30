import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import 'support.dart';

const _plan = TrainingPlan(
  id: 'transition-boundary',
  source: 'template',
  title: '转场边界训练',
  summary: '',
  goal: 'mixed',
  scene: 'home',
  equipment: [],
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
          exerciseId: 'h-forearm-plank',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 60,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  final sessionWrites = <Map<String, dynamic>>[];
  Completer<void>? gate;
  var failures = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == AppStore.key) {
      final state = jsonDecode(value) as Map<String, dynamic>;
      final sessions = state['sessions'] as List;
      if (sessions.isNotEmpty) {
        sessionWrites.add(Map<String, dynamic>.from(sessions.single as Map));
        final pending = gate;
        gate = null;
        if (pending != null) await pending.future;
        if (failures > 0) {
          failures--;
          throw StateError('session persistence fixture');
        }
      }
    }
    values[key] = value;
  }
}

class _Voice extends MutedVoiceOutput {
  int begins = 0;
  @override
  Future<void> begin() async {
    begins++;
  }

  final spoken = <List<String>>[];
  final chimes = <String>[];

  @override
  Future<void> speak(List<String> assets) async => spoken.add([...assets]);

  @override
  Future<void> chime(String asset) async => chimes.add(asset);
}

class _NativeVideo extends trainer.PackedAlphaPlatform
    implements trainer.PackedAlphaUriPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final created = <int>[];
  final live = <int>{};
  final commands = <(int, String)>[];
  Completer<void>? createGate;
  Completer<double?>? positionGate;
  var heldPositionCalls = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;

  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      createUri(Uri(scheme: 'asset', path: '/$asset'));

  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    final id = created.length + 1;
    created.add(id);
    final pending = createGate;
    createGate = null;
    if (pending != null) await pending.future;
    live.add(id);
    return (playerId: id, textureId: 100 + id);
  }

  @override
  Future<Object?> command(int playerId, String type, [Object? value]) async {
    commands.add((playerId, type));
    if (type == 'dispose') live.remove(playerId);
    if (type == 'position' && positionGate != null) {
      final pending = positionGate!;
      positionGate = null;
      heldPositionCalls++;
      return pending.future;
    }
    return type == 'position' ? .25 : null;
  }

  void frame(int id) {
    _events.add({'playerId': id, 'type': 'ready'});
    _events.add({'playerId': id, 'type': 'first-frame'});
  }

  void fail(int id) => _events.add({'playerId': id, 'type': 'error'});

  Future<void> close() => _events.close();
}

Exercise _packed(Exercise source) => Exercise(
  id: source.id,
  name: source.name,
  muscles: source.muscles,
  unilateral: source.unilateral,
  category: source.category,
  equipment: source.equipment,
  position: source.position,
  level: source.level,
  scenes: source.scenes,
  dose: source.dose,
  repSeconds: source.repSeconds,
  cues: source.cues,
  cautions: source.cautions,
  alternative: source.alternative,
  media: ExerciseMedia(
    id: source.media.id,
    video: source.media.video,
    poster: source.media.poster,
    loopSeconds: source.media.loopSeconds,
    posterSeconds: source.media.posterSeconds,
    source: source.media.source,
    packedAlphaVideo: source.media.video,
    alphaPlaybackPoster: source.media.playbackPosterFor(light: false),
    playbackPoster: source.media.playbackPoster,
    lightPlaybackPoster: source.media.lightPlaybackPoster,
    lightPoster: source.media.lightPoster,
  ),
);

class _Fixture {
  final storage = _Storage();
  final voice = _Voice();
  final nav = GlobalKey<NavigatorState>();
  final completed = <trainer.SessionResult>[];
  late final services = AppServices(
    library: ExerciseLibrary(loadLibrary().all.map(_packed).toList()),
    catalog: loadCatalog(),
    store: AppStore(storage)..starfield = false,
    voiceLibrary: loadVoices(),
    voiceOutput: voice,
    chatReplyDelay: Duration.zero,
  );
  late TrainingRoute<trainer.SessionResult> route;
  void open(BuildContext context) {
    route = TrainingRoute<trainer.SessionResult>(
      context: context,
      sourceEntry: 'chat',
      builder: (_) => const PlayerPage(plan: _plan),
    );
    unawaited(
      nav.currentState!.push(route).then((result) async {
        await route.completed;
        if (result != null) completed.add(result);
      }),
    );
  }
}

Future<_Fixture> _mount(
  WidgetTester tester,
  Brightness brightness, {
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final f = _Fixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await f.services.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.reset();
  });
  await tester.pumpWidget(
    AppScope(
      services: f.services,
      child: MaterialApp(
        navigatorKey: f.nav,
        theme: buildTheme(
          brightness == Brightness.dark ? SfPalette.dark : SfPalette.light,
        ),
        builder: (context, child) => SfPaletteScope(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => f.open(context),
              child: const Text('open training'),
            ),
          ),
        ),
      ),
    ),
  );
  final source = tester.element(find.byType(Scaffold));
  await tester.runAsync(
    () => TrainingPosterImages.precache(
      source,
      f.services.library[_plan.items.first.exerciseId],
    ),
  );
  await tester.tap(find.text('open training'));
  await tester.pump();
  await tester.pump();
  return f;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(microseconds: 1));
  await tester.pump();
  await tester.pump();
}

Future<void> _confirmExit(
  WidgetTester tester, {
  bool systemBack = false,
}) async {
  if (systemBack) {
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
  } else {
    await tester.tap(find.byKey(const ValueKey('close')));
  }
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('close-confirm')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('close-confirm')));
  await tester.pump();
}

Finder _key(String value) => find.byKey(ValueKey(value), skipOffstage: false);
bool _hasCompletion(WidgetTester tester) => find
    .byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('completion-'),
      skipOffstage: false,
    )
    .evaluate()
    .isNotEmpty;

void main() {
  late _NativeVideo native;
  setUp(() {
    native = _NativeVideo();
    trainer.UgkPackedAlphaVideo.debugPlatform = native;
    trainer.UgkPackedAlphaVideo.debugFilterBuilder = (_) =>
        const SizedBox.expand();
  });
  tearDown(() async {
    trainer.UgkPackedAlphaVideo.debugPlatform = null;
    trainer.UgkPackedAlphaVideo.debugFilterBuilder = null;
    await native.close();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name}: complete SDK frame, gate, identical poster bounds and real first-frame handoff',
      (tester) async {
        final f = await _mount(tester, brightness);
        final control = f.route.control;
        final sdk = tester.widget<trainer.TrainerPlayer>(
          find.byType(trainer.TrainerPlayer),
        );
        expect(sdk.chromeAnimation, isNull);
        for (final key in [
          'info-card',
          'top-hud',
          'pause',
          'counter',
          'prev',
          'skip',
        ]) {
          expect(_key(key), findsOneWidget);
        }
        expect(find.byType(TrainingPoster), findsOneWidget);
        final still = tester.widget<TrainingPoster>(
          find.byType(TrainingPoster),
        );
        expect(still.stageColor, sdk.theme.mediaStage);
        final stillFill = find.descendant(
          of: find.byType(TrainingPoster),
          matching: find.byType(ColoredBox),
        );
        expect(
          tester.widget<ColoredBox>(stillFill.first).color,
          sdk.theme.mediaStage,
        );
        expect(
          tester.widget<RawImage>(find.byType(RawImage).first).image,
          isNotNull,
        );
        expect(find.byType(ExerciseVideo), findsNothing);
        expect(native.created, isEmpty);
        expect(f.voice.begins, 0);
        await tester.pump(const Duration(milliseconds: 299));
        expect(control.entered, isFalse);
        expect(native.created, isEmpty);
        expect(f.voice.begins, 0);
        final posterBounds = tester.getRect(find.byType(TrainingPoster));
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        await tester.pump();
        expect(control.entered, isTrue);
        expect(f.voice.begins, 1);
        expect(native.created, hasLength(1));
        final videoBounds = tester.getRect(find.byType(ExerciseVideo));
        expect(
          tester.widget<ExerciseVideo>(find.byType(ExerciseVideo)).stageColor,
          sdk.theme.mediaStage,
        );
        expect(
          tester
              .widget<CachedExerciseMedia>(find.byType(CachedExerciseMedia))
              .stageColor,
          sdk.theme.mediaStage,
        );
        expect(videoBounds.width, closeTo(posterBounds.width, 1e-6));
        expect(videoBounds.height, closeTo(posterBounds.height, 1e-6));
        expect(videoBounds.top, closeTo(posterBounds.top, 1));
        final cover = find.byWidgetPredicate(
          (w) =>
              w is AnimatedOpacity &&
              w.key.toString().contains('cached-media-poster'),
        );
        expect(tester.widget<AnimatedOpacity>(cover).opacity, 1);
        native.frame(native.created.single);
        expect(tester.widget<AnimatedOpacity>(cover).opacity, 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        await tester.pump();
        expect(tester.widget<AnimatedOpacity>(cover).opacity, 0);
        expect(
          tester.widget<AnimatedOpacity>(cover).duration,
          const Duration(milliseconds: 200),
        );
        expect(tester.getRect(find.byType(ExerciseVideo)), videoBounds);
        expect(tester.takeException(), isNull);
      },
    );

    for (final systemBack in [false, true]) {
      testWidgets(
        '${brightness.name}: slow early save and systemBack=$systemBack slide immediately, preserve frame until 280, no completion, receipt once',
        (tester) async {
          final f = await _mount(tester, brightness);
          await _enter(tester);
          native.frame(native.created.single);
          await tester.pump(const Duration(milliseconds: 100));
          final saved = Completer<void>();
          f.storage.gate = saved;
          await _confirmExit(tester, systemBack: systemBack);
          expect(f.route.animation!.status, AnimationStatus.reverse);
          expect(f.route.control.exiting, isTrue);
          expect(native.live, hasLength(1));
          expect(f.storage.sessionWrites, hasLength(1));
          expect(f.services.store.history, isEmpty);
          await tester.pump(const Duration(milliseconds: 140));
          expect(tester.getTopLeft(find.byType(PlayerPage)).dx, greaterThan(0));
          expect(native.live, hasLength(1));
          expect(_hasCompletion(tester), isFalse);
          await tester.pump(const Duration(milliseconds: 140));
          await tester.pump(const Duration(microseconds: 1));
          await tester.pump();
          expect(f.route.animation!.status, AnimationStatus.dismissed);
          expect(native.live, isEmpty);
          expect(f.completed, isEmpty);
          expect(f.route.isActive, isTrue);
          saved.complete();
          await tester.pump();
          await tester.pump();
          await tester.pump();
          expect(f.completed, hasLength(1));
          expect(f.services.store.history, hasLength(1));
          expect(f.storage.sessionWrites, hasLength(1));
          expect(_hasCompletion(tester), isFalse);
          expect(find.byType(PlayerPage), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '${brightness.name}: failed save restores retry page; retry saves once, then finish slides out',
      (tester) async {
        final f = await _mount(tester, brightness);
        await _enter(tester);
        f.storage.failures = 1;
        await _confirmExit(tester);
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        expect(f.route.isActive, isTrue);
        expect(f.route.control.saveFailed, isTrue);
        expect(_key('save-retry'), findsOneWidget);
        expect(f.services.store.history, isEmpty);
        await tester.ensureVisible(_key('save-retry'));
        await tester.tap(_key('save-retry'));
        await tester.pump();
        await tester.pump();
        expect(f.services.store.history, hasLength(1));
        expect(f.route.isActive, isTrue);
        expect(f.completed, isEmpty);
        await tester.ensureVisible(_key('finish'));
        await tester.tap(_key('finish'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        await tester.pump();
        expect(f.services.store.history, hasLength(1));
        expect(f.completed, hasLength(1));
        expect(f.storage.sessionWrites, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'offline training retains the same complete image mode without loading placeholder',
    (tester) async {
      final f = await _mount(tester, Brightness.light);
      await _enter(tester);
      // The fake decoder never reports ready/first-frame: a failed download or
      // unavailable texture must keep the original frame-zero image visible.
      for (var second = 0; second < 4; second++) {
        await tester.pump(const Duration(seconds: 1));
        final cover = find.byWidgetPredicate(
          (w) =>
              w is AnimatedOpacity &&
              w.key.toString().contains('cached-media-poster'),
        );
        expect(tester.widget<AnimatedOpacity>(cover).opacity, 1);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      expect(f.voice.begins, 1);
      expect(find.byKey(const ValueKey('counter')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'completion receipt retry keeps the full page until an explicit finish',
    (tester) async {
      final f = await _mount(tester, Brightness.light);
      await _enter(tester);
      for (var second = 0; second < 120 && !_hasCompletion(tester); second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_hasCompletion(tester), isTrue);
      expect(f.services.store.history, hasLength(1));
      await tester.tap(_key('completion-feeling-tired'));
      await tester.pump();
      f.storage.failures = 1;
      await tester.tap(_key('finish'));
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.route.control.saveFailed, isTrue);
      expect(_key('save-retry'), findsOneWidget);
      await tester.tap(_key('save-retry'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(f.route.control.exiting, isFalse);
      expect(f.route.animation!.status, AnimationStatus.completed);
      expect(f.completed, isEmpty);
      expect(_hasCompletion(tester), isTrue);
      expect(f.services.store.history, hasLength(1));
      expect(
        f.services.store.sessionResults.single.feeling,
        trainer.TrainingFeeling.tired,
      );
      await tester.tap(_key('finish'));
      await tester.pump();
      expect(f.route.animation!.status, AnimationStatus.reverse);
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      await tester.pump();
      expect(f.completed, hasLength(1));
      expect(f.services.store.history, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'decoder failure keeps poster; timed workout completes and finish uses the same slide',
    (tester) async {
      final f = await _mount(tester, Brightness.dark);
      await _enter(tester);
      native.fail(native.created.single);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(native.live, isEmpty);
      final cover = find.byWidgetPredicate(
        (w) =>
            w is AnimatedOpacity &&
            w.key.toString().contains('cached-media-poster'),
      );
      expect(tester.widget<AnimatedOpacity>(cover).opacity, 1);
      for (var second = 0; second < 120 && !_hasCompletion(tester); second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(_hasCompletion(tester), isTrue);
      expect(f.services.store.history, hasLength(1));
      await tester.ensureVisible(_key('finish'));
      await tester.tap(_key('finish'));
      await tester.pump();
      expect(f.route.animation!.status, AnimationStatus.reverse);
      await tester.pump(const Duration(milliseconds: 279));
      expect(f.completed, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      await tester.pump();
      expect(f.completed, hasLength(1));
      expect(f.services.store.history, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
