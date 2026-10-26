import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import '../app/services.dart';
import '../domain/exercise.dart';
import '../diagnostics/runtime_log.dart';
import 'theme.dart';
import 'theme/trainer_theme.dart';
import 'posehub_download_status.dart';

/// App styling around the shared, verified on-demand training media view.
class ExerciseVideo extends StatefulWidget {
  const ExerciseVideo({
    super.key,
    required this.exercise,
    this.playing = true,
    this.paused = false,
    this.mirrored = false,
    this.radius = 16,
    this.playbackHandle,
  });

  final Exercise exercise;
  final bool playing;
  final bool paused;
  final bool mirrored;
  final double radius;
  final DrillMediaPlaybackHandle? playbackHandle;

  @override
  State<ExerciseVideo> createState() => _ExerciseVideoState();
}

class _ExerciseVideoState extends State<ExerciseVideo> {
  late final String _operation;

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
    if (widget.exercise.id != oldWidget.exercise.id ||
        widget.playing != oldWidget.playing ||
        widget.paused != oldWidget.paused) {
      _record('video.surface.updated');
    }
  }

  @override
  void dispose() {
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
    if (action != null) {
      return _PoseHubExerciseVideo(
        action: action,
        repo: services?.poseHubMedia,
        playing: widget.playing,
        paused: widget.paused,
        mirrored: widget.mirrored,
        radius: widget.radius,
        playbackHandle: widget.playbackHandle,
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
      stage: stage.mediaStage,
      errorColor: stage.onStageMuted,
      errorLabel: '示范暂时加载不了，计时和语音仍可继续',
      unavailableLabel: '此动作暂无视频示范',
      playbackHandle: widget.playbackHandle,
    );
  }
}

/// A pack action never falls through to the older App asset resolver.
class _PoseHubExerciseVideo extends StatefulWidget {
  const _PoseHubExerciseVideo({
    required this.action,
    required this.repo,
    required this.playing,
    required this.paused,
    required this.mirrored,
    required this.radius,
    required this.playbackHandle,
  });

  final coach.PoseHubPackAction action;
  final PoseHubMediaRepository? repo;
  final bool playing, paused, mirrored;
  final double radius;
  final DrillMediaPlaybackHandle? playbackHandle;

  @override
  State<_PoseHubExerciseVideo> createState() => _PoseHubExerciseVideoState();
}

class _PoseHubExerciseVideoState extends State<_PoseHubExerciseVideo>
    with WidgetsBindingObserver {
  Future<Uri>? _ready;
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _backgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    _ready = _prepare();
    _bindIdentity();
  }

  void _bindIdentity() => widget.playbackHandle?.bind(
    owner: this,
    mediaId: widget.action.id,
    controller: null,
  );

  Future<Uri>? _prepare() {
    final repo = widget.repo;
    if (repo == null) return null;
    if (widget.playing) return repo.ensureAction(widget.action.id);
    return repo.ensureFile(widget.action.cover).then((_) => repo.mediaBaseUri);
  }

  @override
  void didUpdateWidget(_PoseHubExerciseVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repo, widget.repo) ||
        oldWidget.action.id != widget.action.id ||
        oldWidget.action.cover.sha256 != widget.action.cover.sha256 ||
        oldWidget.action.video.sha256 != widget.action.video.sha256 ||
        oldWidget.playing != widget.playing) {
      _ready = _prepare();
    }
    if (!identical(oldWidget.playbackHandle, widget.playbackHandle)) {
      oldWidget.playbackHandle?.unbind(this);
    }
    _bindIdentity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final backgrounded = state != AppLifecycleState.resumed;
    if (backgrounded != _backgrounded && mounted) {
      setState(() => _backgrounded = backgrounded);
    }
  }

  void _retry() {
    final ready = _prepare();
    setState(() {
      _ready = ready;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.playbackHandle?.unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = SmartFitTrainerTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: FutureBuilder<Uri>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              snapshot.hasData) {
            return Transform.flip(
              flipX: widget.mirrored,
              child: PoseHubPackMedia(
                key: ValueKey('posehub-exercise-media-${widget.action.id}'),
                action: widget.action,
                baseUri: snapshot.data!,
                playing:
                    widget.playing &&
                    !_backgrounded &&
                    TickerMode.valuesOf(context).enabled,
                paused: widget.paused || _backgrounded,
                theme: theme,
              ),
            );
          }
          return AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(
              color: theme.mediaStage,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(SfSpace.x4),
                  child: widget.repo != null
                      ? PoseHubDownloadStatus(
                          repo: widget.repo!,
                          actionId: widget.action.id,
                          onRetry: _retry,
                        )
                      : Text(
                          '动作素材暂时无法准备',
                          key: const ValueKey('posehub-media-error'),
                          style: theme.label,
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
