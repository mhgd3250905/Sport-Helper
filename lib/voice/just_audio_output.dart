import 'dart:async';

import 'package:ugk_trainer/ugk_trainer.dart' as trainer;

import '../diagnostics/runtime_log.dart';

/// Diagnostics around the shared audio implementation, retaining its queue,
/// interruption, focus and disposal behavior. A request settling is not proof
/// that the speaker produced sound.
class JustAudioVoiceOutput extends trainer.JustAudioVoiceOutput {
  JustAudioVoiceOutput({super.keepAliveAsset});

  String? trainingOperation;
  String? Function()? beforeSessionBegin;
  String? _audioOperation;
  String? _lineOperation;
  bool _numberLine = false;
  int _numberRequests = 0;
  int _numberLoads = 0;
  int _numberSettled = 0;
  int _chimes = 0;
  Timer? _summary;

  RuntimeLog get _log => RuntimeLog.instance;
  String? get _operation => trainingOperation ?? _audioOperation;

  void _record(String event, [Map<String, Object?> fields = const {}]) =>
      _log.record(event, fields: fields, operation: _operation);

  @override
  Future<void> begin() {
    if (_log.enabled) {
      trainingOperation = beforeSessionBegin?.call() ?? trainingOperation;
      _audioOperation = _log.newOperation('audio');
      // Bind replay before the shared player's first new media callback.
      // The audio operation also distinguishes repeated audio sessions.
      _record('voice.session.begin_requested', {
        'operationId': _audioOperation,
      });
      _summary ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _sample(),
      );
    }
    return super.begin();
  }

  @override
  Stream<trainer.AudioInterruption> get interruptions =>
      super.interruptions.map((event) {
        _record('voice.interruption', {'kind': event.name});
        return event;
      });

  @override
  Future<void> reactivate() {
    _record('voice.session.reactivate_requested');
    return super.reactivate();
  }

  static bool _numbersOnly(List<String> assets) =>
      assets.isNotEmpty &&
      assets.every((asset) => RegExp(r'/n\.\d+\.(m4a|mp3)$').hasMatch(asset));

  @override
  Future<void> speak(List<String> assets) {
    if (!_log.enabled) return super.speak(assets);
    if (_numbersOnly(assets)) {
      _numberRequests++;
    } else {
      _record('voice.line.requested', {'count': assets.length});
    }
    return super.speak(assets);
  }

  @override
  Future<void> loadVoice(List<String> assets) async {
    if (!_log.enabled) return super.loadVoice(assets);
    final operation = _log.newOperation('voice');
    final numbers = _numbersOnly(assets);
    final watch = Stopwatch()..start();
    _lineOperation = operation;
    _numberLine = numbers;
    if (!numbers) {
      _record('voice.load.started', {
        'operationId': operation,
        'count': assets.length,
      });
    }
    try {
      await super.loadVoice(assets);
      if (numbers) _numberLoads++;
      if (!numbers ||
          watch.elapsedMilliseconds > trainer.JustAudioVoiceOutput.slowLoadMs) {
        _record('voice.load.completed', {
          'operationId': operation,
          'kind': numbers ? 'number' : 'line',
          'elapsedMs': watch.elapsedMilliseconds,
        });
      }
    } on Object catch (error) {
      _record('voice.load.failed', {
        'operationId': operation,
        'elapsedMs': watch.elapsedMilliseconds,
        'errorType': RuntimeLog.errorType(error),
      });
      rethrow;
    }
  }

  @override
  Future<void> playVoiceToEnd() async {
    if (!_log.enabled) return super.playVoiceToEnd();
    final operation = _lineOperation;
    final numbers = _numberLine;
    final watch = Stopwatch()..start();
    if (!numbers) {
      _record('voice.playback.requested', {'operationId': operation});
    }
    try {
      await super.playVoiceToEnd();
      if (numbers) {
        _numberSettled++;
      } else {
        _record('voice.playback.settled', {
          'operationId': operation,
          'elapsedMs': watch.elapsedMilliseconds,
        });
      }
    } on Object catch (error) {
      _record('voice.playback.failed', {
        'operationId': operation,
        'errorType': RuntimeLog.errorType(error),
      });
      rethrow;
    }
  }

  @override
  Future<void> stopSpeech() {
    _record('voice.speech.stop_requested');
    return super.stopSpeech();
  }

  @override
  Future<void> chime(String asset) {
    if (_log.enabled) _chimes++;
    return super.chime(asset);
  }

  void _sample() {
    if (_numberRequests + _numberLoads + _numberSettled + _chimes == 0) return;
    _record('voice.counts.summary', {
      'count': _numberRequests,
      'completed': _numberLoads,
      'total': _numberSettled,
      'chimes': _chimes,
    });
    _numberRequests = _numberLoads = _numberSettled = _chimes = 0;
  }

  @override
  Future<void> end() {
    _summary?.cancel();
    _summary = null;
    _sample();
    _record('voice.session.end_requested');
    return super.end();
  }
}
