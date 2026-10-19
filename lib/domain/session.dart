/// Follow-along session: a TrainingPlan expanded into fixed-length phases,
/// driven by absolute active time (the HipLab SessionEngine design: dropped
/// frames or a throttled timer never drift the count, the next update simply
/// lands in the right phase). Extended here with sets × reps, per-side sets,
/// rests between sets and circuit rounds.
library;

import 'exercise.dart';
import 'plan.dart';

enum PhaseKind { prep, work, switchSide, rest, roundRest, done }

enum Side { right, left }

extension SideZh on Side {
  String get zh => this == Side.right ? '右侧' : '左侧';
}

class SessionPhase {
  const SessionPhase({
    required this.kind,
    required this.seconds,
    this.exerciseId,
    this.item,
    this.itemIndex = -1,
    this.set = 0,
    this.sets = 0,
    this.round = 0,
    this.rounds = 0,
    this.side,
    this.blockName = '',
    this.reps,
    this.repSeconds,
    this.nextExerciseId,
    this.nextItem,
    this.doneExerciseId,
  });

  final PhaseKind kind;
  final double seconds;

  /// The exercise on screen: the one being done, or the upcoming one during
  /// prep / rest.
  final String? exerciseId;
  final PlanItem? item;

  /// Index of the exercise occurrence in play order (for progress / skip).
  final int itemIndex;

  /// 1-based set number and total sets of this item (work / rest phases).
  final int set;
  final int sets;

  /// 1-based circuit round and total rounds (0 when not a circuit).
  final int round;
  final int rounds;
  final Side? side;
  final String blockName;

  /// Reps to count in a work phase (reps mode).
  final int? reps;
  final double? repSeconds;

  /// During rest: what comes next (null when the next set is the same item).
  final String? nextExerciseId;
  final PlanItem? nextItem;

  /// During the rest after an exercise: the one just finished (for "X，完成").
  final String? doneExerciseId;

  bool get isWork => kind == PhaseKind.work;

  @override
  String toString() =>
      '${kind.name} $exerciseId s$set/$sets r$round/$rounds ${side?.name ?? ''} ${seconds.toStringAsFixed(1)}s';
}

/// One occurrence of an item in play order (a circuit repeats its items).
class _Occurrence {
  _Occurrence(this.block, this.item, this.round, this.rounds, this.sets);
  final PlanBlock block;
  final PlanItem item;
  final int round;
  final int rounds;
  final int sets;
}

class SessionBuilder {
  SessionBuilder(this.lib, {this.prepSeconds = 10});
  final ExerciseLibrary lib;
  final int prepSeconds;

  List<_Occurrence> _occurrences(TrainingPlan plan) {
    final out = <_Occurrence>[];
    for (final b in plan.blocks) {
      final circuit = b.type == BlockType.circuit && b.rounds > 1;
      final rounds = circuit ? b.rounds : 1;
      for (var r = 1; r <= rounds; r++) {
        for (final item in b.items) {
          if (!lib.contains(item.exerciseId)) continue;
          out.add(
            _Occurrence(
              b,
              item,
              circuit ? r : 0,
              circuit ? rounds : 0,
              circuit ? 1 : item.sets,
            ),
          );
        }
      }
    }
    return out;
  }

  List<SessionPhase> phases(TrainingPlan plan) {
    final occ = _occurrences(plan);
    final out = <SessionPhase>[];
    if (occ.isEmpty) {
      return [const SessionPhase(kind: PhaseKind.done, seconds: 0)];
    }
    out.add(
      SessionPhase(
        kind: PhaseKind.prep,
        seconds: prepSeconds.toDouble(),
        exerciseId: occ.first.item.exerciseId,
        item: occ.first.item,
        itemIndex: 0,
        sets: occ.first.sets,
        set: 1,
        round: occ.first.round,
        rounds: occ.first.rounds,
        blockName: occ.first.block.name,
      ),
    );
    for (var i = 0; i < occ.length; i++) {
      final o = occ[i];
      final e = lib[o.item.exerciseId];
      final work = o.item.workFor(e);
      for (var s = 1; s <= o.sets; s++) {
        final sides = o.item.perSide ? [Side.right, Side.left] : [null];
        for (var k = 0; k < sides.length; k++) {
          if (k > 0) {
            out.add(
              SessionPhase(
                kind: PhaseKind.switchSide,
                seconds: switchSideSeconds.toDouble(),
                exerciseId: e.id,
                item: o.item,
                itemIndex: i,
                set: s,
                sets: o.sets,
                round: o.round,
                rounds: o.rounds,
                side: sides[k],
                blockName: o.block.name,
              ),
            );
          }
          out.add(
            SessionPhase(
              kind: PhaseKind.work,
              seconds: work,
              exerciseId: e.id,
              item: o.item,
              itemIndex: i,
              set: s,
              sets: o.sets,
              round: o.round,
              rounds: o.rounds,
              side: sides[k],
              blockName: o.block.name,
              reps: o.item.mode == DoseMode.reps ? o.item.reps : null,
              repSeconds: o.item.mode == DoseMode.reps
                  ? e.repSeconds ?? 3
                  : null,
            ),
          );
        }
        if (s < o.sets) {
          out.add(
            SessionPhase(
              kind: PhaseKind.rest,
              seconds: o.item.restSeconds.toDouble(),
              exerciseId: e.id,
              item: o.item,
              itemIndex: i,
              set: s + 1,
              sets: o.sets,
              round: o.round,
              rounds: o.rounds,
              blockName: o.block.name,
            ),
          );
        }
      }
      if (i < occ.length - 1) {
        final n = occ[i + 1];
        final roundBoundary =
            n.block == o.block && n.round != o.round && o.rounds > 0;
        final restLen = roundBoundary
            ? (o.block.restBetweenRoundsSeconds > transitionSeconds
                  ? o.block.restBetweenRoundsSeconds
                  : transitionSeconds)
            : transitionSeconds;
        out.add(
          SessionPhase(
            kind: roundBoundary ? PhaseKind.roundRest : PhaseKind.rest,
            seconds: restLen.toDouble(),
            exerciseId: n.item.exerciseId,
            item: n.item,
            itemIndex: i + 1,
            set: 1,
            sets: n.sets,
            round: n.round,
            rounds: n.rounds,
            blockName: n.block.name,
            nextExerciseId: n.item.exerciseId,
            nextItem: n.item,
            doneExerciseId: o.item.exerciseId,
          ),
        );
      }
    }
    out.add(
      SessionPhase(kind: PhaseKind.done, seconds: 0, itemIndex: occ.length),
    );
    return out;
  }

  /// Total active seconds of the plan, excluding the lead-in.
  double planSeconds(TrainingPlan plan) => phases(
    plan,
  ).where((p) => p.kind != PhaseKind.prep).fold(0.0, (s, p) => s + p.seconds);

  int occurrenceCount(TrainingPlan plan) => _occurrences(plan).length;
}

/// The training clock.
class SessionEngine {
  SessionEngine(List<SessionPhase> phases)
    : _phases = List.unmodifiable(phases);

  final List<SessionPhase> _phases;
  int _index = 0;
  double _phaseStart = 0;
  bool _enteredBySkip = false;
  int? _completedOnEarlyEnd;

  /// Bumped every time the phase changes (for listeners).
  int generation = 0;

  List<SessionPhase> get phases => _phases;
  SessionPhase get phase => _phases[_index];
  int get index => _index;
  bool get done => phase.kind == PhaseKind.done;
  bool get endedEarly => _completedOnEarlyEnd != null;
  double get phaseStart => _phaseStart;
  bool get enteredBySkip => _enteredBySkip;

  double elapsedIn(double t) =>
      (t - _phaseStart).clamp(0, phase.seconds).toDouble();
  double remainingIn(double t) => phase.seconds - elapsedIn(t);
  int secondsLeft(double t) => remainingIn(t).ceil();

  /// Exercise occurrences fully passed (prep 0; a transition rest already
  /// points at the next one, so its index equals the count done).
  int get completedExercises =>
      _completedOnEarlyEnd ?? phase.itemIndex.clamp(0, 1 << 30);

  /// Advance to active time [t]; returns true when the phase changed.
  bool update(double t) {
    var changed = false;
    while (!done && t - _phaseStart >= phase.seconds) {
      _phaseStart += phase.seconds;
      _index++;
      _enteredBySkip = false;
      changed = true;
    }
    if (changed) generation++;
    return changed;
  }

  void _jump(int index, double t) {
    _completedOnEarlyEnd = null;
    _index = index.clamp(0, _phases.length - 1);
    _phaseStart = t;
    _enteredBySkip = true;
    generation++;
  }

  /// 跳过: from prep / rest straight into the next work; from work (any
  /// set or side) to the rest before the next exercise.
  void skip(double t) {
    if (done) return;
    var target = _index + 1;
    if (phase.kind == PhaseKind.work || phase.kind == PhaseKind.switchSide) {
      final cur = phase.itemIndex;
      while (target < _phases.length - 1 && _phases[target].itemIndex <= cur) {
        target++;
      }
    } else {
      while (target < _phases.length - 1 && !_phases[target].isWork) {
        target++;
      }
    }
    _jump(target, t);
  }

  /// 上一个: back to the start of the previous exercise occurrence (or the
  /// start of this one if we are past its first second).
  void previous(double t) {
    final cur = phase.itemIndex;
    var target = _phases.indexWhere(
      (p) => p.itemIndex == (cur - 1).clamp(0, 1 << 30) && p.isWork,
    );
    if (target < 0) target = 0;
    _jump(target, t);
  }

  /// End now, preserving progress instead of counting unvisited exercises.
  void finish(double t) {
    update(t);
    if (done) return;
    final completed = completedExercises;
    _jump(_phases.length - 1, t);
    _completedOnEarlyEnd = completed;
  }
}
