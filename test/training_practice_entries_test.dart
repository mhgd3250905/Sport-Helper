import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/single_practice_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

enum _Entry { actionLibrary, recommendation }

class _VoiceProbe extends MutedVoiceOutput {
  int begins = 0;

  @override
  Future<void> begin() async => begins++;
}

class _NavigationProbe extends NavigatorObserver {
  int trainingPushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'player') trainingPushes++;
  }
}

Finder _key(String value, {bool offstage = false}) =>
    find.byKey(ValueKey(value), skipOffstage: !offstage);

Finder get _practice => find.byType(SinglePracticePage, skipOffstage: false);

void _expectCompletePreview(WidgetTester tester, {required bool gated}) {
  expect(_practice, findsOneWidget);
  final sdk = tester.widget<TrainerPlayer>(
    find.byType(TrainerPlayer, skipOffstage: false),
  );
  expect(sdk.startMode, TrainerStartMode.preview);
  expect(sdk.chromeAnimation, isNull);
  expect(sdk.startGate, isNotNull);
  for (final control in [
    'info-card',
    'close',
    'preview-labels',
    'start-training',
  ]) {
    final finder = find.descendant(
      of: _practice,
      matching: _key(control, offstage: true),
      skipOffstage: false,
    );
    expect(
      finder,
      findsOneWidget,
      reason: '$control exists in the first frame',
    );
    expect(tester.getSize(finder).isEmpty, isFalse);
  }
  expect(
    find.descendant(
      of: _practice,
      matching: find.byType(CircularProgressIndicator, skipOffstage: false),
      skipOffstage: false,
    ),
    findsNothing,
  );
  if (gated) {
    expect(_key('posehub-video-loading', offstage: true), findsNothing);
    expect(find.byType(ExerciseVideo, skipOffstage: false), findsNothing);
    final poster = _key('single-practice-poster', offstage: true);
    expect(poster, findsOneWidget);
    final pixels = tester.widgetList<RawImage>(
      find.descendant(
        of: poster,
        matching: find.byType(RawImage, skipOffstage: false),
        skipOffstage: false,
      ),
    );
    expect(pixels, isNotEmpty);
    expect(pixels.any((image) => image.image != null), isTrue);
  } else {
    expect(find.byType(ExerciseVideo, skipOffstage: false), findsOneWidget);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late ExerciseLibrary library;

  setUpAll(() async {
    catalog = await PoseHubActionLibrary.load();
    library = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(catalog),
      legacyLibrary: ExerciseLibrary([]),
    ).library;
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    for (final entry in _Entry.values) {
      testWidgets(
        '${palette.brightness.name} ${entry.name}: full 0/150/300ms preview, one push and retained source',
        (tester) async {
          tester.view.physicalSize = const Size(390, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final base = Uri.parse('file:///practice-entry-contract/');
          final pending = Completer<Uri>();
          final repository = PoseHubUiRepository(
            mediaBaseUri: base,
            onEnsureAction: (_) => pending.future,
          );
          final platform = PoseHubUiVideoPlatform();
          UgkPackedAlphaVideo.debugPlatform = platform;
          UgkPackedAlphaVideo.debugFilterBuilder = (_) =>
              const SizedBox.expand();
          final voice = _VoiceProbe();
          final app = poseHubUiServices(
            catalog: catalog,
            media: repository,
            library: library,
            voiceOutput: voice,
          );
          final navigation = _NavigationProbe();
          final recommendationScroll = ScrollController();
          addTearDown(() async {
            binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            if (!pending.isCompleted) pending.complete(base);
            await app.dispose();
            recommendationScroll.dispose();
            UgkPackedAlphaVideo.debugPlatform = null;
            UgkPackedAlphaVideo.debugFilterBuilder = null;
            await platform.close();
            SfColors.palette = SfPalette.dark;
          });
          // Viewing the public SDK preview never requires training safety or
          // changes a user's training record merely by opening a card.
          expect(app.store.trainingAllowed, isFalse);
          final action = catalog.semanticCompleteActions.first;
          final exercise = library[action.id];
          late BuildContext sourceContext;
          await tester.pumpWidget(
            AppScope(
              services: app,
              child: MaterialApp(
                theme: buildTheme(palette),
                navigatorObservers: [navigation],
                builder: (_, child) => SfPaletteScope(child: child!),
                home: entry == _Entry.actionLibrary
                    ? const LibraryPage()
                    : Builder(
                        builder: (context) {
                          sourceContext = context;
                          return Scaffold(
                            body: SingleChildScrollView(
                              key: const ValueKey(
                                'recommendation-source-scroll',
                              ),
                              controller: recommendationScroll,
                              child: Column(
                                children: [
                                  const SizedBox(height: 200),
                                  withSmartfitRecommendUi(
                                    context,
                                    CoachRecommendCard(
                                      actionIds: [action.id],
                                      note: '先看这个动作的示范。',
                                      library: CoachExerciseLibrary([
                                        toCoachRecommendationExercise(exercise),
                                      ]),
                                      onOpenAction: (_) => unawaited(
                                        showExerciseDetails(context, exercise),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1200),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          late Finder start;
          late VoidCallback repeatStart;
          late ScrollPosition sourceScroll;
          late Element sourceElement;
          if (entry == _Entry.actionLibrary) {
            // Exercise a real SDK filter/search state, rather than a synthetic
            // launcher, and ensure the shared route does not recreate it.
            final search = _key('posehub-search');
            await tester.enterText(search, action.nameZh);
            await tester.pumpAndSettle();
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            start = _key('posehub-action-${action.id}');
            repeatStart = tester.widget<GestureDetector>(start).onTap!;
            sourceElement = tester.element(find.byType(PoseHubActionBrowser));
            sourceContext = tester.element(find.byType(LibraryPage));
            sourceScroll = tester
                .state<ScrollableState>(
                  find.descendant(
                    of: _key('posehub-action-list'),
                    matching: find.byType(Scrollable),
                  ),
                )
                .position;
          } else {
            recommendationScroll.jumpTo(120);
            await tester.pump();
            start = _key('recommend-action-${action.id}');
            final card = tester.widget<CoachRecommendCard>(
              find.byType(CoachRecommendCard),
            );
            repeatStart = () => card.onOpenAction(action.id);
            sourceElement = tester.element(find.byType(CoachRecommendCard));
            sourceScroll = recommendationScroll.position;
          }
          final sourceOffset = sourceScroll.pixels;
          final sourceBrightness = Theme.of(sourceContext).brightness;
          final sourceCard = start.evaluate().single;
          await tester.runAsync(
            () => TrainingPosterImages.precache(sourceContext, exercise),
          );
          await tester.pump();
          expect(repository.actionRequests, isEmpty);
          expect(platform.uris, isEmpty);
          await tester.tap(start);
          for (var i = 0; i < 12 && _practice.evaluate().isEmpty; i++) {
            await tester.pump();
          }
          await tester.pump();
          expect(navigation.trainingPushes, 1);
          final control = TrainingRouteScope.maybeOf(
            tester.element(_practice),
          )!;
          final route =
              ModalRoute.of(tester.element(_practice))! as TrainingRoute;
          expect(route, isA<TrainerSlideRoute>());
          expect(
            route.sourceEntry,
            entry == _Entry.actionLibrary ? 'action_library' : 'recommendation',
          );
          expect(route.opaque, isTrue);
          var gateOpened = false;
          unawaited(control.startGate.then((_) => gateOpened = true));
          final slide = tester.widget<SlideTransition>(_key('training-slide'));
          expect(slide.position.value, const Offset(1, 0));
          _expectCompletePreview(tester, gated: true);
          expect(control.entered, isFalse);
          expect(gateOpened, isFalse);
          expect(voice.begins, 0);
          expect(repository.actionRequests, isEmpty);
          expect(platform.uris, isEmpty);
          repeatStart();
          repeatStart();
          await tester.pump();
          expect(navigation.trainingPushes, 1);
          await tester.pump(const Duration(milliseconds: 150));
          _expectCompletePreview(tester, gated: true);
          expect(
            slide.position.value.dx,
            closeTo(1 - Curves.easeOutCubic.transform(.5), .0001),
          );
          expect(control.entered, isFalse);
          expect(gateOpened, isFalse);
          expect(repository.actionRequests, isEmpty);
          expect(platform.uris, isEmpty);
          expect(voice.begins, 0);
          expect(sourceScroll.pixels, sourceOffset);
          expect(start.evaluate().single, same(sourceCard));
          repeatStart();
          await tester.pump(const Duration(milliseconds: 150));
          _expectCompletePreview(tester, gated: true);
          await tester.pump(const Duration(microseconds: 1));
          await tester.pump();
          _expectCompletePreview(tester, gated: false);
          expect(control.entered, isTrue);
          expect(gateOpened, isTrue);
          expect(navigation.trainingPushes, 1);
          expect(repository.actionRequests, [action.id]);
          expect(platform.uris, isEmpty, reason: 'Download is still pending');
          expect(voice.begins, 0, reason: 'Preview has not started a workout');
          expect(slide.position.value, Offset.zero);
          await tester.tap(_key('close'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 140));
          expect(_practice, findsOneWidget);
          expect(sourceScroll.pixels, sourceOffset);
          await tester.pump(const Duration(milliseconds: 140));
          await tester.pump(const Duration(microseconds: 1));
          await tester.pumpAndSettle();
          expect(_practice, findsNothing);
          expect(start.evaluate().single, same(sourceCard));
          expect(sourceScroll.pixels, sourceOffset);
          expect(sourceElement.mounted, isTrue);
          expect(Theme.of(sourceContext).brightness, sourceBrightness);
          if (entry == _Entry.actionLibrary) {
            expect(
              tester.widget<TextField>(_key('posehub-search')).controller!.text,
              action.nameZh,
            );
            expect(
              tester.element(find.byType(PoseHubActionBrowser)),
              same(sourceElement),
            );
          } else {
            expect(
              tester.element(find.byType(CoachRecommendCard)),
              same(sourceElement),
            );
          }
          expect(app.store.history, isEmpty);
          expect(voice.begins, 0);
          expect(navigation.trainingPushes, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
