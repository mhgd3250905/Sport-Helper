import 'package:flutter/material.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'chat_bubble_adapter.dart';
export 'chat_bubble_adapter.dart';

/// The chips that open a feature (not plan requests) and their glyphs:
/// the shape says what tapping does (§4.3).
const chipGlyphs = <String, SfGlyph>{
  '看看动作库': SfGlyph.grid,
  '浏览动作库': SfGlyph.grid,
  '动作库': SfGlyph.grid,
  '上次练了什么': SfGlyph.clock,
  '我的计划': SfGlyph.bookmark,
  '换浅色': SfGlyph.contrast,
  '换深色': SfGlyph.contrast,
  '你能做什么': SfGlyph.sparkle,
  '自己选条件': SfGlyph.sliders,
};

/// Quick replies above the input: quiet tonal pills.
class SuggestionStrip extends StatelessWidget {
  const SuggestionStrip({super.key, required this.items, required this.onTap});
  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox(height: SfSpace.x1);
    return SizedBox(
      height: SfComposerTokens.suggestionStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: SfComposerTokens.suggestionStripPadding,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: SfComposerTokens.suggestionGap),
        // M6: a new batch arrives chip by chip (40 ms apart), sliding 8 px
        // left as it fades in.
        itemBuilder: (_, i) => Appear(
          key: ValueKey('suggestion-in-${items.join('|')}-$i'),
          animate: true,
          delay: SfMotion.stagger * i,
          duration: SfMotion.medium,
          rise: 0,
          shift: 8,
          scaleFrom: 1,
          child: SfPressable(
            key: ValueKey('suggestion-$i'),
            semanticLabel: items[i],
            haptic: SfHaptic.selection,
            onTap: () => onTap(items[i]),
            child: Center(
              child: Container(
                height: SfComposerTokens.suggestionFaceHeight,
                padding: SfComposerTokens.suggestionPadding,
                decoration: BoxDecoration(
                  color: SfComposerTokens.suggestionFill,
                  borderRadius: BorderRadius.circular(
                    SfComposerTokens.suggestionRadius,
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    SfComposerTokens.suggestionRadius,
                  ),
                  border: Border.all(
                    color: SfComposerTokens.suggestionEdge,
                    width: SfComposerTokens.suggestionEdgeWidth,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chipGlyphs[items[i]] case final g?) ...[
                      SfIcon(
                        g,
                        size: SfComposerTokens.suggestionIconSize,
                        color: SfComposerTokens.suggestionIcon,
                      ),
                      const SizedBox(width: SfComposerTokens.suggestionIconGap),
                    ],
                    Text(
                      items[i],
                      style: TextStyle(
                        color: SfComposerTokens.suggestionInk,
                        fontSize: SfComposerTokens.suggestionTextSize,
                        height: SfComposerTokens.suggestionTextHeight,
                        fontWeight: SfComposerTokens.suggestionTextWeight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule at the bottom: plans · text · send. The send disc is the
/// accent only when there is something to send.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onPlans,
    this.enabled = true,
    this.focusNode,
    this.panelOpen = false,
    this.onTextTap,
  });

  /// Lets an explicit compose action put the cursor here.
  final FocusNode? focusNode;
  final void Function(String) onSend;
  final VoidCallback? onPlans;
  final bool enabled;
  final bool panelOpen;
  final VoidCallback? onTextTap;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _text = TextEditingController();
  final _ownFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownFocus;

  @override
  void dispose() {
    _text.dispose();
    _ownFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _text.text.trim();
    if (t.isEmpty || !widget.enabled) return;
    widget.onSend(t);
    _text.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ready = _text.text.trim().isNotEmpty && widget.enabled;
    return Padding(
      padding: SfComposerTokens.outerPadding,
      child: Container(
        key: const ValueKey('chat-composer-face'),
        decoration: BoxDecoration(
          gradient: SfComposerTokens.inputGradient,
          borderRadius: BorderRadius.circular(SfComposerTokens.inputRadius),
          boxShadow: SfComposerTokens.inputShadow,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SfComposerTokens.inputRadius),
          border: Border.all(
            color: SfComposerTokens.inputEdge,
            width: SfComposerTokens.edgeWidth,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SfComposerTokens.inputHeight,
            ),
            child: Padding(
              padding: SfComposerTokens.inputInnerPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.onPlans != null)
                    SizedBox(
                      width: SfComposerTokens.actionWidth,
                      height: SfComposerTokens.inputHeight,
                      child: SfPressable(
                        key: const ValueKey('chat-panel-toggle'),
                        tooltip: widget.panelOpen ? '收起面板' : '打开功能面板',
                        semanticLabel: widget.panelOpen ? '收起面板' : '打开功能面板',
                        onTap: widget.onPlans,
                        child: Center(
                          child: Icon(
                            widget.panelOpen
                                ? Icons.keyboard_outlined
                                : Icons.grid_view_rounded,
                            size: SfComposerTokens.bookmarkSize,
                            color: SfComposerTokens.bookmark,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: SfComposerTokens.inputInsetWithoutLeading,
                    ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: _text,
                      focusNode: _focus,
                      onTap: widget.onTextTap,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      style: TextStyle(
                        color: SfColors.text,
                        fontSize: SfComposerTokens.inputTextSize,
                        height: SfComposerTokens.inputTextHeight,
                      ),
                      decoration: InputDecoration(
                        // Keep the whole capsule's input area tappable,
                        // including the space above and below the text.
                        isDense: true,
                        contentPadding: SfComposerTokens.inputTextPadding,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '说说想怎么练…',
                        hintStyle: TextStyle(
                          color: SfComposerTokens.hint,
                          fontSize: SfComposerTokens.inputTextSize,
                          height: SfComposerTokens.inputTextHeight,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  SizedBox(
                    width: SfComposerTokens.actionWidth,
                    height: SfComposerTokens.inputHeight,
                    child: Tooltip(
                      message: '发送',
                      child: SfPressable(
                        key: const ValueKey('chat-send'),
                        semanticLabel: '发送',
                        onTap: ready ? _submit : null,
                        scale: SfComposerTokens.pressScale,
                        child: Center(
                          child: Container(
                            width: SfComposerTokens.sendSize,
                            height: SfComposerTokens.sendSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ready
                                  ? SfColors.accent
                                  : SfComposerTokens.inactiveSendFill,
                            ),
                            child: Center(
                              child: SfIcon(
                                SfGlyph.arrowUp,
                                size: SfComposerTokens.sendIconSize,
                                strokeWidth: SfComposerTokens.sendStrokeWidth,
                                color: ready
                                    ? SfColors.onAccent
                                    : SfComposerTokens.inactiveSendInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatPanelAction {
  const ChatPanelAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final Key key;
  final String label;
  final SfGlyph icon;
  final VoidCallback onTap;
}

/// A content-sized tools grid. Narrow screens and large text add rows instead
/// of keeping the old keyboard-sized empty space.
class ChatFeaturePanel extends StatelessWidget {
  const ChatFeaturePanel({super.key, required this.actions});

  final List<ChatPanelAction> actions;

  /// Fixed for a viewport/text configuration; never measures an animating
  /// panel. The existing grid remains scrollable at accessibility sizes.
  static double heightFor({
    required double width,
    required double viewportHeight,
    required TextScaler textScaler,
    required int actionCount,
  }) {
    final style = SfType.label;
    final scale = textScaler.scale(style.fontSize!) / style.fontSize!;
    final columns =
        ((width - SfFeaturePanelTokens.padding.horizontal) /
                (SfFeaturePanelTokens.minTileWidth * scale))
            .floor()
            .clamp(1, SfFeaturePanelTokens.maxColumns);
    final rows = (actionCount / columns).ceil();
    final labelHeight = textScaler.scale(style.fontSize!) * style.height!;
    final height =
        SfFeaturePanelTokens.padding.vertical +
        rows *
            (SfFeaturePanelTokens.tileSize +
                SfFeaturePanelTokens.labelGap +
                labelHeight) +
        (rows - 1).clamp(0, rows) * SfFeaturePanelTokens.rowGap;
    return height.clamp(
      0,
      viewportHeight * SfFeaturePanelTokens.maxHeightFraction,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final labelStyle = SfType.label;
    final labelSize = labelStyle.fontSize!;
    final textScale = media.textScaler.scale(labelSize) / labelSize;
    return ColoredBox(
      color: SfFeaturePanelTokens.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth =
              constraints.maxWidth - SfFeaturePanelTokens.padding.horizontal;
          final columns =
              (contentWidth / (SfFeaturePanelTokens.minTileWidth * textScale))
                  .floor()
                  .clamp(1, SfFeaturePanelTokens.maxColumns);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  media.size.height * SfFeaturePanelTokens.maxHeightFraction,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: SfFeaturePanelTokens.padding,
                child: Wrap(
                  runSpacing: SfFeaturePanelTokens.rowGap,
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: contentWidth / columns,
                        child: SfPressable(
                          key: action.key,
                          semanticLabel: action.label,
                          onTap: action.onTap,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: SfFeaturePanelTokens.tileSize,
                                height: SfFeaturePanelTokens.tileSize,
                                decoration: BoxDecoration(
                                  color: SfFeaturePanelTokens.tileFill,
                                  borderRadius: BorderRadius.circular(
                                    SfFeaturePanelTokens.tileRadius,
                                  ),
                                  border: Border.all(
                                    color: SfFeaturePanelTokens.tileEdge,
                                  ),
                                ),
                                child: Center(
                                  child: SfIcon(
                                    action.icon,
                                    size: SfFeaturePanelTokens.iconSize,
                                    color: SfColors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: SfFeaturePanelTokens.labelGap,
                              ),
                              Text(
                                action.label,
                                style: labelStyle,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
