import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/action_issue_form.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_route.dart';
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
  _Fixture({this.issueEnabled = false, this.withSource = false});

  final bool issueEnabled;
  final bool withSource;
  final sourceOpacity = ValueNotifier<double>(1);
  Rect? targetRect = const Rect.fromLTWH(36, 180, 200, 150);
  TrainingTransitionMotion? motion;
  final storage = _Storage();
  final voice = _Voice();
  final nav = GlobalKey<NavigatorState>();
  final popped = <trainer.SessionResult>[];
  final completed = <trainer.SessionResult>[];
  late final services = AppServices(
    library: ExerciseLibrary(loadLibrary().all.map(_packed).toList()),
    catalog: loadCatalog(),
    store: AppStore(storage, actionIssueEnabled: issueEnabled)
      ..starfield = false,
    voiceLibrary: loadVoices(),
    voiceOutput: voice,
    chatReplyDelay: Duration.zero,
  );
  late TrainingRoute<trainer.SessionResult> route;

  void open(BuildContext context) {
    route = TrainingRoute<trainer.SessionResult>(
      context: context,
      settings: const RouteSettings(name: 'player'),
      source: withSource
          ? TrainingTransitionSource(
              rect: () => targetRect,
              initialRect: targetRect,
              opacity: sourceOpacity,
            )
          : null,
      builder: (context) {
        motion = TrainingTransitionScope.maybeOf(context);
        return const PlayerPage(plan: _plan);
      },
    );
    unawaited(
      nav.currentState!.push(route).then((r) {
        if (r != null) popped.add(r);
      }),
    );
    unawaited(
      route.popped.then((r) async {
        await route.visualCompleted;
        if (r != null) completed.add(r);
      }),
    );
  }
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  double scale = 1,
  bool reduced = false,
  bool issueEnabled = false,
  bool withSource = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final f = _Fixture(issueEnabled: issueEnabled, withSource: withSource);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await f.services.dispose();
    f.sourceOpacity.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.reset();
  });
  await tester.pumpWidget(
    AppScope(
      services: f.services,
      child: MaterialApp(
        navigatorKey: f.nav,
        theme: buildTheme(SfPalette.dark),
        builder: (context, child) => SfPaletteScope(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 28, bottom: 24),
              viewPadding: const EdgeInsets.only(top: 28, bottom: 24),
            ),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            key: const ValueKey('transition-source'),
            body: Center(
              child: TextButton(
                onPressed: () => f.open(context),
                child: const Text('开始测试训练'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('开始测试训练'));
  await tester.pump();
  await tester.pump(); // Mount and measure the real gated SDK tree at t=0.
  return f;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 560));
  await tester.pump(const Duration(microseconds: 1));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
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

Finder _key(String key) => find.byKey(ValueKey(key));

int _eventCount(RuntimeLog log, String name) =>
    ((jsonDecode(log.exportJson()) as Map)['events'] as List)
        .where((event) => (event as Map)['event'] == name)
        .length;

Finder _layer(String id) =>
    find.byKey(ValueKey('trainer-chrome-$id'), skipOffstage: false);

Opacity _layerOpacity(WidgetTester tester, String id) => tester.widget<Opacity>(
  find
      .descendant(
        of: _layer(id),
        matching: find.byType(Opacity, skipOffstage: false),
        skipOffstage: false,
      )
      .first,
);

Transform _layerTransform(WidgetTester tester, String id) =>
    tester.widget<Transform>(
      find
          .descendant(
            of: _layer(id),
            matching: find.byType(Transform, skipOffstage: false),
            skipOffstage: false,
          )
          .first,
    );

double _effectiveOpacity(WidgetTester tester, Finder finder) {
  var opacity = 1.0;
  tester.element(finder).visitAncestorElements((element) {
    final w = element.widget;
    if (w is Opacity) opacity *= w.opacity;
    if (w is FadeTransition) opacity *= w.opacity.value;
    return true;
  });
  return opacity;
}

Future<void> _settleReturn(
  WidgetTester tester, {
  int milliseconds = 260,
}) async {
  await tester.pump(const Duration(microseconds: 1));
  await tester.pump(Duration(milliseconds: milliseconds));
  await tester.pump(const Duration(microseconds: 1));
  await tester.pump();
}

void main() {
  late _NativeVideo native;
  late RuntimeLog previousLog;
  late RuntimeLog log;
  setUp(() {
    native = _NativeVideo();
    trainer.UgkPackedAlphaVideo.debugPlatform = native;
    trainer.UgkPackedAlphaVideo.debugFilterBuilder = (_) =>
        const SizedBox.expand();
    previousLog = RuntimeLog.instance;
    log = RuntimeLog(enabled: true);
    RuntimeLog.instance = log;
  });
  tearDown(() async {
    trainer.UgkPackedAlphaVideo.debugPlatform = null;
    trainer.UgkPackedAlphaVideo.debugFilterBuilder = null;
    RuntimeLog.instance = previousLog;
    SfColors.palette = SfPalette.dark;
    await native.close();
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'entry $scale×: real SDK mounts immediately, start gate holds media/audio/clock until 560ms',
      (tester) async {
        final f = await _mount(tester, scale: scale);
        expect(f.route.opaque, isFalse);
        expect(f.route.transitionDuration, Duration.zero);
        expect(f.route.reverseTransitionDuration, Duration.zero);
        expect(
          find.byType(trainer.TrainerPlayer, skipOffstage: false),
          findsOneWidget,
        );
        expect(_key('training-entry-placeholder'), findsNothing);
        expect(find.byType(ExerciseVideo, skipOffstage: false), findsNothing);
        expect(native.created, isEmpty);
        expect(f.voice.spoken, isEmpty);
        expect(f.voice.chimes, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        expect(f.motion!.entered, isFalse);
        var released = false;
        unawaited(f.motion!.startGate.then((_) => released = true));
        final stage = f.motion!.mediaRect!;
        await tester.pump(const Duration(milliseconds: 280));
        expect(find.byType(trainer.TrainerPlayer), findsOneWidget);
        expect(_key('training-entry-fallback'), findsOneWidget);
        expect(f.motion!.chrome.value, closeTo(0, 1e-6));
        await tester.pump(const Duration(milliseconds: 279));
        expect(released, isFalse);
        expect(f.motion!.entered, isFalse);
        expect(native.created, isEmpty);
        expect(f.voice.spoken, isEmpty);
        expect(f.voice.chimes, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        expect(find.byType(ExerciseVideo, skipOffstage: false), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        for (var i = 0; i < 4; i++) {
          await tester.pump();
        }
        expect(released, isTrue);
        expect(f.motion!.entered, isTrue);
        expect(f.motion!.chrome.value, 1);
        expect(_key('training-entry-fallback'), findsNothing);
        expect(find.byType(ExerciseVideo), findsOneWidget);
        final actual = tester.getRect(find.byType(ExerciseVideo));
        expect(actual.left, closeTo(stage.left, .01));
        expect(actual.top, closeTo(stage.top, .01));
        expect(actual.width, closeTo(stage.width, .01));
        expect(actual.height, closeTo(stage.height, .01));
        expect(native.created, [1]);
        expect(_eventCount(log, 'training.started'), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'SDK chrome follows every approved interval and finishes at 560ms',
    (tester) async {
      final f = await _mount(tester, issueEnabled: true);
      var elapsed = 0;
      for (final ms in [
        0,
        140,
        279,
        280,
        300,
        320,
        340,
        400,
        480,
        500,
        520,
        540,
        559,
        560,
      ]) {
        await tester.pump(Duration(milliseconds: ms - elapsed));
        elapsed = ms;
        final raw = ((ms - 280) / 280).clamp(0.0, 1.0);
        expect(
          f.motion!.chrome.value,
          closeTo(raw, 1e-6),
          reason: 'raw chrome at ${ms}ms',
        );
        for (final layer in [
          ('info', 0, 200, -12.0),
          ('hud', 20, 200, -8.0),
          ('cues', 40, 200, 16.0),
          ('transport-digits', 60, 200, 16.0),
          ('previous', 60, 200, 16.0),
          ('next', 60, 200, 16.0),
          ('pause', 60, 220, 0.0),
        ]) {
          final t = ((ms - 280 - layer.$2) / layer.$3).clamp(0.0, 1.0);
          final opacity = Curves.easeOutCubic.transform(t);
          expect(
            _layerOpacity(tester, layer.$1).opacity,
            closeTo(opacity, 1e-5),
            reason: '${layer.$1} opacity at ${ms}ms',
          );
          final transform = _layerTransform(tester, layer.$1).transform;
          if (layer.$1 == 'pause') {
            expect(
              transform.storage[0],
              closeTo(.85 + .15 * Curves.easeOutBack.transform(t), 1e-5),
              reason: 'pause scale at ${ms}ms',
            );
          } else {
            expect(
              transform.storage[13],
              closeTo(layer.$4 * (1 - opacity), 1e-5),
              reason: '${layer.$1} y at ${ms}ms',
            );
          }
        }
        final issueT = ((ms - 340) / 200).clamp(0.0, 1.0);
        expect(
          _effectiveOpacity(
            tester,
            find.byKey(
              const ValueKey('player-action-issue'),
              skipOffstage: false,
            ),
          ),
          closeTo(Curves.easeOutCubic.transform(issueT), 1e-5),
        );
        if (ms < 560) {
          expect(native.created, isEmpty);
          expect(_eventCount(log, 'training.started'), 0);
          expect(f.voice.spoken, isEmpty);
          expect(f.voice.chimes, isEmpty);
        }
      }
      await tester.pump(const Duration(microseconds: 1));
      expect(f.motion!.entered, isTrue);
      expect(_layerOpacity(tester, 'pause').opacity, 1);
      expect(_layerTransform(tester, 'pause').transform.storage[0], 1);
      expect(_eventCount(log, 'training.started'), 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final background in [false, true]) {
    testWidgets(
      '${background ? 'background' : 'back'} during entry leaves gate pending and saves nothing',
      (tester) async {
        final f = await _mount(tester, withSource: true);
        final motion = f.motion!;
        var released = false;
        var visualDone = false;
        unawaited(motion.startGate.then((_) => released = true));
        unawaited(f.route.visualCompleted.then((_) => visualDone = true));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byType(trainer.TrainerPlayer, skipOffstage: false),
          findsOneWidget,
        );
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          await f.nav.currentState!.maybePop();
        }
        await tester.pumpAndSettle();
        expect(released, isFalse);
        expect(visualDone, isTrue);
        expect(f.sourceOpacity.value, 1);
        expect(find.byType(PlayerPage), findsNothing);
        expect(_key('training-morph-poster'), findsNothing);
        expect(_key('training-return-morph'), findsNothing);
        expect(_key('training-return-fallback'), findsNothing);
        expect(native.created, isEmpty);
        expect(f.voice.spoken, isEmpty);
        expect(f.voice.chimes, isEmpty);
        expect(f.storage.sessionWrites, isEmpty);
        expect(f.services.store.history, isEmpty);
        expect(f.popped, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reduced motion gates startup for one 150ms cross-fade without scale or slide',
    (tester) async {
      final f = await _mount(tester, reduced: true, issueEnabled: true);
      expect(f.route.transitionDuration, Duration.zero);
      expect(f.route.reverseTransitionDuration, Duration.zero);
      expect(find.byType(trainer.TrainerPlayer), findsOneWidget);
      expect(_key('training-entry-placeholder'), findsNothing);
      await tester.pump(const Duration(milliseconds: 75));
      expect(f.motion!.chrome.value, closeTo(.5, 1e-6));
      for (final id in [
        'info',
        'hud',
        'cues',
        'transport-digits',
        'previous',
        'next',
        'pause',
      ]) {
        expect(_layerOpacity(tester, id).child, isNot(isA<Transform>()));
      }
      expect(native.created, isEmpty);
      expect(_eventCount(log, 'training.started'), 0);
      await tester.pump(const Duration(milliseconds: 74));
      expect(native.created, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.motion!.entered, isTrue);
      expect(f.motion!.chrome.value, 1);
      expect(_eventCount(log, 'training.started'), 1);
      expect(native.created, [1]);
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.popped, hasLength(1));
      expect(f.completed, hasLength(1));
      expect(_key('training-return-fallback'), findsNothing);
      expect(_key('training-return-morph'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final systemBack in [false, true]) {
    testWidgets(
      '${systemBack ? 'back' : 'close'} exits: 250ms chrome overlaps save, video disposed immediately, visual receipt waits for return',
      (tester) async {
        final f = await _mount(tester, issueEnabled: !systemBack);
        await _enter(tester);
        expect(native.created, [1]);
        native.frame(1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        Completer<double?>? capture;
        if (!systemBack) {
          capture = Completer<double?>();
          native.positionGate = capture;
          await tester.tap(_key('player-action-issue'));
          await tester.pump();
          expect(native.heldPositionCalls, 1);
          expect(find.byType(ActionIssueForm), findsNothing);
        }
        final gate = Completer<void>();
        f.storage.gate = gate;
        await _confirmExit(tester, systemBack: systemBack);
        expect(f.motion!.exiting, isTrue);
        expect(find.byType(ExerciseVideo), findsNothing);
        expect(_key('training-transition-poster'), findsOneWidget);
        expect(native.live, isEmpty);
        expect(native.commands.where((c) => c.$2 == 'dispose'), [
          (1, 'dispose'),
        ]);
        if (capture != null) {
          capture.complete(2.75);
          await tester.pump();
          expect(find.byType(ActionIssueForm), findsNothing);
          expect(f.services.store.actionIssueStore.count, 0);
        }
        expect(f.storage.sessionWrites, hasLength(1));
        expect(f.popped, isEmpty);
        expect(_key('completion-celebration'), findsNothing);
        final counter = tester
            .widget<trainer.TrainerCountdownDigits>(
              find.byType(trainer.TrainerCountdownDigits),
            )
            .value;
        await tester.pump(const Duration(milliseconds: 125));
        expect(f.motion!.chrome.value, closeTo(.5, 1e-6));
        expect(_layerOpacity(tester, 'transport-digits').opacity, lessThan(1));
        expect(
          _layerOpacity(tester, 'info').opacity,
          greaterThan(_layerOpacity(tester, 'transport-digits').opacity),
        );
        await tester.pump(const Duration(milliseconds: 125));
        expect(f.motion!.chrome.value, 0);
        expect(
          f.popped,
          isEmpty,
          reason: 'Chrome finishing cannot bypass persistence.',
        );
        await tester.pump(const Duration(milliseconds: 149));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        final spinner = find.byType(CircularProgressIndicator);
        expect(spinner, findsOneWidget);
        expect(tester.getSize(spinner), const Size(24, 24));
        expect(
          tester
              .widget<trainer.TrainerCountdownDigits>(
                find.byType(trainer.TrainerCountdownDigits),
              )
              .value,
          counter,
        );
        // Repeated-back interruption is covered separately: it deliberately
        // skips the remaining visual return, while still waiting for this save.
        expect(f.storage.sessionWrites, hasLength(1));
        expect(f.popped, isEmpty);
        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(f.popped, hasLength(1));
        expect(f.completed, isEmpty);
        expect(find.byType(PlayerPage), findsNothing);
        expect(_key('training-return-fallback'), findsOneWidget);
        expect(_key('completion-celebration'), findsNothing);
        await tester.pump(const Duration(milliseconds: 259));
        expect(f.completed, isEmpty);
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();
        expect(f.completed, hasLength(1));
        expect(_key('training-return-fallback'), findsNothing);
        expect(f.storage.sessionWrites, hasLength(1));
        expect(f.services.store.history, hasLength(1));
        expect(
          f.services.store.sessionResults.single.sessionId,
          f.popped.single.sessionId,
        );
        expect(f.popped.single.endedEarly, isTrue);
        expect(f.popped.single.full, isFalse);
        expect(_eventCount(log, 'training.started'), 1);
        expect(_eventCount(log, 'training.finished'), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'visible source returns for 380ms then cross-fades 120ms before visual completion',
    (tester) async {
      final f = await _mount(tester, withSource: true);
      expect(f.sourceOpacity.value, 0);
      expect(_key('training-morph-poster'), findsOneWidget);
      await _enter(tester);
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.popped, hasLength(1));
      expect(f.completed, isEmpty);
      expect(_key('training-return-morph'), findsOneWidget);
      expect(f.sourceOpacity.value, 0);
      await tester.pump(const Duration(milliseconds: 380));
      expect(f.sourceOpacity.value, 1);
      expect(f.completed, isEmpty);
      await tester.pump(const Duration(milliseconds: 119));
      expect(f.completed, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.completed, hasLength(1));
      expect(_key('training-return-morph'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a source that leaves the viewport takes the 260ms return fallback',
    (tester) async {
      final f = await _mount(tester, withSource: true);
      await _enter(tester);
      f.targetRect = const Rect.fromLTWH(0, -500, 200, 150);
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.popped, hasLength(1));
      expect(f.completed, isEmpty);
      expect(_key('training-return-morph'), findsNothing);
      expect(_key('training-return-fallback'), findsOneWidget);
      await _settleReturn(tester);
      expect(f.completed, hasLength(1));
      expect(f.sourceOpacity.value, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failure exposes full completion and issue action; retry keeps one App receipt',
    (tester) async {
      final f = await _mount(tester, issueEnabled: true);
      await _enter(tester);
      f.storage.failures = 1;
      await _confirmExit(tester);
      await tester.pumpAndSettle();
      expect(f.popped, isEmpty);
      expect(f.storage.sessionWrites, hasLength(1));
      expect(f.services.store.history, isEmpty);
      expect(find.byType(trainer.TrainerResultStage), findsOneWidget);
      expect(
        _effectiveOpacity(tester, find.byType(trainer.TrainerResultStage)),
        1,
      );
      expect(_key('save-retry'), findsOneWidget);
      expect(_key('player-action-issue'), findsOneWidget);
      expect(_effectiveOpacity(tester, _key('player-action-issue')), 1);
      expect(f.motion!.saveFailed, isTrue);
      expect(_eventCount(log, 'training.finished'), 1);
      await tester.ensureVisible(_key('save-retry'));
      await tester.tap(_key('save-retry'));
      await tester.pumpAndSettle();
      expect(f.storage.sessionWrites, hasLength(2));
      expect(f.storage.sessionWrites[1], f.storage.sessionWrites[0]);
      expect(f.services.store.history, hasLength(1));
      expect(f.services.store.sessionResults, hasLength(1));
      expect(_key('save-retry'), findsNothing);
      expect(f.popped, isEmpty);
      await tester.ensureVisible(_key('finish'));
      await tester.tap(_key('finish'));
      await tester.pumpAndSettle();
      expect(f.popped, hasLength(1));
      expect(f.completed, hasLength(1));
      expect(f.storage.sessionWrites, hasLength(2));
      expect(_eventCount(log, 'training.started'), 1);
      expect(_eventCount(log, 'training.finished'), 1);
      expect(_eventCount(log, 'training.result.save_failed'), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'natural Finish waits for the post-pop return layer before visual completion',
    (tester) async {
      final f = await _mount(tester);
      await _enter(tester);
      for (
        var i = 0;
        i < 3 && find.byType(trainer.TrainerResultStage).evaluate().isEmpty;
        i++
      ) {
        await tester.tap(_key('skip'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(find.byType(trainer.TrainerResultStage), findsOneWidget);
      expect(f.popped, isEmpty);
      await tester.ensureVisible(_key('finish'));
      await tester.tap(_key('finish'));
      await tester.pump();
      expect(_key('training-completion-exit-poster'), findsOneWidget);
      final player = tester.widget<trainer.TrainerPlayer>(
        find.byType(trainer.TrainerPlayer),
      );
      expect(player.theme.mediaStage.a, 0);
      final layers = tester.widget<Stack>(_key('training-player-layers'));
      expect(
        layers.children.indexWhere((child) => child is trainer.TrainerPlayer),
        greaterThan(1),
      );
      await tester.pump(const Duration(milliseconds: 125));
      expect(_key('training-completion-exit-poster'), findsOneWidget);
      expect(find.byType(ExerciseVideo), findsNothing);
      await tester.pump(const Duration(milliseconds: 125));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(f.popped, hasLength(1));
      expect(f.completed, isEmpty);
      expect(_key('training-return-fallback'), findsOneWidget);
      await _settleReturn(tester);
      expect(f.completed, hasLength(1));
      expect(_eventCount(log, 'training.started'), 1);
      expect(_eventCount(log, 'training.finished'), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late native create after an interrupted route is disposed without a restored video surface',
    (tester) async {
      final gate = Completer<void>();
      native.createGate = gate;
      final f = await _mount(tester);
      await _enter(tester);
      expect(native.created, [1]);
      f.nav.currentState!.pop();
      await tester.pump();
      expect(find.byType(PlayerPage), findsNothing);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(native.live, isEmpty);
      expect(native.commands.where((c) => c.$2 == 'dispose'), [(1, 'dispose')]);
      expect(_key('training-return-fallback'), findsNothing);
      expect(native.created, [1]);
      expect(f.storage.sessionWrites.length, lessThanOrEqualTo(1));
      expect(f.services.store.history.length, lessThanOrEqualTo(1));
      expect(
        f.services.store.sessionResults.length,
        f.services.store.history.length,
      );
      expect(_eventCount(log, 'training.finished'), lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background during the return removes its overlay and restores the source',
    (tester) async {
      final f = await _mount(tester, withSource: true);
      await _enter(tester);
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(_key('training-return-morph'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(_key('training-return-morph'), findsNothing);
      expect(f.sourceOpacity.value, 1);
      expect(f.completed, hasLength(1));
      expect(native.live, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final back in [false, true]) {
    testWidgets(
      'exit A interruption finishes visuals without bypassing save, back=$back',
      (tester) async {
        final f = await _mount(tester, withSource: true);
        await _enter(tester);
        final save = Completer<void>();
        f.storage.gate = save;
        await _confirmExit(tester);
        await tester.pump(const Duration(milliseconds: 100));
        if (back) {
          await f.nav.currentState!.maybePop();
        } else {
          await tester.tapAt(const Offset(195, 400));
        }
        await tester.pump();
        expect(f.motion!.chrome.value, 0);
        expect(f.motion!.interrupted, isTrue);
        expect(f.popped, isEmpty);
        save.complete();
        await tester.pumpAndSettle();
        expect(f.completed, hasLength(1));
        expect(f.storage.sessionWrites, hasLength(1));
        expect(_key('training-return-morph'), findsNothing);
        expect(_key('training-return-fallback'), findsNothing);
        expect(native.live, isEmpty);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final slowSave in [false, true]) {
    testWidgets('reduced exit is one 150ms cross-fade, slowSave=$slowSave', (
      tester,
    ) async {
      final f = await _mount(tester, reduced: true, withSource: true);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      final save = slowSave ? Completer<void>() : null;
      f.storage.gate = save;
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 149));
      expect(f.motion!.chrome.value, greaterThan(0));
      expect(find.byType(ExerciseVideo), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(_key('training-return-morph'), findsNothing);
      expect(_key('training-return-fallback'), findsNothing);
      expect(f.sourceOpacity.value, 1);
      if (save != null) {
        expect(f.completed, isEmpty);
        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.byType(PlayerPage),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, 0);
        await tester.pump(const Duration(milliseconds: 250));
        expect(_key('training-reduced-saving'), findsOneWidget);
        save.complete();
      }
      await tester.pumpAndSettle();
      expect(f.completed, hasLength(1));
      expect(f.storage.sessionWrites, hasLength(1));
      expect(find.byType(PlayerPage), findsNothing);
      expect(native.live, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'background during exit A lets a late save finish without creating a return overlay',
    (tester) async {
      final f = await _mount(tester, withSource: true);
      await _enter(tester);
      final save = Completer<void>();
      f.storage.gate = save;
      var visualDone = false;
      unawaited(f.route.visualCompleted.then((_) => visualDone = true));
      await _confirmExit(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(f.motion!.exiting, isTrue);
      expect(f.motion!.chrome.value, closeTo(.6, 1e-6));
      expect(f.storage.sessionWrites, hasLength(1));
      expect(f.popped, isEmpty);
      expect(visualDone, isFalse);
      expect(native.live, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(f.motion!.chrome.value, 0);
      expect(
        f.popped,
        isEmpty,
        reason: 'Background must not bypass the pending durable save.',
      );
      expect(_key('training-return-morph'), findsNothing);
      expect(_key('training-return-fallback'), findsNothing);
      save.complete();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(f.popped, hasLength(1));
      expect(f.completed, hasLength(1));
      expect(visualDone, isTrue);
      expect(f.storage.sessionWrites, hasLength(1));
      expect(f.services.store.history, hasLength(1));
      expect(f.sourceOpacity.value, 1);
      expect(f.route.isActive, isFalse);
      // Background has no draw frames. Its receipt is already terminal; the
      // old element is removed on the first resumed frame without a new flight.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(_key('training-return-morph'), findsNothing);
      expect(_key('training-return-fallback'), findsNothing);
      expect(native.live, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(_eventCount(log, 'training.finished'), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'external App removal during entry keeps gate pending and retires its frame scenario',
    (tester) async {
      final previousRecorder = FrameRecorder.instance;
      final recorder = FrameRecorder(enabled: true);
      FrameRecorder.instance = recorder;
      try {
        final f = await _mount(tester, withSource: true);
        final gate = f.motion!.startGate;
        var released = false;
        var visualDone = false;
        unawaited(gate.then((_) => released = true));
        unawaited(f.route.visualCompleted.then((_) => visualDone = true));
        await tester.pump(const Duration(milliseconds: 100));
        expect(recorder.currentScenario, FrameScenario.trainingRouteEntry);
        expect(
          find.byType(trainer.TrainerPlayer, skipOffstage: false),
          findsOneWidget,
        );
        expect(released, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(released, isFalse);
        expect(visualDone, isTrue);
        expect(recorder.currentScenario, isNull);
        expect(f.sourceOpacity.value, 1);
        expect(find.byType(PlayerPage, skipOffstage: false), findsNothing);
        expect(_key('training-morph-poster'), findsNothing);
        expect(_key('training-entry-fallback'), findsNothing);
        expect(_key('training-return-morph'), findsNothing);
        expect(_key('training-return-fallback'), findsNothing);
        expect(native.created, isEmpty);
        expect(f.voice.spoken, isEmpty);
        expect(f.voice.chimes, isEmpty);
        expect(f.storage.sessionWrites, isEmpty);
        expect(f.services.store.history, isEmpty);
        expect(f.popped, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        recorder.stop();
        FrameRecorder.instance = previousRecorder;
      }
    },
  );
}
