import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../domain/exercise.dart';
import 'cached_exercise_media.dart';
import 'theme.dart';
import 'theme/trainer_theme.dart';

/// A still-only entry surface: no trainer, clock, voice, media resolver or
/// decoder. The exported SDK floor and the ordinary frame-zero image are reused.
class TrainingEntryPlaceholder extends StatelessWidget {
  const TrainingEntryPlaceholder({super.key, required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = SmartFitTrainerTheme.of(context);
    return Scaffold(
      backgroundColor: theme.mediaStage,
      body: LayoutBuilder(
        builder: (context, box) {
          final rect = _mediaRect(context, box.biggest);
          return Stack(
            children: [
              Positioned.fill(
                child: TrainerStageFloor(
                  theme: theme,
                  clipSize: rect.width,
                  clipLeft: rect.left,
                  clipTop: rect.top,
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: TrainingTransitionPoster(exercise: exercise),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Geometry adapter for the pinned SDK 652135f's default training slots.
  /// The SDK exports the floor, but not a stage-rect calculator. Keep this
  /// small host placeholder aligned with its actual mediaBuilder bounds via
  /// integration tests (safe areas, compact screens and nonlinear text scales).
  /// This does not duplicate the SDK's controls, layout widgets or player state.
  Rect _mediaRect(BuildContext context, Size size) {
    final query = MediaQuery.of(context);
    final scale = query.textScaler;
    final cardRow = math.max(
      42.0,
      math.max(
        scale.scale(17) * 1.2 + 3 + scale.scale(12.5) * 1.25 + 2,
        scale.scale(30) * 1.25,
      ),
    );
    final cardBottom = TrainerSpace.x2 * 2 + 10 + cardRow + 8 + 3 + 10;
    final digits = math.max(44.0, scale.scale(32) * 1.2);
    final transport = TrainerSpace.x3 + digits + 2 + 96 + TrainerSpace.x5;
    final top = query.padding.top + cardBottom;
    final room = math.max(
      0.0,
      size.height - transport - query.padding.bottom - top,
    );
    final side = math.min(size.width * 1.15, math.max(160.0, room));
    return Rect.fromLTWH(
      (size.width - side) / 2,
      top + math.max(0.0, room - side) * .35,
      side,
      side,
    );
  }
}

/// Matches ExerciseVideo's existing still layer, including theme, frame-zero
/// precedence, contain fitting, mirroring and image decoding width.
class TrainingTransitionPoster extends StatelessWidget {
  const TrainingTransitionPoster({
    super.key,
    required this.exercise,
    this.mirrored = false,
    this.radius = 0,
  });

  final Exercise exercise;
  final bool mirrored;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: ColoredBox(
      color: SfColors.mediaStage,
      child: Transform.flip(
        flipX: mirrored,
        child: AspectRatio(
          aspectRatio: 1,
          child: ExerciseFrameZero(exercise: exercise),
        ),
      ),
    ),
  );
}
