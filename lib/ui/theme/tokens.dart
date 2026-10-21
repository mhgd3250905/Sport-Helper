import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// SmartFit design tokens (docs/design-language.md). Every colour, type
/// size, spacing step, radius, shadow and motion timing in the UI comes
/// from here, so the app is drawn with one hand.
///
/// The discipline is HipLab's (docs/tactile-design-rationale-2026-10-19.md
/// in that repo): one accent, tonal layers instead of glass and strokes,
/// emphasis by colour rather than height, a small set of radii, and one
/// motion vocabulary. The look is SmartFit's own: the chat floats in an
/// endless sky (dark, default) or an endless white room (light).

/// Bundled Noto Sans SC (assets/fonts/NotoSansSC.ttf, OFL 1.1; GB2312 +
/// UI subset of the variable font, weights 100–900).
const sfFontFamily = 'NotoSansSC';

/// One complete set of colour tokens: [dark] (deep sky) and [light]
/// (paper white). Same roles in both; only values differ.
@immutable
class SfPalette {
  const SfPalette({
    required this.brightness,
    required this.skyTop,
    required this.skyBottom,
    required this.dust,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.text,
    required this.muted,
    required this.faint,
    required this.caution,
    required this.danger,
    required this.mediaStage,
    required this.onStage,
    required this.onStageMuted,
    required this.thumb,
    required this.scrim,
    required this.track,
    required this.userBubble,
    required this.assistantBubble,
    required this.shadow,
  });

  final Brightness brightness;

  /// The endless space behind the chat and the player (top → bottom).
  final Color skyTop;
  final Color skyBottom;

  /// Star dust (dark) / floating motes (light), drawn at low alpha.
  final Color dust;

  /// Plain pages (library, about …) and the system navigation bar.
  final Color background;

  /// Level 1: cards, the input capsule, sheets, dialogs, the drawer.
  final Color surface;

  /// Level 2: things inside a card or on the page that you press
  /// (chips, circle buttons, the user's bubble, segment tracks).
  final Color surfaceHigh;

  /// Hairline. Light theme only, where white on near-white needs an edge;
  /// on dark the tone steps carry the shape.
  final Color line;

  /// The one accent: the primary action, progress, selection.
  final Color accent;

  /// Accent as small text / icons on the page (AA on [background]).
  final Color accentText;
  final Color onAccent;

  final Color text;
  final Color muted;
  final Color faint;

  /// Safety only (不舒服, 换侧 notice). Never decoration.
  final Color caution;

  /// Destructive confirmations (删除, 结束今天的训练).
  final Color danger;

  /// What sits behind a drill clip: the colour its render is baked on
  /// (#101013 dark renders, #EFEFEF light-stage renders, §6).
  final Color mediaStage;

  /// Text laid over a media stage (the plan card's title and meta line).
  final Color onStage;
  final Color onStageMuted;

  /// The sliding thumb of a segmented control (the one neutral raised part).
  final Color thumb;

  /// Labels floating on media (已暂停, 不舒服).
  final Color scrim;

  /// Ring / progress tracks.
  final Color track;

  final Color userBubble;
  final Color assistantBubble;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Selected chip / option fill.
  Color get accentSoft => accent.withValues(alpha: isDark ? .16 : .12);

  static const dark = SfPalette(
    brightness: Brightness.dark,
    skyTop: Color(0xFF0D1017),
    skyBottom: Color(0xFF060709),
    dust: Color(0xFFDDE3F2),
    background: Color(0xFF0B0C10),
    surface: Color(0xFF15171C),
    surfaceHigh: Color(0xFF1F2228),
    line: Color(0xFF272A31),
    accent: Color(0xFF3CCFA4),
    accentText: Color(0xFF3CCFA4),
    onAccent: Color(0xFF07261D),
    text: Color(0xFFF2F3F5),
    muted: Color(0xFF8D9199),
    faint: Color(0xFF5C6068),
    caution: Color(0xFFF3A443),
    danger: Color(0xFFEF6A6A),
    mediaStage: Color(0xFF101013),
    onStage: Color(0xFFFFFFFF),
    onStageMuted: Color(0xB8FFFFFF),
    thumb: Color(0xFF2A2D34),
    scrim: Color(0xA6000000),
    track: Color(0x1FFFFFFF),
    userBubble: Color(0xFF1B3830), // dark jade, solid (flat, z = 0)
    assistantBubble: Color(0xFF23262D), // dark grey, solid
    shadow: Color(0x00000000),
  );

  static const light = SfPalette(
    brightness: Brightness.light,
    skyTop: Color(0xFFFAFAF8),
    skyBottom: Color(0xFFEEF0EC),
    dust: Color(0xFF7D8781),
    background: Color(0xFFF4F5F3),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEF0EE),
    line: Color(0xFFE1E4E1),
    accent: Color(0xFF14A37B),
    accentText: Color(0xFF0D6E53),
    onAccent: Color(0xFFFFFFFF),
    text: Color(0xFF121614),
    muted: Color(0xFF5D6661),
    faint: Color(0xFF9AA29E),
    caution: Color(0xFFB8650F),
    danger: Color(0xFFD43F3F),
    mediaStage: Color(0xFFEFEFEF),
    onStage: Color(0xFF121614),
    onStageMuted: Color(0xFF5D6661),
    thumb: Color(0xFFFFFFFF),
    scrim: Color(0x8C000000),
    track: Color(0x14000000),
    userBubble: Color(0xFFDCEFE6), // light jade tint, solid (flat, z = 0)
    assistantBubble: Color(0xFFE9ECEA), // neutral light grey, solid
    shadow: Color(0x121D2B25),
  );
}

/// Colour tokens for the theme in effect. [SfPaletteScope] points
/// [palette] at the resolved theme and rebuilds the tree when it changes,
/// so `SfColors.x` always reads the current set.
abstract final class SfColors {
  static SfPalette palette = SfPalette.dark;

  static bool get isDark => palette.isDark;
  static Color get skyTop => palette.skyTop;
  static Color get skyBottom => palette.skyBottom;
  static Color get dust => palette.dust;
  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceHigh => palette.surfaceHigh;
  static Color get line => palette.line;
  static Color get accent => palette.accent;
  static Color get accentText => palette.accentText;
  static Color get accentSoft => palette.accentSoft;
  static Color get onAccent => palette.onAccent;
  static Color get text => palette.text;
  static Color get muted => palette.muted;
  static Color get faint => palette.faint;
  static Color get caution => palette.caution;
  static Color get danger => palette.danger;
  static Color get mediaStage => palette.mediaStage;
  static Color get onStage => palette.onStage;
  static Color get onStageMuted => palette.onStageMuted;
  static Color get thumb => palette.thumb;
  static Color get scrim => palette.scrim;
  static Color get track => palette.track;
  static Color get userBubble => palette.userBubble;
  static Color get assistantBubble => palette.assistantBubble;

  /// Card elevation: none on dark (tone steps carry it), a faint two-layer
  /// ink shadow on light (never coloured).
  static List<BoxShadow>? get cardShadow => palette.isDark
      ? null
      : [
          BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8)),
          const BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
        ];

  /// Hairline for level-1 surfaces: light only.
  static BorderSide get cardEdge =>
      palette.isDark ? BorderSide.none : BorderSide(color: palette.line);
}

/// Type scale. Six steps; weight and colour carry the rest of the
/// hierarchy. Heights are tuned for CJK (1.5–1.6 for running text).
abstract final class SfType {
  /// 完成页 title.
  static TextStyle get display => TextStyle(
    fontSize: 30, height: 1.2, fontWeight: FontWeight.w800, letterSpacing: -.3, color: SfColors.text);

  /// The chat's greeting: large type floating in the sky, no bubble.
  static TextStyle get greeting => TextStyle(
    fontSize: 28, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -.2, color: SfColors.text);

  /// Card / page / exercise titles.
  static TextStyle get title => TextStyle(
    fontSize: 20, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -.1, color: SfColors.text);

  /// Section heads, sheet titles.
  static TextStyle get headline => TextStyle(
    fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: SfColors.text);

  /// Conversation and running text.
  static TextStyle get body => TextStyle(
    fontSize: 16, height: 1.6, fontWeight: FontWeight.w400, color: SfColors.text);

  /// List rows, chips, buttons inside cards.
  static TextStyle get callout => TextStyle(
    fontSize: 15, height: 1.4, fontWeight: FontWeight.w500, color: SfColors.text);

  /// Meta lines (时长 · 动作数 · 器械), doses.
  static TextStyle get label => TextStyle(
    fontSize: 13, height: 1.4, fontWeight: FontWeight.w400, color: SfColors.muted);

  /// Time marks, hints, footnotes.
  static TextStyle get caption => TextStyle(
    fontSize: 12, height: 1.4, fontWeight: FontWeight.w400, color: SfColors.faint);

  /// Numbers that tick (counter, progress).
  static const tabular = [FontFeature.tabularFigures()];

  /// A large number that changes (countdown, stats): tabular, tight, set
  /// solid (HipLab's ring numeral: tracking −1.2 % of the size).
  static TextStyle numeral(double size, {Color? color}) => TextStyle(
    fontSize: size,
    height: 1,
    fontWeight: FontWeight.w700,
    letterSpacing: -size * .012,
    color: color ?? SfColors.text,
    fontFeatures: tabular,
  );
}

/// 4-pt spacing grid.
abstract final class SfSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;

  /// Page gutter.
  static const gutter = 20.0;
}

/// Radii: a small set used everywhere. Nested corners step down by the
/// padding between them (card 22 → inner stage 14 at 8 pt inset).
abstract final class SfRadius {
  static const xs = 8.0; // tiny thumbnails, tags
  static const sm = 12.0; // list thumbnails
  static const md = 16.0; // inner tiles, chips' container rows
  static const lg = 22.0; // cards, bubbles, media
  static const xl = 28.0; // sheets, drawer

  /// Bubble corner on the speaker's side.
  static const tail = 8.0;
}

/// Motion tokens (HipLab's vocabulary): short, no bounce, one large move
/// per transition.
abstract final class SfMotion {
  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);

  /// Press feedback (scale + slightly deeper fill) and its release.
  static const press = Duration(milliseconds: 100);
  static const release = Duration(milliseconds: 180);
  static const pressScale = .97;

  /// A message arriving: fade + 12 px rise.
  static const appear = Duration(milliseconds: 360);

  /// Container transform (plan card → player): the one large move.
  static const expand = Duration(milliseconds: 500);
  static const expandReverse = Duration(milliseconds: 420);

  /// Push / pop of a plain page, its reverse a touch quicker.
  static const page = Duration(milliseconds: 400);
  static const pageReverse = Duration(milliseconds: 340);

  /// Sheets rise on the page timing.
  static const sheet = AnimationStyle(duration: page, reverseDuration: pageReverse);

  /// Items arriving together, one after another.
  static const stagger = Duration(milliseconds: 40);

  /// Messages of one reply (words first, then the card).
  static const replyStagger = Duration(milliseconds: 120);

  /// A digit rolling over (countdown, rep counter).
  static const roll = Duration(milliseconds: 260);

  /// The last-seconds breath of the countdown (once per second).
  static const breath = Duration(milliseconds: 1000);

  /// Segmented thumb slide.
  static const segment = Duration(milliseconds: 380);

  /// Finish: the check drawing itself, the one ring going out, counting up.
  static const check = Duration(milliseconds: 520);
  static const ripple = Duration(milliseconds: 900);
  static const countUp = Duration(milliseconds: 700);

  static const Curve standard = Curves.easeOutCubic;

  /// Pages arriving: a gentle first frame, half way at ~20 %.
  static const Curve enter = Cubic(0.2, 0.0, 0.0, 1.0);

  /// A page leaving (pop), as the distance travelled.
  static const Curve exit = Curves.fastOutSlowIn;

  /// Container bounds, both ways.
  static const Curve container = Curves.fastOutSlowIn;

  /// A soft spring (≈4 % overshoot): the segmented thumb only.
  static const Curve spring = Cubic(0.32, 1.28, 0.52, 1.0);

  /// Whether the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Touch feedback, graded (docs/design-audit-2026-10-19.md §2.9): a
/// selection tick for choices, a light tap for primary buttons, a medium
/// one for starting / finishing a workout. Haptics stay on under reduced
/// motion (they are not motion).
enum SfHaptic {
  none,
  selection,
  light,
  medium;

  void play() {
    switch (this) {
      case SfHaptic.none:
        return;
      case SfHaptic.selection:
        HapticFeedback.selectionClick();
      case SfHaptic.light:
        HapticFeedback.lightImpact();
      case SfHaptic.medium:
        HapticFeedback.mediumImpact();
    }
  }
}
