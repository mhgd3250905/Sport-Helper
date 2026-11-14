import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import '../app/services.dart';
import '../domain/exercise.dart';
import 'theme/trainer_theme.dart';
import 'training_media_progress.dart';

/// Projects the legacy SDK repository's real state without inventing stages.
CatalogMediaDownloadState legacyVideoDownloadState(TrainingMediaState state) =>
    CatalogMediaDownloadState(
      phase: switch (state.phase) {
        TrainingMediaPhase.idle => CatalogMediaDownloadPhase.idle,
        TrainingMediaPhase.queued => CatalogMediaDownloadPhase.queued,
        TrainingMediaPhase.downloading => CatalogMediaDownloadPhase.downloading,
        TrainingMediaPhase.ready => CatalogMediaDownloadPhase.ready,
        TrainingMediaPhase.waitingForWifi ||
        TrainingMediaPhase.offline ||
        TrainingMediaPhase.failed => CatalogMediaDownloadPhase.failed,
      },
      receivedBytes: state.receivedBytes,
      totalBytes: state.totalBytes,
      error: state.error,
    );

abstract class _ObservedDownloadState extends ChangeNotifier {
  bool _alive = true, _pending = false;
  void changed() {
    if (!_alive) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pending) return;
      _pending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pending = false;
        if (_alive) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    super.dispose();
  }
}

class _PoseHubState extends _ObservedDownloadState
    implements ValueListenable<CatalogMediaDownloadState> {
  _PoseHubState(this.source) {
    source.addListener(changed);
  }
  final ValueListenable<PoseHubDownloadState> source;
  @override
  CatalogMediaDownloadState get value => trainingDownloadState(source.value);
  @override
  void dispose() {
    source.removeListener(changed);
    super.dispose();
  }
}

class _LegacyState extends _ObservedDownloadState
    implements ValueListenable<CatalogMediaDownloadState> {
  _LegacyState(this.repository, this.actionId) {
    repository.addListener(changed);
  }
  final TrainingMediaRepository repository;
  final String actionId;
  @override
  CatalogMediaDownloadState get value =>
      legacyVideoDownloadState(repository.stateFor(actionId));
  @override
  void dispose() {
    repository.removeListener(changed);
    super.dispose();
  }
}

/// Observes the existing downloader; only the child may initiate media work.
/// The caller owns [playbackHandle], shared with the actual video renderer.
class VisibleVideoProgress extends StatefulWidget {
  const VisibleVideoProgress({
    super.key,
    required this.exercise,
    required this.active,
    required this.playbackHandle,
    required this.onRetry,
    required this.child,
    this.top = 8,
    this.right = 8,
  });
  final Exercise exercise;
  final bool active;
  final DrillMediaPlaybackHandle playbackHandle;
  final VoidCallback onRetry;
  final Widget child;
  final double top, right;

  @override
  State<VisibleVideoProgress> createState() => _VisibleVideoProgressState();
}

class _VisibleVideoProgressState extends State<VisibleVideoProgress> {
  Object? _source;
  String? _actionId;
  ChangeNotifier? _projection;
  ValueListenable<CatalogMediaDownloadState>? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(VisibleVideoProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id) _bind();
  }

  void _bind() {
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(widget.exercise.id);
    final host = services?.poseHubMedia;
    final PoseHubMediaRepository? poseHub =
        action != null && host is PoseHubTrainingVideoPreparation ? host : null;
    final legacy = action != null
        ? null
        : services?.media ?? TrainingMediaScope.maybeOf(context);
    final Object? source = poseHub ?? legacy;
    if (identical(source, _source) && _actionId == widget.exercise.id) return;
    _projection?.dispose();
    _projection = null;
    _state = null;
    _source = source;
    _actionId = widget.exercise.id;
    if (poseHub != null && action != null) {
      final state = _PoseHubState(poseHub.watchFile(action.video));
      _projection = state;
      _state = state;
    } else if (legacy != null) {
      final state = _LegacyState(legacy, widget.exercise.id);
      _projection = state;
      _state = state;
    }
  }

  @override
  void dispose() {
    _projection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final poseHub =
        services?.poseHubCatalog?.tryGet(widget.exercise.id) != null;
    final available =
        poseHub ||
        widget.exercise.media.videoAvailableFor(
          light: Theme.of(context).brightness == Brightness.light,
        );
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (widget.active && available && state != null)
          Positioned(
            top: widget.top,
            right: widget.right,
            child: TrainerMediaDownloadIndicator(
              key: ValueKey('visible-video-download-${widget.exercise.id}'),
              state: state,
              actionId: widget.exercise.id,
              theme: SmartFitTrainerTheme.of(context),
              strings: TrainerStrings.zh(),
              playbackHandle: widget.playbackHandle,
              onRetry: widget.onRetry,
              videoSupported:
                  (!poseHub && !widget.exercise.media.hasPackedAlpha) ||
                  UgkPackedAlphaVideo.isSupported,
            ),
          ),
      ],
    );
  }
}
