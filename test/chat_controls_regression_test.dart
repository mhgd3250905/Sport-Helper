import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/library_page.dart';
import 'package:smartfit/ui/chat/saved_plans_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/widgets.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import 'support.dart';
import 'app_flow_test.dart' show widgetFixtureStateEncoder;

class _MemoryStorage implements LocalStateStorage {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  testWidgets(
    'custom controls support Tab, Enter and Space, skipping disabled actions',
    (tester) async {
      final activated = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SfPrimaryButton(
                  label: '开始',
                  onPressed: () => activated.add('start'),
                ),
                const SfPrimaryButton(label: '不可用', onPressed: null),
                SfTextAction(
                  label: '保存',
                  onPressed: () => activated.add('save'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activated, ['start']);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(activated, ['start', 'save']);
    },
  );

  testWidgets(
    'button accessibility names stay separate and activate through semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final activated = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('训练前请阅读以下免责声明。'),
                SfPressable(
                  semanticLabel: '我已了解',
                  tooltip: '我已了解',
                  onTap: () => activated.add('ack'),
                  child: const Text('我已了解'),
                ),
                const SfPressable(
                  semanticLabel: '不可用',
                  onTap: null,
                  child: Text('不可用'),
                ),
                SfPressable(
                  onTap: () => activated.add('inferred'),
                  child: const Text('从文字识别'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.semantics.byLabel('训练前请阅读以下免责声明。'), findsOne);
      expect(find.semantics.byLabel('我已了解'), findsOne);
      expect(find.semantics.byLabel('不可用'), findsOne);
      expect(find.semantics.byLabel('从文字识别'), findsOne);
      tester.semantics.tap(find.semantics.byLabel('我已了解'));
      tester.semantics.tap(find.semantics.byLabel('从文字识别'));
      expect(activated, ['ack', 'inferred']);
      semantics.dispose();
    },
  );

  testWidgets('the empty plans page scrolls in a small landscape viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SavedPlansPage(
          store: AppStore(
            _MemoryStorage(),
            stateEncoder: widgetFixtureStateEncoder,
          ),
          library: loadLibrary(),
          onShow: (_) {},
          onStart: (_, _) {},
          onCompose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('还没有保存的计划'), 120);
    await tester.pumpAndSettle();
    expect(find.text('0 套'), findsOneWidget);
    expect(find.text('还没有保存的计划').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy library reuses SDK recommendation cards at narrow widths and enlarged text',
    (tester) async {
      final loader = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
      await loader.load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = AppServices(
        library: loadLibrary(),
        catalog: loadCatalog(),
        store: AppStore(
          _MemoryStorage(),
          stateEncoder: widgetFixtureStateEncoder,
        ),
        voiceLibrary: VoiceLibrary.empty,
        voiceOutput: const MutedVoiceOutput(),
      );
      for (final width in [360.0, 320.0]) {
        tester.view.physicalSize = Size(width, 780);
        for (final scale in [1.0, 1.3]) {
          await tester.pumpWidget(
            AppScope(
              services: services,
              child: MaterialApp(
                theme: buildTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const LibraryPage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CoachRecommendCard), findsOneWidget);
          final ids = services.library.all
              .take(2)
              .map((exercise) => exercise.id)
              .toList();
          final firstTile = find.byKey(ValueKey('recommend-surface-${ids[0]}'));
          final nextTile = find.byKey(ValueKey('recommend-surface-${ids[1]}'));
          final first = tester.getRect(firstTile);
          final next = tester.getRect(nextTile);
          expect(first.size, next.size);
          expect(next.left - first.right, 12);
          final artwork = tester.getRect(
            find.byKey(ValueKey('recommend-image-area-${ids[0]}')),
          );
          expect(artwork.left - first.left, 12);
          expect(artwork.top - first.top, 12);
          expect(artwork.width, first.width - 24);
          expect(artwork.height, artwork.width);
          final firstTexts = find.descendant(
            of: firstTile,
            matching: find.byType(Text),
          );
          final nextTexts = find.descendant(
            of: nextTile,
            matching: find.byType(Text),
          );
          expect(
            tester.getRect(firstTexts.first).height,
            tester.getRect(nextTexts.first).height,
          );
          expect(
            tester.getRect(firstTexts.last).bottom,
            tester.getRect(nextTexts.last).bottom,
          );
          expect(
            first.bottom - tester.getRect(firstTexts.last).bottom,
            closeTo(12, .000001),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'width=$width, text scale=$scale',
          );
        }
      }
    },
  );
}
