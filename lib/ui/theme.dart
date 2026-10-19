import 'package:flutter/material.dart';

/// UGK family look (graphite + one accent, like HipLab's jade): SmartFit
/// uses a warm coral so it reads as "training" next to HipLab.
class SfColors {
  static const bg = Color(0xFF101013); // same as the clips' background
  static const surface = Color(0xFF1A1A20);
  static const surface2 = Color(0xFF24242C);
  static const line = Color(0xFF2E2E38);
  static const text = Color(0xFFF2F2F5);
  static const muted = Color(0xFF9A9AA6);
  static const accent = Color(0xFFFF7A45);
  static const accentSoft = Color(0x33FF7A45);
  static const rest = Color(0xFF4FC3F7);
  static const ok = Color(0xFF3CCFA4);
  static const warn = Color(0xFFFFC857);
}

ThemeData buildTheme({String? fontFamily}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: SfColors.accent,
    brightness: Brightness.dark,
    surface: SfColors.surface,
  ).copyWith(primary: SfColors.accent, onPrimary: Colors.white);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: SfColors.bg,
    brightness: Brightness.dark,
    fontFamily: fontFamily,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: SfColors.bg,
      foregroundColor: SfColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: SfColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: SfColors.surface2,
      selectedColor: SfColors.accentSoft,
      side: const BorderSide(color: SfColors.line),
      labelStyle: TextStyle(color: SfColors.text, fontSize: 14, fontFamily: fontFamily),
      shape: const StadiumBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SfColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        textStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: fontFamily),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SfColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: SfColors.muted),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: SfColors.text,
      displayColor: SfColors.text,
    ),
  );
}

String levelZh(int l) => switch (l) {
  1 => '入门',
  2 => '基础',
  _ => '进阶',
};

String minutesZh(double seconds) {
  final m = (seconds / 60).round();
  return m < 1 ? '不到 1 分钟' : '约 $m 分钟';
}
