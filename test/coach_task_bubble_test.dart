import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/polish_card.dart';
import 'package:smartfit/ui/theme/ui_polish_tokens.dart';
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
  VoidCallback? onCancel,
  SfPalette palette = SfPalette.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(palette),
      builder: (context, child) => SfPaletteScope(
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
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
        expect(find.text('正在为你准备 · 居家拉伸'), findsOneWidget);
        expect(find.text('读懂你的需求'), findsOneWidget);
        expect(find.byType(SfPolishCard), findsOneWidget);
        expect(
          tester.widget<SfPolishCard>(find.byType(SfPolishCard)).padding,
          const EdgeInsets.all(16),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('generation-animation'))),
          const Size(56, 56),
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('generation-cancel-target')),
          ),
          const Size(44, 44),
        );
        for (final field in ['scene', 'goal', 'equipment', 'level', 'limits']) {
          expect(tester.getSize(_face(field)).height, 26);
          expect(tester.getSize(_face(field)).width, lessThan(130));
        }
        final scene =
            tester.widget<Container>(_face('scene')).decoration!
                as BoxDecoration;
        expect(scene.color, palette.accent.withValues(alpha: .12));
        expect(scene.border, isNull);
        final inferred =
            tester.widget<Container>(_face('level')).decoration!
                as BoxDecoration;
        expect(inferred.color, Colors.transparent);
        expect((inferred.border! as Border).top.width, 1);
        expect((inferred.border! as Border).top.color, SfCardTokens.edge);
        expect(
          tester.widget<Text>(find.text('进阶')).style!.color,
          palette.muted,
        );
        for (final internal in ['教练待办', '交付卡片', '核对方案', '（你说的）', '（默认）']) {
          expect(find.textContaining(internal), findsNothing);
        }
        final title = tester.widget<Text>(find.text('正在为你准备 · 居家拉伸')).style!;
        expect(title.fontSize, 15);
        expect(title.fontWeight, FontWeight.w600);
        expect(tester.widget<Text>(find.text('读懂你的需求')).style!.fontSize, 16);
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
    expect(find.text('正在想怎么练…'), findsOneWidget);
    expect(find.text('居家'), findsNothing);
    expect(find.text('徒手'), findsNothing);
    expect(find.text('无伤痛'), findsNothing);
    expect(find.byKey(const ValueKey('generation-dots')), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      expect(
        tester.getSize(find.byKey(ValueKey('generation-dot-$index'))),
        const Size(6, 6),
      );
    }
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
    expect(find.text('正在想怎么练…'), findsOneWidget);
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
        expect(fill.widthFactor, index <= completed ? 1 : 0);
        expect(
          tester.widget<ClipRRect>(segment).borderRadius,
          BorderRadius.circular(2),
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'current progress fills in 400ms easeOutCubic and status moves in 220ms',
    (tester) async {
      await _show(tester, task: _task('actions'));
      expect(tester.widget<FractionallySizedBox>(_fill(1)).widthFactor, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<FractionallySizedBox>(_fill(1)).widthFactor,
        closeTo(Curves.easeOutCubic.transform(.5), .001),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<FractionallySizedBox>(_fill(1)).widthFactor, 1);
      await _show(tester, task: _task('planning'));
      expect(find.text('读懂你的需求'), findsOneWidget);
      expect(find.text('安排顺序和时长'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 110));
      final old = find
          .ancestor(of: find.text('读懂你的需求'), matching: find.byType(Transform))
          .first;
      final next = find
          .ancestor(of: find.text('安排顺序和时长'), matching: find.byType(Transform))
          .first;
      expect(
        tester.widget<Transform>(old).transform.storage[13],
        closeTo(-4, .001),
      );
      expect(
        tester.widget<Transform>(next).transform.storage[13],
        closeTo(4, .001),
      );
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.text('读懂你的需求'), findsNothing);
      expect(find.text('安排顺序和时长'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rotation is linear and stops for reduced motion and TickerMode',
    (tester) async {
      await _show(tester);
      await tester.pump(const Duration(milliseconds: 300));
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
      expect(fade('scene').opacity.value, closeTo(.3, .001));
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

  testWidgets('completion uses 300ms size transition without diagnostic text', (
    tester,
  ) async {
    await _show(tester, task: _task('review'), reduced: true);
    await _show(
      tester,
      task: _task('output', complete: true),
      waiting: false,
      reduced: true,
    );
    final size = tester.widget<AnimatedSize>(
      find.byKey(const ValueKey('generation-completion-size')),
    );
    expect(size.duration, const Duration(milliseconds: 300));
    expect(size.curve, Curves.easeOutCubic);
    await tester.pumpAndSettle();
    expect(find.byType(SfPolishCard), findsNothing);
  });
}
