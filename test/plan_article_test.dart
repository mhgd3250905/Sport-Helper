import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/guide_media.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show PackedAlphaPlatform, PackedAlphaUriPlatform, UgkPackedAlphaVideo;

import 'app_flow_test.dart' show services, warmTrainingPoster;

const _plan = TrainingPlan(
  id: 'article',
  source: 'template',
  title: '今天的舒展安排',
  summary: '先活动肩背，再轻柔舒展腰侧，最后放松。',
  goal: 'fullbody',
  scene: 'home',
  equipment: ['mat'],
  level: 1,
  targetMinutes: 10,
  notes: ['按你的徒手和居家条件安排'],
  blocks: [
    PlanBlock(
      id: 'warm',
      name: '先活动开',
      type: BlockType.warmup,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-catcow-quad',
          mode: DoseMode.reps,
          sets: 1,
          reps: 8,
          perSide: false,
          restSeconds: 10,
        ),
      ],
    ),
    PlanBlock(
      id: 'main',
      name: '重点舒展',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-banana',
          mode: DoseMode.time,
          sets: 2,
          workSeconds: 30,
          perSide: true,
          restSeconds: 10,
          note: '两侧依次进行，保持自然呼吸',
        ),
      ],
    ),
    PlanBlock(
      id: 'cool',
      name: '收尾放松',
      type: BlockType.cooldown,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'n-windshield',
          mode: DoseMode.reps,
          sets: 1,
          reps: 6,
          perSide: false,
          restSeconds: 10,
        ),
      ],
    ),
  ],
);

Exercise _copyExercise(
  Exercise source, {
  List<String>? cues,
  ExerciseMedia? media,
  String? alternative,
}) => Exercise(
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
  cues: cues ?? source.cues,
  cautions: source.cautions,
  alternative: alternative ?? source.alternative,
  media: media ?? source.media,
);

Future<AppServices> _show(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
  double scale = 1,
  SfPalette palette = SfPalette.dark,
  TrainingPlan plan = _plan,
  Exercise Function(Exercise)? transform,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var s = services();
  if (transform != null) {
    s = AppServices(
      library: ExerciseLibrary(s.library.all.map(transform).toList()),
      catalog: s.catalog,
      store: s.store,
      voiceLibrary: s.voiceLibrary,
      voiceOutput: s.voiceOutput,
    );
  }
  await s.store.acceptSafety(blocked: false);
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(
        theme: buildTheme(palette),
        builder: (context, child) => SfPaletteScope(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: child!,
          ),
        ),
        home: PlanPage(plan: plan),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await s.dispose();
  });
  return s;
}

class _PreviewPlatform extends PackedAlphaPlatform
    implements PackedAlphaUriPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final sources = <Uri>[];
  final operations = <(String, int)>[];
  final live = <int>{};
  var maxLive = 0;

  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      createUri(Uri(scheme: 'asset', host: '', path: '/$asset'));
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    sources.add(uri);
    final id = sources.length;
    live.add(id);
    if (live.length > maxLive) maxLive = live.length;
    operations.add(('create', id));
    return (playerId: id, textureId: 100 + id);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    operations.add((type, id));
    if (type == 'dispose') live.remove(id);
    return type == 'position' ? .25 : null;
  }

  void ready(int id) {
    _events.add({'playerId': id, 'type': 'ready'});
    _events.add({'playerId': id, 'type': 'first-frame'});
  }

  Future<void> close() => _events.close();
}

Exercise _packed(Exercise exercise, {List<String>? cues}) {
  final media = exercise.media;
  return _copyExercise(
    exercise,
    cues: cues,
    media: ExerciseMedia(
      id: media.id,
      video: media.video,
      poster: media.poster,
      loopSeconds: media.loopSeconds,
      posterSeconds: media.posterSeconds,
      source: media.source,
      videoAvailable: media.videoAvailable,
      lightVideo: media.lightVideo,
      lightPoster: media.lightPoster,
      lightVideoAvailable: media.lightVideoAvailable,
      playbackPoster: media.playbackPoster,
      lightPlaybackPoster: media.lightPlaybackPoster,
      packedAlphaVideo: media.video,
      alphaPlaybackPoster: media.playbackPosterFor(light: false),
    ),
  );
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _toggle(String slot) => _key('guide-media-control-$slot');
ListView _list(WidgetTester tester) =>
    tester.widget<ListView>(_key('plan-article'));
GuideMedia _media(WidgetTester tester, String slot) =>
    tester.widget<GuideMedia>(
      find.descendant(
        of: find.byKey(ValueKey('article-video-$slot'), skipOffstage: false),
        matching: find.byType(GuideMedia, skipOffstage: false),
        skipOffstage: false,
      ),
    );
UgkPackedAlphaVideo _video(WidgetTester tester, String slot) =>
    tester.widget<UgkPackedAlphaVideo>(_key('cached-media-video-$slot'));

String? _asset(ImageProvider provider) => switch (provider) {
  AssetImage(:final assetName) => assetName,
  ResizeImage(:final imageProvider) => _asset(imageProvider),
  _ => null,
};

void main() {
  late _PreviewPlatform platform;
  setUp(() {
    platform = _PreviewPlatform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.close();
  });

  Future<void> play(WidgetTester tester, String slot) async {
    final before = platform.sources.length;
    await tester.tap(_toggle(slot));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump();
    }
    expect(platform.sources.length, before + 1);
    platform.ready(platform.sources.length);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(_key('guide-media-loading-$slot'), findsNothing);
  }

  testWidgets('article hides empty or duplicate arrangement sections', (
    tester,
  ) async {
    for (final summary in ['', '   ', _plan.title, ' ${_plan.title} ']) {
      final plan = TrainingPlan.fromJson({
        ..._plan.toJson(),
        'summary': summary,
      });
      await _show(tester, plan: plan);
      expect(find.text('安排说明'), findsNothing);
      expect(find.text(_plan.notes.first), findsNothing);
      expect(find.text(_plan.title), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('article localizes protocol sections and keeps shared duration', (
    tester,
  ) async {
    final plan = TrainingPlan.fromJson({
      ..._plan.toJson(),
      'blocks': [
        for (final block in _plan.blocks)
          {...block.toJson(), 'name': block.type.name},
      ],
    });
    final s = await _show(tester, plan: plan);
    expect(find.text('热身'), findsOneWidget);
    expect(find.text('warmup'), findsNothing);
    final duration = toCoachRoutine(plan, s.library).durationLabel;
    expect(find.text(duration), findsOneWidget);
    expect(duration, isNot('${plan.targetMinutes} 分钟'));
    final face = tester.widget<Container>(_key('guide-training-button'));
    expect((face.decoration! as BoxDecoration).color, SfPalette.dark.accent);
    await tester.scrollUntilVisible(find.text('主训'), 200);
    await tester.pumpAndSettle();
    expect(find.text('main'), findsNothing);
    await tester.scrollUntilVisible(find.text('放松'), 200);
    await tester.pumpAndSettle();
    expect(find.text('cooldown'), findsNothing);
    final controller = _list(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final action = tester.getRect(_key('guide-training-button'));
    final last = tester.getRect(_key('guide-card-2:0'));
    expect(last.bottom, lessThanOrEqualTo(action.top - 24));
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name} article mounts only themed text and static stills',
      (tester) async {
        final s = await _show(tester, palette: palette);
        final exercise = s.library['h-catcow-quad'];
        final video = _key('article-video-0:0');
        expect(Theme.of(tester.element(video)).brightness, palette.brightness);
        expect(
          tester.widget<Text>(find.text(_plan.summary)).style!.color,
          palette.muted,
        );
        expect(
          tester.widget<Text>(_key('guide-step-text-0:0-1')).style!.color,
          palette.text,
        );
        final candidate =
            exercise.media.alphaPlaybackPoster ??
            exercise.media.playbackPosterFor(light: !palette.isDark);
        final stills = tester
            .widgetList<Image>(
              find.descendant(of: video, matching: find.byType(Image)),
            )
            .map((image) => _asset(image.image))
            .whereType<String>();
        expect(stills, contains(candidate));
        expect(tester.widget<AspectRatio>(video).aspectRatio, 4 / 3);
        expect(_toggle('0:0').hitTestable(), findsOneWidget);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        expect(platform.sources, isEmpty);
        expect(_media(tester, '0:0').coordinator.activeSlot, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'article preserves custom sections and global numbers without autoplay',
    (tester) async {
      final s = await _show(tester);
      expect(_key('plan-introduction'), findsOneWidget);
      expect(find.text('安排说明'), findsOneWidget);
      expect(find.text(_plan.title), findsOneWidget);
      expect(find.text('3 个动作'), findsOneWidget);
      expect(find.text('先活动开'), findsOneWidget);
      final items = _plan.items.toList();
      for (var index = 0; index < items.length; index++) {
        final name = _key('guide-name-$index:0');
        await tester.scrollUntilVisible(name, 220);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(name).data,
          s.library[items[index].exerciseId].name,
        );
        expect(
          find.descendant(
            of: _key('guide-number-$index:0'),
            matching: find.text('${index + 1}'),
          ),
          findsOneWidget,
        );
        expect(platform.sources, isEmpty);
      }
      expect(find.text('收尾放松'), findsOneWidget);
      expect(find.text('怎么做'), findsWidgets);
      expect(find.text('前往训练'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview requires a tap and pauses/resumes one retained frame', (
    tester,
  ) async {
    await _show(tester, transform: _packed);
    final coordinator = _media(tester, '0:0').coordinator;
    expect(platform.sources, isEmpty);
    await play(tester, '0:0');
    final controller = _video(tester, '0:0').controller;
    expect(controller.wantsPlay, isTrue);
    expect(coordinator.activeSlot, '0:0');
    await tester.tap(_toggle('0:0'));
    await tester.pumpAndSettle();
    expect(_video(tester, '0:0').controller, same(controller));
    expect(controller.wantsPlay, isFalse);
    expect(coordinator.activeSlot, '0:0');
    expect(platform.live, hasLength(1));
    await tester.tap(_toggle('0:0'));
    await tester.pumpAndSettle();
    expect(_video(tester, '0:0').controller, same(controller));
    expect(controller.wantsPlay, isTrue);
    expect(platform.sources, hasLength(1));
    expect(platform.maxLive, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'standalone guide restores the same article and enables preview only after exit completes',
    (tester) async {
      final app = await _show(tester, transform: _packed);
      await play(tester, '0:0');
      final coordinator = _media(tester, '0:0').coordinator;
      final article = tester.element(find.byType(PlanPage));
      final scroll = _list(tester).controller!;
      scroll.jumpTo(36);
      await tester.pump();
      final offset = scroll.offset;
      await warmTrainingPoster(tester, app, _plan, sourceContext: article);
      await tester.tap(_key('start'));
      // Preview retirement precedes the one shared opaque slide route.
      final player = find.byType(PlayerPage, skipOffstage: false);
      for (var i = 0; i < 12 && player.evaluate().isEmpty; i++) {
        await tester.pump();
      }
      expect(player, findsOneWidget);
      await tester.pump();
      final playerContext = tester.element(player);
      final route = ModalRoute.of(playerContext)! as TrainingRoute;
      final control = TrainingRouteScope.maybeOf(playerContext)!;
      var routeComplete = false;
      unawaited(route.completed.then((_) => routeComplete = true));
      expect(route.transitionDuration, const Duration(milliseconds: 300));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 280),
      );
      expect(route.opaque, isTrue);
      expect(control.entered, isFalse);
      expect(coordinator.activeSlot, isNull);
      expect(platform.live, isEmpty);
      expect(_media(tester, '0:0').enabled, isFalse);
      final createsBeforeStart = platform.sources.length;
      await tester.pump(const Duration(milliseconds: 299));
      expect(control.entered, isFalse);
      expect(platform.sources, hasLength(createsBeforeStart));
      expect(platform.live, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      expect(control.entered, isTrue);
      expect(_media(tester, '0:0').enabled, isFalse);
      await tester.tap(_key('close'));
      await tester.pumpAndSettle();
      // Gate release starts async media creation. Capture the actual paused
      // handle after the confirmation is fully shown, immediately before exit.
      final playingHandles = {...platform.live};
      expect(playingHandles, isNotEmpty);
      await tester.tap(_key('close-confirm'));
      await tester.pump();
      await tester.pump();
      expect(control.exiting, isTrue);
      expect(route.isActive, isTrue);
      expect(_media(tester, '0:0').enabled, isFalse);
      expect(coordinator.activeSlot, isNull);
      await tester.pump(const Duration(milliseconds: 279));
      expect(route.isActive, isTrue);
      expect(routeComplete, isFalse);
      expect(_media(tester, '0:0').enabled, isFalse);
      expect(
        platform.live,
        playingHandles,
        reason: 'Retain the paused texture until the page is offscreen.',
      );
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(microseconds: 1));
      await tester.pumpAndSettle();
      expect(routeComplete, isTrue);
      expect(find.byType(PlayerPage), findsNothing);
      expect(tester.element(find.byType(PlanPage)), same(article));
      expect(_list(tester).controller, same(scroll));
      expect(scroll.offset, offset);
      expect(_media(tester, '0:0').enabled, isTrue);
      expect(coordinator.activeSlot, isNull);
      expect(platform.live, isEmpty);
      expect(app.store.history, hasLength(1));
      final creates = platform.sources.length;
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        platform.sources,
        hasLength(creates),
        reason: 'Returning does not autoplay.',
      );
      await play(tester, '0:0');
      expect(coordinator.activeSlot, '0:0');
      expect(platform.sources, hasLength(creates + 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selecting B releases A before allocating its decoder', (
    tester,
  ) async {
    await _show(tester, height: 1800, transform: _packed);
    await play(tester, '0:0');
    final coordinator = _media(tester, '0:0').coordinator;
    expect(_toggle('1:0').hitTestable(), findsOneWidget);
    await play(tester, '1:0');
    expect(coordinator.activeSlot, '1:0');
    expect(_key('cached-media-video-0:0'), findsNothing);
    expect(_key('cached-media-video-1:0'), findsOneWidget);
    expect(platform.live, {2});
    expect(platform.maxLive, 1);
    expect(
      platform.operations.indexOf(('dispose', 1)),
      lessThan(platform.operations.indexOf(('create', 2))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'under 20 percent media visibility releases while long article remains',
    (tester) async {
      await _show(
        tester,
        transform: (e) => _packed(
          e,
          cues: e.id == 'h-catcow-quad' ? List.filled(9, e.cues.first) : null,
        ),
      );
      await play(tester, '0:0');
      final coordinator = _media(tester, '0:0').coordinator;
      final view = tester.getRect(_key('plan-article'));
      final media = tester.getRect(_key('article-video-0:0'));
      _list(
        tester,
      ).controller!.jumpTo(media.bottom - view.top - media.height * .15);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_key('plan-move-0:0')).bottom,
        greaterThan(view.top),
      );
      expect(coordinator.activeSlot, isNull);
      expect(_key('cached-media-video-0:0'), findsNothing);
      expect(platform.live, isEmpty);
      _list(tester).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_key('cached-media-video-0:0'), findsNothing);
      expect(_toggle('0:0').hitTestable(), findsOneWidget);
      expect(platform.sources, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('320px/1.5x final article clears the fixed training bar', (
    tester,
  ) async {
    await _show(
      tester,
      width: 320,
      scale: 1.5,
      transform: (e) => e.id == 'h-catcow-quad'
          ? _copyExercise(e, cues: List.filled(6, e.cues.first))
          : e,
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.floatingActionButton, isNull);
    expect(_key('start').hitTestable(), findsOneWidget);
    final action = tester.getRect(_key('guide-training-button'));
    expect(action.height, 52);
    expect(action.left, 20);
    expect(action.right, 300);
    expect(action.bottom, 844 - 24 - 12);
    final controller = _list(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final last = tester.getRect(_key('guide-card-2:0'));
    expect(last.bottom, lessThanOrEqualTo(action.top - 24));
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two replacements before a frame preserve both current edits', (
    tester,
  ) async {
    final plan = _plan.copyWith(
      blocks: [
        for (final block in _plan.blocks)
          block.copyWith(
            items: [
              for (final item in block.items) item.copyWith(perSide: false),
            ],
          ),
      ],
    );
    final app = await _show(
      tester,
      height: 1800,
      plan: plan,
      transform: (exercise) => _copyExercise(
        _packed(exercise),
        alternative: switch (exercise.id) {
          'h-catcow-quad' => 'h-banana',
          'h-banana' => 'h-catcow-quad',
          _ => null,
        },
      ),
    );
    expect(PlanValidator(app.library).validate(plan), isEmpty);
    await play(tester, '0:0');
    expect(platform.live, {1});
    expect(_key('swap-h-catcow-quad').hitTestable(), findsOneWidget);
    expect(_key('swap-h-banana').hitTestable(), findsOneWidget);
    // The first replacement retires a live surface at the next frame. A second
    // input before that frame must read the newly committed plan, not its prior
    // snapshot while awaiting retirement.
    await tester.tap(_key('swap-h-catcow-quad'));
    await tester.tap(_key('swap-h-banana'));
    await tester.pumpAndSettle();
    final edited = app.store.lastPlan!;
    expect(edited.blocks[0].items.single.exerciseId, 'h-banana');
    expect(edited.blocks[1].items.single.exerciseId, 'h-catcow-quad');
    expect(edited.blocks[2].items.single.exerciseId, 'n-windshield');
    expect(
      edited.notes,
      containsAll([
        '手动把「${app.library['h-catcow-quad'].name}」换成「${app.library['h-banana'].name}」',
        '手动把「${app.library['h-banana'].name}」换成「${app.library['h-catcow-quad'].name}」',
      ]),
    );
    expect(platform.sources, hasLength(1));
    expect(platform.live, isEmpty);
    expect(platform.operations, contains(('dispose', 1)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a move without video has no misleading play control', (
    tester,
  ) async {
    await _show(
      tester,
      transform: (e) => e.id == 'h-catcow-quad'
          ? _copyExercise(
              e,
              media: ExerciseMedia(
                id: e.id,
                video: '',
                poster: e.media.poster,
                loopSeconds: e.media.loopSeconds,
                posterSeconds: e.media.posterSeconds,
                source: e.media.source,
                videoAvailable: false,
                lightPoster: e.media.lightPoster,
                lightVideoAvailable: false,
              ),
            )
          : e,
    );
    expect(_toggle('0:0'), findsNothing);
    expect(find.text('此动作暂无视频示范'), findsOneWidget);
    expect(_key('cached-media-video-0:0'), findsNothing);
    expect(platform.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
