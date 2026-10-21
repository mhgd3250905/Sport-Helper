import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../domain/plan.dart';
import '../domain/session.dart' show trainerPlan, trainerRhythms;
import 'chat/cosmos.dart';
import 'exercise_video.dart';
import 'theme/celebration.dart';
import 'theme/glass.dart';
import 'theme/tokens.dart';

/// App styling, assets and storage injected into the shared training player.
class PlayerPage extends StatelessWidget {
  const PlayerPage({
    super.key,
    required this.plan,
    this.tick = const Duration(milliseconds: 50),
  });
  final TrainingPlan plan;
  final Duration tick;

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
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
            mediaBuilder: (context, request) => ExerciseVideo(
              key: ValueKey('trainer-media-${request.drill.id}'),
              exercise: s.library[request.drill.id],
              paused: request.paused,
              mirrored: request.mirrored,
              radius: request.theme.radius,
            ),
            voice: s.trainerVoice(),
            onFinished: s.store.saveSession,
            feedbackBuilder: (context, result) => SfFinishTimeline(
              full: result.full,
              child: SfFinishReveal(
                beginMs: 420,
                child: SfFinishMark(full: result.full),
              ),
            ),
            tick: tick,
            notificationIcon: 'drawable/ic_stat_training',
          ),
        ],
      ),
    );
  }
}
