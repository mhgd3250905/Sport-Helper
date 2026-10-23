import 'dart:async';

import 'package:ugk_trainer/ugk_trainer.dart';

import 'runtime_log.dart';

/// App-owned observations of the shared player. Heartbeats are explicitly wall
/// time; the authoritative active clock is reported by SessionResult at end.
class TrainingLog {
  TrainingLog({RuntimeLog? log}) : _log = log ?? RuntimeLog.instance;

  final RuntimeLog _log;
  String? _operation;
  Timer? _heartbeat;
  final _wall = Stopwatch();
  String? _action;
  bool? _paused;
  bool _finished = false;
  int _actionCount = 0;
  bool _voice = false;
  bool _chimes = false;

  String? get operation => _operation;

  void start({
    required int actionCount,
    required bool voice,
    required bool chimes,
  }) {
    if (_operation != null || !_log.enabled) return;
    _actionCount = actionCount;
    _voice = voice;
    _chimes = chimes;
    _begin();
  }

  void _begin({bool replayed = false}) {
    _operation = _log.newOperation('training');
    _finished = false;
    _action = null;
    _paused = null;
    _wall
      ..reset()
      ..start();
    _record('training.started', {
      'count': _actionCount,
      'voice': _voice,
      'chimes': _chimes,
      if (replayed) 'reason': 'replayed',
    });
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _record('training.heartbeat.wall', {
        'elapsedMs': _wall.elapsedMilliseconds,
        if (_paused != null) 'paused': _paused,
        if (_action != null) 'actionId': _action,
      });
    });
  }

  /// The shared player passes its actual pause state to the media builder.
  /// The visible action may also be the upcoming action during prep/rest.
  void visibleAction(String actionId, {required bool paused}) {
    if (_operation == null) return;
    // The completed shared player renders no media. A new media request after
    // completion therefore marks its built-in replay, including voice-off mode.
    if (_finished) _begin(replayed: true);
    if (_action != actionId) {
      _action = actionId;
      _record('training.action.visible', {'actionId': actionId});
    }
    if (_paused != null && _paused != paused) {
      _record(paused ? 'training.paused' : 'training.resumed', {
        'paused': paused,
        'elapsedMs': _wall.elapsedMilliseconds,
      });
    }
    _paused = paused;
  }

  /// Audio can start before the first replay media build.
  void audioBeginning() {
    if (_operation != null && _finished) _begin(replayed: true);
  }

  void finished(SessionResult result) {
    if (_operation == null || _finished) return;
    _finished = true;
    _heartbeat?.cancel();
    _wall.stop();
    _record('training.finished', {
      'status': result.endedEarly ? 'ended_early' : 'completed',
      'completed': result.completedExercises,
      'total': result.totalExercises,
      'durationMs': (result.activeSeconds * 1000).round(),
      'elapsedMs': _wall.elapsedMilliseconds,
      'success': result.full,
    });
  }

  void saving() => _record('training.result.save_started', {});
  void saved() => _record('training.result.saved', {'success': true});
  void saveFailed(Object error) => _record('training.result.save_failed', {
    'errorType': RuntimeLog.errorType(error),
  });

  void _record(String event, Map<String, Object?> fields) {
    if (_operation == null) return;
    _log.record(event, fields: fields, operation: _operation);
  }

  void dispose() {
    _heartbeat?.cancel();
    _wall.stop();
    _record('training.player.closed', {
      'status': _finished ? 'finished' : 'route_closed',
    });
  }
}
