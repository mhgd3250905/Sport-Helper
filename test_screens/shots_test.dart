// Renders key screens to docs/screenshots/*.png (not part of `flutter test`):
//   flutter test test_screens/shots_test.dart --update-goldens
// Uses the bundled CJK font; SF_CJK_FONT can override it. Set
// SF_SCREENSHOT_DIR to an absolute output directory to keep docs unchanged.
// Videos show their posters (no WebView in tests).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/custom_plan_page.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/support.dart';

Future<void> _loadFonts() async {
  final cjk = Platform.environment['SF_CJK_FONT'] ?? 'assets/fonts/NotoSansSC.ttf';
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/workspace/tools/flutter';
  final mat = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      if (File(f).existsSync()) {
        l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
      }
    }
    await l.load();
  }
  await load('NotoSansSC', [cjk]);
  await load('MaterialIcons', ['$mat/MaterialIcons-Regular.otf']);
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in tester.allElements.toList()) {
      final w = e.widget;
      if (w is Image) {
        try {
          await precacheImage(w.image, e);
        } catch (_) {}
      }
    }
  });
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settleImages(tester);
  final out = Platform.environment['SF_SCREENSHOT_DIR'];
  final target = out == null ? Uri.parse('../docs/screenshots/$name.png') : Uri.file('$out/$name.png');
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(target));
}

void main() {
  testWidgets('screens', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = AppStore(MemoryStorage())..starfield = false;
    final s = AppServices(
      library: loadLibrary(), catalog: loadCatalog(), store: store,
      voiceLibrary: VoiceLibrary.empty, voiceOutput: const MutedVoiceOutput(),
      chatReplyDelay: Duration.zero);
    // The chat home opens with the safety talk (chat-*.png come from the
    // web harness, test_screens/web_shots_main.dart).
    await tester.pumpWidget(SmartFitApp(services: s, fontFamily: 'NotoSansSC'));
    await tester.pumpAndSettle();
    await _shot(tester, '01-safety');

    // 02–08: the custom form (drawer → 自定义计划) and the player.
    await s.store.acceptSafety(blocked: false);
    Widget app(Widget home) => AppScope(
      services: s,
      child: MaterialApp(key: UniqueKey(), theme: buildTheme(), home: home),
    );
    await tester.pumpWidget(app(const CustomPlanPage()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('prompt')), '家里有哑铃，想练 25 分钟全身力量');
    await tester.tap(find.text('力量塑形'));
    await tester.tap(find.text('哑铃'));
    await tester.pumpAndSettle();
    await _shot(tester, '02-home');

    await tester.scrollUntilVisible(find.byKey(const ValueKey('generate')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    await _shot(tester, '04-plan');
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await _shot(tester, '05-plan-groups');

    await tester.tap(find.byKey(const ValueKey('start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '06-player-prep');
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '07-player-work');
    await tester.tap(find.byKey(const ValueKey('skip')));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '08-player-rest');
    await tester.tap(find.byKey(const ValueKey('close')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结束'));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop(); // plan → form
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    await _shot(tester, '03-templates');
    await tester.pumpWidget(app(const LibraryPage()));
    await tester.pumpAndSettle();
    await _shot(tester, '09-library');
    await tester.pumpWidget(app(const AboutPage()));
    await tester.pumpAndSettle();
    await _shot(tester, '10-about');
  });
}
