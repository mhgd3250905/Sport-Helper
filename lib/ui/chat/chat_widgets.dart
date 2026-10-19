import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import 'cosmos.dart';
import 'glass.dart';

const _bodyStyle = TextStyle(
  color: CosmosColors.text,
  fontSize: 15.5,
  height: 1.6,
  letterSpacing: .2,
);

/// New messages drift up and fade in once; old ones (and everything under
/// reduced motion) appear as they are.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.animate, required this.child, this.delay = Duration.zero});
  final bool animate;
  final Duration delay;
  final Widget child;
  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

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
      child: Transform.translate(offset: Offset(0, 16 * (1 - _t.value)), child: child),
    ),
  );
}

/// A text bubble: the assistant on cool glass (left), the user on warm
/// glass (right). Options sit inside the assistant bubble.
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
    final maxW = MediaQuery.sizeOf(context).width * (user ? .78 : .84);
    final bubble = Glass(
      tint: user ? CosmosColors.accentGlass : CosmosColors.glass,
      colors: user ? CosmosColors.userFill : null,
      edge: user ? CosmosColors.accentEdge : CosmosColors.edge,
      radius: BorderRadius.only(
        topLeft: const Radius.circular(22),
        topRight: const Radius.circular(22),
        bottomLeft: Radius.circular(user ? 22 : 8),
        bottomRight: Radius.circular(user ? 8 : 22),
      ),
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: user ? _bodyStyle.copyWith(color: Colors.white) : _bodyStyle,
            ),
          if (message.options.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
        ? Colors.white
        : dimmed
        ? CosmosColors.faint
        : CosmosColors.text;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: chosen ? CosmosColors.accent.withValues(alpha: .85) : CosmosColors.glassHi,
              border: Border.all(
                color: chosen ? CosmosColors.accentEdge : CosmosColors.edge,
                width: .7,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500, height: 1.2),
            ),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(color: CosmosColors.faint, fontSize: 11.5, letterSpacing: .6),
        ),
      ),
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
    child: Glass(
      radius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        topRight: Radius.circular(22),
        bottomRight: Radius.circular(22),
        bottomLeft: Radius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Opacity(
                opacity: .35 + .65 * _pulse((_c.value - i * .18) % 1),
                child: const SizedBox.square(
                  dimension: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: CosmosColors.textSoft, shape: BoxShape.circle),
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

/// Quick replies above the input.
class SuggestionStrip extends StatelessWidget {
  const SuggestionStrip({super.key, required this.items, required this.onTap});
  final List<String> items;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('suggestion-$i'),
            borderRadius: BorderRadius.circular(17),
            onTap: () => onTap(items[i]),
            child: Glass(
              blur: 10,
              radius: BorderRadius.circular(17),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Text(
                items[i],
                style: const TextStyle(color: CosmosColors.textSoft, fontSize: 13.5, height: 1.25),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The capsule at the bottom: plans button · text · send.
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
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Glass(
        blur: 22,
        radius: BorderRadius.circular(28),
        tint: const Color(0x1AFFFFFF),
        glow: const Color(0x14FF7A45),
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.onPlans != null)
              IconButton(
                key: const ValueKey('open-plans'),
                tooltip: '我的计划',
                onPressed: widget.onPlans,
                icon: const Icon(Icons.bookmarks_outlined, size: 21, color: CosmosColors.muted),
              )
            else
              const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _text,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  cursorColor: CosmosColors.accent,
                  textInputAction: TextInputAction.send,
                  style: const TextStyle(color: CosmosColors.text, fontSize: 15.5, height: 1.4),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: '说说想怎么练…',
                    hintStyle: TextStyle(color: CosmosColors.faint, fontSize: 15.5, height: 1.4),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? CosmosColors.accent : CosmosColors.glassHi,
                  boxShadow: ready
                      ? const [BoxShadow(color: Color(0x66FF7A45), blurRadius: 16, spreadRadius: -2)]
                      : null,
                ),
                child: IconButton(
                  key: const ValueKey('chat-send'),
                  tooltip: '发送',
                  padding: EdgeInsets.zero,
                  onPressed: ready ? _submit : null,
                  icon: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: ready ? Colors.white : CosmosColors.faint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
