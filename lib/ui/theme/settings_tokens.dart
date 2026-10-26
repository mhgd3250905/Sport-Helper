import 'package:flutter/material.dart';

import 'tokens.dart';

enum SfSettingsTone { mint, violet, coral, blue, amber, red, gray }

/// Local settings roles sampled from the approved D2/D3 reference.
/// Other SmartFit pages keep the existing palette.
@immutable
class SfSettingsTokens {
  const SfSettingsTokens(this.palette);
  final SfPalette palette;
  bool get isDark => palette.isDark;
  Color get background => isDark ? palette.background : const Color(0xFFF2F4F5);
  Color get surface => isDark ? palette.surface : Colors.white;
  Color get track => isDark ? palette.surfaceHigh : const Color(0xFFE8EEF1);
  Color get line => isDark ? palette.line : const Color(0xFFE3E9EC);
  Color get text => isDark ? palette.text : const Color(0xFF17262C);
  Color get muted => isDark ? palette.muted : const Color(0xFF51616C);
  Color get faint => isDark ? palette.muted : const Color(0xFF8695A0);
  Color get chevron => isDark ? palette.faint : const Color(0xFFB4C0C7);
  Color get accent => isDark ? palette.accent : const Color(0xFF137B70);
  Color get switchOff => isDark ? palette.surfaceHigh : const Color(0xFFD3DCE0);
  Color get danger => isDark ? palette.danger : const Color(0xFFD43F3F);
  Color get swatchDark => const Color(0xFF0C1117);
  Color get swatchLight => Colors.white;
  Color get swatchBorder => isDark ? palette.line : const Color(0xFFCBD5DA);

  static const groupRadius = 22.0;
  static const iconSize = 34.0;
  static const iconRadius = 11.0;
  static const rowInset = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
  static const rowGap = 14.0;
  static const dividerInset = 64.0;
  static const appIconSize = 56.0;
  static const appIconRadius = 14.0;
  static const bodyHeight = 1.7;
  List<BoxShadow> get shadows => [
    BoxShadow(
      color: (isDark ? palette.shadow : const Color(0xFF17262C)).withValues(
        alpha: isDark ? .10 : .04,
      ),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: (isDark ? palette.shadow : const Color(0xFF17262C)).withValues(
        alpha: isDark ? .10 : .04,
      ),
      blurRadius: isDark ? 8 : 16,
      offset: const Offset(0, 6),
    ),
  ];

  Color ink(SfSettingsTone tone) => isDark
      ? switch (tone) {
          SfSettingsTone.mint || SfSettingsTone.violet => palette.accentText,
          SfSettingsTone.coral => palette.emphasisText,
          SfSettingsTone.blue => palette.accentText,
          SfSettingsTone.amber => palette.caution,
          SfSettingsTone.red => palette.danger,
          SfSettingsTone.gray => palette.muted,
        }
      : switch (tone) {
          SfSettingsTone.mint => const Color(0xFF137B70),
          SfSettingsTone.violet => const Color(0xFF6B4FD0),
          SfSettingsTone.coral => const Color(0xFFE8775E),
          SfSettingsTone.blue => const Color(0xFF3E7BC2),
          SfSettingsTone.amber => const Color(0xFFC98A12),
          SfSettingsTone.red => const Color(0xFFD43F3F),
          SfSettingsTone.gray => const Color(0xFF51616C),
        };

  Color iconSurface(SfSettingsTone tone) => isDark
      ? Color.alphaBlend(ink(tone).withValues(alpha: .12), surface)
      : switch (tone) {
          SfSettingsTone.mint => const Color(0xFFDCEFEA),
          SfSettingsTone.violet => const Color(0xFFEEE8FB),
          SfSettingsTone.coral => const Color(0xFFFDEDE8),
          SfSettingsTone.blue => const Color(0xFFE7F0FA),
          SfSettingsTone.amber => const Color(0xFFFFF4DE),
          SfSettingsTone.red => const Color(0xFFFCE9E9),
          SfSettingsTone.gray => const Color(0xFFEEF1F3),
        };

  static SfSettingsTokens of(BuildContext context) => SfSettingsTokens(
    Theme.of(context).brightness == Brightness.dark
        ? SfPalette.dark
        : SfPalette.light,
  );

  TextStyle get title => TextStyle(
    fontFamily: sfFontFamily,
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: text,
  );
  TextStyle get detail => TextStyle(
    fontFamily: sfFontFamily,
    fontSize: 12.5,
    height: 1.45,
    color: faint,
  );
  TextStyle get body => TextStyle(
    fontFamily: sfFontFamily,
    fontSize: 14.5,
    height: bodyHeight,
    color: muted,
  );
}
