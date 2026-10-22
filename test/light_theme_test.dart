// Light and dark App themes share realistic-dark training media. Optional
// light variants remain an interface; contrast and theme switching still hold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan_generator.dart';
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

  group('shared realistic-dark media in both App themes', () {
    final lib = loadLibrary();

    test('the full fixture uses versioned videos and bundled lossy covers', () {
      expect(lib.length, 93);
      for (final e in lib.all) {
        expect(
          e.media.video,
          'assets/training_media/v0.3.0/realistic/dark/${e.id}.mp4',
        );
        expect(
          e.media.poster,
          'assets/training_media/v0.3.0-app/common-lossy/covers/${e.id}.webp',
        );
        expect(e.media.hasLight, isFalse, reason: e.id);
        expect(e.media.lightVideo, isNull);
        expect(e.media.lightPoster, isNull);
      }
    });

    test('both themes pick the same dark render, cover and stage', () {
      final e = lib['h-squat'];
      for (final palette in [SfPalette.light, SfPalette.dark]) {
        SfColors.palette = palette;
        expect(sfPoster(e), e.media.poster);
        expect(sfVideo(e), e.media.video);
        expect(sfVariant(e), isNull);
        expect(sfStageFor(e).mediaStage, const Color(0xFF101013));
      }
    });

    test(
      'optional light media fields remain available for a later package',
      () {
        const futureMedia = ExerciseMedia(
          id: 'future',
          video: 'realistic/dark/future.mp4',
          poster: 'covers/future.webp',
          loopSeconds: 4,
          posterSeconds: 0,
          source: 'future',
          lightVideo: 'realistic/light/future.mp4',
          lightPoster: 'light-covers/future.webp',
        );
        expect(futureMedia.hasLight, isTrue);
        expect(futureMedia.lightVideo, 'realistic/light/future.mp4');
        expect(futureMedia.lightPoster, 'light-covers/future.webp');
      },
    );

    testWidgets(
      'a demonstration previews the bundled cover in the light App theme',
      (tester) async {
        final e = lib['h-squat'];
        SfColors.palette = SfPalette.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(SfPalette.light),
            home: Center(
              child: SizedBox(
                width: 300,
                child: ExerciseVideo(exercise: e, playing: false),
              ),
            ),
          ),
        );
        expect(_assetsIn(tester), contains(e.media.poster));
        expect(
          _assetsIn(tester).where((path) => path.startsWith('assets/packs/')),
          isEmpty,
        );
        final stage = tester.widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(ExerciseVideo),
            matching: find.byType(ColoredBox),
          ),
        );
        expect(stage.first.color, const Color(0xFF101013));
      },
    );
  });

  group('contrast (WCAG AA) in both themes', () {
    for (final p in [SfPalette.dark, SfPalette.light]) {
      final name = p.isDark ? 'dark' : 'light';
      test('$name: text, muted and accent text on every page level', () {
        for (final bg in [p.background, p.surface, p.skyTop, p.skyBottom]) {
          expect(
            contrast(p.text, bg),
            greaterThanOrEqualTo(7),
            reason: '$name text',
          );
          expect(
            contrast(p.muted, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name muted',
          );
          expect(
            contrast(p.accentText, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name accentText',
          );
        }
        expect(contrast(p.text, p.userBubble), greaterThanOrEqualTo(7));
        expect(contrast(p.text, p.assistantBubble), greaterThanOrEqualTo(7));
        expect(
          contrast(p.onAccent, p.accent),
          greaterThanOrEqualTo(3),
          reason: '$name onAccent (large/bold)',
        );
      });

      test('$name: titles over the media stage', () {
        expect(contrast(p.onStage, p.mediaStage), greaterThanOrEqualTo(7));
        expect(
          contrast(p.onStageMuted, p.mediaStage),
          greaterThanOrEqualTo(4.5),
        );
        // Media tags (已暂停, 换侧) are white on the scrim, over either stage.
        final tag = Color.alphaBlend(p.scrim, p.mediaStage);
        expect(
          contrast(const Color(0xFFFFFFFF), tag),
          greaterThanOrEqualTo(4.5),
        );
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
    test(
      '「你能做什么」 offers the opposite of the look in effect, follow-system included',
      () async {
        final lib = loadLibrary();
        final engine = RuleChatEngine(
          lib: lib,
          templates: TemplatePlanGenerator(lib: lib, catalog: loadCatalog()),
        );
        Future<List<String>> labels(ChatState s) async => [
          for (final o in (await engine.reply(
            '你能做什么',
            s,
          )).messages.first.options)
            o.label,
        ];
        expect(
          await labels(
            const ChatState(appearance: 'system', systemLight: true),
          ),
          contains('换深色'),
        );
        expect(
          await labels(const ChatState(appearance: 'system')),
          contains('换浅色'),
        );
        expect(
          await labels(const ChatState(appearance: 'light')),
          contains('换深色'),
        );
        expect(
          await labels(const ChatState(appearance: 'dark', systemLight: true)),
          contains('换浅色'),
        );
      },
    );

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

    testWidgets(
      'follow-system tracks the platform and keeps the bundled plan covers',
      (tester) async {
        tall(tester);
        final s = services();
        await s.store.acceptSafety(blocked: false);
        s.chat.start();
        await s.chat.send('在家 15 分钟练核心，徒手');
        // Hero and strip previews use the same bundled release covers in
        // either theme, independently of video download availability.
        final items = s.chat.currentPlan!.items.toList();
        final hero = s.library[items.first.exerciseId];
        final first = s.library[items[1].exerciseId];
        expect(s.store.appearance, 'system');

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(SmartFitApp(services: s));
        await tester.pumpAndSettle();
        expect(SfColors.isDark, isTrue);
        expect(_assetsIn(tester), contains(first.media.poster));
        expect(_assetsIn(tester), contains(hero.media.poster));
        expect(
          _assetsIn(tester).where((path) => path.startsWith('assets/cutouts/')),
          isEmpty,
        );

        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpAndSettle();
        expect(SfColors.isDark, isFalse);
        expect(_assetsIn(tester), contains(first.media.poster));
        expect(_assetsIn(tester), contains(hero.media.poster));

        // 「换深色」 in the conversation overrides the system.
        await tester.enterText(find.byKey(const ValueKey('chat-input')), '换深色');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-send')));
        await tester.pumpAndSettle();
        expect(s.store.appearance, 'dark');
        expect(SfColors.isDark, isTrue);
        expect(_assetsIn(tester), contains(first.media.poster));

        // 「换浅色」 back: the shared covers remain without losing the chat.
        final messages = s.chat.messages.length;
        await tester.enterText(find.byKey(const ValueKey('chat-input')), '换浅色');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('chat-send')));
        await tester.pumpAndSettle();
        expect(s.store.appearance, 'light');
        expect(SfColors.isDark, isFalse);
        expect(_assetsIn(tester), contains(first.media.poster));
        expect(s.chat.messages.length, greaterThan(messages));
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
