import 'package:flutter/material.dart';

import 'tokens.dart';

enum SfSurfaceLevel { base, card, raised }

/// An opaque painted surface; the layout and interaction remain child-owned.
class SfSolidSurface extends StatelessWidget {
  const SfSolidSurface({
    super.key,
    required this.child,
    this.level = SfSurfaceLevel.card,
    this.radius,
    this.padding,
    this.width,
    this.height,
    this.control = false,
  });

  final Widget child;
  final SfSurfaceLevel level;
  final double? radius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool control;

  @override
  Widget build(BuildContext context) {
    final fill = switch (level) {
      SfSurfaceLevel.base => SfColors.surfaceLow,
      SfSurfaceLevel.card => SfColors.surface,
      SfSurfaceLevel.raised => SfColors.surfaceHigh,
    };
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius ?? 999),
        boxShadow: level == SfSurfaceLevel.card && !control
            ? SfColors.cardShadow
            : null,
      ),
      // Paint the edge without introducing implicit padding or moving hitboxes.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? 999),
        border: Border.all(color: SfColors.line),
      ),
      child: child,
    );
  }
}

void showSfSolidToast(
  BuildContext context,
  String text, {
  required Widget icon,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: SfColors.surfaceHigh,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 112),
      content: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: SfType.callout)),
        ],
      ),
    ),
  );
}
