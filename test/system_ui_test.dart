import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

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
    'real chat rows paint through the status-bar area while input stays safe',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await s.store.setAppearance('light');
      final at = DateTime.now();
      String line(int i) => '普通消息 $i，用来检查聊天内容滚动。';
      await s.store.setChatLog([
        for (var i = 0; i < 24; i++)
          ChatMessage(
            id: 'status-message-$i',
            role: i.isEven ? ChatRole.user : ChatRole.assistant,
            at: at,
            text: line(i),
          ).toJson().cast<String, dynamic>(),
      ]);
      final frame = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: SmartFitApp(services: s),
        ),
      );
      await tester.pumpAndSettle();

      final chat = find.byType(CoachChatList);
      final widget = tester.widget<CoachChatList>(chat);
      expect(widget.topInset, 32);
      expect(widget.fadeTop, isFalse);
      final list = find.descendant(of: chat, matching: find.byType(ListView));
      expect(
        tester.widget<ListView>(list).padding!.resolve(TextDirection.ltr).top,
        80,
      );
      final viewport = find.descendant(
        of: chat,
        matching: find.byType(Viewport),
      );
      expect(tester.getRect(viewport).top, 0);
      expect(tester.getRect(viewport).bottom, 844);
      expect(tester.getRect(find.byType(ChatInputBar)).bottom, 820);

      final controller = widget.controller;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(line(0))).dy,
        greaterThanOrEqualTo(80),
      );
      controller.jumpTo(controller.position.maxScrollExtent / 2);
      await tester.pumpAndSettle();

      // A real, older App bubble moves into y=8..32. Measuring only Scaffold's
      // y=0 would miss a SafeArea or paint clip around the conversation itself.
      final row = find.byKey(const ValueKey('status-message-12'));
      final face = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  SfPalette.light.userBubble,
        ),
      );
      expect(face, findsOneWidget);
      final initial = tester.getRect(face);
      final offset = controller.offset + 8 - initial.top;
      expect(offset, inExclusiveRange(0, controller.position.maxScrollExtent));
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
      final rect = tester.getRect(face);
      expect(rect.top, closeTo(8, .01));
      expect(rect.bottom, greaterThan(32));

      final boundary =
          frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final color = SfPalette.light.userBubble;
        final expected = [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
          255,
        ];
        final x = rect.center.dx.floor();
        for (var y = 14; y <= 16; y++) {
          for (var dx = -2; dx <= 2; dx++) {
            final pixel = (y * image.width + x + dx) * 4;
            expect(
              [
                for (var channel = 0; channel < 4; channel++)
                  bytes.getUint8(pixel + channel),
              ],
              expected,
              reason:
                  'The actual bubble must paint below the transparent status bar',
            );
          }
        }
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    },
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
      // SystemChrome caches its last style across widget tests. Start from a
      // distinct mocked value so this App mount must send its real overlay.
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(statusBarColor: Color(0xFF000001)),
      );
      await tester.pump();
      styles.clear();
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
