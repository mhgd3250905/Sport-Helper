import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show TrainerTheme;

import 'tokens.dart';

/// The SDK owns training and action-card surfaces. Map only the brand accent
/// and bundled font, keeping its card, text and primary-foreground defaults.
abstract final class SmartFitTrainerTheme {
  static const playerV1Enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_TRAINER_PLAYER_V1');

  static TrainerTheme of(BuildContext context) => fromPalette(
    Theme.of(context).brightness == Brightness.light
        ? SfPalette.light
        : SfPalette.dark,
  );

  static TrainerTheme playerOf(BuildContext context) {
    if (!playerV1Enabled) return of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return (dark ? TrainerTheme.playerV1Dark : TrainerTheme.playerV1).copyWith(
      fontFamily: sfFontFamily,
    );
  }

  static TrainerTheme fromPalette(SfPalette p) =>
      (p.isDark ? TrainerTheme.dark : TrainerTheme.light).copyWith(
        accent: p.accent,
        accentSubtle: p.accentSoft,
        accentText: p.accentText,
        onAccent: p.onAccent,
        pausedColor: p.accent,
        onPaused: p.onAccent,
        fontFamily: sfFontFamily,
      );
}
