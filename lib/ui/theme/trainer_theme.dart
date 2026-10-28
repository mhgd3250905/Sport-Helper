import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show TrainerTheme;

import 'tokens.dart';

/// The same SmartFit palette for the shared player, action browser and media.
abstract final class SmartFitTrainerTheme {
  static TrainerTheme of(BuildContext context) => fromPalette(
    Theme.of(context).brightness == Brightness.light
        ? SfPalette.light
        : SfPalette.dark,
  );

  static TrainerTheme fromPalette(SfPalette p) => TrainerTheme(
    brightness: p.brightness,
    background: p.background,
    surface: p.surface,
    surfaceHigh: p.surfaceHigh,
    border: p.line,
    shadow: p.shadow,
    track: Color.alphaBlend(p.track, p.surfaceHigh),
    ringKnob: p.isDark ? p.text : p.surface,
    accent: p.accent,
    accentSubtle: p.accentSoft,
    accentText: p.accentText,
    onAccent: p.onAccent,
    pausedColor: p.accent,
    onPaused: p.onAccent,
    text: p.text,
    muted: p.muted,
    faint: p.faint,
    caution: p.caution,
    danger: p.danger,
    mediaStage: p.mediaStage,
    fontFamily: sfFontFamily,
    radius: SfRadius.lg,
  );
}
