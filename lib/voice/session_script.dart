/// What the coach says in each session phase. Lines are built only from
/// pre-recorded clips (assets/voice/zh, tools/voice/build_voice.py): fixed
/// phrases, numbers 1–60, exercise names (`ex.<id>`) and key points
/// (`cue.<id>`). A plan from any generator can be voiced as long as it only
/// references library ids — no runtime TTS.
library;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import 'voice_cue.dart';
import 'voice_library.dart';

class SessionScript {
  SessionScript({required this.lib, required this.exercises, this.lang = 'zh'});

  final VoiceLibrary lib;
  final ExerciseLibrary exercises;
  final String lang;

  double _len(List<String> clips) => lib.total(clips, lang: lang);

  static List<String> number(int n) =>
      n >= 1 && n <= 60 ? ['n.$n'] : const [];

  /// "3 组，每侧 12 次" as clips.
  static List<String> dose(PlanItem i, {bool withSets = true}) => [
    if (withSets && i.sets > 1) ...[...number(i.sets), 'u.sets'],
    if (i.perSide) 'p.per_side',
    if (i.mode == DoseMode.reps) ...[...number(i.reps ?? 10), 'u.reps']
    else ...[...number(i.workSeconds ?? 30), 'u.sec'],
  ];

  /// Lines one after another from [start], dropping what would run past
  /// [until] (the countdown owns the last seconds).
  List<VoiceCue> _sequence(
    double start,
    double until,
    List<(List<String>, CuePriority)> lines,
  ) {
    final out = <VoiceCue>[];
    var t = start;
    for (final (clips, prio) in lines) {
      if (clips.isEmpty) continue;
      final len = _len(clips);
      if (t + len > until) break;
      out.add(VoiceCue(t, clips, prio, subtitle: _subtitle(clips)));
      t += len + .35;
    }
    return out;
  }

  String? _subtitle(List<String> clips) {
    for (final c in clips) {
      if (c.startsWith('cue.')) return lib.line(c, lang: 'zh');
    }
    return null;
  }

  List<VoiceCue> _countdown(double end, {int from = 3}) => [
    for (var k = from; k >= 1; k--)
      if (end - k > 0.5)
        VoiceCue(end - k, ['chime.tick', 'n.$k'], CuePriority.count),
  ];

  List<VoiceCue> cues(SessionPhase p, {required double planSeconds, bool bySkip = false}) {
    final e = p.exerciseId == null ? null : exercises.tryGet(p.exerciseId!);
    switch (p.kind) {
      case PhaseKind.prep:
        final minutes = (planSeconds / 60).round().clamp(1, 60);
        return [
          ..._sequence(0, p.seconds - 3.3, [
            (['p.welcome', 'p.total', ...number(minutes), 'u.min'], CuePriority.info),
            if (e != null && p.item != null)
              (['p.first', 'ex.${e.id}', ...dose(p.item!)], CuePriority.info),
          ]),
          ..._countdown(p.seconds),
        ];
      case PhaseKind.work:
        return _work(p, e);
      case PhaseKind.switchSide:
        return [
          const VoiceCue(0, ['chime.end', 'p.switch_left'], CuePriority.call),
          ..._countdown(p.seconds),
        ];
      case PhaseKind.rest:
      case PhaseKind.roundRest:
        final rest = p.seconds.round();
        final head = <String>[
          'chime.end',
          if (p.kind == PhaseKind.roundRest) 'p.round_done' else if (!bySkip) 'p.nice',
          'p.rest',
          ...number(rest),
          'u.sec',
        ];
        final next = p.nextExerciseId != null && e != null && p.item != null;
        final List<(List<String>, CuePriority)> lines = [
          (head, CuePriority.call),
          if (p.kind == PhaseKind.roundRest && p.round > 0)
            (['p.di', ...number(p.round), 'u.rounds'], CuePriority.info),
          if (next) (['p.next', 'ex.${e.id}', ...dose(p.item!, withSets: p.rounds == 0)], CuePriority.info)
          else if (p.set == p.sets && p.sets > 1) (['p.last_set'], CuePriority.info)
          else if (p.sets > 1) (['p.di', ...number(p.set), 'u.sets'], CuePriority.info),
          if (next) (['cue.${e.id}'], CuePriority.coach),
        ];
        return [..._sequence(0, p.seconds - 3.3, lines), ..._countdown(p.seconds)];
      case PhaseKind.done:
        return const [
          VoiceCue(0, ['chime.finish', 'p.finish'], CuePriority.call),
        ];
    }
  }

  List<VoiceCue> _work(SessionPhase p, Exercise? e) {
    final w = p.seconds;
    final firstSide = p.side == Side.right;
    final go = firstSide ? 'p.go_right' : 'p.go';
    final out = <VoiceCue>[VoiceCue(0, ['chime.start', go], CuePriority.call)];
    final busy = _len([go]) + .3;
    final reps = p.reps;
    final rep = p.repSeconds ?? 3;
    if (reps != null) {
      // Count each rep on its beat (the clip's own tempo).
      if (rep >= 1.6) {
        for (var k = 1; k <= reps; k++) {
          final at = k * rep - .45;
          if (at < busy) continue;
          out.add(VoiceCue(at, number(k), CuePriority.count));
        }
      }
      if (reps >= 6 && rep * 2 > busy + _len(['p.slow']) + .3 && rep < 1.6) {
        out.add(VoiceCue(busy, const ['p.slow'], CuePriority.coach));
      }
      return out;
    }
    // Timed hold / flow.
    if (e != null && w >= 20) {
      out.add(VoiceCue(busy, ['cue.${e.id}'], CuePriority.coach,
          subtitle: lib.line('cue.${e.id}', lang: 'zh')));
    }
    if (w >= 40) out.add(VoiceCue(w / 2, const ['p.half'], CuePriority.info));
    if (w >= 25) out.add(VoiceCue(w - 10, const ['p.ten_left'], CuePriority.call));
    out.addAll(_countdown(w));
    return out;
  }
}
