// Actual SDK widget previews using the SDK's bundled standing frames.
// A pending UI FakeRepo keeps the shared Trainer visible without native video.
// This does not validate downloads/cache integrity or device performance.
// SF_SCREENSHOT_DIR=<output>
// flutter test --no-pub test_screens/posehub_library_review_test.dart --update-goldens
import 'dart:async';
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
  final output = Platform.environment['SF_SCREENSHOT_DIR'];
  late coach.PoseHubAppTestCatalog catalog;
  setUpAll(() async {
    await _fonts();
    catalog = await PoseHubActionLibrary.load();
  });
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'actual SDK complete library and immediate trainer ${palette.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final pending = Completer<Uri>();
        final media = PoseHubUiRepository(
          mediaBaseUri: Uri.parse('file:///ui-screenshot-contract/'),
          onEnsureAction: (_) => pending.future,
        );
        final services = poseHubUiServices(catalog: catalog, media: media);
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
        final grid = tester.widget<GridView>(find.byType(GridView));
        expect(
          (grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
          211,
        );
        await _shot(tester, 'library-${palette.brightness.name}');

        await tester.tap(find.byKey(const ValueKey('posehub-器械-徒手')));
        await tester.pumpAndSettle();
        await _shot(tester, 'library-filtered-${palette.brightness.name}');
        await tester.tap(find.byKey(const ValueKey('posehub-clear-filters')));
        final action = catalog.semanticCompleteActions.first;
        await tester.enterText(
          find.byKey(const ValueKey('posehub-search')),
          action.nameZh,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('posehub-action-${action.id}')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(PoseHubSinglePracticePage), findsOneWidget);
        expect(find.byType(TrainerPlayer), findsOneWidget);
        expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
        expect(find.byType(UgkPackedAlphaVideo), findsNothing);
        await _shot(tester, 'practice-${palette.brightness.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        pending.complete(media.mediaBaseUri);
        media.dispose();
      },
      skip: output == null,
    );
  }
}
