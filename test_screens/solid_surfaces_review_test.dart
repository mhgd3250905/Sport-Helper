// Actual App widget previews; no device or performance claims.
// SF_SCREENSHOT_DIR=<absolute output> flutter test --no-pub
//   test_screens/solid_surfaces_review_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/solid_surface.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/support.dart';

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  for (final (family, path) in [
    ('NotoSansSC', 'assets/fonts/NotoSansSC.ttf'),
    (
      'MaterialIcons',
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ),
  ]) {
    final loader = FontLoader(family);
    loader.addFont(
      Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
    );
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
  await tester.pump(const Duration(milliseconds: 100));
  final output = Platform.environment['SF_SCREENSHOT_DIR']!;
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile(Uri.file('$output/$name.png')),
  );
}

void _assertOpaqueSurfaces(WidgetTester tester) {
  expect(find.byType(BackdropFilter), findsNothing);
  final surfaces = find.byType(SfSolidSurface);
  expect(surfaces, findsWidgets);
  for (final element in surfaces.evaluate()) {
    final container =
        (element.widget as SfSolidSurface).build(element) as Container;
    final paint = container.decoration! as BoxDecoration;
    expect(paint.color!.a, 1);
    expect(paint.gradient, isNull);
    final edge = container.foregroundDecoration! as BoxDecoration;
    expect(edge.border!.top.width, 1);
    for (final shadow in paint.boxShadow ?? <BoxShadow>[]) {
      expect(shadow.blurRadius, lessThanOrEqualTo(4));
    }
  }
}

void main() {
  setUpAll(_loadFonts);
  for (final theme in ['light', 'dark']) {
    testWidgets('$theme home and conversation retain input, plan and save', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = AppStore(MemoryStorage())..starfield = false;
      await store.acceptSafety(blocked: false);
      await store.setAppearance(theme);
      final services = AppServices(
        library: loadLibrary(),
        catalog: loadCatalog(),
        store: store,
        voiceLibrary: VoiceLibrary.empty,
        voiceOutput: const MutedVoiceOutput(),
        chatReplyDelay: Duration.zero,
      );
      await tester.pumpWidget(SmartFitApp(services: services));
      await tester.pumpAndSettle();
      expect(find.byType(GreetingBlock), findsOneWidget);
      _assertOpaqueSurfaces(tester);
      final palette = SfColors.palette;
      expect(
        {palette.surfaceLow, palette.surface, palette.surfaceHigh}.length,
        3,
      );
      await _shot(tester, 'home-$theme');

      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '在家 15 分钟练核心，徒手',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(find.byType(PlanCard), findsOneWidget);
      expect(services.chat.currentPlan, isNotNull);
      _assertOpaqueSurfaces(tester);
      await _shot(tester, 'conversation-$theme');

      final plan = services.chat.currentPlan!;
      await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
      await tester.pumpAndSettle();
      final save = find.byKey(ValueKey('plan-save-${plan.id}'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.savedPlans, hasLength(1));
      _assertOpaqueSurfaces(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
