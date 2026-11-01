import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'app_flow_test.dart' show MemoryStorage, tall, pumpOperation;
import 'support/coach_v2_fixtures.dart';
import 'support/chat_sdk_support.dart';
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'support/widget_test_timeout.dart';

late CoachV2Fixtures fixtures;

AppServices _services() =>
    sdkChatServices(AppStore(MemoryStorage())..starfield = false, fixtures);

Future<CoachChatController> _mount(
  WidgetTester tester,
  AppServices app,
  coach.LlmClient client,
) async {
  tall(tester);
  await app.store.acceptSafety(blocked: false);
  final chat = fakeHostChat(app, client);
  expect((await chat.start()).ok, isTrue);
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(
        theme: buildTheme(),
        home: ChatHomePage(controller: chat),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chat;
}

Future<void> _settleRequest(
  WidgetTester tester,
  CoachChatController chat,
) async {
  for (var i = 0; i < 15 && chat.typing; i++) {
    await tester.pump(const Duration(seconds: 30));
  }
  await tester.pumpAndSettle();
  expect(chat.typing, isFalse);
}

void main() {
  configureWidgetTestTimeout();
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => fixtures = await CoachV2Fixtures.load());

  testWidgets('offline turn shows failure bubble and no App preset plan', (
    tester,
  ) async {
    final app = _services();
    final client = coach.FakeLlmClient([
      for (var i = 0; i < 8; i++)
        const coach.LlmException(coach.LlmErrorKind.network, 'offline'),
    ], latency: Duration.zero);
    final chat = await _mount(tester, app, client);
    final send = chat.send('在家徒手10分钟练全身');
    await tester.pump();
    await _settleRequest(tester, chat);
    await send;
    expect(find.byType(CoachFailureBubble), findsOneWidget);
    expect(chat.messages.where((m) => m.isPlanningFailure), hasLength(1));
    expect(chat.messages.where((m) => m.isPlan), isEmpty);
    expect(find.textContaining('预设方案'), findsNothing);
    expect(find.textContaining('当前模板未通过安全检查'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOperation(
      tester,
      chat.close(),
      label: 'Close offline SDK conversation',
    );
  });
}
