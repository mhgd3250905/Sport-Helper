// Actual SDK widget previews with verified original pack images.
// This captures covers and controls, not native video or device performance.
// UI FakeRepo only resolves the independently verified installed-v2 source;
// this test does not validate downloads/cache integrity or SDK provider hooks.
// SMARTFIT_POSEHUB_TEST_PACK=<installed root> SF_SCREENSHOT_DIR=<output>
// flutter test --no-pub test_screens/posehub_library_review_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../test/posehub_ui_support.dart';

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
    (
      'packages/cupertino_icons/CupertinoIcons',
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
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
        if (image.image case final FileImage source) {
          expect(await source.file.exists(), isTrue, reason: source.file.path);
        }
        await precacheImage(image.image, element);
      }
    }
  });
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
  final output = Platform.environment['SF_SCREENSHOT_DIR']!;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(Uri.file('$output/$name.png')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final installedRoot = Platform.environment['SMARTFIT_POSEHUB_TEST_PACK'];
  late coach.PoseHubAppTestCatalog catalog;
  setUpAll(() async {
    await _fonts();
    catalog = await PoseHubActionLibrary.load();
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'actual SDK library and pending practice ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final media = PoseHubUiRepository(
          mediaBaseUri: Directory(installedRoot!).absolute.uri,
        );
        final services = poseHubUiServices(catalog: catalog, media: media);
        // Start real file decoding outside the fake widget clock, before any
        // Image.file starts a pending stream that would await that same clock.
        await tester.pumpWidget(
          poseHubUiApp(palette: palette, home: const SizedBox.shrink()),
        );
        final imageContext = tester.element(find.byType(SizedBox).first);
        final base = Directory(installedRoot).absolute.uri;
        final previewFiles = {
          for (final action in catalog.allActions.take(12)) action.thumbnail,
          for (final action in catalog.pendingActions) action.thumbnail,
          catalog.tryGet('h-towel-isometric-curl')!.cover,
        };
        await tester.runAsync(() async {
          for (final file in previewFiles) {
            final original = File.fromUri(file.resolve(base));
            expect(original.existsSync(), isTrue, reason: original.path);
            await precacheImage(FileImage(original), imageContext);
          }
        });
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          poseHubUiApp(
            palette: palette,
            services: services,
            navigatorKey: navigator,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        );
        navigator.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const LibraryPage()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PoseHubActionBrowser), findsOneWidget);
        expect(find.text('显示 219 个动作'), findsOneWidget);
        await _shot(tester, 'library-${palette.brightness.name}');

        await tester.tap(find.byKey(const ValueKey('posehub-filter-pending')));
        await tester.pumpAndSettle();
        expect(find.text('显示 8 个动作'), findsOneWidget);
        await _shot(tester, 'library-pending-${palette.brightness.name}');
        final pending = catalog.tryGet('h-towel-isometric-curl')!;
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          pending.id,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('posehub-action-${pending.id}')));
        await tester.pumpAndSettle();
        expect(find.byType(PoseHubActionDetail), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('posehub-practice')),
          250,
        );
        await tester.tap(find.byKey(const ValueKey('posehub-practice')));
        await tester.pumpAndSettle();
        expect(find.byType(PoseHubSinglePracticePage), findsOneWidget);
        expect(find.text('训练说明待补'), findsOneWidget);
        expect(find.text('开始单练'), findsOneWidget);
        expect(find.textContaining('原始建议：'), findsNothing);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        await _shot(tester, 'practice-pending-${palette.brightness.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        media.dispose();
      },
      skip: installedRoot == null,
    );
  }
}
