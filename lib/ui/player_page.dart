import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../domain/plan.dart';
import '../domain/session.dart' show trainerPlan, trainerRhythms;
import '../diagnostics/training_log.dart';
import '../voice/just_audio_output.dart' as diagnostic_voice;
import 'chat/cosmos.dart';
import 'exercise_video.dart';
import 'theme/celebration.dart';
import 'theme/glass.dart';
import 'theme/tokens.dart';

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    final plan = widget.plan;
    if (plan.items.any((item) => !s.library.contains(item.exerciseId))) {
      return const Scaffold(
        body: SafeArea(child: Center(child: Text('计划包含尚未可用的动作，暂时无法开始。'))),
      );
    }
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
    final p = SfColors.palette;
    return CosmosBackground(
      animate: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SfGlassField(player: true),
          TrainerPlayer(
            plan: trainerPlan(plan),
            rhythms: trainerRhythms(s.library),
            strings: TrainerStrings.zh(),
            theme: TrainerTheme(
              brightness: p.brightness,
              background: Colors.transparent,
              surface: p.surface,
              surfaceHigh: p.surfaceHigh,
              track: p.track,
              accent: p.accent,
              accentText: p.accentText,
              onAccent: p.onAccent,
              text: p.text,
              muted: p.muted,
              faint: p.faint,
              caution: p.caution,
              danger: p.danger,
              mediaStage: p.mediaStage,
              scrim: p.scrim,
              fontFamily: sfFontFamily,
            ),
            drillOf: (id) {
              final e = s.library.tryGet(id);
              if (e == null) return null;
              final m = e.media;
              return TrainerDrill(
                id: id,
                name: e.name,
                cue: e.cue,
                media: DrillMedia(
                  id: m.playerId,
                  videoAsset: m.video,
                  posterAsset: m.poster,
                  duration: m.loopSeconds,
                  posterTime: m.posterSeconds,
                  lightVideoAsset: m.lightVideo,
                  lightPosterAsset: m.lightPoster,
                ),
              );
            },
            mediaBuilder: (context, request) {
              _log.visibleAction(request.drill.id, paused: request.paused);
              if (s.voiceOutput
                  case final diagnostic_voice.JustAudioVoiceOutput output) {
                output.trainingOperation = _log.operation;
              }
              return ExerciseVideo(
                key: ValueKey('trainer-media-${request.drill.id}'),
                exercise: s.library[request.drill.id],
                paused: request.paused,
                mirrored: request.mirrored,
                radius: request.theme.radius,
              );
            },
            voice: s.trainerVoice(),
            onFinished: (result) async {
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
        ],
      ),
    );
  }
}
