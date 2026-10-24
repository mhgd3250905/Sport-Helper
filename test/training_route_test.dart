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

void main() {
  for (final brightness in Brightness.values) {
    for (final reduced in [false, true]) {
      testWidgets(
        '${brightness.name}, reduced=$reduced: training paints at final bounds while the source stays offstage',
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
            await tester.pump();
            final sourceElement = tester.element(find.byKey(sourceKey));
            sourcePainter.paints = 0;
            sourceFrame.value++;
            await tester.pump();
            expect(
              sourcePainter.paints,
              1,
              reason: 'Source paint probe works.',
            );

            final route = TrainingRoute<void>(
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
            sourcePainter.paints = 0;
            unawaited(nav.currentState!.push(route));
            await tester.pump();
            await tester.pump();
            expect(route.opaque, isTrue);
            expect(route.animation!.status, AnimationStatus.completed);
            expect(route.transitionDuration, Duration.zero);
            expect(route.reverseTransitionDuration, Duration.zero);
            expect(
              tester.getRect(find.byKey(stageKey)),
              const Rect.fromLTWH(0, 0, 390, 844),
            );
            expect(
              tester.widget<Scaffold>(find.byKey(stageKey)).backgroundColor,
              palette.surface,
            );
            for (final wrapper in [Opacity, FadeTransition, ClipRRect]) {
              expect(
                find.ancestor(
                  of: find.byKey(stageKey),
                  matching: find.byType(wrapper),
                ),
                findsNothing,
                reason: 'The route must not composite the entire video page.',
              );
            }
            expect(find.byKey(sourceKey), findsNothing);
            expect(sourcePainter.paints, 0);

            videoPainter.paints = 0;
            for (var i = 0; i < 6; i++) {
              // Dirty both pages, as a running chat background and live media
              // could do. The covered page must remain out of the paint path.
              sourceFrame.value++;
              videoFrame.value++;
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(videoPainter.paints, 6);
            expect(sourcePainter.paints, 0);

            nav.currentState!.pop();
            await tester.pump();
            await tester.pump();
            expect(find.byKey(stageKey), findsNothing);
            expect(tester.element(find.byKey(sourceKey)), same(sourceElement));
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
