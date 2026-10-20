// Light theme (docs/design-audit-2026-10-19.md §6): light-stage media in
// the light theme, symmetric contrast, follow-system default and switching.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/theme.dart';

import 'app_flow_test.dart' show MemoryStorage, services, tall;
import 'support.dart';

double _lum(Color c) => c.computeLuminance();
double contrast(Color fg, Color bg) {
  // Flatten a translucent foreground onto its background first.
  final f = Color.alphaBlend(fg, bg);
  final a = _lum(f), b = _lum(bg);
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

Iterable<String> _assetsIn(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((a) => a.assetName);

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  group('light-stage media', () {
    final lib = loadLibrary();

    test('every drill has a light render on the #EFEFEF stage', () {
      expect(lib.length, 93);
      for (final e in lib.all) {
        expect(e.media.hasLight, isTrue, reason: e.id);
        expect(e.media.lightVideo, endsWith('/demo-light.mp4'));
        expect(e.media.lightPoster, endsWith('/cover-light.jpg'));
      }
      expect(SfPalette.light.mediaStage, const Color(0xFFEFEFEF));
    });

    test('the theme picks the matching cover, clip, player variant and stage', () {
      final e = lib['h-squat'];
      SfColors.palette = SfPalette.light;
      expect(sfPoster(e), e.media.lightPoster);
      expect(sfVideo(e), e.media.lightVideo);
      expect(sfVariant(e), 'light');
      expect(sfStageFor(e).mediaStage, const Color(0xFFEFEFEF));
      SfColors.palette = SfPalette.dark;
      expect(sfPoster(e), e.media.poster);
      expect(sfVideo(e), e.media.video);
      expect(sfVariant(e), isNull);
      expect(sfStageFor(e).mediaStage, const Color(0xFF101013));
    });

    testWidgets('a demonstration shows the light poster on the light stage', (tester) async {
      final e = lib['h-squat'];
      SfColors.palette = SfPalette.light;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(SfPalette.light),
        home: Center(child: SizedBox(width: 300, child: ExerciseVideo(exercise: e, playing: false))),
      ));
      expect(_assetsIn(tester), contains(e.media.lightPoster));
      expect(_assetsIn(tester), isNot(contains(e.media.poster)));
      final stage = tester.widgetList<ColoredBox>(
        find.descendant(of: find.byType(ExerciseVideo), matching: find.byType(ColoredBox)),
      );
      expect(stage.first.color, const Color(0xFFEFEFEF));
    });
  });

  group('contrast (WCAG AA) in both themes', () {
    for (final p in [SfPalette.dark, SfPalette.light]) {
      final name = p.isDark ? 'dark' : 'light';
      test('$name: text, muted and accent text on every page level', () {
        for (final bg in [p.background, p.surface, p.skyTop, p.skyBottom]) {
          expect(contrast(p.text, bg), greaterThanOrEqualTo(7), reason: '$name text');
          expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: '$name muted');
          expect(contrast(p.accentText, bg), greaterThanOrEqualTo(4.5), reason: '$name accentText');
        }
        expect(contrast(p.text, p.userBubble), greaterThanOrEqualTo(7));
        expect(contrast(p.text, p.assistantBubble), greaterThanOrEqualTo(7));
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(3), reason: '$name onAccent (large/bold)');
      });

      test('$name: titles over the media stage', () {
        expect(contrast(p.onStage, p.mediaStage), greaterThanOrEqualTo(7));
        expect(contrast(p.onStageMuted, p.mediaStage), greaterThanOrEqualTo(4.5));
        // Media tags (已暂停, 换侧) are white on the scrim, over either stage.
        final tag = Color.alphaBlend(p.scrim, p.mediaStage);
        expect(contrast(const Color(0xFFFFFFFF), tag), greaterThanOrEqualTo(4.5));
      });
    }

    test('the two themes are symmetric: the same roles, the opposite ink', () {
      for (final (d, l) in [
        (SfPalette.dark.text, SfPalette.light.text),
        (SfPalette.dark.onStage, SfPalette.light.onStage),
        (SfPalette.dark.mediaStage, SfPalette.light.mediaStage),
        (SfPalette.dark.background, SfPalette.light.background),
      ]) {
        expect(_lum(d) < .5, isNot(_lum(l) < .5));
      }
    });
  });

  group('switching', () {
    test('a new install follows the system; a stored choice is kept', () async {
      final fresh = AppStore(MemoryStorage());
      await fresh.load();
      expect(fresh.appearance, 'system');
      final storage = MemoryStorage();
      final first = AppStore(storage);
      await first.load();
      await first.setAppearance('dark');
      final again = AppStore(storage);
      await again.load();
      expect(again.appearance, 'dark');
    });

    testWidgets('follow-system tracks the platform, and the plan card swaps its cover', (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      s.chat.start();
      await s.chat.send('在家 15 分钟练核心，徒手');
      final first = s.library[s.chat.currentPlan!.blocks.first.items.first.exerciseId];
      expect(s.store.appearance, 'system');

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      expect(SfColors.isDark, isTrue);
      expect(_assetsIn(tester), contains(first.media.poster));

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect(SfColors.isDark, isFalse);
      expect(_assetsIn(tester), contains(first.media.lightPoster));
      expect(_assetsIn(tester), isNot(contains(first.media.poster)));

      // 「换深色」 in the conversation overrides the system.
      await tester.enterText(find.byKey(const ValueKey('chat-input')), '换深色');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(s.store.appearance, 'dark');
      expect(SfColors.isDark, isTrue);
      expect(_assetsIn(tester), contains(first.media.poster));

      // 「换浅色」 back: the light renders return without losing the chat.
      final messages = s.chat.messages.length;
      await tester.enterText(find.byKey(const ValueKey('chat-input')), '换浅色');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(s.store.appearance, 'light');
      expect(SfColors.isDark, isFalse);
      expect(_assetsIn(tester), contains(first.media.lightPoster));
      expect(s.chat.messages.length, greaterThan(messages));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
