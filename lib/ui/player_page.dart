import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../domain/plan.dart';
import '../domain/session.dart' show trainerPlan, trainerRhythms;
import '../diagnostics/training_log.dart';
import '../voice/just_audio_output.dart' as diagnostic_voice;
import 'chat/cosmos.dart';
import 'action_issue_actions.dart';
import 'alpha_artwork.dart';
import 'exercise_video.dart';
import 'theme/celebration.dart';
import 'theme/trainer_theme.dart';
import 'theme.dart';

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
    final preparer = s.poseHubPreparer;
    if (preparer != null) {
      final actions = [
        for (final id in plan.exerciseIds.toSet())
          ?s.poseHubCatalog?.tryGet(id),
      ];
      if (actions.isNotEmpty) {
        return _PlanMediaPreflight(
          key: ValueKey((
            plan.id,
            preparer,
            actions.map((a) => a.id).join(','),
          )),
          actions: actions,
          preparer: preparer,
          player: () => _player(context, s, plan),
        );
      }
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
    return CosmosBackground(
      animate: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TrainerPlayer(
            plan: trainerPlan(plan),
            rhythms: trainerRhythms(s.library),
            strings: TrainerStrings.zh(),
            theme: SmartFitTrainerTheme.of(context),
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
            feedbackBuilder: (context, result) => SfFinishTimeline(
              full: result.full,
              child: SfFinishReveal(
                beginMs: 420,
                child: SfFinishMark(full: result.full),
              ),
            ),
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
      ),
    );
  }
}

/// TrainerPlayer has no public readiness/pause hook. Prepare only this plan's
/// referenced actions before mounting its clock, including subsequent actions.
class _PlanMediaPreflight extends StatefulWidget {
  const _PlanMediaPreflight({
    super.key,
    required this.actions,
    required this.preparer,
    required this.player,
  });
  final List<coach.PoseHubPackAction> actions;
  final PoseHubMediaPreparer preparer;
  final Widget Function() player;
  @override
  State<_PlanMediaPreflight> createState() => _PlanMediaPreflightState();
}

class _PlanMediaPreflightState extends State<_PlanMediaPreflight>
    with WidgetsBindingObserver {
  final _preparation = PoseHubMediaPreparationController();
  var _index = 0;
  var _complete = false;
  var _started = false;
  var _foreground = true;
  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _preparation.addListener(_changed);
    _prepare();
  }

  void _prepare() =>
      _preparation.start(widget.preparer, widget.actions[_index]);
  void _changed() {
    if (!mounted) return;
    if (_preparation.state.status == PoseHubMediaPreparationStatus.ready) {
      if (_index + 1 < widget.actions.length) {
        _index++;
        _prepare();
        return;
      }
      _complete = true;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preparation.removeListener(_changed);
    _preparation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_complete && _foreground && TickerMode.valuesOf(context).enabled) {
      _started = true;
    }
    if (_started) return widget.player();
    return Scaffold(
      appBar: const SfTopBar(title: '准备训练'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(SfSpace.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '本次计划 ${_index + 1} / ${widget.actions.length} · ${widget.actions[_index].nameZh}',
                key: const ValueKey('posehub-plan-preflight'),
                style: SfType.callout,
              ),
              const SizedBox(height: SfSpace.x4),
              PoseHubMediaPreparationPanel(
                state: _preparation.state,
                theme: SmartFitTrainerTheme.of(context),
                onRetry: _prepare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
