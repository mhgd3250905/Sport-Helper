// Chat home discovery, explicit navigation/settings and SDK-owned text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/session.dart' show trainerPlan;
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services, tall, showManualChatCard;
import 'support/coach_v2_fixtures.dart';
import 'support/chat_sdk_support.dart';

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async => fixture = await CoachV2Fixtures.load());

  Future<void> say(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
  }

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
      final plan = await showManualChatCard(s, tester: tester);
      final saved = await s.chat.save(trainerPlan(plan));
      s.chat.finished(trainerPlan(plan), completed: 8, total: 8);
      expect(s.chat.suggestions, contains('在家 20 分钟练核心'));
      expect(s.chat.suggestions, isNot(contains('上次那个')));
      expect(s.store.history.single.title, '核心激活');
      await s.chat.start();
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
    await s.chat.start();
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
      final client = coach.FakeLlmClient([
        for (var index = 0; index < 4; index++)
          CoachV2Fixtures.batch([
            CoachV2Fixtures.call('host-explicit-$index', 'ask_user', {
              'question': '这次准备练多久？',
              'mode': 'choice',
              'options': ['10分钟', '15分钟'],
            }),
          ]),
      ], latency: Duration.zero);
      final chat = fakeHostChat(sdkChatServices(s.store, fixture), client);
      addTearDown(chat.close);
      await chat.start();
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
      expect(chat.agent.sessionState.userTurns.map((turn) => turn.text), [
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
    await s.chat.start();
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
    await s.chat.start();
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
    await s.chat.start();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我已了解').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('安全确认 1/4'), findsOneWidget);
    expect(find.textContaining('1/4\u3000'), findsNothing);
  });
}
