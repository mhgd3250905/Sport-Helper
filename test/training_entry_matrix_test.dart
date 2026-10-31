import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_timeline.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachPlanExpanded;
import 'package:ugk_trainer/ugk_trainer.dart'
    show TrainerCountdownDigits, TrainerPlayer, TrainerSlideRoute;

import 'app_flow_test.dart'
    show services, showManualChatCard, warmTrainingPoster;

enum _Entry { chatCollapsed, chatExpanded, savedPlan, guide }

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

Finder _key(String key, {bool offstage = false}) =>
    find.byKey(ValueKey(key), skipOffstage: !offstage);

Finder get _player => find.byType(PlayerPage, skipOffstage: false);

void _expectCompleteFrame(WidgetTester tester, {required bool gated}) {
  expect(_player, findsOneWidget);
  final sdk = tester.widget<TrainerPlayer>(
    find.byType(TrainerPlayer, skipOffstage: false),
  );
  expect(sdk.chromeAnimation, isNull);
  expect(sdk.startGate, isNotNull);
  for (final control in [
    'info-card',
    'close',
    'counter',
    'prev',
    'pause',
    'skip',
  ]) {
    final finder = find.descendant(
      of: _player,
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
      of: _player,
      matching: find.byType(CircularProgressIndicator, skipOffstage: false),
      skipOffstage: false,
    ),
    findsNothing,
  );
  final media = gated
      ? find.byType(TrainingPoster, skipOffstage: false)
      : _key('trainer-media', offstage: true);
  expect(media, findsOneWidget);
  final pixels = tester.widgetList<RawImage>(
    find.descendant(
      of: media,
      matching: find.byType(RawImage, skipOffstage: false),
      skipOffstage: false,
    ),
  );
  expect(
    pixels,
    isNotEmpty,
    reason: 'The media has actual decoded poster pixels',
  );
  expect(pixels.any((image) => image.image != null), isTrue);
  expect(
    find.byType(ExerciseVideo, skipOffstage: false),
    gated ? findsNothing : findsOneWidget,
  );
}

ScrollController _sourceScroll(WidgetTester tester, _Entry entry) =>
    switch (entry) {
      _Entry.chatCollapsed || _Entry.chatExpanded =>
        tester.widget<ChatTimeline>(find.byType(ChatTimeline)).controller,
      _Entry.savedPlan =>
        tester.widget<CustomScrollView>(_key('saved-plans-scroll')).controller!,
      _Entry.guide => tester.widget<ListView>(_key('plan-article')).controller!,
    };

Finder _sourcePage(_Entry entry) => find.byType(switch (entry) {
  _Entry.chatCollapsed || _Entry.chatExpanded => ChatHomePage,
  _Entry.savedPlan => SavedPlansPage,
  _Entry.guide => PlanPage,
}, skipOffstage: false);

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    for (final entry in _Entry.values) {
      testWidgets(
        '${palette.brightness.name} ${entry.name}: full 0/150/300ms page and one push',
        (tester) async {
          tester.view.physicalSize = const Size(390, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final output = _VoiceProbe();
          final app = services(output: output);
          final navigation = _NavigationProbe();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await app.dispose();
            SfColors.palette = SfPalette.dark;
          });
          await app.store.acceptSafety(blocked: false);
          app.chat.start();
          final plan = await showManualChatCard(app, template: 'office-relax');
          SavedPlan? saved;
          if (entry == _Entry.savedPlan) {
            saved = await app.store.savePlan(plan, name: '已保存的舒展');
          }
          await tester.pumpWidget(
            AppScope(
              services: app,
              child: MaterialApp(
                theme: buildTheme(palette),
                navigatorObservers: [navigation],
                builder: (_, child) => SfPaletteScope(child: child!),
                home: const ChatHomePage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          late Finder start;
          late VoidCallback repeatStart;
          if (entry == _Entry.savedPlan) {
            await tester.tap(_key('chat-panel-toggle'));
            await tester.pumpAndSettle();
            await tester.tap(_key('panel-plans'));
            await tester.pumpAndSettle();
            await tester.tap(_key('saved-expanded-${saved!.id}'));
            await tester.pumpAndSettle();
            start = _key('plan-start-${plan.id}');
            final source = tester.element(find.byType(SavedPlansPage));
            final page = tester.widget<SavedPlansPage>(
              find.byType(SavedPlansPage),
            );
            repeatStart = () => page.onStart(saved!, source);
          } else if (entry == _Entry.guide) {
            await tester.ensureVisible(_key('plan-open-${plan.id}'));
            await tester.tap(_key('plan-open-${plan.id}'));
            await tester.pumpAndSettle();
            start = _key('start');
            repeatStart = tester.widget<SfPressable>(start).onTap!;
          } else {
            if (entry == _Entry.chatExpanded) {
              await tester.tap(_key('plan-expand-${plan.id}'));
              await tester.pumpAndSettle();
            }
            start = _key('plan-start-${plan.id}');
            repeatStart = tester
                .widget<PlanCard>(find.byType(PlanCard))
                .onStart;
          }
          await tester.ensureVisible(start);
          await tester.pumpAndSettle();
          final source = tester.element(_sourcePage(entry));
          final scroll = _sourceScroll(tester, entry);
          final offset = scroll.offset;
          final sourceBrightness = Theme.of(source).brightness;
          final expanded = entry == _Entry.savedPlan
              ? tester
                    .widget<CoachPlanExpanded>(
                      _key('saved-expanded-${saved!.id}'),
                    )
                    .expanded
              : entry == _Entry.chatExpanded;
          final sourceCard = switch (entry) {
            _Entry.chatCollapsed ||
            _Entry.chatExpanded => find.byType(PlanCard),
            _Entry.savedPlan => _key('saved-expanded-${saved!.id}'),
            _Entry.guide => _key('plan-introduction'),
          };
          final sourceCardState = sourceCard.evaluate().single;
          await warmTrainingPoster(tester, app, plan, sourceContext: source);
          await tester.tap(start);
          for (var i = 0; i < 12 && _player.evaluate().isEmpty; i++) {
            await tester.pump();
          }
          await tester.pump();
          expect(navigation.trainingPushes, 1);
          final route =
              ModalRoute.of(tester.element(_player))! as TrainingRoute;
          expect(route, isA<TrainerSlideRoute>());
          final control = TrainingRouteScope.maybeOf(tester.element(_player))!;
          var gateOpened = false;
          unawaited(control.startGate.then((_) => gateOpened = true));
          final counter = tester
              .widget<TrainerCountdownDigits>(
                find.byType(TrainerCountdownDigits, skipOffstage: false),
              )
              .value;
          final slide = tester.widget<SlideTransition>(_key('training-slide'));
          expect(slide.position.value, const Offset(1, 0));
          expect(route.opaque, isTrue);
          expect(route.sourceEntry, switch (entry) {
            _Entry.chatCollapsed || _Entry.chatExpanded => 'chat',
            _Entry.savedPlan => 'saved_plan',
            _Entry.guide => 'guide',
          });
          _expectCompleteFrame(tester, gated: true);
          expect(control.entered, isFalse);
          expect(gateOpened, isFalse);
          expect(output.begins, 0);
          repeatStart();
          repeatStart();
          await tester.pump();
          expect(navigation.trainingPushes, 1);
          expect(scroll.offset, offset);
          await tester.pump(const Duration(milliseconds: 150));
          _expectCompleteFrame(tester, gated: true);
          expect(
            slide.position.value.dx,
            closeTo(1 - Curves.easeOutCubic.transform(.5), .0001),
          );
          expect(control.entered, isFalse);
          expect(gateOpened, isFalse);
          expect(output.begins, 0);
          expect(
            tester
                .widget<TrainerCountdownDigits>(
                  find.byType(TrainerCountdownDigits, skipOffstage: false),
                )
                .value,
            counter,
          );
          expect(scroll.offset, offset);
          expect(tester.element(_sourcePage(entry)), same(source));
          repeatStart();
          await tester.pump(const Duration(milliseconds: 150));
          // The full page is already painted at 300ms; the engine may dispatch
          // completed just after this exact floating-point boundary.
          _expectCompleteFrame(tester, gated: true);
          await tester.pump(const Duration(microseconds: 1));
          await tester.pump();
          _expectCompleteFrame(tester, gated: false);
          expect(control.entered, isTrue);
          expect(gateOpened, isTrue);
          expect(output.begins, 1);
          expect(navigation.trainingPushes, 1);
          expect(slide.position.value, Offset.zero);
          expect(scroll.offset, offset);
          await tester.tap(_key('close'));
          await tester.pumpAndSettle();
          await tester.tap(_key('close-confirm'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 279));
          expect(_player, findsOneWidget);
          expect(scroll.offset, offset);
          await tester.pump(const Duration(milliseconds: 1));
          await tester.pump(const Duration(microseconds: 1));
          await tester.pump();
          await tester.pump();
          expect(find.byType(PlayerPage), findsNothing);
          expect(tester.element(_sourcePage(entry)), same(source));
          expect(sourceCard.evaluate().single, same(sourceCardState));
          expect(Theme.of(source).brightness, sourceBrightness);
          expect(scroll.offset, offset);
          if (entry == _Entry.savedPlan) {
            expect(
              tester
                  .widget<CoachPlanExpanded>(
                    _key('saved-expanded-${saved!.id}'),
                  )
                  .expanded,
              expanded,
            );
          } else if (entry == _Entry.chatExpanded) {
            expect(_key('plan-save-${plan.id}').hitTestable(), findsOneWidget);
          } else if (entry == _Entry.chatCollapsed) {
            expect(_key('plan-save-${plan.id}').hitTestable(), findsNothing);
          }
          expect(navigation.trainingPushes, 1);
          expect(app.store.history, hasLength(1));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
