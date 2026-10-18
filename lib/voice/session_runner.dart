import '../domain/session.dart';
import 'session_script.dart';
import 'voice_cue.dart';

/// Something the session wants said now.
class FiredCue {
  const FiredCue(this.time, this.cue);
  final double time;
  final VoiceCue cue;
}

/// [SessionEngine] + [SessionScript]: advances the clock and returns the
/// cues that fell due. Stale cues (after a long background stretch) are
/// dropped instead of read out late — the HipLab tolerance rule.
class SessionRunner {
  SessionRunner(this.engine, this.script)
    : planSeconds = engine.phases
          .where((p) => p.kind != PhaseKind.prep)
          .fold(0.0, (s, p) => s + p.seconds) {
    _load();
  }

  final SessionEngine engine;
  final SessionScript script;
  final double planSeconds;
  List<VoiceCue> _cues = const [];
  final Set<int> _fired = {};
  int _gen = -1;

  static double _tolerance(VoiceCue c) => switch (c.priority) {
    CuePriority.count => .6,
    CuePriority.call => 1.5,
    CuePriority.info => 2.5,
    CuePriority.coach => 2.0,
  };

  void _load() {
    _gen = engine.generation;
    _cues = script.cues(
      engine.phase,
      planSeconds: planSeconds,
      bySkip: engine.enteredBySkip,
    );
    _fired.clear();
  }

  List<FiredCue> update(double t) {
    final out = <FiredCue>[];
    engine.update(t);
    // Several phases may have passed (background): only the current one speaks.
    if (engine.generation != _gen) _load();
    final local = t - engine.phaseStart;
    for (var i = 0; i < _cues.length; i++) {
      final c = _cues[i];
      if (_fired.contains(i) || c.at > local + 1e-9) continue;
      _fired.add(i);
      if (local - c.at <= _tolerance(c)) {
        out.add(FiredCue(engine.phaseStart + c.at, c));
      }
    }
    return out;
  }

  void skip(double t) {
    engine.skip(t);
    _load();
  }

  void previous(double t) {
    engine.previous(t);
    _load();
  }

  void finish(double t) {
    engine.finish(t);
    _load();
  }
}
