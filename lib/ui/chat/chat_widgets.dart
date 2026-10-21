import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// A new message arriving (docs/design-audit-2026-10-19.md M4): fade +
/// 10 px rise + 0.98 → 1 from the speaker's corner ([anchor]: bottom-left
/// for the assistant, bottom-right for the user), 360 ms. Messages of one
/// reply follow each other by [delay] (words first, then the card). Old
/// messages appear as they are; reduced motion keeps a 200 ms fade only.
///
/// The delay is part of the animation (an [Interval]), not a timer, so
/// nothing is left pending when the chat goes away.
class Appear extends StatefulWidget {
  const Appear({
    super.key,
    required this.animate,
    required this.child,
    this.delay = Duration.zero,
    this.anchor = Alignment.bottomLeft,
    this.rise = 10,
    this.shift = 0,
    this.duration = SfMotion.appear,
    this.scaleFrom = .98,
  });
  final bool animate;
  final Duration delay;
  final Widget child;
  final Alignment anchor;

  /// Pixels it rises (y) / slides left (x, the suggestion chips) as it lands.
  final double rise;
  final double shift;
  final Duration duration;
  final double scaleFrom;
  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Animation<double> _t = kAlwaysCompleteAnimation;
  bool _still = false;
  bool _begun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    _still = SfMotion.reduced(context);
    if (!widget.animate) {
      _c.value = 1;
      return;
    }
    final run = _still ? const Duration(milliseconds: 200) : widget.duration;
    final total = widget.delay + run;
    _c.duration = total;
    final start = widget.delay.inMicroseconds / total.inMicroseconds;
    _t = CurvedAnimation(
      parent: _c,
      curve: Interval(
        start,
        1,
        curve: _still ? Curves.easeOut : SfMotion.standard,
      ),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (_, child) {
      final v = _t.value;
      if (v >= 1) return child!;
      if (_still) return Opacity(opacity: v, child: child);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(widget.shift * (1 - v), widget.rise * (1 - v)),
          child: Transform.scale(
            scale: widget.scaleFrom + (1 - widget.scaleFrom) * v,
            alignment: widget.anchor,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Bubble shape: round corners, a small one on the speaker's side.
BorderRadius bubbleRadius({required bool user}) => BorderRadius.only(
  topLeft: const Radius.circular(SfRadius.lg),
  topRight: const Radius.circular(SfRadius.lg),
  bottomLeft: Radius.circular(user ? SfRadius.lg : SfRadius.tail),
  bottomRight: Radius.circular(user ? SfRadius.tail : SfRadius.lg),
);

/// A tonal bubble floating in the sky: the assistant on the surface tone
/// (white card on light), the user one step lighter and neutral; no glass,
/// no stroke. Colour is kept for what you can do, not for who spoke.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.user, required this.child, this.padding});
  final bool user;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final r = bubbleRadius(user: user);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: user ? SfColors.userBubble : SfColors.assistantBubble,
        borderRadius: r,
        // Light: white on near-white needs the hairline as well as the
        // faint ink shadow (§6.2); dark: the tone step carries it.
        border: user || SfColors.isDark
            ? null
            : Border.fromBorderSide(SfColors.cardEdge),
        boxShadow: user ? null : SfColors.cardShadow,
      ),
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.fromLTRB(SfSpace.x4, 10, SfSpace.x4, 11),
        child: child,
      ),
    );
  }
}

/// "1/4　问题" → ('1/4', '问题'); null for any other text.
(String, String)? _step(String text) {
  final m = RegExp(r'^(\d+/\d+)\u3000(.+)$', dotAll: true).firstMatch(text);
  return m == null ? null : ('安全确认 ${m.group(1)}', m.group(2)!);
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.optionsActive,
    required this.onOption,
  });

  final ChatMessage message;
  final bool optionsActive;
  final void Function(int index) onOption;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    final maxW = MediaQuery.sizeOf(context).width * (user ? .78 : .86);
    final bubble = _Bubble(
      user: user,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_step(message.text) case (final step, final rest)) ...[
            // 安全确认 1/4: the step as a caption over the question.
            Text(
              step,
              style: SfType.caption.copyWith(
                color: SfColors.muted,
                letterSpacing: .6,
                fontFeatures: SfType.tabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(rest, style: SfType.body),
          ] else if (message.text.isNotEmpty)
            Text(message.text, style: SfType.body),
          if (message.options.isNotEmpty) ...[
            const SizedBox(height: SfSpace.x3),
            Wrap(
              spacing: SfSpace.x2,
              runSpacing: SfSpace.x2,
              children: [
                for (var i = 0; i < message.options.length; i++)
                  OptionPill(
                    key: ValueKey('option-${message.id}-$i'),
                    label: message.options[i].label,
                    chosen: message.chosen == i,
                    dimmed: message.chosen != null && message.chosen != i,
                    enabled: optionsActive,
                    onTap: () => onOption(i),
                  ),
              ],
            ),
            const SizedBox(height: 3),
          ],
        ],
      ),
    );
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: bubble,
      ),
    );
  }
}

/// A choice inside an assistant bubble. Chosen: accent tint + accent text
/// (HipLab's selected segment); once answered the others go faint.
class OptionPill extends StatelessWidget {
  const OptionPill({
    super.key,
    required this.label,
    required this.onTap,
    this.chosen = false,
    this.dimmed = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool chosen;
  final bool dimmed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = chosen
        ? SfColors.accentText
        : dimmed
        ? SfColors.faint
        : SfColors.text;
    final bg = chosen
        ? SfColors.accentSoft
        : SfColors.isDark
        ? SfColors.surfaceHigh
        : SfColors.background;
    return SfPressable(
      semanticLabel: label,
      onTap: enabled ? onTap : null,
      haptic: SfHaptic.selection,
      child: AnimatedContainer(
        duration: SfMotion.medium,
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: ShapeDecoration(color: bg, shape: const StadiumBorder()),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            height: 1.35,
            fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// The opening line without a bubble (§2.1): 早上好 / 晚上好… in large type
/// floating in the sky, the invitation under it in muted body text. It is
/// still a message: later ones push it up.
class GreetingBlock extends StatelessWidget {
  const GreetingBlock({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final i = text.indexOf('\n');
    final head = i < 0 ? text : text.substring(0, i);
    final rest = i < 0 ? '' : text.substring(i + 1);
    return Padding(
      key: const ValueKey('greeting'),
      padding: const EdgeInsets.fromLTRB(
        SfSpace.x2,
        SfSpace.x6,
        SfSpace.x2,
        SfSpace.x1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head, style: SfType.greeting),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: SfSpace.x1),
            Text(rest, style: SfType.body.copyWith(color: SfColors.muted)),
          ],
        ],
      ),
    );
  }
}

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

/// "今天 13:40" between sittings.
class TimeMark extends StatelessWidget {
  const TimeMark(this.at, {super.key, required this.now});
  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final d = today.difference(day).inDays;
    final label = switch (d) {
      0 => '今天 $hm',
      1 => '昨天 $hm',
      _ => '${at.month}月${at.day}日 $hm',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SfSpace.x3),
      child: Center(
        child: Text(label, style: SfType.caption.copyWith(letterSpacing: .4)),
      ),
    );
  }
}

/// Three soft dots while the assistant "thinks".
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key, this.onCancel});
  final VoidCallback? onCancel;
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
      _c.value = .5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: _Bubble(
      user: false,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Opacity(
                    opacity: .3 + .7 * _pulse((_c.value - i * .18) % 1),
                    child: SizedBox.square(
                      dimension: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: SfColors.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.onCancel != null) ...[
            const SizedBox(height: SfSpace.x3),
            Text('正在准备回复…', style: SfType.body),
            const SizedBox(height: SfSpace.x1),
            Text('首轮生成计划可能需要 75–120 秒', style: SfType.caption),
            SfTextAction(
              key: const ValueKey('chat-cancel'),
              label: '取消',
              icon: SfGlyph.stop,
              onPressed: widget.onCancel,
            ),
          ],
        ],
      ),
    ),
  );

  static double _pulse(double t) => t < .5 ? t * 2 : (1 - t) * 2;
}

/// Quick replies above the input: quiet tonal pills.
class SuggestionStrip extends StatelessWidget {
  const SuggestionStrip({super.key, required this.items, required this.onTap});
  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox(height: SfSpace.x1);
    return SizedBox(
      height: 48,
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: SfColors.isDark ? SfColors.surface : SfColors.surface,
                shape: StadiumBorder(side: SfColors.cardEdge),
              ),
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
                      color: SfColors.muted,
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: SfColors.cardShadow,
        ),
        child: Material(
          color: SfColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: SfColors.cardEdge,
          ),
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
                          child: SfIcon(
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
                        child: AnimatedContainer(
                          duration: SfMotion.fast,
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: ready
                                ? SfColors.accent
                                : SfColors.surfaceHigh,
                          ),
                          // M9: the arrow grows into place as the disc
                          // turns accent; reduced motion: colour only.
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
