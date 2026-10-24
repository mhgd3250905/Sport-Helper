import 'package:ugk_trainer/ugk_trainer.dart' show TrainerRingPainter;
// The motion list of docs/design-audit-2026-10-19.md §5 as assertions:
// the countdown ring repaints on its own, the last seconds breathe (not
// under reduced motion), plain pages push sideways (cross-fade under
// reduced motion), new messages land from the speaker's corner, and the
// finish moment ends settled.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/celebration.dart';
import 'package:smartfit/ui/theme/countdown.dart';
import 'package:smartfit/ui/theme/transitions.dart';

import 'app_flow_test.dart' show services, tall;

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
  theme: buildTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// One 12-second hold: a timed work phase with nothing before it but the
/// prep countdown.
const _hold = TrainingPlan(
  id: 'hold', source: 'template', title: '一个静态动作', summary: '', goal: 'relax', scene: 'home',
  equipment: [], level: 1, targetMinutes: 1,
  blocks: [PlanBlock(id: 'main', name: '主训练', type: BlockType.main, rounds: 1, restBetweenRoundsSeconds: 0, items: [
    PlanItem(exerciseId: 'h-squat', mode: DoseMode.time, sets: 1, workSeconds: 12, perSide: false, restSeconds: 0),
  ])],
);

void main() {
  testWidgets('countdown: the last seconds breathe; reduced motion only changes colour', (tester) async {
    final p = ValueNotifier(.5);
    addTearDown(p.dispose);
    // Breathing = the ring face is scaled above 1 part-way into a beat.
    Future<bool> breathes() async {
      await tester.pump(const Duration(milliseconds: 300));
      return tester
          .widgetList<Transform>(find.descendant(of: find.byType(SfCountdownRing), matching: find.byType(Transform)))
          .any((t) => t.transform.getMaxScaleOnAxis() > 1.01);
    }

    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '3', urgent: true)));
    expect(await breathes(), isTrue);
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '2', urgent: true), reduced: true));
    expect(await breathes(), isFalse);

    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '8')));
    expect(await breathes(), isFalse);
  });

  testWidgets('countdown: the number rolls (two on screen mid-roll), one key', (tester) async {
    final p = ValueNotifier(.2);
    addTearDown(p.dispose);
    const k = ValueKey('n');
    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '9', numberKey: k)));
    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '8', numberKey: k)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('9'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.byKey(k), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('9'), findsNothing);
  });

  testWidgets('countdown: the last seconds still roll the digit while breathing (PR #3 review P3)', (tester) async {
    final p = ValueNotifier(.8);
    addTearDown(p.dispose);
    const k = ValueKey('n');
    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '4', numberKey: k)));
    final number = tester.element(find.byKey(k));
    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '3', numberKey: k, urgent: true)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_host(SfCountdownRing(progress: p, value: '2', numberKey: k, urgent: true)));
    await tester.pump(const Duration(milliseconds: 100));
    // Same number element (not remounted), old digit still rolling out.
    expect(tester.element(find.byKey(k)), same(number));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
  });

  testWidgets('player: the ring follows time between page rebuilds', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(AppScope(services: s, child: MaterialApp(theme: buildTheme(), home: const PlayerPage(plan: _hold))));
    await tester.pump();
    // Trainer 0.2 uses the same live painter around its pause button,
    // with separate countdown digits instead of TrainerCountdownRing.
    final ring = find.byKey(const ValueKey('ring'));
    TrainerRingPainter painter() =>
        tester.widget<CustomPaint>(ring).painter! as TrainerRingPainter;
    final progress = painter().progress;
    final before = progress.value;
    await tester.pump(const Duration(milliseconds: 300));
    // Same notifier, advanced: the painter listens, the page need not.
    expect(painter().progress, same(progress));
    expect(progress.value, greaterThan(before));
    // Pausing dims the ring.
    await tester.tap(find.byKey(const ValueKey('pause')));
    await tester.pump();
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(
        of: ring,
        matching: find.byType(AnimatedOpacity),
      ).first).opacity,
      .45,
    );
    final paused = progress.value;
    await tester.pump(const Duration(milliseconds: 300));
    expect(progress.value, paused);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pages push sideways; reduced motion cross-fades', (tester) async {
    for (final reduced in [false, true]) {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ));
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('next'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(SfPageSlide), reduced ? findsNothing : findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('next'), findsOneWidget);
    }
    expect(SfPageTransitionsBuilder().transitionDuration, SfMotion.page);
    expect(buildTheme().pageTransitionsTheme.builders[defaultTargetPlatform], isA<SfPageTransitionsBuilder>());
  });

  testWidgets('a new message lands from its corner; reduced motion only fades', (tester) async {
    Finder scaled() => find.descendant(of: find.byType(Appear), matching: find.byType(Transform));
    await tester.pumpWidget(_host(const Appear(animate: true, anchor: Alignment.bottomRight, child: Text('hi'))));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scaled(), findsWidgets);
    await tester.pumpAndSettle();
    expect(scaled(), findsNothing);

    await tester.pumpWidget(_host(const Appear(key: ValueKey('b'), animate: true, child: Text('hi')), reduced: true));
    await tester.pump(const Duration(milliseconds: 60));
    expect(scaled(), findsNothing);
    expect(find.descendant(of: find.byType(Appear), matching: find.byType(Opacity)), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('finish: plays once and settles; reduced motion is there at once', (tester) async {
    Widget finish() => const SfFinishTimeline(
      full: true,
      child: Column(children: [SfFinishMark(full: true), SfFinishReveal(beginMs: 420, child: Text('训练完成！'))]),
    );
    double opacity() => tester.widget<Opacity>(find.ancestor(of: find.text('训练完成！'), matching: find.byType(Opacity)).first).opacity;

    await tester.pumpWidget(_host(finish()));
    expect(opacity(), 0);
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(finish(), reduced: true));
    expect(opacity(), 1);
  });
}
