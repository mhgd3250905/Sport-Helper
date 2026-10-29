import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

coach.CoachTaskState _task(String stage, {bool complete = false}) {
  const ids = [
    'understand',
    'parameters',
    'actions',
    'planning',
    'review',
    'output',
  ];
  final current = ids.indexOf(stage);
  return coach.CoachTaskState(
    type: 'plan',
    reused: false,
    nodes: [
      for (var index = 0; index < ids.length; index++)
        coach.CoachNodeState(
          id: ids[index],
          status: complete || index < current
              ? 'done'
              : index == current
              ? 'current'
              : 'pending',
          stamp: '教练待办：核对方案、交付卡片（你说的）（默认）',
        ),
    ],
  );
}

coach.CoachParamValue _param(Object? value, String source) =>
    coach.CoachParamValue(value: value, source: source, turn: 1);

Map<String, coach.CoachParamValue> _params() => {
  'scene': _param('home', 'user'),
  'goal': _param(['body.hip', 'purpose.stretch'], 'user'),
  'equipment': _param(<String>[], 'default'),
  'level': _param(3, 'derived'),
  'limits': _param(<String>[], 'default'),
};

Future<void> _show(
  WidgetTester tester, {
  coach.CoachTaskState? task,
  coach.CoachSessionState? state,
  ExerciseLibrary? library,
  bool waiting = true,
  bool reduced = false,
  bool tickers = true,
  bool visualComplete = false,
  double width = 390,
  double textScale = 1,
  VoidCallback? onCancel,
  SfPalette palette = SfPalette.light,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(palette),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => SfPaletteScope(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: TickerMode(
          enabled: tickers,
          child: CoachTaskBubble(
            task: task,
            sessionState: state,
            library: library,
            waiting: waiting,
            visualComplete: visualComplete,
            onCancel: onCancel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _face(String field) =>
    find.byKey(ValueKey('generation-chip-face-$field'));
Finder _fill(int index) =>
    find.byKey(ValueKey('generation-progress-fill-$index'));

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name} sourced capsules and approved card values',
      (tester) async {
        var cancelled = false;
        await _show(
          tester,
          state: coach.CoachSessionState(
            task: _task('parameters'),
            params: _params(),
          ),
          reduced: true,
          onCancel: () => cancelled = true,
          palette: palette,
        );
        expect(find.text('为你准备 · 居家拉伸'), findsOneWidget);
        expect(find.text('读懂你的需求'), findsOneWidget);
        final card = tester.widget<Container>(
          find.byKey(const ValueKey('generation-card')),
        );
        expect(card.padding, const EdgeInsets.fromLTRB(16, 14, 16, 16));
        final decoration = card.decoration! as BoxDecoration;
        final outline = card.foregroundDecoration! as BoxDecoration;
        final dark = palette.brightness == Brightness.dark;
        expect(decoration.color, palette.surface);
        expect(decoration.borderRadius, BorderRadius.circular(20));
        expect((outline.border! as Border).top.width, .5);
        expect(
          (outline.border! as Border).top.color,
          (dark ? Colors.white : Colors.black).withValues(
            alpha: dark ? .08 : .06,
          ),
        );
        if (dark) {
          expect(decoration.boxShadow, isEmpty);
        } else {
          expect(decoration.boxShadow, [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              offset: const Offset(0, 6),
              blurRadius: 20,
            ),
          ]);
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('generation-animation'))),
          const Size(44, 44),
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('generation-cancel-target')),
          ),
          const Size(44, 44),
        );
        for (final field in ['scene', 'goal', 'equipment', 'level', 'limits']) {
          expect(tester.getSize(_face(field)).height, 24);
          expect(tester.getSize(_face(field)).width, lessThan(130));
        }
        final scene =
            tester.widget<Container>(_face('scene')).decoration!
                as BoxDecoration;
        expect(scene.color, palette.accent.withValues(alpha: dark ? .18 : .10));
        expect(scene.border, isNull);
        final inferredContainer = tester.widget<Container>(_face('level'));
        final inferred = inferredContainer.decoration! as BoxDecoration;
        final inferredOutline =
            inferredContainer.foregroundDecoration! as BoxDecoration;
        expect(inferred.color, Colors.transparent);
        expect((inferredOutline.border! as Border).top.width, 1);
        expect(
          (inferredOutline.border! as Border).top.color,
          (dark ? Colors.white : Colors.black).withValues(
            alpha: dark ? .12 : .10,
          ),
        );
        expect(
          tester.widget<Text>(find.text('进阶')).style!.color,
          palette.muted,
        );
        for (final internal in ['教练待办', '交付卡片', '核对方案', '（你说的）', '（默认）']) {
          expect(find.textContaining(internal), findsNothing);
        }
        final title = tester.widget<Text>(find.text('为你准备 · 居家拉伸')).style!;
        expect(title.fontSize, 15);
        expect(title.fontWeight, FontWeight.w600);
        expect(title.height, 1.35);
        final status = tester.widget<Text>(find.text('读懂你的需求')).style!;
        expect(status.fontSize, 13);
        expect(status.fontWeight, FontWeight.w500);
        expect(status.height, 18 / 13);
        expect(tester.widget<Text>(find.text('取消')).style!.fontSize, 13);
        await tester.tap(find.text('取消'));
        expect(cancelled, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unknown parameters do not invent default tags or leak codes', (
    tester,
  ) async {
    await _show(tester, reduced: true);
    expect(find.text('正在想怎么练'), findsOneWidget);
    expect(find.text('居家'), findsNothing);
    expect(find.text('徒手'), findsNothing);
    expect(find.text('无伤痛'), findsNothing);
    expect(find.byKey(const ValueKey('generation-dots')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('generation-core'))),
      const Size(10, 10),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('generation-halo'))),
      const Size(20, 20),
    );
    await _show(
      tester,
      state: coach.CoachSessionState(
        params: {
          'goal': _param(['purpose.internal_unknown'], 'user'),
          'equipment': _param(['equip.internal_unknown'], 'user'),
        },
      ),
      reduced: true,
    );
    expect(find.textContaining('internal_unknown'), findsNothing);
    expect(find.text('正在想怎么练'), findsOneWidget);
  });

  testWidgets('SDK nodes map to status sentences and four measured segments', (
    tester,
  ) async {
    const stages = [
      ('actions', '挑好了 2 个动作', 1),
      ('planning', '安排顺序和时长', 2),
      ('review', '最后检查一遍', 3),
      ('output', '马上就好', 4),
    ];
    for (final (stage, sentence, completed) in stages) {
      await _show(
        tester,
        state: coach.CoachSessionState(
          task: _task(stage),
          picks: ['h-catcow-quad', 'h-banana'],
        ),
        reduced: true,
      );
      expect(find.text(sentence), findsOneWidget);
      for (var index = 0; index < 4; index++) {
        final segment = find.byKey(ValueKey('generation-progress-$index'));
        expect(tester.getSize(segment).height, 3);
        final first = tester.getRect(
          find.byKey(const ValueKey('generation-progress-0')),
        );
        expect(tester.getRect(segment).width, closeTo(first.width, .001));
        if (index > 0) {
          final previous = tester.getRect(
            find.byKey(ValueKey('generation-progress-${index - 1}')),
          );
          expect(
            tester.getRect(segment).left - previous.right,
            closeTo(4, .001),
          );
        }
        final fill = tester.widget<FractionallySizedBox>(_fill(index));
        expect(fill.widthFactor, index < completed ? 1 : 0);
        expect(
          tester.widget<ClipRRect>(segment).borderRadius,
          BorderRadius.circular(1.5),
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed segment fills in 400ms and status uses staggered 160/220ms motion',
    (tester) async {
      await _show(tester, task: _task('understand'));
      await _show(tester, task: _task('actions'));
      expect(tester.widget<FractionallySizedBox>(_fill(0)).widthFactor, 0);
      expect(tester.widget<FractionallySizedBox>(_fill(1)).widthFactor, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<FractionallySizedBox>(_fill(0)).widthFactor,
        closeTo(Curves.easeOutCubic.transform(.5), .001),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<FractionallySizedBox>(_fill(0)).widthFactor, 1);
      expect(tester.widget<FractionallySizedBox>(_fill(1)).widthFactor, 0);
      await _show(tester, task: _task('planning'));
      expect(find.text('读懂你的需求'), findsOneWidget);
      expect(find.text('安排顺序和时长'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 80));
      final old = find
          .ancestor(of: find.text('读懂你的需求'), matching: find.byType(Transform))
          .first;
      final next = find
          .ancestor(of: find.text('安排顺序和时长'), matching: find.byType(Transform))
          .first;
      expect(
        tester.widget<Transform>(old).transform.storage[13],
        closeTo(-6 * Curves.easeInCubic.transform(.5), .001),
      );
      expect(
        tester.widget<Transform>(next).transform.storage[13],
        closeTo(6 * (1 - Curves.easeOutCubic.transform(20 / 220)), .001),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('读懂你的需求'), findsNothing);
      expect(find.text('安排顺序和时长'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rotation is linear and stops for reduced motion and TickerMode',
    (tester) async {
      await _show(tester);
      await tester.pump(const Duration(milliseconds: 350));
      final rotation = find.byKey(const ValueKey('generation-rotation'));
      expect(
        tester.widget<RotationTransition>(rotation).turns.value,
        closeTo(.25, .001),
      );
      await _show(tester, tickers: false);
      final mutedValue = tester
          .widget<RotationTransition>(rotation)
          .turns
          .value;
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.widget<RotationTransition>(rotation).turns.value,
        mutedValue,
      );
      await _show(tester, reduced: true);
      final value = tester.widget<RotationTransition>(rotation).turns.value;
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.widget<RotationTransition>(rotation).turns.value, value);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('trusted picked thumbnails hold 900ms and crossfade for 250ms', (
    tester,
  ) async {
    final library = loadLibrary();
    final state = coach.CoachSessionState(
      task: _task('actions'),
      picks: ['h-catcow-quad', 'h-banana'],
    );
    await _show(tester, state: state, library: library);
    expect(find.byKey(const ValueKey('generation-dots')), findsNothing);
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-catcow-quad')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-banana')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-banana')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 125));
    for (final id in state.picks) {
      final image = find.byKey(ValueKey('generation-thumbnail-$id'));
      expect(image, findsOneWidget);
      final opacity = find
          .ancestor(of: image, matching: find.byType(Opacity))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, closeTo(.5, .001));
    }
    await tester.pump(const Duration(milliseconds: 125));
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-catcow-quad')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-banana')),
      findsOneWidget,
    );
    await _show(
      tester,
      state: state.copyWith(picks: ['h-catcow-quad']),
      library: library,
    );
    expect(
      find.byKey(const ValueKey('generation-thumbnail-h-catcow-quad')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'parameter changes use sourced capsules with 60ms stagger and 200ms entrance',
    (tester) async {
      await _show(tester, reduced: true);
      await _show(tester, state: coach.CoachSessionState(params: _params()));
      FadeTransition fade(String field) => tester.widget<FadeTransition>(
        find
            .ancestor(of: _face(field), matching: find.byType(FadeTransition))
            .first,
      );
      expect(fade('scene').opacity.value, 0);
      expect(fade('goal').opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        fade('scene').opacity.value,
        closeTo(Curves.easeOutCubic.transform(.3), .001),
      );
      expect(fade('goal').opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fade('scene').opacity.value, 1);
      expect(fade('goal').opacity.value, 1);
      final source = coach.CoachSessionState(
        params: {
          ..._params(),
          'equipment': _param(['equip.chair', 'equip.wall'], 'user'),
        },
      );
      await _show(tester, state: source, reduced: true);
      expect(find.text('椅子'), findsOneWidget);
      expect(find.text('墙'), findsNothing);
      expect(find.text('徒手'), findsNothing);
      expect(
        (tester.widget<Container>(_face('equipment')).decoration!
                as BoxDecoration)
            .border,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'completion shows check and reserves cancel space without changing height',
    (tester) async {
      final state = coach.CoachSessionState(
        task: _task('review'),
        params: _params(),
      );
      await _show(tester, state: state, reduced: true, onCancel: () {});
      final card = find.byKey(const ValueKey('generation-card'));
      final previousHeight = tester.getSize(card).height;
      final cancelRect = tester.getRect(
        find.byKey(const ValueKey('generation-cancel-target')),
      );
      expect(find.text('取消'), findsOneWidget);
      await _show(
        tester,
        state: state.copyWith(task: _task('output', complete: true)),
        waiting: false,
        reduced: true,
        onCancel: () {},
      );
      expect(tester.getSize(card).height, previousHeight);
      expect(
        tester.getRect(find.byKey(const ValueKey('generation-cancel-target'))),
        cancelRect,
      );
      expect(find.text('取消'), findsNothing);
      final check = tester.widget<Icon>(
        find.byKey(const ValueKey('generation-check')),
      );
      expect(check.icon, Icons.check_rounded);
      expect(check.size, 20);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('马上就好'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('SDK output done while waiting does not announce reply success', (
    tester,
  ) async {
    final state = coach.CoachSessionState(
      task: _task('output', complete: true),
    );
    await _show(tester, state: state, onCancel: () {});
    expect(find.text('马上就好'), findsOneWidget);
    expect(find.byKey(const ValueKey('generation-check')), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    await _show(tester, state: state, visualComplete: true, onCancel: () {});
    expect(find.byKey(const ValueKey('generation-check')), findsOneWidget);
    expect(find.text('取消'), findsNothing);
    await tester.pump(const Duration(milliseconds: 240));
    final rotation = find.byKey(const ValueKey('generation-rotation'));
    final stopped = tester.widget<RotationTransition>(rotation).turns.value;
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<RotationTransition>(rotation).turns.value, stopped);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('success check preserves the completed segment 400ms fill', (
    tester,
  ) async {
    await _show(tester, task: _task('review'));
    await tester.pump(const Duration(milliseconds: 450));
    await _show(
      tester,
      task: _task('output', complete: true),
      visualComplete: true,
    );
    expect(tester.widget<FractionallySizedBox>(_fill(3)).widthFactor, 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<FractionallySizedBox>(_fill(3)).widthFactor,
      closeTo(Curves.easeOutCubic.transform(.5), .001),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byKey(const ValueKey('generation-check')), findsOneWidget);
    final rotation = find.byKey(const ValueKey('generation-rotation'));
    final turn = tester.widget<RotationTransition>(rotation).turns.value;
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.widget<FractionallySizedBox>(_fill(3)).widthFactor, 1);
    expect(tester.widget<RotationTransition>(rotation).turns.value, turn);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'switching to reduced motion stops all in-flight tickers and pins first image',
    (tester) async {
      final state = coach.CoachSessionState(
        task: _task('actions'),
        params: _params(),
        picks: ['h-catcow-quad', 'h-banana'],
      );
      final library = loadLibrary();
      await _show(tester);
      await _show(tester, state: state, library: library);
      await tester.pump(const Duration(milliseconds: 75));
      await _show(
        tester,
        state: state.copyWith(task: _task('planning')),
        library: library,
        reduced: true,
      );
      await tester.pump();
      expect(find.text('挑好了 2 个动作'), findsNothing);
      expect(find.text('安排顺序和时长'), findsOneWidget);
      expect(find.byType(ShaderMask), findsNothing);
      expect(
        find.byKey(const ValueKey('generation-progress-band-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('generation-thumbnail-h-catcow-quad')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('generation-thumbnail-h-banana')),
        findsNothing,
      );
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets(
    'visual completion closes the ring and settles the check at 240ms',
    (tester) async {
      await _show(tester, task: _task('review'), onCancel: () {});
      final card = find.byKey(const ValueKey('generation-card'));
      final height = tester.getSize(card).height;
      await _show(
        tester,
        task: _task('review'),
        visualComplete: true,
        onCancel: () {},
      );
      expect(find.byKey(const ValueKey('generation-check')), findsOneWidget);
      expect(find.text('取消'), findsNothing);
      expect(tester.getSize(card).height, height);
      await tester.pump(const Duration(milliseconds: 240));
      final rotation = find.byKey(const ValueKey('generation-rotation'));
      final turn = tester.widget<RotationTransition>(rotation).turns.value;
      final check = find.byKey(const ValueKey('generation-check'));
      final opacity = find
          .ancestor(of: check, matching: find.byType(Opacity))
          .first;
      final scale = find
          .ancestor(of: check, matching: find.byType(Transform))
          .first;
      expect(tester.widget<Opacity>(opacity).opacity, 1);
      expect(
        tester.widget<Transform>(scale).transform.storage[0],
        closeTo(1, .001),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<RotationTransition>(rotation).turns.value, turn);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets('320px Chinese title stays within one line at ${scale}x', (
      tester,
    ) async {
      await _show(
        tester,
        state: coach.CoachSessionState(
          task: _task('planning'),
          params: {..._params(), 'scene': _param('office', 'user')},
        ),
        reduced: true,
        width: 320,
        textScale: scale,
        onCancel: () {},
      );
      final title = find.text('为你准备 · 办公室拉伸');
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).maxLines, 1);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
      final rect = tester.getRect(title);
      final cancel = tester.getRect(
        find.byKey(const ValueKey('generation-cancel-target')),
      );
      expect(rect.right, lessThanOrEqualTo(cancel.left));
      expect(rect.left, greaterThanOrEqualTo(72));
      expect(
        tester.getRect(find.byKey(const ValueKey('generation-card'))).right,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
