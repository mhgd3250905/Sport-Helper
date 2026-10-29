import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_composer_dock.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_focus_label.dart';
import 'package:smartfit/ui/theme.dart';

class _FocusHost extends StatefulWidget {
  const _FocusHost({
    super.key,
    this.title,
    this.palette = SfPalette.light,
    this.dock = false,
    this.reduced = false,
  });

  final String? title;
  final SfPalette palette;
  final bool dock, reduced;

  @override
  State<_FocusHost> createState() => _FocusHostState();
}

class _FocusHostState extends State<_FocusHost> {
  final focus = FocusNode();
  final extent = ValueNotifier<double>(112);
  late String? title = widget.title;
  var clears = 0;

  void setTitle(String? value) => setState(() => title = value);

  void clear() {
    clears++;
    setTitle(null);
  }

  @override
  void dispose() {
    focus.dispose();
    extent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildTheme(widget.palette),
    builder: (context, child) => SfPaletteScope(
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: widget.reduced),
        child: child!,
      ),
    ),
    home: Scaffold(
      resizeToAvoidBottomInset: false,
      body: widget.dock
          ? Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: extent,
                  builder: (context, value, child) => Positioned.fill(
                    bottom: value,
                    child: const ColoredBox(
                      key: ValueKey('focus-thread-viewport'),
                      color: Colors.transparent,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ChatComposerDock(
                    panelOpen: false,
                    focusNode: focus,
                    extent: extent,
                    suggestions: const SizedBox(height: 52),
                    input: const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        key: ValueKey('focus-input'),
                        height: 54,
                        width: double.infinity,
                      ),
                    ),
                    panel: ChatFeaturePanel(
                      actions: [
                        ChatPanelAction(
                          key: const ValueKey('focus-panel-action'),
                          label: '我的计划',
                          icon: SfGlyph.bookmark,
                          onTap: () {},
                        ),
                      ],
                    ),
                    planFocusTitle: title,
                    onClearPlanFocus: clear,
                  ),
                ),
              ],
            )
          : Align(
              alignment: Alignment.topLeft,
              child: PlanFocusLabel(title: title, onClear: clear),
            ),
    ),
  );
}

Future<GlobalKey<_FocusHostState>> _show(
  WidgetTester tester, {
  String? title,
  SfPalette palette = SfPalette.light,
  bool dock = false,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = GlobalKey<_FocusHostState>();
  await tester.pumpWidget(
    _FocusHost(
      key: host,
      title: title,
      palette: palette,
      dock: dock,
      reduced: reduced,
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

Finder get _label => find.byKey(const ValueKey('plan-focus-label'));
Finder get _title => find.byKey(const ValueKey('plan-focus-title'));
Finder get _clear => find.byKey(const ValueKey('plan-focus-clear'));

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(find.byKey(const ValueKey('plan-focus-visibility')))
    .opacity
    .value;

double _offset(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('plan-focus-motion')))
    .transform
    .storage[13];

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets('focus label keeps exact ${palette.brightness.name} values', (
      tester,
    ) async {
      const title = '一份名称很长很长很长很长很长很长很长的已保存训练计划';
      await _show(tester, title: title, palette: palette);
      final size = tester.getSize(_label);
      expect(size.height, 28);
      expect(size.width, lessThanOrEqualTo(350));
      final label = tester.widget<Container>(_label);
      final decoration = label.decoration! as BoxDecoration;
      expect(label.padding, const EdgeInsets.only(left: 10, right: 4));
      expect(decoration.borderRadius, BorderRadius.circular(14));
      expect(decoration.border, isNull);
      expect(
        decoration.color,
        palette.accent.withValues(alpha: palette.isDark ? .18 : .10),
      );
      final text = tester.widget<Text>(
        find.descendant(of: _title, matching: find.text('正在讨论：$title')),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.fontSize, 13);
      expect(text.style!.fontWeight, FontWeight.w500);
      final rendered = tester.widget<RichText>(
        find.descendant(of: _title, matching: find.byType(RichText)),
      );
      expect(rendered.text.style!.fontFamily, sfFontFamily);
      expect(text.style!.color, palette.accent);
      final icons = tester.widgetList<SfIcon>(
        find.descendant(of: _label, matching: find.byType(SfIcon)),
      );
      final bookmark = icons.singleWhere(
        (icon) => icon.glyph == SfGlyph.bookmark,
      );
      final close = icons.singleWhere((icon) => icon.glyph == SfGlyph.close);
      expect(bookmark.size, 14);
      expect(bookmark.color, palette.accent);
      expect(close.size, 14);
      expect(close.color, palette.muted);
      expect(tester.getSize(_clear), const Size(28, 28));
      final bookmarkBounds = tester.getRect(
        find.descendant(
          of: _label,
          matching: find.byWidgetPredicate(
            (widget) => widget is SfIcon && widget.glyph == SfGlyph.bookmark,
          ),
        ),
      );
      expect(tester.getTopLeft(_title).dx - bookmarkBounds.right, 6);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('focus appears through a 180ms fade and 8px upward motion', (
    tester,
  ) async {
    final host = await _show(tester);
    expect(_label, findsNothing);
    host.currentState!.setTitle('晨间舒展');
    await tester.pump();
    expect(_opacity(tester), 0);
    expect(_offset(tester), 8);
    final motion =
        tester
                .widget<FadeTransition>(
                  find.byKey(const ValueKey('plan-focus-visibility')),
                )
                .opacity
            as CurvedAnimation;
    expect(motion.curve, Curves.easeOutCubic);
    expect(motion.reverseCurve, Curves.easeInCubic);
    expect(
      (motion.parent as AnimationController).duration,
      const Duration(milliseconds: 180),
    );
    expect(
      (motion.parent as AnimationController).reverseDuration,
      const Duration(milliseconds: 120),
    );
    await tester.pump(const Duration(milliseconds: 90));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    expect(_offset(tester), inExclusiveRange(0, 8));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_opacity(tester), 1);
    expect(_offset(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'changing focus crossfades its title for 150ms in the same label',
    (tester) async {
      final host = await _show(tester, title: '原计划');
      final labelState = tester.state(find.byType(PlanFocusLabel));
      host.currentState!.setTitle('新版计划');
      await tester.pump();
      expect(tester.state(find.byType(PlanFocusLabel)), same(labelState));
      expect(find.text('正在讨论：原计划'), findsOneWidget);
      expect(find.text('正在讨论：新版计划'), findsOneWidget);
      final crossfade = tester.widget<AnimatedSwitcher>(_title);
      expect(crossfade.duration, const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 75));
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(of: _title, matching: find.byType(FadeTransition)),
      );
      expect(fades, hasLength(2));
      for (final fade in fades) {
        expect(fade.opacity.value, inExclusiveRange(0, 1));
      }
      expect(tester.getSize(_label).height, 28);
      await tester.pumpAndSettle();
      expect(find.text('正在讨论：原计划'), findsNothing);
      expect(find.text('正在讨论：新版计划'), findsOneWidget);
      expect(_opacity(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clear calls the host and retains the label through its 120ms exit',
    (tester) async {
      final host = await _show(tester, title: '晚间计划');
      await tester.tap(_clear);
      await tester.pump();
      expect(host.currentState!.clears, 1);
      expect(host.currentState!.title, isNull);
      expect(_label, findsOneWidget);
      expect(_opacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_opacity(tester), inExclusiveRange(0, 1));
      expect(
        _offset(tester),
        0,
        reason: 'Exit fades in place after entry settles.',
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        _opacity(tester),
        0,
        reason: 'The visual fade ends at exactly 120ms.',
      );
      // Flutter's interpolation completes strictly after its duration boundary.
      // Retire the already transparent widget on the following ticker frame.
      await tester.pump(const Duration(milliseconds: 1));
      expect(_label, findsNothing);
      expect(tester.getSize(find.byType(PlanFocusLabel)).height, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus height is included in the dock extent and clears the thread',
    (tester) async {
      final host = await _show(tester, dock: true);
      final baseExtent = host.currentState!.extent.value;
      final panelMotion =
          tester
                  .widget<SizeTransition>(
                    find.byKey(const ValueKey('chat-panel-transition')),
                  )
                  .sizeFactor
              as CurvedAnimation;
      final panelDriver = panelMotion.parent;

      void checkViewport() {
        final dock = tester.getRect(find.byType(ChatComposerDock));
        final viewport = tester.getRect(
          find.byKey(const ValueKey('focus-thread-viewport')),
        );
        expect(host.currentState!.extent.value, closeTo(dock.height, .01));
        expect(viewport.bottom, closeTo(dock.top, .01));
      }

      checkViewport();
      host.currentState!.setTitle('正在讨论的计划');
      await tester.pumpAndSettle();
      expect(host.currentState!.extent.value, closeTo(baseExtent + 36, .01));
      expect(tester.getTopLeft(_label).dx, 20);
      final input = tester.getRect(find.byKey(const ValueKey('focus-input')));
      expect(input.top - tester.getBottomLeft(_label).dy, 8);
      checkViewport();
      host.currentState!.setTitle('另一个名称更长的计划');
      await tester.pumpAndSettle();
      expect(host.currentState!.extent.value, closeTo(baseExtent + 36, .01));
      final updatedMotion =
          tester
                  .widget<SizeTransition>(
                    find.byKey(const ValueKey('chat-panel-transition')),
                  )
                  .sizeFactor
              as CurvedAnimation;
      expect(updatedMotion.parent, same(panelDriver));
      checkViewport();
      await tester.tap(_clear);
      await tester.pump();
      expect(host.currentState!.extent.value, closeTo(baseExtent + 36, .01));
      await tester.pumpAndSettle();
      expect(host.currentState!.extent.value, closeTo(baseExtent, .01));
      checkViewport();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion updates focus visibility without a pending exit',
    (tester) async {
      final host = await _show(tester, reduced: true);
      host.currentState!.setTitle('计划');
      await tester.pumpAndSettle();
      expect(_opacity(tester), 1);
      await tester.tap(_clear);
      await tester.pumpAndSettle();
      expect(host.currentState!.clears, 1);
      expect(_label, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a dock that never had plan focus disposes without creating a ticker',
    (tester) async {
      await _show(tester, dock: true);
      expect(_label, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Disposal must leave no stale dock observer for the next keyboard.
      tester.view.viewInsets = const FakeViewPadding(bottom: 250);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
