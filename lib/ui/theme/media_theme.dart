import '../../domain/exercise.dart';
import 'tokens.dart';

/// Theme-matched drill media (docs/design-audit-2026-10-19.md §6, after
/// HipLab's `HipMediaVariants`): in the light theme every cover, thumbnail
/// and clip is the light-stage render, so no dark box sits on a light page.
/// A pack without a light render keeps its dark one (and its dark stage).
bool sfUsesLight(Exercise e) => !SfColors.isDark && e.media.hasLight;

/// The cover for the theme in effect.
String sfPoster(Exercise e) => sfUsesLight(e) ? e.media.lightPoster! : e.media.poster;

/// The stage colour behind [e]'s media: the colour its render is baked on.
/// (Light stage = #EFEFEF, the light renders' background.)
SfPalette sfStageFor(Exercise? e) =>
    e != null && sfUsesLight(e) ? SfPalette.light : SfPalette.dark;

/// The clip for the theme in effect.
String sfVideo(Exercise e) => sfUsesLight(e) ? e.media.lightVideo! : e.media.video;

/// The web player's variant ('light' → `demo-light.mp4`), or null.
String? sfVariant(Exercise e) => sfUsesLight(e) ? 'light' : null;

/// Chroma-keyed figures (Pose-Hub green-screen masters → alpha WebP, see
/// tools/media/build_cutouts.py) for the moves whose figure stands straight
/// on the glass plan card, with no stage box. Only these two so far.
abstract final class SfCutouts {
  /// Animated cutouts play; off in the test harness (an endless animated
  /// image never lets the frame scheduler settle) and under reduced motion.
  static bool animate = true;

  static const _ids = {'h-catcow-quad', 'w-dead-bug'};

  static bool has(Exercise? e) => e != null && _ids.contains(e.id);

  /// The alpha figure for [e]: animated WebP, or its still cover.
  static String asset(Exercise e, {bool still = false}) =>
      still || !animate ? 'assets/cutouts/${e.id}-cover.webp' : 'assets/cutouts/${e.id}.webp';
}
