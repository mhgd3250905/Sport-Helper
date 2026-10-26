import 'package:flutter/material.dart';
import '../theme/sf_icons.dart';
import '../theme/solid_surface.dart';
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
    final dark = SfColors.isDark;
    return SizedBox(
      height: dark ? 52 : 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          SfSpace.x4,
          SfSpace.x1,
          SfSpace.x4,
          SfSpace.x2,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: SfSpace.x2),
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
            child: SfSolidSurface(
              level: SfSurfaceLevel.raised,
              radius: dark ? 20 : 18,
              height: dark ? 40 : 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              control: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chipGlyphs[items[i]] case final g?) ...[
                    SfIcon(g, size: 16, color: SfColors.accentText),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    items[i],
                    style: TextStyle(
                      color: SfColors.text.withValues(alpha: dark ? .95 : .78),
                      fontSize: 14,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
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

/// The capsule at the bottom: plans · text · send. The send disc is the
/// accent only when there is something to send.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onPlans,
    this.enabled = true,
    this.focusNode,
  });

  /// Lets the page put the cursor here (the drawer's 「去排一套」).
  final FocusNode? focusNode;
  final void Function(String) onSend;
  final VoidCallback? onPlans;
  final bool enabled;

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
      padding: const EdgeInsets.fromLTRB(SfSpace.x3, 0, SfSpace.x3, SfSpace.x3),
      child: SfSolidSurface(
        radius: 26,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(SfSpace.x1, 0, 7, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.onPlans != null)
                    SizedBox(
                      width: 44,
                      height: 52,
                      child: SfPressable(
                        key: const ValueKey('open-plans'),
                        tooltip: '我的计划',
                        semanticLabel: '我的计划',
                        onTap: widget.onPlans,
                        child: Center(
                          child: SfColors.isDark
                              ? SfSolidSurface(
                                  level: SfSurfaceLevel.raised,
                                  width: 40,
                                  height: 40,
                                  radius: 20,
                                  control: true,
                                  child: Center(
                                    child: SfIcon(
                                      SfGlyph.bookmark,
                                      size: 19,
                                      color: SfColors.text.withValues(
                                        alpha: .9,
                                      ),
                                    ),
                                  ),
                                )
                              : SfIcon(
                                  SfGlyph.bookmark,
                                  size: 21,
                                  color: SfColors.muted,
                                ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: SfSpace.x3),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat-input'),
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      style: TextStyle(
                        color: SfColors.text,
                        fontSize: 16,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        // Keep the whole capsule's input area tappable,
                        // including the space above and below the text.
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '说说想怎么练…',
                        hintStyle: TextStyle(
                          color: SfColors.faint,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 6),
                    child: Tooltip(
                      message: '发送',
                      child: SfPressable(
                        key: const ValueKey('chat-send'),
                        semanticLabel: '发送',
                        onTap: ready ? _submit : null,
                        scale: .9,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ready
                                ? SfColors.accent
                                : SfColors.surfaceHigh,
                          ),
                          // Keep the existing send affordance without
                          // animating the capsule's surface colour.
                          child: Center(
                            child: AnimatedScale(
                              scale: ready || SfMotion.reduced(context)
                                  ? 1
                                  : .84,
                              duration: SfMotion.fast,
                              curve: SfMotion.standard,
                              child: SfIcon(
                                SfGlyph.arrowUp,
                                size: 18,
                                strokeWidth: 2.2,
                                color: ready
                                    ? SfColors.onAccent
                                    : SfColors.faint,
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
