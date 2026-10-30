import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/gated_posehub_media_preparer.dart';
import '../app/services.dart';
import '../domain/exercise.dart' show equipmentLabel;
import '../domain/plan.dart';
import '../domain/session.dart' as session;
import '../diagnostics/training_log.dart';
import '../voice/just_audio_output.dart' as diagnostic_voice;
import 'action_issue_actions.dart';
import 'alpha_artwork.dart';
import 'exercise_video.dart';
import 'theme/trainer_theme.dart';
import 'training_poster_image.dart';
import 'training_route.dart';

/// App styling, assets and durable callbacks; all training UI belongs to SDK.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.plan,
    this.tick = const Duration(milliseconds: 50),
  });
  final TrainingPlan plan;
  final Duration tick;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _log = TrainingLog();
  diagnostic_voice.JustAudioVoiceOutput? _voiceOutput;
  DrillMediaPlaybackHandle? _issuePlayback;
  String? _visibleActionId;
  TrainingRouteControl? _control;
  PoseHubMediaPreparer? _preparer;
  TrainingRouteControl? _preparerControl;
  bool _sessionFinished = false, _prefetchStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _control = TrainingRouteScope.maybeOf(context);
  }

  void _startLog(AppServices services) {
    if (!_prefetchStarted) {
      _prefetchStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (_control?.entered ?? true) &&
            _control?.exiting != true) {
          services.prefetchPlan(widget.plan);
        }
      });
    }
    _log.start(
      actionCount: widget.plan.items.length,
      voice: services.store.voice.voice,
      chimes: services.store.voice.chimes,
    );
    if (services.voiceOutput
        case final diagnostic_voice.JustAudioVoiceOutput output) {
      _voiceOutput = output;
      output.beforeSessionBegin = _audioBeginning;
      output.trainingOperation = _log.operation;
    }
  }

  String? _audioBeginning() {
    _log.audioBeginning();
    return _log.operation;
  }

  @override
  void dispose() {
    final output = _voiceOutput;
    if (output?.beforeSessionBegin == _audioBeginning) {
      output?.beforeSessionBegin = null;
      if (output?.trainingOperation == _log.operation) {
        output?.trainingOperation = null;
      }
    }
    _log.dispose();
    _issuePlayback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final plan = widget.plan;
    if (plan.exerciseIds.any((id) => !services.library.contains(id))) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('计划包含尚未可用的动作，暂时无法开始。'))),
      );
    }
    final control = _control;
    if (control == null || control.entered) _startLog(services);
    if (_preparer == null || !identical(_preparerControl, control)) {
      _preparerControl = control;
      final delegate = services.poseHubPreparer;
      _preparer = delegate == null || control == null
          ? delegate
          : GatedPoseHubMediaPreparer(delegate, control.startGate);
    }
    final issueStore = services.store.actionIssueStore;
    final issuePlayback = issueStore.enabled
        ? (_issuePlayback ??= DrillMediaPlaybackHandle())
        : null;
    return Stack(
      key: const ValueKey('training-player-layers'),
      fit: StackFit.expand,
      children: [
        TrainerPlayer(
          plan: session.trainerPlan(plan),
          startMode: TrainerStartMode.training,
          startGate: control?.startGate,
          onExitStarted: control?.beginExit,
          beforeExitPop: control?.beforeExitPop,
          rhythms: session.trainerRhythms(services.library),
          strings: TrainerStrings.zh(),
          theme: SmartFitTrainerTheme.of(context),
          poseHubActionOf: services.poseHubCatalog?.tryGet,
          poseHubMediaBaseUri: services.poseHubMedia?.mediaBaseUri,
          poseHubMediaPreparer: _preparer,
          drillOf: (id) {
            final exercise = services.library.tryGet(id);
            if (exercise == null) return null;
            final media = exercise.media;
            final alpha = SfAlphaCards.enabledOf(context)
                ? media.alphaThumbnail
                : null;
            return TrainerDrill(
              id: id,
              name: exercise.name,
              cue: exercise.cue,
              cues: exercise.cues,
              precautions: exercise.cautions,
              targetMuscles: exercise.muscles.join('、'),
              equipment: exercise.effectiveEquipmentIds.isEmpty
                  ? '徒手'
                  : exercise.effectiveEquipmentIds
                        .map(equipmentLabel)
                        .join('、'),
              thumbnailAsset:
                  alpha ??
                  (Theme.of(context).brightness == Brightness.light
                      ? media.lightPoster ?? media.poster
                      : media.poster),
              media: DrillMedia(
                id: media.playerId,
                videoAsset: media.video,
                posterAsset: alpha ?? media.poster,
                duration: media.loopSeconds,
                posterTime: media.posterSeconds,
                lightVideoAsset: media.lightVideo,
                lightPosterAsset: alpha ?? media.lightPoster,
              ),
            );
          },
          mediaBuilder: (context, request) {
            if (_sessionFinished && !request.paused) {
              _sessionFinished = false;
              if (control?.saveFailed == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) control?.replay();
                });
              }
            }
            _visibleActionId = request.drill.id;
            final exercise = services.library[request.drill.id];
            if (control != null && !control.canPlay) {
              return TrainingPoster(
                key: const ValueKey('training-route-poster'),
                exercise: exercise,
                mirrored: request.mirrored,
                radius: request.theme.radius,
              );
            }
            _log.visibleAction(request.drill.id, paused: request.paused);
            return ExerciseVideo(
              key: const ValueKey('trainer-media'),
              exercise: exercise,
              paused: request.paused || control?.exiting == true,
              mirrored: request.mirrored,
              radius: request.theme.radius,
              playbackHandle: issuePlayback,
              mediaPreparer: request.mediaPreparer,
              training: true,
            );
          },
          voice: services.trainerVoice(),
          onFinished: (result) async {
            _sessionFinished = true;
            _log.finished(result);
            _log.saving();
            try {
              await services.store.saveSession(result);
              _log.saved();
            } on Object catch (error) {
              _log.saveFailed(error);
              control?.exitSaveFailed();
              rethrow;
            }
          },
          onCompleted: (result) async {
            control?.retryExitSave();
            if (result.endedEarly && result.feeling == null) return;
            try {
              await services.recordTrainingCompletion(result);
            } on Object {
              control?.exitSaveFailed();
              rethrow;
            }
          },
          tick: widget.tick,
          notificationIcon: 'drawable/ic_stat_training',
        ),
        if (issuePlayback != null)
          Positioned(
            right: 12,
            top: (MediaQuery.sizeOf(context).height - 48) / 2,
            child: ActionIssueMarkButton(
              key: const ValueKey('player-action-issue'),
              store: issueStore,
              library: services.library,
              playbackHandle: issuePlayback,
              actionIdAtTap: () => _sessionFinished || control?.exiting == true
                  ? null
                  : _visibleActionId,
              iconOnly: true,
            ),
          ),
      ],
    );
  }
}
