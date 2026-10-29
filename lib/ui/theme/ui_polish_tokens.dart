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
  static const cardPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);
  static const padding = cardPadding;
  static const cardRadius = 20.0;
  static const cardEdgeWidth = .5;
  static const glowRadius = 160.0;
  static const animationSize = 44.0;
  static const animationGap = 12.0;
  static const arcStroke = 1.5;
  static const arcWidth = arcStroke;
  static const arcSweep = 300.0;
  static const arcHeadSize = 1.5;
  static const rotation = Duration(milliseconds: 1400);
  static const coreSize = 10.0;
  static const haloSize = 20.0;
  static const breath = Duration(milliseconds: 1200);
  static const breathInitialScale = .8;
  static const breathInitialOpacity = .6;
  static const coreCollapse = Duration(milliseconds: 180);
  static const silhouetteHold = Duration(milliseconds: 900);
  static const silhouetteFade = Duration(milliseconds: 250);
  static const imageHold = silhouetteHold;
  static const imageTransition = silhouetteFade;
  static const imageInitialScale = .94;
  static const statusExit = Duration(milliseconds: 160);
  static const statusDelay = Duration(milliseconds: 60);
  static const statusTransition = Duration(milliseconds: 220);
  static const statusOffset = 6.0;
  static const statusGap = 3.0;
  static const shimmer = Duration(milliseconds: 1600);
  static const progressTransition = Duration(milliseconds: 400);
  static const progressBand = Duration(milliseconds: 1200);
  static const progressBandFraction = .4;
  static const progressTopGap = 14.0;
  static const progressHeight = 3.0;
  static const progressRadius = 1.5;
  static const progressGap = 4.0;
  static const progressSegments = 4;
  static const thumbnailInset = 6.0;
  static const chipsTopGap = 12.0;
  static const chipGap = 6.0;
  static const chipHeight = 24.0;
  static const chipPadding = EdgeInsets.symmetric(horizontal: 9);
  static const chipRadius = 12.0;
  static const chipTransition = Duration(milliseconds: 200);
  static const chipDelay = Duration(milliseconds: 60);
  static const chipInitialScale = .9;
  static const cancelTouchSize = 44.0;
  static const completionVisual = Duration(milliseconds: 240);
  static const completionHold = Duration(milliseconds: 350);
  static const completionTransition = Duration(milliseconds: 300);
  static const completionFade = Duration(milliseconds: 200);
  static const completionDetail = Duration(milliseconds: 120);
  static const checkSize = 20.0;
  static const checkInitialScale = .6;
  static const maxWidth = 400.0;

  static Color get cardEdge => (SfColors.isDark ? Colors.white : Colors.black)
      .withValues(alpha: SfColors.isDark ? .08 : .06);
  static List<BoxShadow> get cardShadow => SfColors.isDark
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            offset: const Offset(0, 6),
            blurRadius: 20,
          ),
        ];
  static Color get glow =>
      SfColors.accent.withValues(alpha: SfColors.isDark ? .10 : .06);
  static Color get orbFill =>
      SfColors.accent.withValues(alpha: SfColors.isDark ? .14 : .08);
  static Color get progressTrack =>
      (SfColors.isDark ? Colors.white : Colors.black).withValues(
        alpha: SfColors.isDark ? .10 : .08,
      );
  static Color get chipEdge => (SfColors.isDark ? Colors.white : Colors.black)
      .withValues(alpha: SfColors.isDark ? .12 : .10);
  static TextStyle get title => SfType.callout.copyWith(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: SfColors.text,
  );
  static TextStyle get status => SfType.body.copyWith(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w500,
    color: SfColors.muted,
  );
  static TextStyle get cancel => SfType.label.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: SfColors.muted,
  );
  static TextStyle chipText(bool user) => SfType.caption.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: user ? SfColors.accent : SfColors.muted,
  );
  static Color chipFill(bool user) => user
      ? SfColors.accent.withValues(alpha: SfColors.isDark ? .18 : .10)
      : Colors.transparent;
  static Color get highlight => SfColors.text;
  static const shimmerStops = [0.0, .35, .5, .65, 1.0];
}

abstract final class SfPlanPolishTokens {
  static const toggleHeight = 32.0;
  static const togglePadding = EdgeInsets.symmetric(horizontal: 12);
  static const toggleRadius = 16.0;
  static const toggleInset = 12.0;
  static const expansion = SfMotion.medium;
  static const rowFade = SfMotion.fast;
  static const revealScroll = Duration(milliseconds: 240);
  static const detailActionGap = 24.0;
  static TextStyle get toggle => SfType.label.copyWith(fontSize: 13);
  static TextStyle get details =>
      SfType.callout.copyWith(fontSize: 14, color: SfColors.accent);
}

/// Approved second-batch saved-plan values. Do not retune these independently.
abstract final class SfSavedPlanTokens {
  static const pageInset = 20.0;
  static const gap = 12.0;
  static const inset = 16.0;
  static const thumbnail = 76.0;
  static const thumbnailRadius = 14.0;
  static const thumbnailInset = 6.0;
  static const textGap = 14.0;
  static const playSize = 44.0;
  static const playIcon = 20.0;
  static const menuWidth = 208.0;
  static const menuHeight = 165.0;
  static const menuGap = 8.0;
  static const menuRadius = 16.0;
  static const menuItemHeight = 48.0;
  static const press = Duration(milliseconds: 120);
  static const rebound = Duration(milliseconds: 160);
  static const menuEnter = Duration(milliseconds: 180);
  static const menuExit = Duration(milliseconds: 120);
  static const maskEnter = Duration(milliseconds: 160);
  static const removal = Duration(milliseconds: 240);
  static Color get insetFill =>
      SfColors.isDark ? const Color(0xFF223031) : const Color(0xFFF1F4F3);
  static Color get secondary => SfColors.isDark
      ? Colors.white.withValues(alpha: .64)
      : const Color(0xFF5F6B68);
  static Color get tertiary => SfColors.isDark
      ? Colors.white.withValues(alpha: .42)
      : const Color(0xFF8A9592);
  static Color get destructive =>
      SfColors.isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD64545);
}

abstract final class SfDockPolishTokens {
  static const fadeAboveInput = 72.0;
  static const menuDuration = Duration(milliseconds: 240);
  static const menuRise = SfSpace.x2;
  static Color get background => SfFeaturePanelTokens.background;
  static LinearGradient get gradient => SfComposerTokens.dockGradient;
}
