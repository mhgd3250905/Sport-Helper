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
