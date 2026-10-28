import 'package:flutter/material.dart';

import 'tokens.dart';

/// Approved first-batch UI values. Keep product-specific values in the theme.
abstract final class SfCardTokens {
  static const radius = 20.0;
  static const edgeWidth = 1.0;
  static const inset = 12.0;
  static const padding = EdgeInsets.all(inset);
  static const gridGap = 12.0;
  static const imageAspectRatio = 1.0;
  static const titleLines = 2;

  static Color get fill =>
      SfColors.isDark ? const Color(0xFF1A2324) : const Color(0xFFFFFFFF);
  static Color get edge => SfColors.isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: .08)
      : const Color(0xFFE3E8E6);
  static TextStyle get title => SfType.callout.copyWith(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
  static TextStyle get metadata =>
      SfType.caption.copyWith(fontSize: 12, color: SfColors.muted);
}

abstract final class SfGenerationTokens {
  static const padding = EdgeInsets.all(16);
  static const animationSize = 56.0;
  static const arcWidth = 2.0;
  static const arcSweep = 90.0;
  static const dotSize = 6.0;
  static const dotDelay = Duration(milliseconds: 120);
  static const rotation = Duration(milliseconds: 1200);
  static const imageHold = Duration(milliseconds: 900);
  static const imageTransition = Duration(milliseconds: 250);
  static const statusTransition = Duration(milliseconds: 220);
  static const statusOffset = 8.0;
  static const shimmer = Duration(milliseconds: 1600);
  static const progressTransition = Duration(milliseconds: 400);
  static const progressHeight = 3.0;
  static const progressRadius = 2.0;
  static const progressGap = 4.0;
  static const progressSegments = 4;
  static const dotCount = 3;
  static const dotGap = SfSpace.x1;
  static const dotLift = SfSpace.x1;
  static const thumbnailInset = SfSpace.x2;
  static const chipHeight = 26.0;
  static const chipPadding = EdgeInsets.symmetric(horizontal: 10);
  static const chipRadius = 13.0;
  static const chipTransition = Duration(milliseconds: 200);
  static const chipDelay = Duration(milliseconds: 60);
  static const chipInitialScale = .9;
  static const cancelTouchSize = 44.0;
  static const completionTransition = Duration(milliseconds: 300);
  static const maxWidth = 400.0;

  static TextStyle get title =>
      SfType.callout.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle get status =>
      SfType.body.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
  static TextStyle get cancel =>
      SfType.label.copyWith(fontSize: 13, color: SfColors.muted);
  static TextStyle chipText(bool user) => SfType.caption.copyWith(
    fontSize: 12,
    color: user ? SfColors.accent : SfColors.muted,
  );
  static Color chipFill(bool user) =>
      user ? SfColors.accent.withValues(alpha: .12) : Colors.transparent;
  static Color get highlight => Color.alphaBlend(
    SfPalette.light.surface.withValues(alpha: .12),
    SfColors.text,
  );
  static const shimmerStops = [0.0, .5, 1.0];
}

abstract final class SfPlanPolishTokens {
  static const toggleHeight = 32.0;
  static const togglePadding = EdgeInsets.symmetric(horizontal: 12);
  static const toggleRadius = 16.0;
  static const toggleInset = 12.0;
  static const expansion = Duration(milliseconds: 280);
  static const detailActionGap = 24.0;
  static TextStyle get toggle => SfType.label.copyWith(fontSize: 13);
  static TextStyle get details =>
      SfType.callout.copyWith(fontSize: 14, color: SfColors.accent);
}

abstract final class SfDockPolishTokens {
  static const fadeAboveInput = 72.0;
  static Color get background => SfFeaturePanelTokens.background;
  static LinearGradient get gradient => SfComposerTokens.dockGradient;
}
