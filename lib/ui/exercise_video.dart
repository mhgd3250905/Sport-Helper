import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../domain/exercise.dart';
import 'theme.dart';

/// App styling around the shared, verified on-demand training media view.
class ExerciseVideo extends StatelessWidget {
  const ExerciseVideo({
    super.key,
    required this.exercise,
    this.playing = true,
    this.paused = false,
    this.mirrored = false,
    this.radius = 16,
  });

  final Exercise exercise;
  final bool playing;
  final bool paused;
  final bool mirrored;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final m = exercise.media;
    final stage = sfStageFor(exercise);
    return DrillMediaView(
      media: DrillMedia(
        id: exercise.id,
        videoAsset: m.video,
        posterAsset: m.poster,
        duration: m.loopSeconds,
        posterTime: m.posterSeconds,
        lightVideoAsset: m.lightVideo,
        lightPosterAsset: m.lightPoster,
      ),
      playing: playing,
      paused: paused,
      mirrored: mirrored,
      radius: radius,
      stage: stage.mediaStage,
      errorColor: stage.onStageMuted,
      errorLabel: '示范暂时加载不了，计时和语音仍可继续',
    );
  }
}
