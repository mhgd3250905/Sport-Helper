import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../training_poster_image.dart';

/// Warms the first training poster when an entry is built. The SDK card keeps
/// its normal layout, expanded state, and media builders without interception.
class TrainingCardMedia extends StatefulWidget {
  const TrainingCardMedia({
    super.key,
    required this.exercise,
    required this.child,
  });

  final Exercise exercise;
  final Widget child;

  @override
  State<TrainingCardMedia> createState() => _TrainingCardMediaState();
}

class _TrainingCardMediaState extends State<TrainingCardMedia> {
  String? _warmed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm();
  }

  @override
  void didUpdateWidget(TrainingCardMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.exercise, oldWidget.exercise)) _warm();
  }

  void _warm() {
    final signature =
        '${widget.exercise.id}/${Theme.of(context).brightness}/'
        '${TrainingPosterImages.decodeWidth(context)}';
    if (_warmed == signature) return;
    _warmed = signature;
    unawaited(TrainingPosterImages.precache(context, widget.exercise));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
