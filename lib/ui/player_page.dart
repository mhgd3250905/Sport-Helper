import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

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
import 'training_entry_placeholder.dart';

/// App styling, assets and storage injected into the shared training player.
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
  Animation<double>? _routeAnimation;
  bool _entered = false;
  bool _sessionFinished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) {
      if (animation == null) _entered = true;
      return;
    }
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
    _routeAnimation = animation;
    _entered =
        animation == null ||
        (ModalRoute.of(context)?.offstage == false &&
            animation.status == AnimationStatus.completed);
    animation?.addStatusListener(_routeStatusChanged);
  }

  void _routeStatusChanged(AnimationStatus status) {
    if (!mounted) return;
    setState(() {
      if (status == AnimationStatus.completed &&
          ModalRoute.of(context)?.offstage == false) {
        _entered = true;
      }
    });
  }

  String? _audioBeginning() {
    _log.audioBeginning();
    return _log.operation;
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatusChanged);
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
    final s = AppServices.of(context);
    final plan = widget.plan;
    // Hero pre-layout makes ModalRoute.animation temporarily report completed
    // while the page is offstage, before its actual 320ms entrance starts.
    // A zero-duration route may leave that pre-layout without a status change.
    final route = ModalRoute.of(context);
    if (!_entered &&
        (route == null ||
            (!route.offstage &&
                route.animation?.status == AnimationStatus.completed))) {
      _entered = true;
    }
    if (plan.exerciseIds.any((id) => !s.library.contains(id))) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('计划包含尚未可用的动作，暂时无法开始。'))),
      );
    }
    if (!_entered) {
      final phases = session.SessionBuilder(s.library).phases(plan);
      final first = phases.firstOrNull?.exerciseId;
      return first == null
          ? Scaffold(
              backgroundColor: SmartFitTrainerTheme.of(context).mediaStage,
            )
          : TrainingEntryPlaceholder(
              key: const ValueKey('training-entry-placeholder'),
              exercise: s.library[first],
            );
    }
    return _player(context, s, plan);
  }

  Widget _player(BuildContext context, AppServices s, TrainingPlan plan) {
    _log.start(
      actionCount: plan.items.length,
      voice: s.store.voice.voice,
      chimes: s.store.voice.chimes,
    );
    if (s.voiceOutput case final diagnostic_voice.JustAudioVoiceOutput output) {
      _voiceOutput = output;
      output.beforeSessionBegin = _audioBeginning;
      output.trainingOperation = _log.operation;
    }
    final issueStore = s.store.actionIssueStore;
    final issuePlayback = issueStore.enabled
        ? (_issuePlayback ??= DrillMediaPlaybackHandle())
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        TrainerPlayer(
          plan: session.trainerPlan(plan),
          startMode: TrainerStartMode.training,
          rhythms: session.trainerRhythms(s.library),
          strings: TrainerStrings.zh(),
          theme: SmartFitTrainerTheme.of(context),
          poseHubActionOf: s.poseHubCatalog?.tryGet,
          poseHubMediaBaseUri: s.poseHubMedia?.mediaBaseUri,
          poseHubMediaPreparer: s.poseHubPreparer,
          drillOf: (id) {
            final e = s.library.tryGet(id);
            if (e == null) return null;
            final m = e.media;
            final alphaThumb = SfAlphaCards.enabledOf(context)
                ? m.alphaThumbnail
                : null;
            return TrainerDrill(
              id: id,
              name: e.name,
              cue: e.cue,
              cues: e.cues,
              precautions: e.cautions,
              targetMuscles: e.muscles.join('、'),
              equipment: e.effectiveEquipmentIds.isEmpty
                  ? '徒手'
                  : e.effectiveEquipmentIds.map(equipmentLabel).join('、'),
              thumbnailAsset:
                  alphaThumb ??
                  (Theme.of(context).brightness == Brightness.light
                      ? m.lightPoster ?? m.poster
                      : m.poster),
              media: DrillMedia(
                id: m.playerId,
                videoAsset: m.video,
                posterAsset: alphaThumb ?? m.poster,
                duration: m.loopSeconds,
                posterTime: m.posterSeconds,
                lightVideoAsset: m.lightVideo,
                lightPosterAsset: alphaThumb ?? m.lightPoster,
              ),
            );
          },
          mediaBuilder: (context, request) {
            // The SDK keeps requesting its paused last frame while an early
            // exit is saving. That frame must not reopen App-owned issue UI
            // above the navigator whose pending receipt will shortly pop.
            if (_sessionFinished && !request.paused) _sessionFinished = false;
            _visibleActionId = _sessionFinished ? null : request.drill.id;
            final animation = ModalRoute.of(context)?.animation;
            if (animation != null &&
                animation.status != AnimationStatus.completed) {
              return TrainingTransitionPoster(
                key: const ValueKey('training-transition-poster'),
                exercise: s.library[request.drill.id],
                mirrored: request.mirrored,
                radius: request.theme.radius,
              );
            }
            _log.visibleAction(request.drill.id, paused: request.paused);
            if (s.voiceOutput
                case final diagnostic_voice.JustAudioVoiceOutput output) {
              output.trainingOperation = _log.operation;
            }
            return ExerciseVideo(
              key: const ValueKey('trainer-media'),
              exercise: s.library[request.drill.id],
              paused: request.paused,
              mirrored: request.mirrored,
              radius: request.theme.radius,
              playbackHandle: issuePlayback,
              mediaPreparer: request.mediaPreparer,
              training: true,
            );
          },
          voice: s.trainerVoice(),
          onFinished: (result) async {
            _sessionFinished = true;
            _visibleActionId = null;
            _log.finished(result);
            _log.saving();
            try {
              await s.store.saveSession(result);
              _log.saved();
            } on Object catch (error) {
              _log.saveFailed(error);
              rethrow;
            }
          },
          onCompleted: (result) async {
            // Confirmed early exit has no completion-page feeling to persist.
            // Its identical receipt was durably saved by onFinished already.
            // A feeling chosen after a failed save still follows the usual path.
            if (result.endedEarly && result.feeling == null) return;
            await s.recordTrainingCompletion(result);
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
              library: s.library,
              playbackHandle: issuePlayback,
              actionIdAtTap: () =>
                  _sessionFinished ||
                      (_routeAnimation?.status ?? AnimationStatus.completed) !=
                          AnimationStatus.completed
                  ? null
                  : _visibleActionId,
              iconOnly: true,
            ),
          ),
      ],
    );
  }
}
