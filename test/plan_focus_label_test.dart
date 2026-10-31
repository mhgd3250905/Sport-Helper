import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/chat_composer_dock.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show PlanFocusLabel;
import 'package:smartfit/ui/theme.dart';

class _FocusHost extends StatefulWidget {
  const _FocusHost({
    super.key,
    this.title,
    this.palette = SfPalette.light,
    this.reduced = false,
  });

  final String? title;
  final SfPalette palette;
  final bool reduced;

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
      body: Stack(
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
      ),
    ),
  );
}

Future<GlobalKey<_FocusHostState>> _show(
  WidgetTester tester, {
  String? title,
  SfPalette palette = SfPalette.light,
  bool reduced = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = GlobalKey<_FocusHostState>();
  await tester.pumpWidget(
    _FocusHost(key: host, title: title, palette: palette, reduced: reduced),
  );
  await tester.pumpAndSettle();
  return host;
}

Finder get _label => find.byKey(const ValueKey('plan-focus-label'));
Finder get _clear => find.byKey(const ValueKey('plan-focus-clear'));

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  testWidgets(
    'focus height is included in the dock extent and clears the thread',
    (tester) async {
      final host = await _show(tester);
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
      expect(find.byType(PlanFocusLabel), findsOneWidget);
      final icons = tester
          .widgetList<SfIcon>(
            find.descendant(of: _label, matching: find.byType(SfIcon)),
          )
          .toList();
      expect(icons.map((icon) => icon.glyph), [
        SfGlyph.bookmark,
        SfGlyph.close,
      ]);
      expect(icons.map((icon) => icon.size), [14, 14]);
      expect(icons.map((icon) => icon.color), [
        SfPalette.light.accent,
        SfPalette.light.muted,
      ]);
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
    'a dock that never had plan focus disposes without creating a ticker',
    (tester) async {
      await _show(tester);
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
