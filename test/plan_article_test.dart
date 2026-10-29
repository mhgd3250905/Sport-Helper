import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show
        DrillMediaHandoff,
        DrillMediaView,
        UgkPackedAlphaVideo,
        PackedAlphaPlatform,
        PackedAlphaUriPlatform;

import 'app_flow_test.dart' show services;

/// Native transport only. The actual exported SDK widget/controller still run;
/// these tests make no decoding or composed-alpha claim for the fixture MP4s.
class _ArticlePlatform extends PackedAlphaPlatform
    implements PackedAlphaUriPlatform {
  final assets = <String>[];
  final operations = <(String, int)>[];
  final stream = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => stream.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) async {
    assets.add(asset);
    final id = assets.length;
    operations.add(('create', id));
    scheduleMicrotask(() {
      stream.add({'playerId': id, 'type': 'ready'});
      stream.add({'playerId': id, 'type': 'first-frame'});
    });
    return (playerId: id, textureId: id + 100);
  }

  @override
  Future<({int playerId, int textureId})> createUri(Uri sourceUri) =>
      throw StateError('This legacy layout fixture uses asset media only');
  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    operations.add((type, id));
    return type == 'position' ? .25 : null;
  }
}

late _ArticlePlatform _platform;

Exercise _playable(Exercise source, SfPalette palette) {
  final media = source.media;
  return _copyExercise(
    source,
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
      packedAlphaVideo: palette.isDark ? media.video : media.lightVideo,
      alphaPlaybackPoster: media.playbackPosterFor(light: !palette.isDark),
    ),
  );
}

String? _assetOf(Image image) {
  ImageProvider provider = image.image;
  while (provider is ResizeImage) {
    provider = provider.imageProvider;
  }
  return provider is AssetImage ? provider.assetName : null;
}

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
  alternative: source.alternative,
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
  bool playable = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var s = services();
  if (transform != null || playable) {
    s = AppServices(
      library: ExerciseLibrary(
        s.library.all.map((exercise) {
          final value = transform?.call(exercise) ?? exercise;
          return playable ? _playable(value, palette) : value;
        }).toList(),
      ),
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
        themeAnimationDuration: Duration.zero,
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
  });
  return s;
}

Iterable<CachedExerciseMedia> _running(WidgetTester tester) => tester
    .widgetList<CachedExerciseMedia>(find.byType(CachedExerciseMedia))
    .where((v) => v.playing && !v.paused);

CachedExerciseMedia _video(WidgetTester tester, String slot) =>
    tester.widget<CachedExerciseMedia>(
      find.descendant(
        of: find.byKey(ValueKey('article-video-$slot')),
        matching: find.byType(CachedExerciseMedia),
      ),
    );

Finder _toggle(String slot) =>
    find.byKey(ValueKey('article-video-toggle-$slot'));

Icon _icon(WidgetTester tester, String slot) => tester.widget<Icon>(
  find.descendant(of: _toggle(slot), matching: find.byType(Icon)).last,
);

ListView _list(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(const ValueKey('plan-article')));

void main() {
  setUp(() {
    _platform = _ArticlePlatform();
    UgkPackedAlphaVideo.debugPlatform = _platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await _platform.stream.close();
  });

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

  testWidgets('article localizes protocol sections and uses primary action', (
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
    final cardDuration = toCoachRoutine(plan, s.library).durationLabel;
    expect(find.text(cardDuration), findsOneWidget);
    expect(cardDuration, isNot('${plan.targetMinutes} 分钟'));
    expect(
      tester
          .widget<SfPrimaryButton>(find.byKey(const ValueKey('start')))
          .emphasized,
      isFalse,
    );
    await tester.scrollUntilVisible(find.text('主练'), 200);
    await tester.pumpAndSettle();
    expect(find.text('main'), findsNothing);
    await tester.scrollUntilVisible(find.text('放松'), 200);
    await tester.pumpAndSettle();
    expect(find.text('cooldown'), findsNothing);
    final controller = _list(tester).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final action = tester.getRect(find.byKey(const ValueKey('start')));
    final last = tester.getRect(find.byKey(const ValueKey('plan-move-2:0')));
    expect(last.bottom, lessThanOrEqualTo(action.top - SfSpace.x6));
    expect(tester.takeException(), isNull);
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final theme = palette.isDark ? 'dark' : 'light';
    testWidgets(
      '$theme article uses themed text and stills and retains manual preview control',
      (tester) async {
        final s = await _show(tester, palette: palette, playable: true);
        final exercise = s.library['h-catcow-quad'];
        final media = exercise.media;
        final video = find.byKey(const ValueKey('article-video-0:0'));
        expect(Theme.of(tester.element(video)).brightness, palette.brightness);
        expect(
          tester.widget<Text>(find.text(_plan.summary)).style!.color,
          palette.muted,
        );
        expect(
          tester
              .widget<Text>(find.text('1. ${exercise.cues.first}'))
              .style!
              .color,
          palette.text,
        );
        final poster = media.playbackPosterFor(light: !palette.isDark);
        final otherPoster = media.playbackPosterFor(light: palette.isDark);
        final stills = tester
            .widgetList<Image>(
              find.descendant(of: video, matching: find.byType(Image)),
            )
            .map(_assetOf)
            .whereType<String>();
        expect(stills, contains(poster));
        expect(stills, isNot(contains(otherPoster)));
        expect(find.byType(DrillMediaView), findsNothing);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        expect(_platform.assets, isEmpty);
        expect(find.byType(DrillMediaHandoff), findsNothing);
        final control = _toggle('0:0');
        expect(control.hitTestable(), findsOneWidget);
        expect(
          _icon(tester, '0:0').color,
          palette.isDark ? Colors.white : palette.accent,
        );
        expect(tester.getSize(control), const Size(44, 44));
        expect(_running(tester), isEmpty);

        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(_running(tester), hasLength(1));
        expect(
          _platform.assets.single,
          palette.isDark ? media.video : media.lightVideo!,
        );
        expect(_icon(tester, '0:0').icon, Icons.pause_rounded);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(_video(tester, '0:0').playing, isTrue);
        expect(_video(tester, '0:0').paused, isTrue);
        expect(_running(tester), isEmpty);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(_running(tester), hasLength(1));

        final view = tester.getRect(find.byKey(const ValueKey('plan-article')));
        final videoRect = tester.getRect(video);
        _list(tester).controller!.jumpTo(videoRect.bottom - view.top + 2);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const ValueKey('plan-move-0:0'))).bottom,
          greaterThan(view.top),
        );
        expect(_video(tester, '0:0').playing, isFalse);
        expect(_running(tester), isEmpty);
        _list(tester).controller!.jumpTo(0);
        await tester.pumpAndSettle();
        expect(_video(tester, '0:0').playing, isFalse);
        expect(control.hitTestable(), findsOneWidget);
        expect(_icon(tester, '0:0').icon, Icons.play_arrow_rounded);
        expect(_running(tester), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'article keeps introduction, original sections and global move numbers without autoplay',
    (tester) async {
      final s = await _show(tester);
      expect(find.byKey(const ValueKey('plan-introduction')), findsOneWidget);
      expect(find.text('安排说明'), findsOneWidget);
      expect(find.text(_plan.title), findsOneWidget);
      expect(find.text('3 个动作'), findsOneWidget);
      expect(find.text('先活动开'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview')), findsNothing);
      expect(find.byType(SfPanel), findsNothing);
      expect(_running(tester), isEmpty);
      final items = _plan.items.toList();
      for (var i = 0; i < items.length; i++) {
        final title = find.text(
          '${i + 1}. ${s.library[items[i].exerciseId].name}',
        );
        await tester.scrollUntilVisible(title, 220);
        await tester.pumpAndSettle();
        expect(title, findsOneWidget);
        expect(_running(tester), isEmpty);
      }
      expect(find.text('收尾放松'), findsOneWidget);
      expect(find.text('怎么做'), findsWidgets);
      expect(find.text('前往训练'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview requires a tap and pauses/resumes its retained frame', (
    tester,
  ) async {
    await _show(tester, playable: true);
    final control = _toggle('0:0');
    expect(_video(tester, '0:0').playing, isFalse);
    expect(_icon(tester, '0:0').icon, Icons.play_arrow_rounded);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(_running(tester), hasLength(1));
    expect(_video(tester, '0:0').playing, isTrue);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(_running(tester), isEmpty);
    expect(_video(tester, '0:0').playing, isTrue);
    expect(_video(tester, '0:0').paused, isTrue);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(_video(tester, '0:0').paused, isFalse);
    expect(_running(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting another visible preview releases the previous decoder',
    (tester) async {
      await _show(tester, height: 1000, playable: true);
      await tester.tap(_toggle('0:0'));
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byKey(const ValueKey('plan-article')));
      final second = _toggle('1:0');
      final shift = tester.getRect(second).bottom - view.bottom + 64;
      if (shift > 0) {
        _list(tester).controller!.jumpTo(shift);
        await tester.pumpAndSettle();
      }
      expect(_video(tester, '0:0').playing, isTrue);
      final visibleMedia = tester
          .getRect(find.byKey(const ValueKey('article-video-1:0')))
          .intersect(view);
      expect(visibleMedia.height, greaterThan(48));
      // The right-side button can overlap the floating training action. Tap
      // the visible left side of the same media instead of the covered centre.
      final point = visibleMedia.topLeft + const Offset(24, 24);
      expect(
        tester.getRect(find.byKey(const ValueKey('start'))).contains(point),
        isFalse,
      );
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(_video(tester, '0:0').playing, isFalse);
      expect(_video(tester, '1:0').playing, isTrue);
      expect(_video(tester, '1:0').paused, isFalse);
      expect(_running(tester), hasLength(1));
      expect(find.byType(UgkPackedAlphaVideo), findsOneWidget);
      expect(
        _platform.operations.indexOf(('dispose', 1)),
        lessThan(_platform.operations.indexOf(('create', 2))),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'video leaving the viewport stops even while its article remains',
    (tester) async {
      await _show(
        tester,
        playable: true,
        transform: (e) => e.id == 'h-catcow-quad'
            ? _copyExercise(e, cues: List.filled(9, e.cues.first))
            : e,
      );
      await tester.tap(_toggle('0:0'));
      await tester.pumpAndSettle();
      final view = tester.getRect(find.byKey(const ValueKey('plan-article')));
      final video = tester.getRect(
        find.byKey(const ValueKey('article-video-0:0')),
      );
      _list(tester).controller!.jumpTo(video.bottom - view.top + 2);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('plan-move-0:0'))).bottom,
        greaterThan(view.top),
      );
      expect(_video(tester, '0:0').playing, isFalse);
      expect(_running(tester), isEmpty);
      _list(tester).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_video(tester, '0:0').playing, isFalse);
      expect(_running(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px/1.5x article and final section clear the floating action',
    (tester) async {
      await _show(
        tester,
        width: 320,
        scale: 1.5,
        transform: (e) => e.id == 'h-catcow-quad'
            ? _copyExercise(e, cues: List.filled(6, e.cues.first))
            : e,
      );
      final start = find.byKey(const ValueKey('start'));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isNull);
      expect(
        scaffold.floatingActionButtonLocation,
        FloatingActionButtonLocation.endFloat,
      );
      expect(start.hitTestable(), findsOneWidget);
      expect(tester.getRect(start).height, greaterThanOrEqualTo(52));
      final controller = _list(tester).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('plan-move-2:0')));
      final action = tester.getRect(start);
      expect(last.bottom, lessThanOrEqualTo(action.top - 12));
      expect(action.right, lessThanOrEqualTo(320 - 12));
      expect(action.bottom, lessThanOrEqualTo(844 - 24));
      expect(_running(tester), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a move declared without video has no misleading play control', (
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
    expect(_video(tester, '0:0').playing, isFalse);
    expect(_running(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
