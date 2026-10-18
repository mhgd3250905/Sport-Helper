import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'support.dart';

class MemoryStorage implements LocalStateStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

AppServices services() => AppServices(
  library: loadLibrary(),
  catalog: loadCatalog(),
  store: AppStore(MemoryStorage()),
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
);

/// Tall phone so the lazy lists build every row the test taps.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('safety → describe → plan → player → skip → close', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    // Safety: four "否" + agree.
    expect(find.text('开始之前'), findsOneWidget);
    for (final no in find.text('否').evaluate().toList()) {
      await tester.tap(find.byWidget(no.widget));
    }
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('safety-continue')));
    await tester.tap(find.byKey(const ValueKey('safety-continue')));
    await tester.pumpAndSettle();
    expect(s.store.safetyAccepted, isTrue);
    expect(s.store.safetyBlocked, isFalse);

    // Describe and generate.
    expect(find.text('描述你今天想怎么练'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('prompt')), '在办公室午休 10 分钟，肩颈很僵');
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('工位肩颈腰放松'), findsWidgets);
    expect(find.text('开始跟练'), findsOneWidget);
    expect(s.store.lastPlan?.templateId, 'office-relax');

    // Player.
    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.textContaining('准备'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('秒'), findsWidgets);

    // Close → confirm → back on the plan.
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);
    expect(s.store.history, hasLength(1));
  });

  testWidgets('a "是" safety answer keeps the app in browse-only mode', (tester) async {
    tall(tester);
    final s = services();
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();
    final yes = find.text('是').evaluate().toList();
    final no = find.text('否').evaluate().toList();
    await tester.tap(find.byWidget(yes.first.widget));
    for (final n in no.skip(1)) {
      await tester.tap(find.byWidget(n.widget));
    }
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('safety-continue')));
    await tester.tap(find.byKey(const ValueKey('safety-continue')));
    await tester.pumpAndSettle();
    expect(s.store.safetyBlocked, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(find.text('暂不生成训练计划'), findsOneWidget);
  });
}
