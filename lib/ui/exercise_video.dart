import 'package:flutter/material.dart';

import '../core/media/drill_media.dart';
import '../core/media/media_controller.dart';
import '../core/media/media_view.dart';
import '../domain/exercise.dart';
import 'theme.dart';

/// Poster first, then the looping pre-rendered clip on top once its first
/// frame is on screen (the HipLab hand-over: no black flash). Only
/// [playing] cards create a WebView, so a list stays light.
class ExerciseVideo extends StatefulWidget {
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

  /// Freeze an existing demonstration without discarding its current frame.
  final bool paused;

  /// Left side of a unilateral move: the clip shows the right side.
  final bool mirrored;
  final double radius;

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  DrillMediaController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _start();
  }

  @override
  void didUpdateWidget(ExerciseVideo old) {
    super.didUpdateWidget(old);
    if (old.exercise.id != widget.exercise.id ||
        old.playing != widget.playing) {
      _stop();
      if (widget.playing) _start();
    } else if (old.paused != widget.paused) {
      final c = _controller;
      if (widget.paused) {
        c?.pause();
      } else if (c != null && !c.wantsPlay) {
        c.toggle();
      }
    }
  }

  void _start() {
    final c = DrillMediaController()..addListener(_changed);
    if (!widget.paused) c.toggle(); // play as soon as the page is ready
    _controller = c;
  }

  void _stop() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    _controller = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final c = _controller;
    final media = DrillMedia(
      id: e.media.playerId,
      videoAsset: e.media.video,
      posterAsset: e.media.poster,
      duration: e.media.loopSeconds,
      posterTime: e.media.posterSeconds,
    );
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (c != null)
          DrillMediaPlatformView(
            key: ValueKey(e.id),
            media: media,
            controller: c,
            labels: const {},
          ),
        if (c == null || !c.hasFrame)
          Image.asset(
            e.media.poster,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => ColoredBox(color: SfColors.mediaStage),
          ),
      ],
    );
    if (widget.mirrored) {
      content = Transform.flip(flipX: true, child: content);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: ColoredBox(
        color: SfColors.mediaStage,
        child: AspectRatio(aspectRatio: 1, child: content),
      ),
    );
  }
}
