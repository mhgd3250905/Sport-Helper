import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import 'theme.dart';
import 'training_poster_image.dart';

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
  static Future<void> precache(BuildContext context, Exercise exercise) =>
      TrainingPosterImages.precache(context, exercise);

  @override
  Widget build(BuildContext context) => ClipRRect(
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: SfColors.mediaStage,
      child: Transform.flip(
        flipX: mirrored,
        child: AspectRatio(
          aspectRatio: 1,
          child: DecodedTrainingPoster(
            exercise: exercise,
            cacheWidth: cacheWidth,
            builder: (_, pixels, _) => pixels,
          ),
        ),
      ),
    ),
  );
}
