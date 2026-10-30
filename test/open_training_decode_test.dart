import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/training_transition_activity.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/chat/training_card_media.dart';
import 'package:smartfit/ui/open_training.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';

import 'app_flow_test.dart' show services;

class _SlowPosters extends CachingAssetBundle {
  final image = Completer<ByteData>();
  var requested = 0;
  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('.webp') || key.endsWith('.png')) {
      requested++;
      return image.future;
    }
    return rootBundle.load(key);
  }
}

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      '${palette.brightness.name}: decode admission times out at 150ms without starting or pushing an empty page',
      (tester) async {
        final app = services();
        await app.store.acceptSafety(blocked: false);
        final generated = await app.generator.generate(
          const ScenarioRequest(templateId: 'office-relax'),
        );
        final plan = generated.plan!;
        final exercise = app.library[plan.items.first.exerciseId];
        final bundle = _SlowPosters();
        tester.binding.imageCache.clear();
        var starts = 0, returns = 0;
        late BuildContext source;
        addTearDown(() async {
          if (!bundle.image.isCompleted) {
            final data = await tester.runAsync(
              () => rootBundle.load(
                exercise.media.playbackPosterFor(
                  light: palette.brightness == Brightness.light,
                ),
              ),
            );
            bundle.image.complete(data!);
            await tester.runAsync(
              () async =>
                  Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await app.dispose();
          SfColors.palette = SfPalette.dark;
        });
        await tester.pumpWidget(
          AppScope(
            services: app,
            child: MaterialApp(
              theme: buildTheme(palette),
              builder: (_, child) => SfPaletteScope(child: child!),
              home: DefaultAssetBundle(
                bundle: bundle,
                child: Builder(
                  builder: (context) {
                    source = context;
                    return Scaffold(
                      key: const ValueKey('decode-source'),
                      body: TrainingCardMedia(
                        exercise: exercise,
                        child: TextButton(
                          onPressed: () => unawaited(
                            openTraining(
                              context,
                              plan: plan,
                              onStarting: () async {
                                starts++;
                                return true;
                              },
                            ).then((_) => returns++),
                          ),
                          child: const Text('start'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          bundle.requested,
          greaterThan(0),
          reason: 'The visible entry prewarms its poster.',
        );
        final original = tester.element(
          find.byKey(const ValueKey('decode-source')),
        );
        await tester.tap(find.text('start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 149));
        expect(starts, 0);
        expect(returns, 0);
        expect(find.byType(PlayerPage), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(starts, 0);
        expect(returns, 1);
        expect(find.byType(PlayerPage), findsNothing);
        expect(
          tester.element(find.byKey(const ValueKey('decode-source'))),
          same(original),
        );
        expect(TrainingTransitionActivity.instance.active, isFalse);
        // Let the ongoing prewarm finish, then prove a second tap is admitted.
        final asset = TrainingPosterImages.candidates(source, exercise).first;
        bundle.image.complete(
          (await tester.runAsync(() => rootBundle.load(asset)))!,
        );
        await tester.runAsync(
          () => TrainingPosterImages.precache(source, exercise),
        );
        await tester.pump();
        await tester.tap(find.text('start'));
        await tester.pump();
        await tester.pump();
        expect(starts, 1);
        expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
