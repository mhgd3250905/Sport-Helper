import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show DrillMediaHandoff, DrillMediaView;

import 'app_flow_test.dart' show services;

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
        home: const PlanPage(plan: _plan),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

Iterable<ExerciseVideo> _running(WidgetTester tester) => tester
    .widgetList<ExerciseVideo>(find.byType(ExerciseVideo))
    .where((v) => v.playing && !v.paused);

ExerciseVideo _video(WidgetTester tester, String slot) =>
    tester.widget<ExerciseVideo>(
      find.descendant(
        of: find.byKey(ValueKey('article-video-$slot')),
        matching: find.byType(ExerciseVideo),
      ),
    );

Finder _toggle(String slot) =>
    find.byKey(ValueKey('article-video-toggle-$slot'));

ListView _list(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(const ValueKey('plan-article')));

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final theme = palette.isDark ? 'dark' : 'light';
    testWidgets(
      '$theme article uses themed text and stills and retains manual preview control',
      (tester) async {
        final s = await _show(tester, palette: palette);
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
            .map((image) => image.image)
            .whereType<AssetImage>()
            .map((image) => image.assetName);
        expect(stills, contains(poster));
        expect(stills, isNot(contains(otherPoster)));
        final surface = tester.widget<DrillMediaView>(
          find.descendant(of: video, matching: find.byType(DrillMediaView)),
        );
        expect(surface.stage, palette.mediaStage);
        expect(
          surface.media.videoAsset,
          palette.isDark ? media.video : media.lightVideo!,
        );
        expect(find.byType(DrillMediaHandoff), findsNothing);
        final control = _toggle('0:0');
        expect(control.hitTestable(), findsOneWidget);
        expect(tester.widget<SfCircleButton>(control).iconColor, palette.text);
        expect(_running(tester), isEmpty);

        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(_running(tester), hasLength(1));
        expect(
          tester.widget<SfCircleButton>(control).tooltip,
          '暂停${exercise.name}示范',
        );
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
        expect(
          tester.widget<SfCircleButton>(control).tooltip,
          '播放${exercise.name}示范',
        );
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
    final s = await _show(tester);
    final control = _toggle('0:0');
    expect(_video(tester, '0:0').playing, isFalse);
    expect(
      tester.widget<SfCircleButton>(control).tooltip,
      '播放${s.library['h-catcow-quad'].name}示范',
    );
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

  testWidgets('selecting another visible preview pauses the previous one', (
    tester,
  ) async {
    await _show(tester, height: 1000);
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
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(_video(tester, '0:0').playing, isTrue);
    expect(_video(tester, '0:0').paused, isTrue);
    expect(_video(tester, '1:0').playing, isTrue);
    expect(_video(tester, '1:0').paused, isFalse);
    expect(_running(tester), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'video leaving the viewport stops even while its article remains',
    (tester) async {
      await _show(
        tester,
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
