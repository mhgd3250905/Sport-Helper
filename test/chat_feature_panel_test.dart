import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';

import 'app_flow_test.dart'
    show MemoryStorage, services, tall, showManualChatCard;
import 'support/widget_test_timeout.dart';

const _toggle = ValueKey('chat-panel-toggle');

void main() {
  configureWidgetTestTimeout();
  test(
    'obsolete keyboard height is ignored without disturbing preferences',
    () async {
      final storage = MemoryStorage();
      storage.data[AppStore.key] = jsonEncode({
        'appearance': 'light',
        'lastKeyboardHeight': 314,
        'mediaWifiOnly': false,
      });
      final store = AppStore(storage);
      await store.load();
      expect(store.appearance, 'light');
      expect(store.mediaWifiOnly, isFalse);
      await store.setAppearance('dark');
      expect(
        (jsonDecode(storage.data[AppStore.key]!) as Map).containsKey(
          'lastKeyboardHeight',
        ),
        isFalse,
      );
      final restored = AppStore(storage);
      await restored.load();
      expect(restored.appearance, 'dark');
      expect(restored.mediaWifiOnly, isFalse);
    },
  );

  testWidgets('saved plans page can show and delete a saved plan', (
    tester,
  ) async {
    tall(tester);
    final app = services();
    await app.store.acceptSafety(blocked: false);
    final plan = await showManualChatCard(
      app,
      template: 'office-relax',
      tester: tester,
    );
    final saved = await app.store.savePlan(plan);
    await app.chat.start();
    await tester.pumpWidget(SmartFitApp(services: app));
    await tester.pumpAndSettle();
    Future<void> openPlans() async {
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('panel-plans')));
      await tester.pumpAndSettle();
      expect(find.byType(SavedPlansPage), findsOneWidget);
    }

    await openPlans();
    expect(find.text('1 套'), findsOneWidget);
    expect(find.textContaining('套 · 点一下'), findsNothing);
    await tester.longPress(find.byKey(ValueKey('saved-expanded-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发到对话'));
    await tester.pumpAndSettle();
    expect(app.chat.messages.last.plan?.id, plan.id);
    await openPlans();
    await tester.longPress(find.byKey(ValueKey('saved-expanded-${saved.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-ok')));
    await tester.pumpAndSettle();
    expect(app.store.savedPlans, isEmpty);
  });
}
