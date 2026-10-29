import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../domain/exercise.dart' show equipmentLabel;
import '../domain/plan.dart';
import '../domain/session.dart' show trainerPlan, trainerRhythms;
import '../diagnostics/training_log.dart';
import '../voice/just_audio_output.dart' as diagnostic_voice;
import 'action_issue_actions.dart';
import 'alpha_artwork.dart';
import 'exercise_video.dart';
import 'theme/trainer_theme.dart';

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
    final s = AppServices.of(context);
    final plan = widget.plan;
    if (plan.exerciseIds.any((id) => !s.library.contains(id))) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('计划包含尚未可用的动作，暂时无法开始。'))),
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
          plan: trainerPlan(plan),
          startMode: TrainerStartMode.training,
          rhythms: trainerRhythms(s.library),
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
            _visibleActionId = request.drill.id;
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
            );
          },
          voice: s.trainerVoice(),
          onFinished: (result) async {
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
          onCompleted: s.recordTrainingCompletion,
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
              actionIdAtTap: () => _visibleActionId,
              iconOnly: true,
            ),
          ),
      ],
    );
  }
}
