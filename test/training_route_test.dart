import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:smartfit/ui/training_entry_placeholder.dart';

import 'support.dart';

void expectRect(Rect actual, Rect? expected) {
  expect(expected, isNotNull);
  expect(actual.left, closeTo(expected!.left, 1e-4));
  expect(actual.top, closeTo(expected.top, 1e-4));
  expect(actual.width, closeTo(expected.width, 1e-4));
  expect(actual.height, closeTo(expected.height, 1e-4));
}

void main() {
  for (final brightness in Brightness.values) {
    for (final reduced in [false, true]) {
      for (final interruption in ['none', 'back', 'remove']) {
        testWidgets(
          '${brightness.name} reduced=$reduced: zero route, measured card morph, independent return, interruption=$interruption',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            final nav = GlobalKey<NavigatorState>();
            final image = GlobalKey();
            final alpha = ValueNotifier<double>(1);
            final exercise = loadLibrary()['h-forearm-plank'];
            TrainingRoute<void>? route;
            TrainingTransitionMotion? motion;
            var started = false;
            var visualDone = false;
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              alpha.dispose();
              tester.view.reset();
            });
            await tester.pumpWidget(
              MaterialApp(
                navigatorKey: nav,
                theme: buildTheme(
                  brightness == Brightness.dark
                      ? SfPalette.dark
                      : SfPalette.light,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduced),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: Stack(
                      children: [
                        Positioned(
                          left: 20,
                          top: 70,
                          width: 200,
                          height: 150,
                          child: ValueListenableBuilder<double>(
                            valueListenable: alpha,
                            builder: (_, opacity, child) =>
                                Opacity(opacity: opacity, child: child),
                            child: RepaintBoundary(
                              key: image,
                              child: const ColoredBox(color: Colors.green),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Rect? sourceRect() {
                              final box = image.currentContext
                                  ?.findRenderObject();
                              return box is RenderBox && box.hasSize
                                  ? box.localToGlobal(Offset.zero) & box.size
                                  : null;
                            }

                            route = TrainingRoute<void>(
                              context: context,
                              source: TrainingTransitionSource(
                                rect: sourceRect,
                                initialRect: sourceRect(),
                                opacity: alpha,
                                repaintKey: image,
                              ),
                              builder: (context) {
                                final m = TrainingTransitionScope.maybeOf(
                                  context,
                                )!;
                                if (motion == null) {
                                  motion = m;
                                  unawaited(
                                    m.startGate.then((_) => started = true),
                                  );
                                }
                                m.reportMedia(exercise, mirrored: false);
                                return Stack(
                                  children: [
                                    Positioned(
                                      left: 0,
                                      top: 220,
                                      width: 390,
                                      height: 390,
                                      child: SizedBox(
                                        key: m.mediaKey,
                                        child: TrainingEntranceMedia(
                                          motion: m,
                                          exercise: exercise,
                                          mirrored: false,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                            unawaited(
                              route!.visualCompleted.then(
                                (_) => visualDone = true,
                              ),
                            );
                            unawaited(nav.currentState!.push(route!));
                          },
                          child: const Text('open'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            final original = tester.getRect(find.byKey(image));
            await tester.tap(find.text('open'));
            await tester.pump();
            await tester.pump();
            expect(route!.opaque, isFalse);
            expect(route!.transitionDuration, Duration.zero);
            expect(route!.reverseTransitionDuration, Duration.zero);
            expect(started, isFalse);
            expect(alpha.value, reduced ? 1 : 0);
            if (reduced) {
              await tester.pump(const Duration(milliseconds: 149));
              expect(started, isFalse);
              await tester.pump(const Duration(milliseconds: 1));
            } else {
              final poster = find.byKey(
                const ValueKey('training-morph-poster'),
              );
              expectRect(tester.getRect(poster), original);
              await tester.pump(const Duration(milliseconds: 210));
              final t = Curves.easeInOutCubicEmphasized.transform(.5);
              expectRect(
                tester.getRect(poster),
                Rect.lerp(original, const Rect.fromLTWH(0, 220, 390, 390), t),
              );
              expect(
                tester.widget<TrainingTransitionPoster>(poster).radius,
                closeTo(20 * (1 - t), 1e-6),
              );
              expect(motion!.chrome.value, 0);
              await tester.pump(const Duration(milliseconds: 70));
              expect(motion!.chrome.value, 0);
              await tester.pump(const Duration(milliseconds: 140));
              expectRect(
                tester.getRect(poster),
                const Rect.fromLTWH(0, 220, 390, 390),
              );
              expect(motion!.chrome.value, closeTo(.5, 1e-6));
              await tester.pump(const Duration(milliseconds: 139));
              expect(started, isFalse);
              await tester.pump(const Duration(milliseconds: 1));
            }
            await tester.pump();
            expect(started, isTrue);
            expect(motion!.chrome.value, 1);
            expectRect(tester.getRect(find.byKey(image)), original);
            motion!.exitStarted();
            await tester.pump();
            await tester.pump(Duration(milliseconds: reduced ? 149 : 249));
            expect(motion!.chrome.value, greaterThan(0));
            await tester.pump(const Duration(milliseconds: 1));
            await tester.pump();
            nav.currentState!.pop();
            await tester.pump();
            await tester.pump();
            if (reduced) {
              expect(visualDone, isTrue);
              expect(
                find.byKey(const ValueKey('training-return-poster')),
                findsNothing,
              );
              expect(alpha.value, 1);
              expect(tester.binding.transientCallbackCount, 0);
              expect(tester.takeException(), isNull);
              return;
            }
            expect(visualDone, isFalse);
            final returning = find.byKey(
              const ValueKey('training-return-poster'),
            );
            expect(returning, findsOneWidget);
            if (interruption == 'remove') {
              await tester.pumpWidget(const SizedBox.shrink());
              expect(visualDone, isTrue);
              expect(returning, findsNothing);
              expect(tester.binding.transientCallbackCount, 0);
              expect(tester.takeException(), isNull);
              return;
            }
            if (interruption == 'back') {
              expect(await nav.currentState!.maybePop(), isTrue);
              await tester.pump();
              expect(visualDone, isTrue);
              expect(returning, findsNothing);
              expect(find.byKey(image), findsOneWidget);
              expect(alpha.value, 1);
              expect(tester.binding.transientCallbackCount, 0);
              expect(tester.takeException(), isNull);
              return;
            }
            if (reduced) {
              await tester.pump(const Duration(milliseconds: 149));
              expect(visualDone, isFalse);
              await tester.pump(const Duration(milliseconds: 1));
            } else {
              await tester.pump(const Duration(milliseconds: 190));
              expectRect(
                tester.getRect(returning),
                Rect.lerp(
                  const Rect.fromLTWH(0, 220, 390, 390),
                  original,
                  Curves.easeInOutCubicEmphasized.transform(.5),
                ),
              );
              await tester.pump(const Duration(milliseconds: 190));
              expectRect(tester.getRect(returning), original);
              expect(alpha.value, 1);
              expect(visualDone, isFalse);
              await tester.pump(const Duration(milliseconds: 119));
              expect(visualDone, isFalse);
              await tester.pump(const Duration(milliseconds: 1));
            }
            await tester.pump();
            expect(visualDone, isTrue);
            expect(returning, findsNothing);
            expect(alpha.value, 1);
            expectRect(tester.getRect(find.byKey(image)), original);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
