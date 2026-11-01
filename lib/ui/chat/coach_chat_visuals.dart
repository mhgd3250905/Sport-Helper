import 'package:flutter/material.dart';
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../../domain/exercise.dart';
import '../alpha_artwork.dart';
import '../cached_exercise_media.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../training_poster_image.dart';
import 'coach_ui_adapter.dart';

/// Only original brand roles, glyphs and real media live in the host.
CoachChatVisuals smartfitCoachChatVisuals(ExerciseLibrary library) {
  final cutouts = <(String, String, Size, Brightness), Widget>{};
  final previews = Expando<Map<String, _PreviewSurface>>();
  final status = <String, ValueNotifier<CoachChatPreviewStatus>>{};
  ValueNotifier<CoachChatPreviewStatus> statusFor(String id) =>
      status.putIfAbsent(
        id,
        () => ValueNotifier(const CoachChatPreviewStatus(revealed: false)),
      );
  _PreviewSurface surface(BuildContext context, String id) =>
      (previews[context] ??= {}).putIfAbsent(id, _PreviewSurface.new);
  return CoachChatVisuals(
    light: _palette(SfPalette.light),
    dark: _palette(SfPalette.dark),
    fontFamily: sfFontFamily,
    iconBuilder: (_, icon) => SfIcon(
      SfGlyph.values.byName(icon.glyph.name),
      size: icon.size,
      color: icon.color,
      filled: icon.filled,
      strokeWidth: icon.strokeWidth,
    ),
    exerciseFor: (id, _) {
      final exercise = library.tryGet(id);
      return exercise == null ? null : toCoachRecommendationExercise(exercise);
    },
    mediaBuilder: (context, request) =>
        smartfitCoachUiStyle().builders.media?.call(context, request),
    cutoutBuilder: (context, id, size, brightness) {
      final exercise = library.tryGet(id);
      if (exercise == null) return const SizedBox.shrink();
      final asset =
          exercise.media.alphaThumbnail ??
          exercise.media.alphaCover ??
          (brightness == Brightness.light
              ? exercise.media.lightPoster ?? exercise.media.poster
              : exercise.media.poster);
      return cutouts.putIfAbsent(
        (asset, exercise.name, size, brightness),
        () => ClipOval(
          child: SizedBox.fromSize(
            size: size,
            child: SfAlphaAsset(
              asset: asset,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              semanticLabel: exercise.name,
            ),
          ),
        ),
      );
    },
    preloadPoster: (context, id) async {
      if (library.tryGet(id) case final exercise?) {
        await TrainingPosterImages.precache(context, exercise);
      }
    },
    previewBuilder: (context, id, playing) {
      final exercise = library.tryGet(id);
      if (exercise == null) return const SizedBox.expand();
      final entry = surface(context, id);
      if (playing) entry.started = true;
      return CachedExerciseMedia(
        key: entry.handle.key,
        retirementHandle: entry.handle,
        exercise: exercise,
        playing: entry.started,
        paused: !playing,
        radius: 0,
        stageColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        extractMissingPoster: true,
        onStatus: (value) => statusFor(id).value = CoachChatPreviewStatus(
          loading: value.loading,
          failed: value.failed,
          revealed: value.revealed,
          progress: value.progress,
        ),
      );
    },
    retirePreview: (context, id) async {
      final entry = previews[context]?[id];
      if (entry == null) return;
      entry.started = false;
      await entry.handle.retire();
    },
    previewStatusFor: statusFor,
  );
}

class _PreviewSurface {
  final handle = CachedExerciseMediaHandle();
  bool started = false;
}

CoachChatPalette _palette(SfPalette p) => CoachChatPalette(
  brightness: p.brightness,
  skyTop: p.skyTop,
  skyBottom: p.skyBottom,
  dust: p.dust,
  background: p.background,
  surfaceLow: p.surfaceLow,
  surface: p.surface,
  surfaceHigh: p.surfaceHigh,
  line: p.line,
  accent: p.accent,
  accentText: p.accentText,
  onAccent: p.onAccent,
  emphasis: p.emphasis,
  emphasisText: p.emphasisText,
  onEmphasis: p.onEmphasis,
  text: p.text,
  muted: p.muted,
  faint: p.faint,
  caution: p.caution,
  danger: p.danger,
  mediaStage: p.mediaStage,
  onStage: p.onStage,
  onStageMuted: p.onStageMuted,
  thumb: p.thumb,
  scrim: p.scrim,
  track: p.track,
  userBubble: p.userBubble,
  assistantBubble: p.assistantBubble,
  shadow: p.shadow,
);
