import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'transitions.dart';

/// Material theme built from the tokens, so stock widgets (app bars,
/// switches, dialogs, sheets, snack bars, chips) already look like ours.
ThemeData buildTheme([SfPalette p = SfPalette.dark]) {
  final scheme = (p.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    tertiary: p.emphasis,
    onTertiary: p.onEmphasis,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerHighest: p.surfaceHigh,
    outline: p.line,
    outlineVariant: p.line,
    error: p.danger,
  );
  final base = ThemeData(
    brightness: p.brightness,
    useMaterial3: true,
    fontFamily: sfFontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.text.withValues(alpha: .04),
    hoverColor: p.text.withValues(alpha: .03),
  );
  final label = TextStyle(fontFamily: sfFontFamily, color: p.text);
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: sfFontFamily,
      bodyColor: p.text,
      displayColor: p.text,
    ),
    iconTheme: IconThemeData(color: p.text, size: 22),
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.isDark ? p.surfaceHigh : p.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: label.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
      systemOverlayStyle: _overlay(p),
    ),
    // M2: one push / pop for every plain page on every platform.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values) p: const SfPageTransitionsBuilder(),
      },
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      modalBackgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.faint,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SfRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SfRadius.lg)),
      titleTextStyle: label.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.35),
      contentTextStyle: label.copyWith(fontSize: 15, height: 1.6, color: p.muted),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: p.isDark ? 0 : 3,
      shadowColor: p.shadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SfRadius.md)),
      textStyle: label.copyWith(fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? p.surfaceHigh : p.text,
      contentTextStyle: label.copyWith(
        fontSize: 14,
        color: p.isDark ? p.text : p.background,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SfRadius.md)),
    ),
    listTileTheme: ListTileThemeData(textColor: p.text, iconColor: p.muted),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SfRadius.md + 2),
        side: p.isDark ? BorderSide.none : BorderSide(color: p.line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: label.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.surfaceHigh,
        disabledForegroundColor: p.faint,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        textStyle: label.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        backgroundColor: p.surface,
        side: BorderSide(color: p.line),
        minimumSize: const Size(0, 48),
        textStyle: label.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceHigh,
      selectedColor: p.accentSoft,
      disabledColor: p.surfaceHigh,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: label.copyWith(fontSize: 14),
      secondaryLabelStyle: label.copyWith(fontSize: 14, color: p.accentText, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      checkmarkColor: p.accentText,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? (p.isDark ? p.background : Colors.white) : p.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.surfaceHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.line,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      hintStyle: label.copyWith(color: p.faint, fontSize: 15),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SfRadius.md),
        borderSide: p.isDark ? BorderSide.none : BorderSide(color: p.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SfRadius.md),
        borderSide: p.isDark ? BorderSide.none : BorderSide(color: p.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SfRadius.md),
        borderSide: BorderSide(color: p.accent, width: 1.2),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.track,
      circularTrackColor: p.track,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withValues(alpha: .3),
      selectionHandleColor: p.accent,
    ),
  );
}

SystemUiOverlayStyle _overlay(SfPalette p) =>
    (p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: p.skyBottom,
      systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    );

/// The status / navigation bar style for a page drawn on the sky.
SystemUiOverlayStyle get sfOverlay => _overlay(SfColors.palette);

/// Points [SfColors] at the palette of the theme in effect and, when it
/// changes (settings or the system switching light/dark), rebuilds every
/// widget below in the same frame; pages, sheets and pushed routes keep
/// their state (HipLab's `_PaletteScope`).
class SfPaletteScope extends StatefulWidget {
  const SfPaletteScope({super.key, required this.child});
  final Widget child;
  @override
  State<SfPaletteScope> createState() => _SfPaletteScopeState();
}

class _SfPaletteScopeState extends State<SfPaletteScope> {
  Brightness? _applied;

  static void _rebuildAll(Element e) {
    e.markNeedsBuild();
    e.visitChildren(_rebuildAll);
  }

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    if (b != _applied) {
      final first = _applied == null;
      _applied = b;
      SfColors.palette = b == Brightness.dark ? SfPalette.dark : SfPalette.light;
      if (!first) (context as Element).visitChildren(_rebuildAll);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sfOverlay,
      child: widget.child,
    );
  }
}
