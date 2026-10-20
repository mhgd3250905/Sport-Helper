// Key screens in both themes for docs/screenshots/aesthetic-v2/ (not part
// of `flutter test`):
//   SF_SCREENSHOT_DIR=/abs/out flutter test test_screens/aesthetic_shots_test.dart --update-goldens
// Shots: home (opening chat), card (a plan card), player (counting down),
// library, settings — each as <name>-dark.png / <name>-light.png at
// 390×844 @3x. Videos show their posters (no WebView in widget tests).
// Only stable keys / texts are used, so the same file shoots the old and
// the new UI for before/after comparisons.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/support.dart';

Future<void> _loadFonts() async {
  final l = FontLoader('NotoSansSC')
    ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/NotoSansSC.ttf').readAsBytesSync())));
  await l.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? '/workspace/flutter-sdk'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
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
  final out = Platform.environment['SF_SCREENSHOT_DIR'] ?? '/tmp/sf-shots';
  await expectLater(find.byType(MaterialApp).first, matchesGoldenFile(Uri.file('$out/$name.png')));
}

Future<AppServices> _app(WidgetTester tester, String theme) async {
  final store = AppStore(MemoryStorage())..starfield = false;
  await store.setAppearance(theme);
  await store.acceptSafety(blocked: false);
  final s = AppServices(
    library: loadLibrary(),
    catalog: loadCatalog(),
    store: store,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );
  await tester.pumpWidget(SmartFitApp(key: UniqueKey(), services: s, fontFamily: 'NotoSansSC'));
  await tester.pump(const Duration(seconds: 2));
  return s;
}

Future<void> _settle(WidgetTester tester, [int ms = 1500]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final theme in ['dark', 'light']) {
    testWidgets('shots $theme', (tester) async {
      await _loadFonts();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await _app(tester, theme);
      await _settle(tester);
      await _shot(tester, 'home-$theme');

      var s = await _app(tester, theme);
      await s.chat.send('在家 15 分钟练核心，徒手');
      await _settle(tester);
      await _shot(tester, 'card-$theme');

      final start = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('plan-start-'),
      );
      await tester.tap(start.last);
      await _settle(tester, 1200);
      await tester.tap(find.byKey(const ValueKey('skip')));
      await _settle(tester, 2300);
      await _shot(tester, 'player-$theme');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));

      s = await _app(tester, theme);
      s.chat.command('@library');
      await _settle(tester);
      await _shot(tester, 'library-$theme');

      s = await _app(tester, theme);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const AboutPage()));
      await _settle(tester);
      await _shot(tester, 'settings-$theme');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
