// Chat home after the IA pass (docs/design-audit-2026-10-19.md §2.1, §4):
// a large greeting instead of a bubble, discovery chips with icons, the
// conversation switching appearance / voice itself, opening the library by
// category and settings, and the drawer's empty state putting the cursor
// in the chat.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
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

  testWidgets('opening: a large greeting (no bubble) and first-visit discovery chips', (tester) async {
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
      find.descendant(of: find.byType(SuggestionStrip), matching: find.byType(Scrollable)),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    final help = find.ancestor(of: find.text('你能做什么'), matching: find.byType(Row)).first;
    expect(find.descendant(of: help, matching: find.byType(SfIcon)), findsOneWidget);
    // The greeting survives a restart as a greeting.
    expect(g.toJson()['greeting'], isTrue);
  });

  testWidgets('returning: 上次那个 / 上次练了什么 lead the chips', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await s.store.addHistory(HistoryEntry(title: '核心激活', at: DateTime.now(), minutes: 15, completed: 8, total: 8));
    s.chat.start();
    await s.chat.send('在家 15 分钟练核心，徒手');
    await s.chat.started(s.chat.currentPlan!);
    s.chat.finished(s.chat.currentPlan!, completed: 8, total: 8);
    expect(s.chat.suggestions.take(2), ['上次那个', '上次练了什么']);
    await s.chat.send('上次练了什么');
    expect(s.chat.messages.last.text, contains('今天的「核心激活」'));
    expect(s.chat.messages.last.options.single.label, '再来一次');
  });

  testWidgets('the conversation switches appearance and voice itself', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await say(tester, '换浅色');
    expect(s.store.appearance, 'light');
    expect(SfColors.isDark, isFalse);
    await say(tester, '换深色');
    expect(s.store.appearance, 'dark');
    await say(tester, '关掉语音');
    expect(s.store.voice.voice, isFalse);
    expect(s.store.voice.chimes, isTrue);
    await say(tester, '静音');
    expect(s.store.voice.chimes, isFalse);
    await say(tester, '打开语音');
    expect(s.store.voice.voice, isTrue);
  });

  testWidgets('有哪些拉伸动作 opens the library on 拉伸; 设置 opens settings', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await say(tester, '有哪些拉伸动作');
    expect(tester.widget<LibraryPage>(find.byType(LibraryPage)).initial, ExerciseCategory.stretch);
    await tester.tap(find.byTooltip('返回').first);
    await tester.pumpAndSettle();
    await say(tester, '设置');
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('drawer: empty state 去排一套 closes it and focuses the input', (tester) async {
    tall(tester);
    final s = services();
    await s.store.acceptSafety(blocked: false);
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-plans')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('自定义计划'), findsNothing);
    await tester.tap(find.text('去排一套'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('chat-input')));
    expect(field.focusNode!.hasFocus, isTrue);
  });
}
