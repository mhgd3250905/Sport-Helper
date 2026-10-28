// Chat home discovery, explicit navigation/settings and SDK-owned text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services, tall, showManualChatCard;
import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
  }

  test('the greeting follows the hour', () {
    expect(greetingFor(DateTime(2026, 10, 20, 8)), '早上好');
    expect(greetingFor(DateTime(2026, 10, 20, 12)), '中午好');
    expect(greetingFor(DateTime(2026, 10, 20, 15)), '下午好');
    expect(greetingFor(DateTime(2026, 10, 20, 20)), '晚上好');
    expect(greetingFor(DateTime(2026, 10, 20, 1)), '夜深了');
  });

  testWidgets(
    'opening: a large greeting (no bubble) and first-visit discovery chips',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      final g = s.chat.messages.single;
      expect(g.greeting, isTrue);
      expect(find.byType(GreetingBlock), findsOneWidget);
      expect(find.byType(MessageBubble), findsNothing);
      expect(find.text(greetingFor(DateTime.now())), findsOneWidget);
      expect(find.text('说说今天想怎么练？'), findsOneWidget);
      // First visit: plan examples, then 你能做什么 with its glyph.
      expect(s.chat.suggestions.last, '你能做什么');
      await tester.dragUntilVisible(
        find.text('你能做什么'),
        find.descendant(
          of: find.byType(SuggestionStrip),
          matching: find.byType(Scrollable),
        ),
        const Offset(-120, 0),
      );
      await tester.pumpAndSettle();
      final help = find
          .ancestor(of: find.text('你能做什么'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: help, matching: find.byType(SfIcon)),
        findsOneWidget,
      );
      // The greeting survives a restart as a greeting.
      expect(g.toJson()['greeting'], isTrue);
    },
  );

  testWidgets(
    'returning users retain training history and use the plan panel',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await s.store.addHistory(
        HistoryEntry(
          title: '核心激活',
          at: DateTime.now(),
          minutes: 15,
          completed: 8,
          total: 8,
        ),
      );
      s.chat.start();
      final plan = await showManualChatCard(s);
      final saved = await s.chat.save(plan);
      s.chat.finished(plan, completed: 8, total: 8);
      expect(s.chat.suggestions, contains('在家 20 分钟练核心'));
      expect(s.chat.suggestions, isNot(contains('上次那个')));
      expect(s.store.history.single.title, '核心激活');
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-plans')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('saved-${saved.id}')), findsOneWidget);
    },
  );

  testWidgets('settings controls switch appearance and voice explicitly', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('appearance-light')));
    await tester.pumpAndSettle();
    expect(s.store.appearance, 'light');
    expect(SfColors.isDark, isFalse);
    await tester.tap(find.byKey(const ValueKey('appearance-dark')));
    await tester.pumpAndSettle();
    expect(s.store.appearance, 'dark');
    await tester.ensureVisible(find.byKey(const ValueKey('voice-switch')));
    await tester.tap(find.byKey(const ValueKey('voice-switch')));
    await tester.pumpAndSettle();
    expect(s.store.voice.voice, isFalse);
    expect(s.store.voice.chimes, isTrue);
    await tester.tap(find.byKey(const ValueKey('chime-switch')));
    await tester.pumpAndSettle();
    expect(s.store.voice.chimes, isFalse);
    await tester.tap(find.byKey(const ValueKey('voice-switch')));
    await tester.pumpAndSettle();
    expect(s.store.voice.voice, isTrue);
  });

  testWidgets(
    'free text reaches SDK and cannot change App settings or navigate',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      final client = coach.FakeLlmClient(
        List.filled(4, 'SDK 已收到。'),
        latency: Duration.zero,
      );
      final engine = AiChatEngine(
        local: const AppChatActions(),
        catalog: fixture.catalog,
        profile: fixture.profile,
        client: client,
        enableUserMemory: false,
      );
      final chat = ChatController(
        engine: engine,
        store: s.store,
        replyDelay: Duration.zero,
      );
      addTearDown(chat.dispose);
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: chat),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final appearance = s.store.appearance;
      final voice = s.store.voice;
      for (final text in ['换浅色', '关掉语音', '有哪些拉伸动作', '设置']) {
        await say(tester, text);
        expect(s.store.appearance, appearance);
        expect(s.store.voice, same(voice));
        expect(find.byType(LibraryPage), findsNothing);
        expect(find.byType(AboutPage), findsNothing);
      }
      expect(client.requests, hasLength(4));
      expect(engine.agent.sessionState.userTurns.map((turn) => turn.text), [
        '换浅色',
        '关掉语音',
        '有哪些拉伸动作',
        '设置',
      ]);
    },
  );

  testWidgets('panel navigation opens the library with filters and settings', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel-library')));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('cat-stretch')));
    await tester.tap(find.byKey(const ValueKey('cat-stretch')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SfChoiceChip>(find.byKey(const ValueKey('cat-stretch')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byTooltip('返回').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('panel-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('drawer: empty state 去排一套 closes it and focuses the input', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('自定义计划'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('panel-plans')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去排一套'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-input')),
    );
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('safety talk: each question carries its step as a caption', (
    tester,
  ) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is OptionPill && w.label == '我已了解' && w.enabled,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('安全确认 1/4'), findsOneWidget);
    expect(find.textContaining('1/4\u3000'), findsNothing);
  });
}
