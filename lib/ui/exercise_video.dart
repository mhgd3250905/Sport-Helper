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

  /// Theme the running clip was started for: a switch reloads the
  /// light/dark render (the poster covers the hand-over).
  Brightness? _brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (_brightness != null && b != _brightness && widget.exercise.media.hasLight && _controller != null) {
      _stop();
      _start();
    }
    _brightness = b;
  }

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
    final stage = sfStageFor(e);
    final poster = sfPoster(e);
    final variant = sfVariant(e);
    final media = DrillMedia(
      id: e.media.playerId,
      videoAsset: sfVideo(e),
      posterAsset: poster,
      duration: e.media.loopSeconds,
      posterTime: e.media.posterSeconds,
    );
    Widget content = Stack(
      fit: StackFit.expand,
      children: [
        if (c != null)
          DrillMediaPlatformView(
            key: ValueKey('${e.id}/${variant ?? 'dark'}'),
            media: media,
            controller: c,
            labels: const {},
            variant: variant,
          ),
        if (c == null || !c.hasFrame)
          Image.asset(
            poster,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // Error state: the stage with a quiet figure and one line, not
            // an empty box that looks like a rendering bug.
            errorBuilder: (_, _, _) => ColoredBox(
              color: stage.mediaStage,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SfIcon(SfGlyph.figure, size: 32, color: stage.onStageMuted.withValues(alpha: .5)),
                    const SizedBox(height: SfSpace.x2),
                    Text('示范暂时加载不了', style: SfType.caption.copyWith(color: stage.onStageMuted)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (widget.mirrored) {
      content = Transform.flip(flipX: true, child: content);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: ColoredBox(
        color: stage.mediaStage,
        child: AspectRatio(aspectRatio: 1, child: content),
      ),
    );
  }
}
