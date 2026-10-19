import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cosmos.dart';

/// Frosted glass over the sky. Inside a [BackdropGroup] (the chat list
/// has one) every pane shares a single backdrop read, which keeps a long
/// conversation cheap to draw.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(22)),
    this.tint = CosmosColors.glass,
    this.edge = CosmosColors.edge,
    this.blur = 16,
    this.padding = EdgeInsets.zero,
    this.glow,
    this.colors,
  });

  final Widget child;
  final BorderRadius radius;
  final Color tint;
  final Color edge;
  final double blur;
  final EdgeInsetsGeometry padding;

  /// Optional soft outer light (the input capsule, plan cards).
  final Color? glow;

  /// A custom fill gradient (top-left → bottom-right) instead of [tint].
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors ?? [Color.alphaBlend(const Color(0x0AFFFFFF), tint), tint],
        ),
        border: Border.all(color: edge, width: .7),
      ),
      child: Padding(padding: padding, child: child),
    );
    final glass = ClipRRect(
      borderRadius: radius,
      child: blur <= 0
          ? decorated
          : BackdropGroup.of(context) != null
          ? BackdropFilter.grouped(filter: filter, child: decorated)
          : BackdropFilter(filter: filter, child: decorated),
    );
    if (glow == null) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: glow!, blurRadius: 30, spreadRadius: -12, offset: const Offset(0, 6))],
      ),
      child: glass,
    );
  }
}
