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
import 'training_route.dart';

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
  TrainingTransitionMotion? _motion;
  bool _sessionFinished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = TrainingTransitionScope.maybeOf(context);
    if (identical(motion, _motion)) return;
    _motion?.removeListener(_motionChanged);
    _motion = motion;
    motion?.addListener(_motionChanged);
  }

  void _motionChanged() {
    if (!mounted) return;
    if (_motion?.entered == true) {
      _startLog(AppServices.of(context), widget.plan);
    }
    setState(() {});
  }

  void _startLog(AppServices s, TrainingPlan plan) {
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
  }

  String? _audioBeginning() {
    _log.audioBeginning();
    return _log.operation;
  }

  @override
  void dispose() {
    _motion?.removeListener(_motionChanged);
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
    if (_motion == null || _motion!.entered) _startLog(s, plan);
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
          startGate: _motion?.startGate,
          chromeAnimation: _motion?.chrome,
          onExitStarted: _motion?.exitStarted,
          beforeExitPop: _motion?.beforeExitPop,
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
            final motion = _motion;
            if (_sessionFinished && !request.paused) {
              _sessionFinished = false;
              if (motion?.exiting == true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && identical(_motion, motion)) motion?.replay();
                });
              }
            }
            _visibleActionId = request.drill.id;
            final exercise = s.library[request.drill.id];
            motion?.reportMedia(exercise, mirrored: request.mirrored);
            if (motion != null && !motion.canPlay) {
              return SizedBox(
                key: motion.mediaKey,
                child: motion.entered
                    ? TrainingTransitionPoster(
                        key: const ValueKey('training-transition-poster'),
                        exercise: exercise,
                        mirrored: request.mirrored,
                        radius: request.theme.radius,
                      )
                    : motion.reduced
                    ? TrainingTransitionPoster(
                        exercise: exercise,
                        mirrored: request.mirrored,
                      )
                    : TrainingEntranceMedia(
                        motion: motion,
                        exercise: exercise,
                        mirrored: request.mirrored,
                      ),
              );
            }
            _log.visibleAction(request.drill.id, paused: request.paused);
            if (s.voiceOutput
                case final diagnostic_voice.JustAudioVoiceOutput output) {
              output.trainingOperation = _log.operation;
            }
            return SizedBox(
              key: motion?.mediaKey,
              child: ExerciseVideo(
                key: const ValueKey('trainer-media'),
                exercise: s.library[request.drill.id],
                paused: request.paused,
                mirrored: request.mirrored,
                radius: request.theme.radius,
                playbackHandle: issuePlayback,
                mediaPreparer: request.mediaPreparer,
                training: true,
              ),
            );
          },
          voice: s.trainerVoice(),
          onFinished: (result) async {
            _motion?.rememberStage();
            _sessionFinished = true;
            _log.finished(result);
            _log.saving();
            try {
              await s.store.saveSession(result);
              _log.saved();
            } on Object catch (error) {
              _log.saveFailed(error);
              _motion?.exitSaveFailed();
              rethrow;
            }
          },
          onCompleted: (result) async {
            // Confirmed early exit has no completion-page feeling to persist.
            // Its identical receipt was durably saved by onFinished already.
            // A feeling chosen after a failed save still follows the usual path.
            if (result.endedEarly && result.feeling == null) return;
            try {
              await s.recordTrainingCompletion(result);
            } on Object {
              _motion?.exitSaveFailed();
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
            child: _IssueMotion(
              motion: _motion,
              child: ActionIssueMarkButton(
                key: const ValueKey('player-action-issue'),
                store: issueStore,
                library: s.library,
                playbackHandle: issuePlayback,
                actionIdAtTap: () =>
                    (_sessionFinished && _motion?.saveFailed != true) ||
                        (_motion != null &&
                            !_motion!.canPlay &&
                            !_motion!.saveFailed)
                    ? null
                    : _visibleActionId,
                iconOnly: true,
              ),
            ),
          ),
      ],
    );
  }
}

/// Match the SDK transport interval without animating the media stage.
class _IssueMotion extends StatelessWidget {
  const _IssueMotion({required this.motion, required this.child});
  final TrainingTransitionMotion? motion;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final m = motion;
    if (m == null || m.saveFailed) return child;
    return AnimatedBuilder(
      animation: m.chrome,
      child: child,
      builder: (_, child) {
        final phase = const Interval(
          60 / 280,
          260 / 280,
        ).transform(m.chrome.value);
        final t =
            (m.chrome.status == AnimationStatus.reverse
                    ? Curves.easeInCubic
                    : Curves.easeOutCubic)
                .transform(phase);
        return IgnorePointer(
          ignoring: m.chrome.value < 1,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, m.reduced ? 0 : 16 * (1 - t)),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
