import 'package:flutter/material.dart';

import 'glass.dart';
import 'sf_icons.dart';
import 'tokens.dart';
import 'widgets.dart';

/// Shared page furniture (docs/design-audit-2026-10-19.md §2): one top bar,
/// one choice chip, one switch row, one list row, one segmented control,
/// one empty state and one toast for every plain page, so no page falls
/// back to Material's own app bar, chips, list tiles or snack bars.

/// The top bar of a plain page: a tonal back disc (our chevron), the
/// title, an optional caption and trailing action. Replaces [AppBar].
class SfTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SfTopBar({super.key, required this.title, this.caption, this.trailing, this.onBack});
  final String title;
  final String? caption;
  final Widget? trailing;

  /// Defaults to popping the route.
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final canPop = onBack != null || (ModalRoute.of(context)?.canPop ?? false);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x3, 0, SfSpace.x4, 0),
          child: Row(
            children: [
              if (canPop) ...[
                SfCircleButton(
                  key: const ValueKey('back'),
                  icon: SfGlyph.back,
                  size: 40,
                  tooltip: '返回',
                  fill: Colors.transparent,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: SfSpace.x1),
              ] else
                const SizedBox(width: SfSpace.x2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SfType.title.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (caption != null)
                      Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.caption.copyWith(color: SfColors.muted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A tonal choice pill. Selected: accent tint + accent text, w600 (the
/// selected-segment idea from HipLab), a selection tick on tap.
class SfChoiceChip extends StatelessWidget {
  const SfChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dense = false,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final SfGlyph? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null
        ? SfColors.faint
        : selected
        ? SfColors.accentText
        : SfColors.text;
    final bg = selected
        ? SfColors.accentSoft
        : SfColors.isDark
        ? SfColors.surfaceHigh
        : SfColors.surface;
    return SfPressable(
      semanticLabel: label,
      selected: selected,
      onTap: onTap,
      haptic: SfHaptic.selection,
      child: AnimatedContainer(
        duration: SfMotion.medium,
        curve: SfMotion.standard,
        constraints: BoxConstraints(minHeight: dense ? 34 : 38),
        padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14),
        decoration: ShapeDecoration(
          color: bg,
          shape: StadiumBorder(
            side: SfColors.isDark || selected ? BorderSide.none : BorderSide(color: SfColors.line),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              SfIcon(icon!, size: 16, color: selected ? SfColors.accentText : SfColors.muted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                height: 1.2,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A settings row with a switch: the whole row toggles; title callout,
/// explanation label.
class SfSwitchRow extends StatelessWidget {
  const SfSwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SfPressable(
    semanticLabel: title,
    semanticHint: subtitle,
    toggled: value,
    onTap: () => onChanged(!value),
    haptic: SfHaptic.selection,
    scale: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1, vertical: SfSpace.x2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: SfType.callout),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: SfType.label.copyWith(fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: SfSpace.x3),
            ExcludeSemantics(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A tappable list row: optional leading glyph, title, optional detail,
/// chevron.
class SfListRow extends StatelessWidget {
  const SfListRow({super.key, required this.title, this.detail, this.icon, required this.onTap, this.color});
  final String title;
  final String? detail;
  final SfGlyph? icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => SfPressable(
    semanticLabel: title,
    onTap: onTap,
    scale: .99,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1, vertical: SfSpace.x2),
        child: Row(
          children: [
            if (icon != null) ...[
              SfIcon(icon!, size: 20, color: color ?? SfColors.muted),
              const SizedBox(width: SfSpace.x3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: SfType.callout.copyWith(color: color)),
                  if (detail != null) Text(detail!, style: SfType.label.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            SfIcon(SfGlyph.chevronRight, size: 16, color: SfColors.faint, strokeWidth: 2),
          ],
        ),
      ),
    ),
  );
}

/// A segmented choice whose thumb really slides along the track (HipLab
/// R1: the one neutral raised part of the app), with a soft spring and a
/// selection tick. Reduced motion: the thumb jumps.
class SfSegmented<T> extends StatelessWidget {
  const SfSegmented({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.height = 44,
    this.keyPrefix,
  });
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  /// Each segment gets `ValueKey('$keyPrefix$value')`.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final index = items.indexWhere((e) => e.$1 == value).clamp(0, items.length - 1);
    final still = SfMotion.reduced(context);
    const pad = 3.0;
    final r = (height - pad * 2) / 2;
    return Container(
      height: height,
      padding: const EdgeInsets.all(pad),
      decoration: ShapeDecoration(
        color: SfColors.isDark ? SfColors.background : SfColors.surfaceHigh,
        shape: const StadiumBorder(),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: still ? Duration.zero : SfMotion.segment,
                curve: SfMotion.spring,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: SfTactile(
                  key: const ValueKey('segment-thumb'),
                  style: SfTactileStyle.neutral(),
                  pressed: false,
                  radius: r,
                ),
              ),
              Row(
                children: [
                  for (final (v, label) in items)
                    Expanded(
                      child: SfPressable(
                        key: keyPrefix == null ? null : ValueKey('$keyPrefix$v'),
                        semanticLabel: label,
                        onTap: v == value ? () {} : () => onChanged(v),
                        haptic: v == value ? SfHaptic.none : SfHaptic.selection,
                        scale: 1,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: SfMotion.medium,
                            style: TextStyle(
                              fontFamily: sfFontFamily,
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: v == value ? FontWeight.w600 : FontWeight.w400,
                              color: v == value ? SfColors.text : SfColors.muted,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Empty / nothing-yet state: a tonal disc with a glyph, a title, a line of
/// explanation and an optional tertiary action.
class SfEmptyState extends StatelessWidget {
  const SfEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });
  final SfGlyph icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: SfSpace.x6, vertical: SfSpace.x8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SfColors.isDark ? SfColors.surfaceHigh : SfColors.surface,
            border: SfColors.isDark ? null : Border.all(color: SfColors.line),
          ),
          alignment: Alignment.center,
          child: SfIcon(icon, size: 28, color: SfColors.muted),
        ),
        const SizedBox(height: SfSpace.x4),
        Text(title, textAlign: TextAlign.center, style: SfType.headline),
        if (body != null) ...[
          const SizedBox(height: SfSpace.x2),
          Text(body!, textAlign: TextAlign.center, style: SfType.label.copyWith(height: 1.6)),
        ],
        if (action != null && onAction != null) ...[
          const SizedBox(height: SfSpace.x3),
          SfTextAction(label: action!, onPressed: onAction, color: SfColors.accentText),
        ],
      ],
    ),
  );
}

/// The one toast: a liquid-glass capsule with the accent check, floating
/// above the input (M18: in with an 8 px rise, out fast; reduced motion:
/// the fade only). Replaces default snack bars.
void showSfToast(BuildContext context, String text, {SfGlyph icon = SfGlyph.checkCircle, double bottom = 96}) {
  showSfGlassToast(context, text, bottom: bottom, icon: SfIcon(icon, size: 18, color: SfColors.accentText, filled: true));
}

/// Pass-through for children that cross-fade on change (names, labels,
/// subtitles): fade + a small rise, on [SfMotion] timing; reduced motion
/// keeps only the fade.
class SfFadeSwitcher extends StatelessWidget {
  const SfFadeSwitcher({
    super.key,
    required this.child,
    this.duration = SfMotion.medium,
    this.rise = 6,
    this.alignment = Alignment.centerLeft,
  });
  final Widget child;
  final Duration duration;
  final double rise;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final still = SfMotion.reduced(context);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: SfMotion.standard,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, a) {
        final fade = FadeTransition(opacity: a, child: child);
        if (still || rise == 0) return fade;
        return AnimatedBuilder(
          animation: a,
          child: fade,
          builder: (_, c) => Transform.translate(offset: Offset(0, rise * (1 - a.value)), child: c),
        );
      },
      child: child,
    );
  }
}
