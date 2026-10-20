import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// New messages rise 12 px and fade in once; old ones (and everything
/// under reduced motion) appear as they are.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.animate, required this.child, this.delay = Duration.zero});
  final bool animate;
  final Duration delay;
  final Widget child;
  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: SfMotion.appear);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: SfMotion.standard);

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    } else {
      _c.value = 1;
    }
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
    builder: (_, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(offset: Offset(0, 12 * (1 - _t.value)), child: child),
    ),
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
        boxShadow: user ? null : SfColors.cardShadow,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(SfSpace.x4, 10, SfSpace.x4, 11),
        child: child,
      ),
    );
  }
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
          if (message.text.isNotEmpty) Text(message.text, style: SfType.body),
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
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: bubble),
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

/// "今天 13:40" between sittings.
class TimeMark extends StatelessWidget {
  const TimeMark(this.at, {super.key, required this.now});
  final DateTime at;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final d = today.difference(day).inDays;
    final label = switch (d) {
      0 => '今天 $hm',
      1 => '昨天 $hm',
      _ => '${at.month}月${at.day}日 $hm',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SfSpace.x3),
      child: Center(child: Text(label, style: SfType.caption.copyWith(letterSpacing: .4))),
    );
  }
}

/// Three soft dots while the assistant "thinks".
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});
  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> with SingleTickerProviderStateMixin {
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
      child: AnimatedBuilder(
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
                    decoration: BoxDecoration(color: SfColors.muted, shape: BoxShape.circle),
                  ),
                ),
              ),
            ],
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x1, SfSpace.x4, SfSpace.x2),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: SfSpace.x2),
        itemBuilder: (_, i) => SfPressable(
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
            child: Text(
              items[i],
              style: TextStyle(color: SfColors.muted, fontSize: 14, height: 1.2, fontWeight: FontWeight.w500),
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
  });

  final void Function(String) onSend;
  final VoidCallback? onPlans;
  final bool enabled;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
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
                        child: Center(child: SfIcon(SfGlyph.bookmark, size: 21, color: SfColors.muted)),
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
                      style: TextStyle(color: SfColors.text, fontSize: 16, height: 1.5),
                      decoration: InputDecoration(
                        // Keep the whole capsule's input area tappable,
                        // including the space above and below the text.
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: '说说想怎么练…',
                        hintStyle: TextStyle(color: SfColors.faint, fontSize: 16, height: 1.5),
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
                            color: ready ? SfColors.accent : SfColors.surfaceHigh,
                          ),
                          child: Center(
                            child: SfIcon(
                              SfGlyph.arrowUp,
                              size: 18,
                              strokeWidth: 2.2,
                              color: ready ? SfColors.onAccent : SfColors.faint,
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
