// Actual 390×844 Flutter widgets. These are software layout evidence,
// without system status bars, native optics, video or performance claims.
// SF_SCREENSHOT_DIR=<output> flutter test --no-pub --flavor internal
// test_screens/settings_review_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/theme.dart';

import '../test/posehub_ui_support.dart';
import '../test/settings_support.dart';

Future<void> _fonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  for (final (family, bytes) in [
    ('NotoSansSC', rootBundle.load('assets/fonts/NotoSansSC.ttf')),
    (
      'MaterialIcons',
      Future.value(
        ByteData.sublistView(
          File(
            '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    ),
  ]) {
    final loader = FontLoader(family)..addFont(bytes);
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final element in tester.allElements.toList()) {
      if (element.widget case final Image image) {
        await precacheImage(image.image, element);
      }
    }
  });
  await tester.pump();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(
      Uri.file('${Platform.environment['SF_SCREENSHOT_DIR']}/$name.png'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['SF_SCREENSHOT_DIR'];
  setUpAll(_fonts);
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'settings actual top and bottom ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cache = SettingsCacheRepository();
        final services = settingsServices(cache: cache);
        await services.store.setAppearance('system');
        await services.store.actionIssueStore.setRecordingEnabled(false);
        addTearDown(services.dispose);
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            home: const AboutPage(),
          ),
        );
        await tester.pumpAndSettle();
        await _shot(tester, 'settings-top-${palette.brightness.name}');
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await _shot(tester, 'settings-bottom-${palette.brightness.name}');
        if (palette.brightness == Brightness.light) {
          // The reference's app viewport excludes its bezel and status bar.
          tester.view.physicalSize = const Size(374, 784);
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await _shot(tester, 'reference-size-top-light');
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pumpAndSettle();
          await _shot(tester, 'reference-size-bottom-light');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        cache.dispose();
      },
      skip: output == null,
    );
  }
}
