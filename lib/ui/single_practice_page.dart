import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/gated_posehub_media_preparer.dart';
import '../app/posehub_media_repository.dart';
import '../app/services.dart';
import '../domain/exercise.dart';
import 'exercise_video.dart';
import 'training_poster_image.dart';
import 'training_route.dart';
import 'training_media_progress.dart';

/// Supplies host route/media hooks without recreating SDK practice UI or doses.
/// The original page is the SDK's fully configured browser callback payload.
class SinglePracticePage extends StatefulWidget {
  const SinglePracticePage({super.key, required this.page, this.exercise});

  final PoseHubSinglePracticePage page;
  final Exercise? exercise;

  @override
  State<SinglePracticePage> createState() => _SinglePracticePageState();
}

class _SinglePracticePageState extends State<SinglePracticePage> {
  TrainingRouteControl? _control;
  // Like TrainerPlayer, capture the caller's gate once for this mounted page.
  late final Future<void>? _originalGate = widget.page.startGate;
  Future<void>? _startGate;
  Future<void>? _preparerGate;
  PoseHubMediaPreparer? _preparerDelegate, _preparer;
  bool _gateOpen = false, _sessionEnded = false, _replayPending = false;
  bool _entryMarked = false;
  TrainingMediaRepositoryBridge? _repository;
  TrainingMediaPolicy? _policy;
  VoidCallback? _releaseTrainingMedia;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindGate();
    if (widget.page.startMode == TrainerStartMode.training &&
        _repository == null) {
      final services = context
          .getInheritedWidgetOfExactType<AppScope>()
          ?.services;
      final catalog = services?.poseHubCatalog;
      final media = services?.poseHubMedia;
      if (services != null &&
          catalog != null &&
          media != null &&
          media is PoseHubTrainingVideoPreparation) {
        _releaseTrainingMedia = services.beginTrainingMediaSession();
        final repository = _repository = TrainingMediaRepositoryBridge(
          catalog: catalog,
          host: media,
        );
        _policy = TrainingMediaPolicy(
          repository: repository,
          posterAssetRoot: PoseHubActionLibrary.standingAssetRoot,
          prefetchBeforeTraining: false,
        );
      }
    }
  }

  @override
  void dispose() {
    _releaseTrainingMedia?.call();
    _repository?.dispose();
    super.dispose();
  }

  void _bindGate() {
    final control = TrainingRouteScope.maybeOf(context);
    final original = _originalGate;
    if (identical(control, _control) && (_startGate != null || _gateOpen)) {
      return;
    }
    _control = control;
    final gates = [if (control != null) control.startGate, ?original];
    final gate = _startGate = gates.isEmpty
        ? null
        : Future.wait<void>(gates).then<void>((_) {});
    _gateOpen = gate == null;
    if (_gateOpen) _markTrainingEntry();
    if (gate != null) {
      // SDK errors release its gate. They cannot release the host's route gate
      // early because Future.wait also waits for every supplied future.
      void open() {
        if (!mounted || !identical(_startGate, gate)) return;
        _markTrainingEntry();
        setState(() => _gateOpen = true);
      }

      unawaited(gate.then<void>((_) => open(), onError: (Object _) => open()));
    }
  }

  void _markTrainingEntry() {
    if (_entryMarked || widget.page.startMode != TrainerStartMode.training) {
      return;
    }
    _entryMarked = true;
    final repository = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services
        .poseHubMedia;
    if (repository case final PoseHubMediaTimingAnchor anchor) {
      anchor.markTrainingEntry();
    }
  }

  void _exitStarted() {
    _control?.beginExit();
    widget.page.onExitStarted?.call();
  }

  Future<void> _beforeExitPop() async {
    final visual = _control?.beforeExitPop();
    try {
      await widget.page.beforeExitPop?.call();
    } finally {
      await visual;
    }
  }

  void _finished(PoseHubPracticeResult result) {
    _sessionEnded = true;
    // The SDK's retry action only saves. It does not mean "close", and replay
    // also reuses receipt callbacks. Only exit hooks may start route motion.
    try {
      widget.page.onFinished?.call(result);
    } on Object {
      _control?.exitSaveFailed();
      rethrow;
    }
  }

  Future<void> _completed(SessionResult result) async {
    _sessionEnded = true;
    try {
      await widget.page.onCompleted?.call(result);
    } on Object {
      _control?.exitSaveFailed();
      rethrow;
    }
  }

  Widget _media(BuildContext context, TrainerMediaRequest request) {
    final control = _control;
    if (_sessionEnded &&
        !request.paused &&
        control?.saveFailed == true &&
        !_replayPending) {
      _replayPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _replayPending = false;
        if (!mounted || !identical(control, _control)) return;
        _sessionEnded = false;
        control?.replay();
      });
    }
    final asset =
        '${PoseHubActionLibrary.standingAssetRoot}${widget.page.action.id}.webp';
    final ready =
        (control?.canPlay ?? true) &&
        (widget.page.startMode == TrainerStartMode.preview || _gateOpen);
    if (!ready) {
      return TrainingPoster.asset(
        key: const ValueKey('single-practice-poster'),
        asset: asset,
        mirrored: request.mirrored,
        radius: request.theme.radius,
        stageColor: request.theme.mediaStage,
      );
    }
    final paused = request.paused || control?.exiting == true;
    final actual = paused == request.paused
        ? request
        : TrainerMediaRequest(
            drill: request.drill,
            paused: paused,
            mirrored: request.mirrored,
            theme: request.theme,
            strings: request.strings,
            mediaPreparer: request.mediaPreparer,
            canPlay: request.canPlay,
            playbackHandle: request.playbackHandle,
          );
    final custom = widget.page.mediaBuilder;
    if (custom != null) {
      return custom(context, actual);
    }
    final exercise =
        widget.exercise ??
        context
            .getInheritedWidgetOfExactType<AppScope>()
            ?.services
            .library
            .tryGet(widget.page.action.id);
    if (exercise == null) {
      if (_policy != null) {
        return TrainingActionMedia(
          actionId: widget.page.action.id,
          policy: _policy,
          playing: actual.canPlay,
          prefetchWhenIdle: true,
          paused: paused,
          mirrored: actual.mirrored,
          radius: actual.theme.radius,
          stage: actual.theme.mediaStage,
          playbackHandle: actual.playbackHandle,
        );
      }
      return _SdkPracticeMedia(
        key: ValueKey('single-practice-sdk-media-${widget.page.action.id}'),
        page: widget.page,
        request: actual,
        asset: asset,
      );
    }
    return ExerciseVideo(
      key: ValueKey('single-practice-media-${exercise.id}'),
      exercise: exercise,
      playing: _policy == null ? true : actual.canPlay,
      prefetchWhenIdle: _policy != null,
      paused: paused,
      mirrored: request.mirrored,
      radius: request.theme.radius,
      stageColor: request.theme.mediaStage,
      mediaPreparer: request.mediaPreparer,
      downloadPlaybackHandle: _policy == null ? null : actual.playbackHandle,
      training: true,
      trainingProgress: _policy != null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final delegate = page.mediaPreparer;
    final preparationGate = page.startMode == TrainerStartMode.preview
        ? _control?.startGate
        : _startGate;
    if (!identical(delegate, _preparerDelegate) ||
        !identical(preparationGate, _preparerGate)) {
      _preparerDelegate = delegate;
      _preparerGate = preparationGate;
      _preparer = delegate == null || preparationGate == null
          ? delegate
          : GatedPoseHubMediaPreparer(
              delegate,
              preparationGate.then<void>((_) {}, onError: (Object _) {}),
            );
    }
    final child = PoseHubSinglePracticePage(
      key: page.key,
      action: page.action,
      mediaBaseUri: page.mediaBaseUri,
      theme: page.theme,
      onFinished: _finished,
      mediaPreparer: _policy == null ? _preparer : null,
      voice: page.voice,
      startMode: page.startMode,
      onStartTraining: page.onStartTraining,
      onCompleted: _completed,
      startGate: _startGate,
      beforeExitPop: _beforeExitPop,
      onExitStarted: _exitStarted,
      mediaBuilder: _media,
    );
    final policy = _policy;
    return policy == null
        ? child
        : TrainingMediaPolicyScope(policy: policy, child: child);
  }
}

/// A self-contained SDK catalogue preview need not exist in the App library.
/// Its public status reaches playing/paused only after a composed video frame.
class _SdkPracticeMedia extends StatefulWidget {
  const _SdkPracticeMedia({
    super.key,
    required this.page,
    required this.request,
    required this.asset,
  });
  final PoseHubSinglePracticePage page;
  final TrainerMediaRequest request;
  final String asset;

  @override
  State<_SdkPracticeMedia> createState() => _SdkPracticeMediaState();
}

class _SdkPracticeMediaState extends State<_SdkPracticeMedia> {
  bool _hasFrame = false;

  void _status(PoseHubPackPlaybackStatus status) {
    final ready =
        status == PoseHubPackPlaybackStatus.playing ||
        status == PoseHubPackPlaybackStatus.paused;
    if (mounted && ready != _hasFrame) setState(() => _hasFrame = ready);
  }

  @override
  void didUpdateWidget(_SdkPracticeMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset ||
        oldWidget.page.mediaBaseUri != widget.page.mediaBaseUri) {
      _hasFrame = false;
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(widget.request.theme.radius),
    child: Transform.flip(
      flipX: widget.request.mirrored,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PoseHubPackMedia(
            action: widget.page.action,
            baseUri: widget.page.mediaBaseUri,
            mediaPreparer: widget.request.mediaPreparer,
            playing: true,
            paused: widget.request.paused,
            theme: widget.request.theme.copyWith(
              mediaStage: Colors.transparent,
            ),
            onStatus: _status,
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              key: const ValueKey('single-practice-sdk-poster-fade'),
              opacity: _hasFrame ? 0 : 1,
              duration: _hasFrame
                  ? const Duration(milliseconds: 200)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              child: TrainingPoster.asset(
                key: const ValueKey('single-practice-sdk-poster'),
                asset: widget.asset,
                stageColor: widget.request.theme.mediaStage,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
