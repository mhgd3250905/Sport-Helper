import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show services;

const _plan = TrainingPlan(
  id: 'system-bars',
  source: 'template',
  title: '活动一下',
  summary: '短时间活动全身。',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '重点',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 20,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

void main() {
  tearDown(() {
    SfColors.palette = SfPalette.dark;
  });

  testWidgets(
    'Android startup opts into drawing behind the system bars',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await configureSystemUi();
      final mode = calls.singleWhere(
        (call) => call.method == 'SystemChrome.setEnabledSystemUIMode',
      );
      expect(mode.arguments, SystemUiMode.edgeToEdge.toString());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'chat, library, plan and training keep transparent themed bars and safe controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      final styles = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            styles.add(Map<Object?, Object?>.from(call.arguments as Map));
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await s.store.setAppearance('light');
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();

      void expectBars(Brightness theme) {
        expect(styles, isNotEmpty);
        final style = styles.last;
        expect(style['statusBarColor'], Colors.transparent.toARGB32());
        expect(style['systemStatusBarContrastEnforced'], isFalse);
        expect(
          style['statusBarIconBrightness'],
          (theme == Brightness.dark ? Brightness.light : Brightness.dark)
              .toString(),
        );
        // The full page still paints at y=0; only its controls use SafeArea.
        expect(tester.getTopLeft(find.byType(Scaffold).last).dy, 0);
        expect(tester.takeException(), isNull);
      }

      expectBars(Brightness.light);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      Future<void> push(Widget page) async {
        unawaited(
          navigator.push(MaterialPageRoute<void>(builder: (_) => page)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await push(const LibraryPage());
      expectBars(Brightness.light);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('back'))).dy,
        greaterThanOrEqualTo(32),
      );
      navigator.pop();
      await tester.pumpAndSettle();

      await push(const PlanPage(plan: _plan));
      expectBars(Brightness.light);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('back'))).dy,
        greaterThanOrEqualTo(32),
      );
      await s.store.setAppearance('dark');
      await tester.pump();
      expectBars(Brightness.dark);
      navigator.pop();
      await tester.pumpAndSettle();

      await push(const PlayerPage(plan: _plan));
      expectBars(Brightness.dark);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('close'))).dy,
        greaterThanOrEqualTo(32),
      );
      await s.store.setAppearance('light');
      await tester.pump();
      expectBars(Brightness.light);
    },
  );
}
