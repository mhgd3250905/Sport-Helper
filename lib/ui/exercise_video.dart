import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../diagnostics/runtime_log.dart';
import 'theme.dart';
import 'cached_exercise_media.dart';

/// App styling around the shared, verified on-demand training media view.
class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({
    super.key,
    required this.exercise,
    this.playing = true,
    this.prefetchWhenIdle = false,
    this.paused = false,
    this.mirrored = false,
    this.radius = 16,
    this.playbackHandle,
    this.downloadPlaybackHandle,
    this.mediaPreparer,
    this.training = false,
    this.trainingProgress = false,
    this.stageColor,
  });

  final Exercise exercise;
  final bool playing;
  final bool prefetchWhenIdle;
  final bool paused;
  final bool mirrored;
  final double radius;
  final DrillMediaPlaybackHandle? playbackHandle;
  final DrillMediaPlaybackHandle? downloadPlaybackHandle;

  /// A TrainerMediaRequest supplies the player's shared SDK prefetch queue.
  final PoseHubMediaPreparer? mediaPreparer;
  final bool training;
  final bool trainingProgress;
  final Color? stageColor;

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  late final String _operation;
  _DownloadPlaybackRelay? _relay;

  DrillMediaPlaybackHandle? get _mediaPlaybackHandle {
    final download = widget.downloadPlaybackHandle;
    if (download == null || identical(download, widget.playbackHandle)) {
      return widget.playbackHandle;
    }
    return _relay ??= _DownloadPlaybackRelay(widget.playbackHandle, download);
  }

  @override
  void initState() {
    super.initState();
    _operation = RuntimeLog.instance.newOperation('video');
    _record('video.surface.requested');
  }

  void _record(String event) => RuntimeLog.instance.record(
    event,
    operation: _operation,
    fields: {
      'actionId': widget.exercise.id,
      'enabled': widget.playing,
      'paused': widget.paused,
    },
  );

  @override
  void didUpdateWidget(ExerciseVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackHandle != widget.playbackHandle ||
        oldWidget.downloadPlaybackHandle != widget.downloadPlaybackHandle) {
      _relay?.dispose();
      _relay = null;
    }
    if (widget.exercise.id != oldWidget.exercise.id ||
        widget.playing != oldWidget.playing ||
        widget.paused != oldWidget.paused) {
      _record('video.surface.updated');
    }
  }

  @override
  void dispose() {
    _relay?.dispose();
    _record('video.surface.closed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final services = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    if (action != null || widget.training) {
      return CachedExerciseMedia(
        key: ValueKey('posehub-exercise-media-${exercise.id}'),
        exercise: exercise,
        mediaPreparer: widget.mediaPreparer ?? services?.poseHubPreparer,
        waitForLoopOnMiss: widget.training,
        retainWhenCovered: widget.training,
        playing: widget.playing,
        prefetchWhenIdle: widget.prefetchWhenIdle,
        training: widget.trainingProgress,
        paused: widget.paused,
        mirrored: widget.mirrored,
        radius: widget.radius,
        stageColor: widget.stageColor,
        playbackHandle: _mediaPlaybackHandle,
      );
    }
    final m = exercise.media;
    final light = Theme.of(context).brightness == Brightness.light;
    final stage = light ? SfPalette.light : SfPalette.dark;
    return DrillMediaView(
      media: DrillMedia(
        id: exercise.id,
        videoAsset: light ? m.lightVideo ?? '' : m.video,
        posterAsset: m.playbackPosterFor(light: light),
        duration: m.loopSeconds,
        posterTime: m.posterSeconds,
        lightVideoAsset: m.lightVideo,
        lightPosterAsset: m.lightPlaybackPoster ?? m.lightPoster,
        theme: light ? 'light' : 'dark',
        videoAvailable: m.videoAvailableFor(light: light),
        packedAlphaVideoAsset: m.packedAlphaVideo,
        packedAlphaPosterAsset: m.alphaPlaybackPoster,
        bundledOnly: m.appTestOnly,
      ),
      playing: widget.playing,
      paused: widget.paused,
      mirrored: widget.mirrored,
      radius: widget.radius,
      stage: widget.stageColor ?? stage.mediaStage,
      errorColor: stage.onStageMuted,
      errorLabel: '示范暂时加载不了，计时和语音仍可继续',
      unavailableLabel: '此动作暂无视频示范',
      playbackHandle: _mediaPlaybackHandle,
    );
  }
}

/// Fans out the SDK's public decoder binding, never owning either caller handle.
class _DownloadPlaybackRelay extends DrillMediaPlaybackHandle {
  _DownloadPlaybackRelay(this.issue, this.download);
  final DrillMediaPlaybackHandle? issue;
  final DrillMediaPlaybackHandle download;
  Object? _boundOwner;
  bool _disposed = false;

  @override
  void bind({
    required Object owner,
    required String mediaId,
    required DrillMediaController? controller,
    bool failed = false,
    VoidCallback? onRetry,
  }) {
    if (_disposed) return;
    _boundOwner = owner;
    super.bind(
      owner: owner,
      mediaId: mediaId,
      controller: controller,
      failed: failed,
      onRetry: onRetry,
    );
    issue?.bind(
      owner: owner,
      mediaId: mediaId,
      controller: controller,
      failed: failed,
      onRetry: onRetry,
    );
    download.bind(
      owner: owner,
      mediaId: mediaId,
      controller: controller,
      failed: failed,
      onRetry: onRetry,
    );
  }

  @override
  void unbind(Object owner) {
    super.unbind(owner);
    issue?.unbind(owner);
    download.unbind(owner);
    if (identical(_boundOwner, owner)) _boundOwner = null;
  }

  @override
  void dispose() {
    final owner = _boundOwner;
    if (owner != null) unbind(owner);
    _disposed = true;
    super.dispose();
  }
}
