import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/action_issue_form.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_entry_placeholder.dart';
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
  _Fixture({this.issueEnabled = false});

  final bool issueEnabled;
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
      builder: (_) => const PlayerPage(plan: _plan),
    );
    unawaited(
      nav.currentState!.push(route).then((r) {
        if (r != null) popped.add(r);
      }),
    );
    unawaited(
      route.completed.then((r) {
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
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final f = _Fixture(issueEnabled: issueEnabled);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await f.services.dispose();
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
  await tester.pump(); // Hero pre-layout is not an elapsed entry frame.
  return f;
}

Future<void> _enter(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 320));
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
      'entry $scale×: still and real media share safe-area geometry; no early trainer/audio/clock',
      (tester) async {
        final f = await _mount(tester, scale: scale);
        expect(_key('training-entry-placeholder'), findsOneWidget);
        expect(find.byType(trainer.TrainerPlayer), findsNothing);
        expect(find.byType(ExerciseVideo), findsNothing);
        expect(native.created, isEmpty);
        expect(f.voice.spoken, isEmpty);
        expect(f.voice.chimes, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        await tester.pump(const Duration(milliseconds: 160));
        final poster = tester.getRect(find.byType(TrainingTransitionPoster));
        // The route transform affects both surfaces equally; compare at rest.
        final stageSlide = tester.widget<SlideTransition>(
          find.ancestor(
            of: find.byType(PlayerPage),
            matching: find.byType(SlideTransition),
          ),
        );
        final still = poster.shift(
          Offset(0, -844 * stageSlide.position.value.dy),
        );
        await tester.pump(const Duration(milliseconds: 159));
        expect(f.route.animation!.status, AnimationStatus.forward);
        expect(find.byType(trainer.TrainerPlayer), findsNothing);
        expect(native.created, isEmpty);
        expect(_eventCount(log, 'training.started'), 0);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump(const Duration(microseconds: 1));
        await tester.pump();
        expect(f.route.animation!.status, AnimationStatus.completed);
        expect(find.byType(trainer.TrainerPlayer), findsOneWidget);
        expect(_key('training-entry-placeholder'), findsNothing);
        final actual = tester.getRect(find.byType(ExerciseVideo));
        expect(actual.left, closeTo(still.left, .01));
        expect(actual.top, closeTo(still.top, .01));
        expect(actual.width, closeTo(still.width, .01));
        expect(actual.height, closeTo(still.height, .01));
        expect(_eventCount(log, 'training.started'), 1);
        expect(_key('skip'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'entry abort never constructs a trainer, decoder or training receipt',
    (tester) async {
      final f = await _mount(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final animationValue = f.route.animation!.value;
      final slide = find.ancestor(
        of: find.byType(PlayerPage),
        matching: find.byType(SlideTransition),
      );
      final fade = find.ancestor(
        of: find.byType(PlayerPage),
        matching: find.byType(FadeTransition),
      );
      final offset = tester.widget<SlideTransition>(slide).position.value;
      final opacity = tester.widget<FadeTransition>(fade).opacity.value;
      f.nav.currentState!.pop();
      await tester.pump();
      expect(f.route.animation!.status, AnimationStatus.reverse);
      expect(f.route.animation!.value, animationValue);
      expect(tester.widget<SlideTransition>(slide).position.value, offset);
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(opacity, 1e-9),
        reason:
            'Changing direction at the same value cannot brighten the page.',
      );
      await tester.pump(const Duration(milliseconds: 261));
      await tester.pump();
      expect(find.byType(PlayerPage), findsNothing);
      expect(native.created, isEmpty);
      expect(f.voice.spoken, isEmpty);
      expect(f.storage.sessionWrites, isEmpty);
      expect(_eventCount(log, 'training.started'), 0);
      expect(f.popped, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system reduced motion starts immediately without a route ticker', (
    tester,
  ) async {
    final f = await _mount(tester, reduced: true);
    await tester.pump();
    expect(f.route.transitionDuration, Duration.zero);
    expect(f.route.reverseTransitionDuration, Duration.zero);
    expect(find.byType(trainer.TrainerPlayer), findsOneWidget);
    expect(_key('training-entry-placeholder'), findsNothing);
    expect(
      find.ancestor(
        of: find.byType(PlayerPage),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(PlayerPage),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    // The SDK's own training UI can animate; the zero-time route adds no ticker.
    expect(f.route.animation!.status, AnimationStatus.completed);
    expect(_eventCount(log, 'training.started'), 1);
    f.nav.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(find.byType(PlayerPage), findsNothing);
    expect(native.live, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final systemBack in [false, true]) {
    testWidgets(
      '${systemBack ? 'back' : 'close'}: frame retained during slow save, one receipt, immediate reverse disposal',
      (tester) async {
        final f = await _mount(tester, issueEnabled: !systemBack);
        await _enter(tester);
        expect(native.created, hasLength(1));
        native.frame(native.created.single);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final mediaState = tester.state(
          find.byType(trainer.UgkPackedAlphaVideo),
        );
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
        if (capture != null) {
          capture.complete(2.75);
          await tester.pump();
          expect(find.byType(ActionIssueForm), findsNothing);
          expect(f.route.isCurrent, isTrue);
          expect(f.services.store.actionIssueStore.count, 0);
        }
        expect(native.created, hasLength(1));
        expect(native.live, {1});
        expect(
          tester.state(find.byType(trainer.UgkPackedAlphaVideo)),
          same(mediaState),
        );
        final counter = tester
            .widget<trainer.TrainerCountdownDigits>(
              find.byType(trainer.TrainerCountdownDigits),
            )
            .value;
        final ring = tester
            .widget<trainer.UgkPlayPauseButton>(
              find.byType(trainer.UgkPlayPauseButton),
            )
            .progress
            .value;
        expect(f.storage.sessionWrites, hasLength(1));
        expect(f.popped, isEmpty);
        expect(_key('completion-celebration'), findsNothing);
        await tester.pump(const Duration(milliseconds: 399));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        final spinner = find.byType(CircularProgressIndicator);
        expect(spinner, findsOneWidget);
        expect(tester.getSize(spinner), const Size(24, 24));
        await tester.pump(const Duration(milliseconds: 150));
        expect(
          tester
              .widget<trainer.TrainerCountdownDigits>(
                find.byType(trainer.TrainerCountdownDigits),
              )
              .value,
          counter,
        );
        expect(
          tester
              .widget<trainer.UgkPlayPauseButton>(
                find.byType(trainer.UgkPlayPauseButton),
              )
              .progress
              .value,
          ring,
        );
        expect(
          tester.state(find.byType(trainer.UgkPackedAlphaVideo)),
          same(mediaState),
        );
        await f.nav.currentState!.maybePop();
        await tester.pump();
        expect(f.storage.sessionWrites, hasLength(1));
        expect(f.popped, isEmpty);
        expect(_eventCount(log, 'training.started'), 1);
        expect(_eventCount(log, 'training.finished'), 1);
        if (!systemBack) {
          expect(f.services.store.actionIssueStore.enabled, isTrue);
          await tester.tap(_key('player-action-issue'));
          await tester.pump();
          expect(find.byType(ActionIssueForm), findsNothing);
          expect(f.route.isCurrent, isTrue);
          expect(f.popped, isEmpty);
        }
        gate.complete();
        await tester.pump();
        await tester.pump();
        expect(f.route.animation!.status, AnimationStatus.reverse);
        expect(f.popped, hasLength(1));
        expect(f.completed, isEmpty);
        expect(find.byType(ExerciseVideo), findsNothing);
        expect(_key('training-transition-poster'), findsOneWidget);
        expect(native.live, isEmpty);
        expect(native.commands.where((c) => c.$2 == 'dispose'), [
          (1, 'dispose'),
        ]);
        expect(_key('completion-celebration'), findsNothing);
        await tester.pump(const Duration(milliseconds: 259));
        expect(find.byType(PlayerPage), findsOneWidget);
        expect(f.completed, isEmpty);
        expect(native.created, hasLength(1));
        await tester.pump(const Duration(milliseconds: 2));
        await tester.pump();
        expect(find.byType(PlayerPage), findsNothing);
        expect(f.completed, hasLength(1));
        expect(f.storage.sessionWrites, hasLength(1));
        expect(
          f.services.store.sessionResults.single.sessionId,
          f.popped.single.sessionId,
        );
        expect(f.services.store.history, hasLength(1));
        expect(f.popped.single.endedEarly, isTrue);
        expect(f.popped.single.full, isFalse);
        expect(_eventCount(log, 'training.started'), 1);
        expect(_eventCount(log, 'training.finished'), 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'save failure retries the same App receipt without duplicate history or finished event',
    (tester) async {
      final f = await _mount(tester);
      await _enter(tester);
      f.storage.failures = 1;
      await _confirmExit(tester);
      await tester.pumpAndSettle();
      expect(f.popped, isEmpty);
      expect(f.storage.sessionWrites, hasLength(1));
      expect(f.services.store.history, isEmpty);
      expect(_key('save-retry'), findsOneWidget);
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
    'late native create after reverse is disposed without restoring a video surface',
    (tester) async {
      final gate = Completer<void>();
      native.createGate = gate;
      final f = await _mount(tester);
      await _enter(tester);
      expect(native.created, [1]);
      f.nav.currentState!.pop();
      await tester.pump();
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(_key('training-transition-poster'), findsOneWidget);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(native.live, isEmpty);
      expect(native.commands.where((c) => c.$2 == 'dispose'), [(1, 'dispose')]);
      await tester.pump(const Duration(milliseconds: 261));
      await tester.pump();
      expect(find.byType(PlayerPage), findsNothing);
      expect(native.created, [1]);
      // A trainer that already started saves its early-exit receipt on disposal.
      // This is distinct from aborting the still-only entrance above.
      expect(f.storage.sessionWrites.length, lessThanOrEqualTo(1));
      expect(f.services.store.history.length, lessThanOrEqualTo(1));
      expect(
        f.services.store.sessionResults.length,
        f.services.store.history.length,
      );
      for (final result in f.services.store.sessionResults) {
        expect(result.endedEarly, isTrue);
        expect(result.full, isFalse);
      }
      expect(_eventCount(log, 'training.finished'), lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    },
  );
}
