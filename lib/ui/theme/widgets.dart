import 'package:flutter/material.dart';

import 'sf_icons.dart';
import 'tokens.dart';

/// Button pyramid (docs/design-language.md §4, after HipLab R3–R5):
///
/// * [SfPrimaryButton] — the one most likely action of a view: flat
///   accent fill, no gradient / shadow / glow. One per view (two at most).
/// * [SfSecondaryButton] — an alternative: tonal (dark) or white with a
///   hairline (light).
/// * [SfTextAction] — tertiary, in cards and footers: icon + text, no
///   container.
/// * [SfCircleButton] — tools (close, skip, previous): a tonal disc.
///
/// All share [SfPressable]: scale 0.97 + a slightly deeper fill, 100 ms
/// down / 180 ms up; no ink ripple (the card → player container transform
/// starts from the card's face, which a ripple would repaint mid-frame).

/// Whether the nearest [SfPressable] is held down.
class SfPressedScope extends InheritedWidget {
  const SfPressedScope({super.key, required this.pressed, required super.child});
  final bool pressed;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SfPressedScope>()?.pressed ?? false;
  @override
  bool updateShouldNotify(SfPressedScope old) => old.pressed != pressed;
}

class SfPressable extends StatefulWidget {
  const SfPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
    this.tooltip,
    this.scale = SfMotion.pressScale,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? tooltip;
  final double scale;

  @override
  State<SfPressable> createState() => _SfPressableState();
}

class _SfPressableState extends State<SfPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Widget child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down && !still ? widget.scale : 1,
        duration: _down ? SfMotion.press : SfMotion.release,
        curve: _down ? Curves.easeOut : Curves.easeOutCubic,
        child: SfPressedScope(pressed: _down, child: widget.child),
      ),
    );
    child = Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: child,
    );
    if (widget.tooltip != null) child = Tooltip(message: widget.tooltip!, child: child);
    return child;
  }
}

/// A stadium face whose fill deepens while pressed.
class _Face extends StatelessWidget {
  const _Face({required this.color, required this.pressedColor, required this.child, this.border});
  final Color color;
  final Color pressedColor;
  final BorderSide? border;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final down = SfPressedScope.of(context);
    return AnimatedContainer(
      duration: down ? SfMotion.press : SfMotion.release,
      curve: Curves.easeOut,
      decoration: ShapeDecoration(
        color: down ? pressedColor : color,
        shape: StadiumBorder(side: border ?? BorderSide.none),
      ),
      child: child,
    );
  }
}

class SfPrimaryButton extends StatelessWidget {
  const SfPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final SfGlyph? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final fill = on ? SfColors.accent : SfColors.surfaceHigh;
    final fg = on ? SfColors.onAccent : SfColors.faint;
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: SfPressable(
        semanticLabel: label,
        onTap: onPressed,
        child: _Face(
          color: fill,
          pressedColor: Color.lerp(fill, Colors.black, .10)!,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SfSpace.x5),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  SfIcon(icon!, size: 20, filled: true, color: fg),
                  const SizedBox(width: SfSpace.x2),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: height >= 52 ? 17 : 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SfSecondaryButton extends StatelessWidget {
  const SfSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 52,
    this.expand = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final SfGlyph? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final fill = SfColors.isDark ? SfColors.surfaceHigh : SfColors.surface;
    final fg = onPressed == null ? SfColors.faint : SfColors.text;
    return SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: SfPressable(
        semanticLabel: label,
        onTap: onPressed,
        child: _Face(
          color: fill,
          pressedColor: SfColors.isDark
              ? Color.lerp(fill, Colors.white, .05)!
              : SfColors.surfaceHigh,
          border: SfColors.isDark ? null : BorderSide(color: SfColors.line),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SfSpace.x5),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  SfIcon(icon!, size: 20, color: fg),
                  const SizedBox(width: SfSpace.x2),
                ],
                Text(
                  label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.2, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tertiary action: icon + text, no container; 44 pt tall hit area.
class SfTextAction extends StatelessWidget {
  const SfTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconFilled = false,
    this.color,
  });
  final String label;
  final VoidCallback? onPressed;
  final SfGlyph? icon;
  final bool iconFilled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = onPressed == null ? SfColors.faint : (color ?? SfColors.muted);
    return SfPressable(
      semanticLabel: label,
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                SfIcon(icon!, size: 18, filled: iconFilled, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round tool button: a flat tonal disc (hairline on light), no shadow.
class SfCircleButton extends StatelessWidget {
  const SfCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.tooltip,
    this.fill,
    this.iconColor,
    this.filled = true,
  });
  final SfGlyph icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;
  final Color? fill;
  final Color? iconColor;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bg = fill ?? SfColors.surfaceHigh;
    return SfPressable(
      semanticLabel: tooltip,
      tooltip: tooltip,
      onTap: onPressed,
      scale: .92,
      child: Builder(
        builder: (context) {
          final down = SfPressedScope.of(context);
          return AnimatedContainer(
            duration: down ? SfMotion.press : SfMotion.release,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: down ? Color.lerp(bg, SfColors.isDark ? Colors.white : Colors.black, .06) : bg,
              shape: BoxShape.circle,
              border: SfColors.isDark || fill != null ? null : Border.all(color: SfColors.line),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: SfMotion.fast,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: Tween(begin: .7, end: 1.0).animate(a), child: child),
              ),
              child: SfIcon(
                icon,
                key: ValueKey(icon),
                size: size * (size > 50 ? .42 : .45),
                color: onPressed == null ? SfColors.faint : (iconColor ?? SfColors.text),
                filled: filled,
                strokeWidth: size > 50 ? 1.75 : 2,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Level-1 surface: a card. Tone on dark; white + hairline + soft ink
/// shadow on light.
class SfPanel extends StatelessWidget {
  const SfPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SfSpace.x4),
    this.radius = SfRadius.lg,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: SfColors.cardShadow,
    ),
    child: Material(
      color: color ?? SfColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: SfColors.cardEdge,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// A small label floating on media (已暂停, 换左侧, 不舒服): dark scrim pill.
class SfMediaTag extends StatelessWidget {
  const SfMediaTag({super.key, required this.label, this.icon, this.color});
  final String label;
  final SfGlyph? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: SfColors.scrim, shape: const StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SfIcon(icon!, size: 15, filled: true, color: color ?? Colors.white),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w500, color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

/// A choice row inside a sheet: tonal tile, icon + label.
class SfSheetOption extends StatelessWidget {
  const SfSheetOption({super.key, required this.icon, required this.label, required this.onTap, this.color});
  final SfGlyph icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SfSpace.x2),
    child: SfPressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: SfSpace.x4),
        decoration: BoxDecoration(
          color: SfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(SfRadius.md),
        ),
        child: Row(
          children: [
            SfIcon(icon, size: 20, color: color ?? SfColors.muted, filled: true),
            const SizedBox(width: SfSpace.x3),
            Expanded(
              child: Text(label, style: SfType.callout.copyWith(color: color ?? SfColors.text)),
            ),
            SfIcon(SfGlyph.chevronRight, size: 16, color: SfColors.faint),
          ],
        ),
      ),
    ),
  );
}

/// A section title on plain pages.
class SfSectionTitle extends StatelessWidget {
  const SfSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SfSpace.x1, SfSpace.x6, SfSpace.x1, SfSpace.x2),
    child: Row(
      children: [
        Expanded(child: Text(text, style: SfType.label.copyWith(fontWeight: FontWeight.w600))),
        ?trailing,
      ],
    ),
  );
}
