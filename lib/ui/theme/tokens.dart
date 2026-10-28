import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// SmartFit design tokens (docs/design-language.md). Every colour, type
/// size, spacing step, radius, shadow and motion timing in the UI comes
/// from here, so the app is drawn with one hand.
///
/// Teal carries the primary action and selection; coral marks starting or
/// completing a workout. The chat floats in an endless sky (dark, default)
/// or an endless white room (light).

/// Bundled Noto Sans SC (assets/fonts/NotoSansSC.ttf, OFL 1.1; GB2312 +
/// UI subset of the variable font, weights 100–900).
const sfFontFamily = 'NotoSansSC';

/// Colours sampled from the icon. The pale colours are decorative; text
/// uses the contrast-adjusted roles in [SfPalette].
abstract final class SfBrand {
  static const mint = Color(0xFFBDF7CF);
  static const teal = Color(0xFF7AD4D5);
  static const coral = Color(0xFFE8705F);
}

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
    required this.surfaceLow,
    required this.surface,
    required this.surfaceHigh,
    required this.line,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.emphasis,
    required this.emphasisText,
    required this.onEmphasis,
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

  /// Level 0: fixed page furniture, underneath cards and raised controls.
  final Color surfaceLow;

  /// Level 1: cards, the input capsule, sheets, dialogs, the drawer.
  final Color surface;

  /// Level 2: things inside a card or on the page that you press
  /// (chips, circle buttons, the user's bubble, segment tracks).
  final Color surfaceHigh;

  /// Hairline. Light theme only, where white on near-white needs an edge;
  /// on dark the tone steps carry the shape.
  final Color line;

  /// Primary action, progress and selection, in the icon's teal hue.
  final Color accent;

  /// Accent as small text / icons on the page (AA on [background]).
  final Color accentText;
  final Color onAccent;

  /// Starting / completing a workout and important non-safety notices.
  /// Safety and destructive actions retain [caution] / [danger].
  final Color emphasis;
  final Color emphasisText;
  final Color onEmphasis;

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
  Color get accentSoft =>
      Color.alphaBlend(accent.withValues(alpha: isDark ? .18 : .12), surface);

  Color get emphasisSoft =>
      Color.alphaBlend(emphasis.withValues(alpha: isDark ? .16 : .12), surface);

  static const dark = SfPalette(
    brightness: Brightness.dark,
    skyTop: Color(0xFF121315), // deep neutral (round 4: no blue cast)
    skyBottom: Color(0xFF0B0B0D),
    dust: Color(0xFFDDE3F2),
    background: Color(0xFF0B0C10),
    surfaceLow: Color(0xFF111A1E),
    surface: Color(0xFF19262B),
    surfaceHigh: Color(0xFF26383E),
    line: Color(0xFF34484F),
    accent: SfBrand.teal,
    accentText: SfBrand.teal,
    onAccent: Color(0xFF092F30),
    emphasis: Color(0xFFF38F7F),
    emphasisText: Color(0xFFF38F7F),
    onEmphasis: Color(0xFF30120E),
    text: Color(0xFFF2F3F5),
    muted: Color(0xFFA0A4AC),
    faint: Color(0xFF5C6068),
    caution: Color(0xFFF3A443),
    danger: Color(0xFFEF6A6A),
    mediaStage: Color(0xFF101013),
    onStage: Color(0xFFFFFFFF),
    onStageMuted: Color(0xB8FFFFFF),
    thumb: Color(0xFF2A2D34),
    scrim: Color(0xA6000000),
    track: Color(0x1FFFFFFF),
    userBubble: Color(0xFF1B3F3D),
    assistantBubble: Color(0xFF19262B),
    shadow: Color(0x24000000),
  );

  static const light = SfPalette(
    brightness: Brightness.light,
    skyTop: Color(0xFFFAFAF8),
    skyBottom: Color(0xFFEEF0EC),
    dust: Color(0xFF7D8781),
    background: Color(0xFFF4F5F3),
    surfaceLow: Color(0xFFF4F8F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEBF2EE),
    line: Color(0xFFD7E3DC),
    accent: Color(0xFF0E7673),
    accentText: Color(0xFF0A6C69),
    onAccent: Color(0xFFFFFFFF),
    emphasis: SfBrand.coral,
    emphasisText: Color(0xFFA83B2E),
    onEmphasis: Color(0xFF30120E),
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
    userBubble: Color(0xFFDCEFEA),
    assistantBubble: Color(0xFFFFFFFF),
    shadow: Color(0x0A142E24),
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
  static Color get surfaceLow => palette.surfaceLow;
  static Color get surface => palette.surface;
  static Color get surfaceHigh => palette.surfaceHigh;
  static Color get line => palette.line;
  static Color get accent => palette.accent;
  static Color get accentText => palette.accentText;
  static Color get accentSoft => palette.accentSoft;
  static Color get onAccent => palette.onAccent;
  static Color get emphasis => palette.emphasis;
  static Color get emphasisText => palette.emphasisText;
  static Color get emphasisSoft => palette.emphasisSoft;
  static Color get onEmphasis => palette.onEmphasis;
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

  /// Short elevation shadow. Surface tones and the outline carry the hierarchy.
  static List<BoxShadow> get cardShadow => [
    BoxShadow(color: palette.shadow, blurRadius: 4, offset: const Offset(0, 2)),
  ];

  static BorderSide get cardEdge => BorderSide(color: palette.line);
}

/// The chat composer has one quiet input plane over the existing sky.
/// Its material stays local to the dock; the page palettes are unchanged.
abstract final class SfComposerTokens {
  static const outerPadding = EdgeInsets.fromLTRB(16, 0, 16, 12);
  static const inputInnerPadding = EdgeInsets.symmetric(horizontal: 4);
  static const inputTextPadding = EdgeInsets.symmetric(vertical: 15);
  static const inputHeight = 54.0;
  static const inputRadius = 22.0;
  static const inputTextSize = 16.0;
  static const inputTextHeight = 1.5;
  static const edgeWidth = 1.0;
  static const actionWidth = 44.0;
  static const bookmarkSize = 21.0;
  static const sendSize = 34.0;
  static const sendIconSize = 18.0;
  static const sendStrokeWidth = 2.0;
  static const inputInsetWithoutLeading = 12.0;
  static const pressScale = .97;
  static const suggestionStripHeight = 52.0;
  static const suggestionStripPadding = EdgeInsets.fromLTRB(16, 4, 16, 4);
  static const suggestionGap = 8.0;
  static const suggestionFaceHeight = 32.0;
  static const suggestionRadius = 16.0;
  static const suggestionPadding = EdgeInsets.symmetric(horizontal: 12);
  static const suggestionTextSize = 14.0;
  static const suggestionTextHeight = 1.2;
  static const suggestionTextWeight = FontWeight.w400;
  static const suggestionIconSize = 14.0;
  static const suggestionIconGap = 6.0;
  static const suggestionEdgeWidth = .75;

  static LinearGradient get dockGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      SfFeaturePanelTokens.background.withValues(alpha: 0),
      SfFeaturePanelTokens.background.withValues(alpha: .18),
      SfFeaturePanelTokens.background.withValues(alpha: .72),
      SfFeaturePanelTokens.background,
    ],
    stops: const [0, .35, .70, 1],
  );

  static LinearGradient get inputGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: SfColors.isDark
        ? const [Color(0xFF1D2225), Color(0xFF171C1F)]
        : const [Color(0xFFFFFFFF), Color(0xFFF7F9F7)],
  );

  static Color get inputEdge =>
      SfColors.isDark ? const Color(0xFF3A4246) : const Color(0xFFD2DCD5);
  static Color get hint =>
      SfColors.isDark ? const Color(0xFF899596) : const Color(0xFF818E86);
  static Color get bookmark =>
      SfColors.isDark ? const Color(0xFFB1BDBE) : const Color(0xFF63736B);
  static Color get inactiveSendFill =>
      SfColors.isDark ? const Color(0xFF262F33) : const Color(0xFFECF0ED);
  static Color get inactiveSendInk =>
      SfColors.isDark ? const Color(0xFF748285) : const Color(0xFF9BA9A1);
  static List<BoxShadow> get inputShadow => [
    BoxShadow(
      color: SfColors.isDark
          ? const Color(0x28000000)
          : const Color(0x0B203B2B),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static Color get suggestionFill =>
      SfColors.isDark ? const Color(0xFF181F22) : const Color(0xFFF0F4F1);
  static Color get suggestionEdge =>
      SfColors.isDark ? const Color(0xFF303A3E) : const Color(0xFFDDE5DF);
  static Color get suggestionInk =>
      SfColors.isDark ? const Color(0xFFBAC5C5) : const Color(0xFF4C5E54);
  static Color get suggestionIcon =>
      SfColors.isDark ? const Color(0xFF8FB7B2) : const Color(0xFF598477);
}

/// Compact chat tools share the sky colour and grow only when a row is added.
abstract final class SfFeaturePanelTokens {
  static const padding = EdgeInsets.fromLTRB(16, 16, 16, 16);
  static const minTileWidth = 80.0;
  static const maxColumns = 4;
  static const rowGap = 16.0;
  static const tileSize = 56.0;
  static const tileRadius = 16.0;
  static const iconSize = 24.0;
  static const labelGap = 8.0;
  static const maxHeightFraction = .45;
  static Color get background => SfColors.skyBottom;
  static Color get tileFill => SfColors.surfaceHigh;
  static Color get tileEdge => SfColors.line;
}

/// Type scale. Six steps; weight and colour carry the rest of the
/// hierarchy. Heights are tuned for CJK (1.5–1.6 for running text).
abstract final class SfType {
  /// 完成页 title.
  static TextStyle get display => TextStyle(
    fontSize: 30,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -.3,
    color: SfColors.text,
  );

  /// The chat's greeting: large type floating in the sky, no bubble.
  static TextStyle get greeting => TextStyle(
    fontSize: 28,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -.2,
    color: SfColors.text,
  );

  /// Card / page / exercise titles.
  static TextStyle get title => TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: -.1,
    color: SfColors.text,
  );

  /// Section heads, sheet titles.
  static TextStyle get headline => TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: SfColors.text,
  );

  /// Conversation and running text.
  static TextStyle get body => TextStyle(
    fontSize: 16,
    height: 1.6,
    fontWeight: FontWeight.w400,
    color: SfColors.text,
  );

  /// List rows, chips, buttons inside cards.
  static TextStyle get callout => TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: SfColors.text,
  );

  /// Meta lines (时长 · 动作数 · 器械), doses.
  static TextStyle get label => TextStyle(
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: SfColors.muted,
  );

  /// Time marks, hints, footnotes.
  static TextStyle get caption => TextStyle(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: SfColors.faint,
  );

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
  static const sheet = AnimationStyle(
    duration: page,
    reverseDuration: pageReverse,
  );

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
