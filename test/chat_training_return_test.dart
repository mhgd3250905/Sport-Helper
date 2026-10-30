import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_timeline.dart';
import 'package:smartfit/ui/chat/training_card_media.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

void main() {
  for (final scrolled in [false, true]) {
    testWidgets(
      'finished row preserves the first layout anchor, scrolled=$scrolled',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        final at = DateTime(2026, 10, 30, 12);
        final old = [
          for (var index = 0; index < 14; index++)
            CoachChatEntry(
              id: 'old-$index',
              at: at,
              isUser: false,
              child: SizedBox(
                key: ValueKey('content-$index'),
                height: 64,
                child: Text('row $index'),
              ),
            ),
        ];
        Widget build(List<CoachChatEntry> rows) => MaterialApp(
          home: Scaffold(
            body: ChatTimeline(
              entries: rows,
              controller: scroll,
              initiallySeen: old.map((row) => row.id).toSet(),
              finishedEntries: const {'finished'},
              timeMarkBuilder: (_, _) => const SizedBox(height: 24),
            ),
          ),
        );
        await tester.pumpWidget(build(old));
        await tester.pumpAndSettle();
        if (scrolled) {
          scroll.jumpTo(100);
          await tester.pump();
        }
        final originalOffset = scroll.offset;
        final anchor = tester.getRect(find.byKey(const ValueKey('content-11')));
        await tester.pumpWidget(
          build([
            ...old,
            CoachChatEntry(
              id: 'finished',
              at: at,
              isUser: false,
              child: const SizedBox(
                key: ValueKey('finished-content'),
                height: 80,
                child: Text('finished'),
              ),
            ),
          ]),
        );
        expect(scroll.offset, originalOffset);
        expect(
          tester.getRect(find.byKey(const ValueKey('content-11'))).top,
          closeTo(anchor.top, .001),
        );
        expect(
          tester
              .getSize(
                find.byKey(
                  const ValueKey('training-finished-size'),
                  skipOffstage: false,
                ),
              )
              .height,
          0,
        );
        final fade = find.byKey(
          const ValueKey('training-finished-opacity'),
          skipOffstage: false,
        );
        final position = find.byKey(
          const ValueKey('training-finished-position'),
          skipOffstage: false,
        );
        expect(tester.widget<Opacity>(fade).opacity, 0);
        expect(tester.widget<Transform>(position).transform.storage[13], 12);
        expect(
          find.ancestor(
            of: find.byKey(
              const ValueKey('finished-content'),
              skipOffstage: false,
            ),
            matching: find.byType(CoachAppear, skipOffstage: false),
          ),
          findsNothing,
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          tester.widget<Opacity>(fade).opacity,
          closeTo(Curves.easeOutCubic.transform(.5), .0001),
        );
        expect(
          tester.widget<Transform>(position).transform.storage[13],
          closeTo(12 * (1 - Curves.easeOutCubic.transform(.5)), .0001),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('content-11'))).top,
          lessThan(anchor.top),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.widget<Opacity>(fade).opacity, 1);
        expect(tester.widget<Transform>(position).transform.storage[13], 0);
        final settled = tester.getRect(
          find.byKey(const ValueKey('content-11')),
        );
        await tester.pump(const Duration(milliseconds: 130));
        expect(
          tester.getRect(find.byKey(const ValueKey('content-11'))),
          settled,
        );
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'card source uses its first action image box and hides only that image',
    (tester) async {
      final registry = TrainingCardMediaRegistry('first');
      final small = GlobalKey();
      final hero = GlobalKey();
      final other = GlobalKey();
      await tester.pumpWidget(
        _mediaFixture(registry, [
          _image(small, 'first', const Size(44, 44)),
          _image(hero, 'first', const Size(240, 160)),
          _image(other, 'other', const Size(260, 180)),
        ]),
      );
      final source = registry.capture()!;
      expect(source.initialRect, tester.getRect(find.byKey(hero)));
      expect(source.rect(), source.initialRect);
      expect(source.repaintKey, isNotNull);
      source.opacity.value = 0;
      await tester.pump();
      final opacityValues = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .map((w) => w.opacity)
          .toList();
      expect(opacityValues.where((v) => v == 0), hasLength(1));
      expect(opacityValues.where((v) => v == 1), hasLength(1));
      source.opacity.value = 1;
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(source.rect(), isNull);
      registry.dispose();
      source.opacity.value = 1;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card with a folded hero no longer visible uses no-origin fallback',
    (tester) async {
      final registry = TrainingCardMediaRegistry('first');
      await tester.pumpWidget(
        _mediaFixture(registry, [
          _image(GlobalKey(), 'first', const Size(240, 160)),
          CoachPressable(
            expanded: true,
            onTap: () {},
            child: const Text('expanded'),
          ),
        ]),
      );
      expect(registry.capture(), isNull);
      await tester.pumpWidget(const SizedBox());
      registry.dispose();
    },
  );
}

Widget _mediaFixture(
  TrainingCardMediaRegistry registry,
  List<Widget> children,
) => MaterialApp(
  home: Builder(
    builder: (context) {
      final base = CoachUiStyle.fromTheme(Theme.of(context));
      return CoachUiTheme(
        style: CoachUiStyle(
          colors: base.colors,
          typography: base.typography,
          builders: CoachUiBuilders(
            media: (_, _) => const ColoredBox(color: Colors.teal),
          ),
        ),
        child: TrainingCardMedia(
          registry: registry,
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
    },
  ),
);

Widget _image(Key key, String id, Size size) => SizedBox.fromSize(
  key: key,
  size: size,
  child: Builder(
    builder: (context) => CoachUiTheme.of(context).builders.media!(
      context,
      CoachMediaRequest(
        exercise: CoachExercise(
          id: id,
          name: id,
          poster: 'test.webp',
          stage: const CoachMediaPalette(
            mediaStage: Colors.white,
            onStage: Colors.black,
            onStageMuted: Colors.grey,
          ),
        ),
        asset: 'test.webp',
        cutout: true,
        still: false,
        landing: false,
        fit: BoxFit.contain,
        alignment: Alignment.center,
      ),
    )!,
  ),
);
