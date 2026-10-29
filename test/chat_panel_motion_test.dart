import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachChatList;

import 'app_flow_test.dart' show services;

const _toggle = ValueKey('chat-panel-toggle');
const _input = ValueKey('chat-input');
const _face = ValueKey('chat-composer-face');
const _transition = ValueKey('chat-panel-transition');
const _fade = ValueKey('chat-panel-fade');
const _fixed = ValueKey('chat-panel-fixed-content');
const _offset = ValueKey('chat-panel-content-offset');
const _listBoundary = ValueKey('chat-messages-boundary');
const _dockBoundary = ValueKey('chat-composer-dock-boundary');

class _Replies implements ChatEngine {
  var count = 0;
  @override
  String get id => 'panel-scroll-fixture';
  @override
  Future<ChatReply> reply(String text, ChatState state) async => ChatReply(
    messages: [BotMessage('答复 ${++count}：这是一段用来确认菜单和输入区不会遮住最新消息的真实对话列表内容。')],
    state: state,
  );
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.reset);
}

Future<AppServices> _mount(WidgetTester tester, {bool reduced = false}) async {
  _viewport(tester);
  if (reduced) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }
  final app = services();
  await app.store.acceptSafety(blocked: false);
  await tester.pumpWidget(SmartFitApp(services: app));
  await tester.pumpAndSettle();
  return app;
}

Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  await tester.pump();
  await tester.pump();
}

Future<void> _togglePanel(WidgetTester tester) async {
  await tester.tap(find.byKey(_toggle));
  await tester.pump();
}

double _inputBottom(WidgetTester tester) =>
    tester.getRect(find.byKey(_face)).bottom;

void _adjoiningBounds(WidgetTester tester) {
  final list = tester.getRect(find.byKey(_listBoundary));
  final dock = tester.getRect(find.byKey(_dockBoundary));
  expect(list.bottom, closeTo(dock.top, .1));
  expect(dock.bottom, closeTo(844, .1));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'menu uses one 240ms timeline and keeps its complete layout fixed',
    (tester) async {
      await _mount(tester);
      final fixedHeight = tester.getSize(find.byKey(_fixed)).height;
      expect(fixedHeight, greaterThan(0));
      expect(tester.getSize(find.byKey(_transition)).height, 0);
      final size = tester.widget<SizeTransition>(find.byKey(_transition));
      expect(size.alignment, AlignmentDirectional.topStart);
      final fade = tester.widget<FadeTransition>(find.byKey(_fade));
      expect(fade.opacity, same(size.sizeFactor));
      final curve = size.sizeFactor as CurvedAnimation;
      final driver = curve.parent as AnimationController;
      expect(driver.duration, const Duration(milliseconds: 240));
      expect(curve.curve, Curves.easeOutCubic);
      expect(curve.reverseCurve, Curves.easeInCubic);
      expect(
        find.ancestor(
          of: find.byKey(_transition),
          matching: find.byType(ClipRect),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byKey(_transition),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(_transition),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Transform>(find.byKey(_offset)).transform.storage[13],
        8,
      );

      await _togglePanel(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(driver.value, closeTo(.25, .001));
      final intermediate = tester.getSize(find.byKey(_transition)).height;
      expect(intermediate, greaterThan(0));
      expect(intermediate, lessThan(fixedHeight));
      expect(tester.getSize(find.byKey(_fixed)).height, fixedHeight);
      expect(
        tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value,
        closeTo(intermediate / fixedHeight, .001),
      );
      expect(
        tester.widget<Transform>(find.byKey(_offset)).transform.storage[13],
        closeTo(8 * (1 - intermediate / fixedHeight), .001),
      );

      // Reverse while opening: the current geometry must not jump to an endpoint.
      await _togglePanel(tester);
      expect(
        tester.getSize(find.byKey(_transition)).height,
        closeTo(intermediate, .01),
      );
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.getSize(find.byKey(_transition)).height, 0);
      expect(driver.isAnimating, isFalse);
      await _togglePanel(tester);
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.getSize(find.byKey(_transition)).height, fixedHeight);
      expect(tester.getSize(find.byKey(_fixed)).height, fixedHeight);
      expect(tester.widget<FadeTransition>(find.byKey(_fade)).opacity.value, 1);
      expect(
        tester.widget<Transform>(find.byKey(_offset)).transform.storage[13],
        0,
      );
      await _togglePanel(tester);
      await tester.pump(const Duration(milliseconds: 240));
      expect(tester.getSize(find.byKey(_transition)).height, 0);
      _adjoiningBounds(tester);
    },
  );

  testWidgets(
    'reduced motion switches immediately without publishing during build',
    (tester) async {
      await _mount(tester, reduced: true);
      await _togglePanel(tester);
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(
        tester.getSize(find.byKey(_transition)).height,
        tester.getSize(find.byKey(_fixed)).height,
      );
      _adjoiningBounds(tester);
      await _togglePanel(tester);
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(tester.getSize(find.byKey(_transition)).height, 0);
      _adjoiningBounds(tester);
    },
  );

  for (final newKeyboard in [250.0, 0.0]) {
    testWidgets(
      'keyboard 320 to menu to keyboard $newKeyboard releases the old slot',
      (tester) async {
        await _mount(tester);
        final closedBottom = _inputBottom(tester);
        await tester.tap(find.byKey(_input));
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue);
        await _keyboard(tester, 320);
        final keyboardBottom = _inputBottom(tester);
        expect(keyboardBottom, closeTo(closedBottom + 24 - 320, .1));
        await _togglePanel(tester);
        expect(
          tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
          isFalse,
        );
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.pump(const Duration(milliseconds: 60));
        await _keyboard(tester, 160);
        expect(_inputBottom(tester), closeTo(keyboardBottom, .1));
        await _keyboard(tester, 0);
        await tester.pump(const Duration(milliseconds: 180));
        expect(tester.getSize(find.byKey(_transition)).height, 320);
        expect(tester.getSize(find.byKey(_fixed)).height, 320);
        expect(_inputBottom(tester), closeTo(keyboardBottom, .1));
        _adjoiningBounds(tester);

        await tester.tap(find.byKey(_input));
        await tester.pump();
        expect(
          tester.widget<TextField>(find.byKey(_input)).focusNode!.hasFocus,
          isTrue,
        );
        expect(tester.testTextInput.isVisible, isTrue);
        await _keyboard(tester, newKeyboard);
        // A shorter IME, or a hardware keyboard with no IME, must eventually
        // replace the old reservation instead of leaving an empty 320px slot.
        var previousBottom = _inputBottom(tester);
        for (var frame = 0; frame < 40; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final currentBottom = _inputBottom(tester);
          expect(currentBottom, greaterThanOrEqualTo(previousBottom - .1));
          expect(
            currentBottom - previousBottom,
            lessThan((320 - newKeyboard) * .3 + 1),
            reason: 'The remaining keyboard slot must retire continuously.',
          );
          previousBottom = currentBottom;
        }
        await tester.pump(const Duration(milliseconds: 10));
        await tester.pump();
        expect(tester.getSize(find.byKey(_transition)).height, 0);
        final expectedBottom = newKeyboard == 0
            ? closedBottom
            : closedBottom + 24 - newKeyboard;
        expect(_inputBottom(tester), closeTo(expectedBottom, .1));
        _adjoiningBounds(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('keyboard and menu of equal height keep the input stationary', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tap(find.byKey(_input));
    await tester.pump();
    await _keyboard(tester, 320);
    final keyboardBottom = _inputBottom(tester);
    await _togglePanel(tester);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 60));
      await _keyboard(tester, (3 - frame) * 80);
      expect(_inputBottom(tester), closeTo(keyboardBottom, .1));
    }
    await tester.tap(find.byKey(_input));
    await tester.pump();
    for (final height in [160.0, 320.0]) {
      await tester.pump(const Duration(milliseconds: 60));
      await _keyboard(tester, height);
      expect(_inputBottom(tester), closeTo(keyboardBottom, .1));
    }
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getSize(find.byKey(_transition)).height, 0);
    expect(_inputBottom(tester), closeTo(keyboardBottom, .1));
    _adjoiningBounds(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'long reverse chat stays pinned with independent repaint boundaries',
    (tester) async {
      _viewport(tester);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      addTearDown(app.dispose);
      final chat = ChatController(
        engine: _Replies(),
        store: app.store,
        replyDelay: Duration.zero,
      )..start();
      addTearDown(chat.dispose);
      for (var message = 0; message < 20; message++) {
        await chat.send('这是第 $message 条消息，用于验证长对话的滚动位置。');
      }
      final latest = chat.messages.last.text;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        AppScope(
          services: app,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: chat, scrollController: scroll),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.maxScrollExtent, greaterThan(400));
      final chatState = tester.state(find.byType(CoachChatList));
      final listRender = tester.renderObject(find.byKey(_listBoundary));
      final dockRender = tester.renderObject(find.byKey(_dockBoundary));
      expect(listRender, isA<RenderRepaintBoundary>());
      expect(dockRender, isA<RenderRepaintBoundary>());
      expect(listRender, isNot(same(dockRender)));
      expect(
        find.ancestor(
          of: find.byKey(_listBoundary),
          matching: find.byKey(_dockBoundary),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(_dockBoundary),
          matching: find.byKey(_listBoundary),
        ),
        findsNothing,
      );

      void checkPinned() {
        expect(
          scroll.position.pixels,
          closeTo(scroll.position.minScrollExtent, .1),
        );
        expect(tester.state(find.byType(CoachChatList)), same(chatState));
        expect(
          tester.renderObject(find.byKey(_listBoundary)),
          same(listRender),
        );
        expect(
          tester.renderObject(find.byKey(_dockBoundary)),
          same(dockRender),
        );
        final newest = tester.getRect(find.text(latest));
        final list = tester.getRect(find.byKey(_listBoundary));
        expect(newest.bottom, lessThanOrEqualTo(list.bottom + .1));
        expect(newest.bottom, lessThan(tester.getRect(find.byKey(_face)).top));
        _adjoiningBounds(tester);
      }

      checkPinned();
      await _togglePanel(tester);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump();
        checkPinned();
      }
      await _togglePanel(tester);
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();
      checkPinned();
      await tester.tap(find.byKey(_input));
      await tester.pump();
      await _keyboard(tester, 320);
      checkPinned();

      // A reader browsing earlier messages keeps that offset during menu motion.
      scroll.jumpTo(300);
      await tester.pump();
      await _togglePanel(tester);
      await _keyboard(tester, 0);
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pump();
      expect(scroll.position.pixels, closeTo(300, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
