import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import 'cached_exercise_media.dart';
import 'theme.dart';

/// Matches ExerciseVideo's existing still layer, including theme, frame-zero
/// precedence, contain fitting, mirroring and image decoding width.
class TrainingTransitionPoster extends StatelessWidget {
  const TrainingTransitionPoster({
    super.key,
    required this.exercise,
    this.mirrored = false,
    this.radius = 0,
    this.cacheWidth,
  });

  final Exercise exercise;
  final bool mirrored;
  final double radius;
  final int? cacheWidth;

  /// Called at the source tap, before persistence/navigation awaits.
  static Future<void> precache(BuildContext context, Exercise exercise) async {
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    final media = exercise.media;
    final asset = action != null
        ? 'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${action.id}.webp'
        : media.alphaPlaybackPoster?.isNotEmpty == true
        ? media.alphaPlaybackPoster!
        : media.playbackPosterFor(
            light: Theme.of(context).brightness == Brightness.light,
          );
    if (asset.isNotEmpty) {
      await precacheImage(AssetImage(asset), context, onError: (_, _) {});
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: SfColors.mediaStage,
      child: Transform.flip(
        flipX: mirrored,
        child: AspectRatio(
          aspectRatio: 1,
          child: ExerciseFrameZero(exercise: exercise, cacheWidth: cacheWidth),
        ),
      ),
    ),
  );
}
