import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import 'theme.dart';
import 'training_poster_image.dart';

/// Fixed final-stage layout. Only Transform, clip and alpha change each tick.
/// Counter-scaling the pixels preserves BoxFit.contain as the card's aspect
/// ratio changes: a simple nonuniform scale would stretch the person/chair.
class TrainingPosterFlight extends StatelessWidget {
  const TrainingPosterFlight({
    super.key,
    required this.animation,
    required this.exercise,
    required this.canvasSize,
    required this.from,
    required this.to,
    required this.durationMs,
    required this.morphMs,
    required this.beginRadius,
    required this.endRadius,
    this.mirrored = false,
    this.cacheWidth,
    this.enterFallback = false,
    this.fadeAfterMs,
    this.fadeDurationMs = 120,
  });
  final Animation<double> animation;
  final Exercise exercise;
  final Size canvasSize;
  final Rect from, to;
  final double durationMs, morphMs, beginRadius, endRadius;
  final bool mirrored, enterFallback;
  final int? cacheWidth;
  final double? fadeAfterMs;
  final double fadeDurationMs;

  Rect rectAt(double value) => Rect.lerp(
    from,
    to,
    Curves.easeInOutCubicEmphasized.transform(
      (value * durationMs / morphMs).clamp(0.0, 1.0),
    ),
  )!;

  double radiusAt(double value) {
    final t = Curves.easeInOutCubicEmphasized.transform(
      (value * durationMs / morphMs).clamp(0.0, 1.0),
    );
    return beginRadius + (endRadius - beginRadius) * t;
  }

  @override
  Widget build(BuildContext context) => DecodedTrainingPoster(
    exercise: exercise,
    cacheWidth: cacheWidth,
    builder: (context, pixels, intrinsic) => AnimatedBuilder(
      animation: animation,
      // This subtree is laid out once at the fixed stage size, never rebuilt
      // or resized by the Rect animation. Its boundary retains the image layer.
      child: Transform.flip(flipX: mirrored, child: pixels),
      builder: (context, child) {
        final value = animation.value;
        final elapsed = value * durationMs;
        final rect = rectAt(value);
        final sx = rect.width / canvasSize.width;
        final sy = rect.height / canvasSize.height;
        final fixedFit = math.min(
          canvasSize.width / intrinsic.width,
          canvasSize.height / intrinsic.height,
        );
        final movingFit = math.min(
          rect.width / intrinsic.width,
          rect.height / intrinsic.height,
        );
        final uniform = movingFit / fixedFit;
        final r = radiusAt(value);
        Widget layer = Transform(
          alignment: Alignment.topLeft,
          transform: Matrix4.identity()
            ..translateByDouble(rect.left, rect.top, 0, 1)
            ..scaleByDouble(sx, sy, 1, 1),
          child: ClipRRect(
            clipBehavior: Clip.antiAlias,
            borderRadius: BorderRadius.all(Radius.elliptical(r / sx, r / sy)),
            child: ColoredBox(
              color: SfColors.mediaStage,
              child: Transform.scale(
                scaleX: uniform / sx,
                scaleY: uniform / sy,
                child: child,
              ),
            ),
          ),
        );
        var alpha = 1.0;
        if (enterFallback) {
          final t = Curves.easeOutCubic.transform(
            (elapsed / 320).clamp(0.0, 1.0),
          );
          layer = Transform.scale(scale: 1.04 - .04 * t, child: layer);
          alpha = t;
        }
        if (fadeAfterMs case final start?) {
          alpha *= 1 - ((elapsed - start) / fadeDurationMs).clamp(0.0, 1.0);
        }
        return FadeTransition(
          opacity: AlwaysStoppedAnimation(alpha),
          child: layer,
        );
      },
    ),
  );
}
