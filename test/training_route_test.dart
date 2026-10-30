import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/ui/training_route.dart';

class _FramePainter extends CustomPainter {
  _FramePainter(ValueNotifier<int> frames) : super(repaint: frames);

  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.grey);
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}

Finder _ancestor(Finder child, Type type) =>
    find.ancestor(of: child, matching: find.byType(type));

void main() {
  for (final brightness in Brightness.values) {
    for (final reduced in [false, true]) {
      testWidgets(
        '${brightness.name}, reduced=$reduced: one unchanged page, 320/260 motion, opaque resting stage',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          final sourceFrame = ValueNotifier(0);
          final videoFrame = ValueNotifier(0);
          final sourcePainter = _FramePainter(sourceFrame);
          final videoPainter = _FramePainter(videoFrame);
          final nav = GlobalKey<NavigatorState>();
          const sourceKey = ValueKey('source-chat');
          const stageKey = ValueKey('training-stage');
          final stage = find.byKey(stageKey);
          final source = find.byKey(sourceKey, skipOffstage: false);
          final palette = brightness == Brightness.dark
              ? SfPalette.dark
              : SfPalette.light;

          try {
            await tester.pumpWidget(
              MaterialApp(
                navigatorKey: nav,
                theme: buildTheme(palette),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: child!,
                ),
                home: Scaffold(
                  key: sourceKey,
                  body: CustomPaint(
                    painter: sourcePainter,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
            final sourceElement = tester.element(source);
            final sourceRect = tester.getRect(source);
            sourcePainter.paints = 0;
            sourceFrame.value++;
            await tester.pump();
            expect(sourcePainter.paints, 1, reason: 'Paint probe works.');

            final route = TrainingRoute<void>(
              context: sourceElement,
              settings: const RouteSettings(name: 'player'),
              builder: (context) => Scaffold(
                key: stageKey,
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: CustomPaint(
                  painter: videoPainter,
                  child: const SizedBox.expand(),
                ),
              ),
            );
            unawaited(nav.currentState!.push(route));
            await tester.pump();
            await tester.pump(); // Leave Hero's zero-time offstage pre-layout.
            final stageElement = tester.element(stage);
            expect(route.opaque, isTrue);
            expect(
              route.transitionDuration,
              reduced ? Duration.zero : const Duration(milliseconds: 320),
            );
            expect(
              route.reverseTransitionDuration,
              reduced ? Duration.zero : const Duration(milliseconds: 260),
            );
            expect(
              route.canTransitionFrom(ModalRoute.of(sourceElement)!),
              isFalse,
            );
            if (reduced) {
              await tester.pump();
              expect(_ancestor(stage, SlideTransition), findsNothing);
              expect(_ancestor(stage, FadeTransition), findsNothing);
            } else {
              expect(route.animation!.value, 0);
              expect(
                tester
                    .widget<SlideTransition>(_ancestor(stage, SlideTransition))
                    .position
                    .value,
                const Offset(0, .06),
              );
              await tester.pump(const Duration(milliseconds: 160));
              expect(route.animation!.value, closeTo(.5, 1e-6));
              expect(
                tester
                    .widget<SlideTransition>(_ancestor(stage, SlideTransition))
                    .position
                    .value
                    .dy,
                closeTo(.06 * (1 - Curves.easeOutCubic.transform(.5)), 1e-6),
              );
              expect(
                tester
                    .widget<FadeTransition>(_ancestor(stage, FadeTransition))
                    .opacity
                    .value,
                closeTo(Curves.easeOutCubic.transform(.5 / .7), 1e-6),
              );
              expect(tester.getRect(source), sourceRect);
              expect(tester.element(source), same(sourceElement));
              expect(tester.element(stage), same(stageElement));
              expect(_ancestor(stage, ScaleTransition), findsNothing);
              expect(_ancestor(stage, ClipRRect), findsNothing);
              expect(route.barrierColor, isNull);
              expect(
                tester
                    .widgetList<ModalBarrier>(find.byType(ModalBarrier))
                    .every(
                      (barrier) =>
                          barrier.color == null || barrier.color!.a == 0,
                    ),
                isTrue,
                reason: 'The route adds no dimming to the source page.',
              );
              await tester.pump(const Duration(milliseconds: 159));
              expect(route.animation!.status, AnimationStatus.forward);
              await tester.pump(const Duration(milliseconds: 1));
              expect(route.animation!.value, 1);
              // Flutter settles the completed status on its next elapsed frame.
              await tester.pump(const Duration(microseconds: 1));
            }
            expect(route.animation!.status, AnimationStatus.completed);
            expect(tester.element(stage), same(stageElement));
            expect(tester.getRect(stage), const Rect.fromLTWH(0, 0, 390, 844));
            expect(
              tester.widget<Scaffold>(stage).backgroundColor,
              palette.surface,
            );
            expect(find.byKey(sourceKey), findsNothing);

            sourcePainter.paints = 0;
            videoPainter.paints = 0;
            for (var i = 0; i < 6; i++) {
              sourceFrame.value++;
              videoFrame.value++;
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(videoPainter.paints, 6);
            expect(sourcePainter.paints, 0);

            var completed = false;
            unawaited(route.completed.then((_) => completed = true));
            nav.currentState!.pop();
            await tester.pump();
            if (!reduced) {
              expect(route.animation!.status, AnimationStatus.reverse);
              expect(completed, isFalse);
              await tester.pump(const Duration(milliseconds: 130));
              final progress = Curves.easeInCubic.transform(.5);
              expect(
                tester
                    .widget<SlideTransition>(_ancestor(stage, SlideTransition))
                    .position
                    .value
                    .dy,
                closeTo(.06 * progress, 1e-6),
              );
              expect(
                tester
                    .widget<FadeTransition>(_ancestor(stage, FadeTransition))
                    .opacity
                    .value,
                closeTo(1 - progress, 1e-6),
              );
              expect(tester.getRect(source), sourceRect);
              await tester.pump(const Duration(milliseconds: 129));
              expect(stage, findsOneWidget);
              expect(completed, isFalse);
              await tester.pump(const Duration(milliseconds: 1));
              await tester.pump(const Duration(microseconds: 1));
            }
            await tester.pump();
            expect(stage, findsNothing);
            expect(completed, isTrue);
            expect(tester.element(source), same(sourceElement));
            sourcePainter.paints = 0;
            sourceFrame.value++;
            await tester.pump();
            expect(
              sourcePainter.paints,
              1,
              reason: 'Returning resumes painting.',
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            sourceFrame.dispose();
            videoFrame.dispose();
            tester.view.reset();
          }
        },
      );
    }
  }
}
