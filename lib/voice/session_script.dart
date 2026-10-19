/// What the coach says in each session phase, built only from pre-recorded
/// drill-pack clips (docs/drill-pack-spec.md): each move's own lines
/// (`<id>/intro`, `<id>/cue1…3`, `<id>/side_switch`, `<id>/rest`,
/// `<id>/finish`) and the shared `_common` pack (calls, units, counts 1–60,
/// chimes). A plan from any generator can be voiced as long as it only
/// references pack ids — no runtime TTS.
///
/// Timing (docs/voice-audit-2026-10-19.md §4): every phase gets one timeline.
/// Fixed-time calls go in first (start, half way, ten seconds left, each rep
/// count, the 3-2-1 countdown). Flexible lines (preview, intro, key points,
/// rest tips) are then placed, in order, only into gaps they fit *whole*,
/// using each clip's decoded length — so two lines never overlap and a long
/// line is never cut by the countdown. A line that does not fit is replaced
/// by its shorter alternative or left out.
library;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import 'voice_cue.dart';
import 'voice_library.dart';

/// Silence kept between two lines.
const lineGap = .35;

/// Extra room before the countdown (audio session activation / loading can
/// start a line a little late).
const countdownMargin = .5;

/// Room before the next rep count when a key point is spoken between two
/// counts (a line that started late must still end before the count, which
/// would otherwise cut it).
const repGapAfter = .6;

class SessionScript {
  SessionScript({required this.lib, required this.exercises, this.lang = 'zh'});

  final VoiceLibrary lib;
  final ExerciseLibrary exercises;
  final String lang;

  double len(List<String> clips) => lib.total(clips, lang: lang);

  static List<String> number(int n) =>
      n >= 1 && n <= 60 ? ['n.$n'] : const [];

  /// "3 组，每侧 12 次" as clips.
  static List<String> dose(PlanItem i, {bool withSets = true}) => [
    if (withSets && i.sets > 1) ...[...number(i.sets), 'u.sets'],
    if (i.perSide) 'p.per_side',
    if (i.mode == DoseMode.reps) ...[...number(i.reps ?? 10), 'u.reps']
    else ...[...number(i.workSeconds ?? 30), 'u.sec'],
  ];

  /// A move's own line key, or null when its pack has no such clip.
  String? own(String exerciseId, String lineId) {
    final k = VoiceLibrary.lineKey(exerciseId, lineId);
    return lib.has(k, lang: lang) ? k : null;
  }

  List<String> cueKeys(String exerciseId) => [
    for (var k = 1; k <= 3; k++) ?own(exerciseId, 'cue$k'),
  ];

  String? _subtitle(List<String> clips) {
    for (final c in clips) {
      if (c.contains('/')) {
        final role = c.substring(c.indexOf('/') + 1);
        if (role != 'name' && role != 'finish') return lib.line(c, lang: lang);
      }
    }
    return null;
  }

  _Timeline _timeline(double seconds, {bool countdown = true}) => _Timeline(
    this,
    limit: countdown ? seconds - 3 - countdownMargin : seconds,
  );

  List<VoiceCue> _countdown(double end, {int from = 3}) => [
    for (var k = from; k >= 1; k--)
      if (end - k > 0.5)
        VoiceCue(end - k, ['chime.tick', 'n.$k'], CuePriority.count),
  ];

  /// "下一个动作，`intro`，`dose`" with shorter fall-backs.
  List<List<String>> _preview(String lead, String id, PlanItem item, {bool withSets = true}) {
    final d = dose(item, withSets: withSets);
    final intro = own(id, 'intro');
    final name = own(id, 'name');
    return [
      if (intro != null) [lead, intro, ...d],
      if (name != null) [lead, name, ...d],
      if (intro != null) [lead, intro],
      if (name != null) [lead, name],
    ];
  }

  List<VoiceCue> cues(SessionPhase p, {required double planSeconds, bool bySkip = false}) {
    final e = p.exerciseId == null ? null : exercises.tryGet(p.exerciseId!);
    switch (p.kind) {
      case PhaseKind.prep:
        final minutes = (planSeconds / 60).round().clamp(1, 60);
        final t = _timeline(p.seconds)..fixAll(_countdown(p.seconds));
        t.place([['p.welcome', 'p.total', ...number(minutes), 'u.min']], CuePriority.info);
        if (e != null && p.item != null) {
          t.place(_preview('p.first', e.id, p.item!), CuePriority.info);
          final c = cueKeys(e.id);
          if (c.isNotEmpty) t.place([[c.first]], CuePriority.coach);
        }
        return t.cues;
      case PhaseKind.work:
        return _work(p, e);
      case PhaseKind.switchSide:
        return [
          const VoiceCue(0, ['chime.end', 'p.switch_left'], CuePriority.call),
          ..._countdown(p.seconds),
        ];
      case PhaseKind.rest:
      case PhaseKind.roundRest:
        return _rest(p, e, bySkip);
      case PhaseKind.done:
        return const [
          VoiceCue(0, ['chime.finish', 'p.finish'], CuePriority.call),
        ];
    }
  }

  List<VoiceCue> _rest(SessionPhase p, Exercise? e, bool bySkip) {
    final rest = p.seconds.round();
    final t = _timeline(p.seconds)..fixAll(_countdown(p.seconds));
    final tail = ['p.rest', ...number(rest), 'u.sec'];
    final done = p.doneExerciseId == null || bySkip ? null : own(p.doneExerciseId!, 'finish');
    t.place([
      if (p.kind == PhaseKind.roundRest) ['chime.end', 'p.round_done', ...tail]
      else ...[
        if (done != null) ['chime.end', done, ...tail],
        ['chime.end', if (!bySkip) 'p.nice', ...tail],
      ],
    ], CuePriority.call);
    if (p.kind == PhaseKind.roundRest && p.round > 0) {
      t.place([['p.di', ...number(p.round), 'u.rounds']], CuePriority.info);
    }
    final next = p.nextExerciseId != null && e != null && p.item != null;
    if (next) {
      // Before a new move: what it is, how much, then its first key point.
      // Prefer the short preview when only that leaves room for the point.
      final previews = _preview('p.next', e.id, p.item!, withSets: p.rounds == 0);
      final cues = cueKeys(e.id);
      // The dose matters more than the point: never drop it to make room.
      final withDose = previews.where((pv) => pv.length > 2).toList();
      final placed = cues.isNotEmpty &&
          t.placeGroup([
            for (final pv in withDose.isEmpty ? previews : withDose)
              [(pv, CuePriority.info), ([cues.first], CuePriority.coach)],
          ]);
      if (!placed) t.place(previews, CuePriority.info);
      if (placed && cues.length > 1) t.place([[cues[1]]], CuePriority.coach);
    } else if (e != null) {
      // Between sets of the same move: which set, then the move's rest tip.
      if (p.set == p.sets && p.sets > 1) {
        t.place([['p.last_set']], CuePriority.info);
      } else if (p.sets > 1) {
        t.place([['p.di', ...number(p.set), 'u.sets']], CuePriority.info);
      }
      // The move's rest tip lands shortly before the next set starts.
      final tip = own(e.id, 'rest');
      final cues = cueKeys(e.id);
      for (final line in [
        ?(tip == null ? null : [tip]),
        if (cues.isNotEmpty) [cues.last],
      ]) {
        if (t.place([line], CuePriority.coach, from: t.limit - len(line) - 1.5)) break;
      }
    }
    return t.cues;
  }

  /// Key points for this side: on the second side the move's own
  /// side_switch line takes the place of the primary point.
  List<String> _sideLines(SessionPhase p, Exercise e) {
    final c = cueKeys(e.id);
    final sw = p.side == Side.left ? own(e.id, 'side_switch') : null;
    if (sw == null) return c;
    return [sw, ...c.skip(1)];
  }

  List<VoiceCue> _work(SessionPhase p, Exercise? e) {
    final w = p.seconds;
    final firstSide = p.side == Side.right;
    final go = firstSide ? 'p.go_right' : 'p.go';
    final reps = p.reps;
    final rep = p.repSeconds ?? 3;
    if (reps != null) {
      final t = _Timeline(this, limit: w)
        ..fix(VoiceCue(0, ['chime.start', go], CuePriority.call));
      // Count each rep on its beat (the clip's own tempo).
      if (rep >= 1.6) {
        for (var k = 1; k <= reps; k++) {
          // The last count must also finish inside the set.
          final at = (k * rep - .45).clamp(0.0, w - len(number(k)) - .05);
          if (at < len([go]) + .3 || at >= w) continue;
          t.fix(VoiceCue(at, number(k), CuePriority.count));
        }
      } else if (reps >= 6) {
        t.place([['p.slow']], CuePriority.coach);
      }
      // One key point per set, only where it fits whole between two counts.
      if (e != null) {
        final lines = _sideLines(p, e);
        if (lines.isNotEmpty) {
          // The preview before the move already said the first point, so set
          // 1 takes the second one, set 2 the third… (second side: side_switch).
          final pick = p.side == Side.left
              ? lines.first
              : lines[p.set.clamp(0, 99) % lines.length];
          // This set's point, else the shortest one that fits between counts.
          final others = [...lines]
            ..remove(pick)
            ..sort((a, b) => len([a]).compareTo(len([b])));
          t.place(
            [[pick], for (final o in others) [o]],
            CuePriority.coach,
            gapAfter: repGapAfter,
          );
        }
      }
      return t.cues;
    }
    // Timed hold / flow.
    final t = _timeline(w)
      ..fix(VoiceCue(0, ['chime.start', go], CuePriority.call))
      ..fixAll(_countdown(w));
    if (w >= 40) t.fix(VoiceCue(w / 2, const ['p.half'], CuePriority.info));
    if (w >= 25) t.fix(VoiceCue(w - 10, const ['p.ten_left'], CuePriority.call));
    if (e != null) {
      final lines = _sideLines(p, e);
      // Spread the key points over the hold instead of reading them back to back.
      final start = len([go]) + lineGap;
      final span = (t.limit - start).clamp(0, 1e9);
      for (var k = 0; k < lines.length; k++) {
        t.place([[lines[k]]], CuePriority.coach, from: start + span * k / lines.length);
      }
    }
    return t.cues;
  }
}

/// One phase's lines with their real lengths; nothing ever overlaps.
class _Timeline {
  _Timeline(this.script, {required this.limit});

  final SessionScript script;

  /// Flexible lines must end by this time (phase-local seconds).
  final double limit;
  final _taken = <(double, double)>[];
  final _cues = <VoiceCue>[];

  /// Where the next flexible line may start (keeps spoken order).
  double _cursor = 0;

  List<VoiceCue> get cues => [..._cues]..sort((a, b) => a.at.compareTo(b.at));

  double _len(VoiceCue c) => script.len(c.clips);

  void fix(VoiceCue c) {
    _cues.add(c);
    _taken.add((c.at, c.at + _len(c)));
  }

  void fixAll(Iterable<VoiceCue> cs) => cs.forEach(fix);

  bool _free(double a, double b, double before, double after) {
    for (final (s, e) in _taken) {
      if (a < e + before && b + after > s) return false;
    }
    return true;
  }

  /// Place the first alternative that fits whole at or after [from], with
  /// [gap] of silence before it and [gapAfter] (default [gap]) before
  /// whatever follows; returns false when none fits.
  bool place(
    List<List<String>> alternatives,
    CuePriority priority, {
    double from = 0,
    double gap = lineGap,
    double? gapAfter,
  }) {
    final after = gapAfter ?? gap;
    for (final clips in alternatives) {
      if (clips.isEmpty) continue;
      final l = script.len(clips);
      final earliest = from > _cursor ? from : _cursor;
      final starts = <double>[
        earliest,
        for (final (_, e) in _taken)
          if (e + gap > earliest) e + gap,
      ]..sort();
      for (final s in starts) {
        if (s + l > limit) break;
        if (_free(s, s + l, gap, after)) {
          _cues.add(VoiceCue(s, clips, priority, subtitle: script._subtitle(clips)));
          _taken.add((s, s + l));
          _cursor = s + l + lineGap;
          return true;
        }
      }
    }
    return false;
  }

  /// Try each option (lines said one after another); keep the first option
  /// whose lines all fit, otherwise change nothing.
  bool placeGroup(List<List<(List<String>, CuePriority)>> options) {
    for (final option in options) {
      final taken = [..._taken], cues = [..._cues], cursor = _cursor;
      if (option.every((line) => place([line.$1], line.$2))) return true;
      _taken
        ..clear()
        ..addAll(taken);
      _cues
        ..clear()
        ..addAll(cues);
      _cursor = cursor;
    }
    return false;
  }
}
