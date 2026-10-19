import 'dart:async';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../core/platform/screen_awake.dart';
import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import '../voice/session_runner.dart';
import '../voice/voice_cue.dart';
import '../voice/voice_queue.dart';
import 'exercise_video.dart';
import 'theme.dart';

/// Full-screen follow-along: clip, set / side / round, rep counter or
/// countdown, rests with a next-move preview, voice coaching.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.plan,
    this.tick = const Duration(milliseconds: 100),
  });
  final TrainingPlan plan;
  final Duration tick;
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _clock = Stopwatch();
  late AppServices _s;
  late SessionRunner _runner;
  late VoiceQueue _queue;
  late int _occurrences;
  Timer? _timer;
  StreamSubscription<AudioInterruption>? _interruptions;
  bool _ready = false;
  bool _recorded = false;
  double? _endedAt;
  String? _subtitle;
  int _shownSecond = -1;
  int _shownGen = -1;

  double get _t => _clock.elapsedMicroseconds / 1e6;
  bool get _paused => !_clock.isRunning;
  SessionEngine get _engine => _runner.engine;
  SessionPhase get _phase => _engine.phase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    _s = AppServices.of(context);
    final builder = SessionBuilder(_s.library);
    _occurrences = builder.occurrenceCount(widget.plan);
    _runner = SessionRunner(
      SessionEngine(builder.phases(widget.plan)),
      _s.script(),
    );
    _queue = _s.voiceQueue();
    final v = _s.store.voice;
    if (v.voice || v.chimes) unawaited(_s.voiceOutput.begin());
    if (_s.voiceOutput case final InterruptibleVoiceOutput out) {
      _interruptions = out.interruptions.listen(_onInterruption);
    }
    ScreenAwake.acquire();
    _clock.start();
    _timer = Timer.periodic(widget.tick, (_) => _tick());
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_interruptions?.cancel());
    if (_ready) {
      ScreenAwake.release();
      _queue.cancelAll(_t);
      unawaited(_s.voiceOutput.end());
    }
    super.dispose();
  }

  void _tick() {
    if (!mounted || (_paused && !_engine.done)) return;
    final t = _t;
    for (final f in _runner.update(t)) {
      _queue.submit(f.cue, t);
      if (f.cue.subtitle != null) _subtitle = f.cue.subtitle;
    }
    _queue.tick(t);
    if (_engine.generation != _shownGen && _phase.kind != PhaseKind.work) {
      _subtitle = null;
    }
    if (_engine.done) {
      _endedAt ??= t;
      _record();
    }
    final sec = (_engine.elapsedIn(t) * 4).floor(); // 4 Hz repaint is plenty
    if (sec != _shownSecond || _engine.generation != _shownGen) {
      setState(() {
        _shownSecond = sec;
        _shownGen = _engine.generation;
      });
    }
  }

  void _record() {
    if (_recorded) return;
    _recorded = true;
    _s.store.addHistory(
      HistoryEntry(
        title: widget.plan.title,
        at: DateTime.now(),
        minutes: ((_endedAt ?? _t) / 60).round(),
        completed: _engine.completedExercises,
        total: _occurrences,
      ),
    );
  }

  void _onInterruption(AudioInterruption e) {
    if (!mounted || _engine.done || e == AudioInterruption.ended || _paused) {
      return;
    }
    _queue.cancelAll(_t);
    _clock.stop();
    setState(() {});
  }

  void _togglePause() {
    if (_paused) {
      if (_s.voiceOutput case final InterruptibleVoiceOutput out) {
        unawaited(out.reactivate());
      }
      _clock.start();
      _queue.submit(const VoiceCue(0, ['p.resume'], CuePriority.call), _t);
    } else {
      _queue.cancelAll(_t);
      _queue.submit(const VoiceCue(0, ['p.paused'], CuePriority.call), _t);
      _clock.stop();
    }
    setState(() {});
  }

  void _skip() {
    _queue.cancelAll(_t);
    _runner.skip(_t);
    _subtitle = null;
    _tick();
    setState(() {});
  }

  void _previous() {
    _queue.cancelAll(_t);
    _runner.previous(_t);
    _subtitle = null;
    _tick();
    setState(() {});
  }

  Future<void> _endEarly() async {
    _queue.cancelAll(_t);
    _runner.finish(_t);
    _endedAt ??= _t;
    _clock.stop();
    _record();
    setState(() {});
  }

  Future<void> _discomfort() async {
    final wasRunning = !_paused;
    if (wasRunning) _togglePause();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SfColors.surface,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '哪里不舒服？',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '出现刺痛、麻木、头晕或胸闷，请立即停止训练。轻微酸胀可以减小幅度、放慢速度。',
                style: TextStyle(color: SfColors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.compress_rounded),
                title: const Text('减小幅度，继续'),
                onTap: () => Navigator.pop(c, 'continue'),
              ),
              ListTile(
                leading: const Icon(Icons.skip_next_rounded),
                title: const Text('跳过这个动作'),
                onTap: () => Navigator.pop(c, 'skip'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.stop_circle_outlined,
                  color: SfColors.warn,
                ),
                title: const Text('结束今天的训练'),
                onTap: () => Navigator.pop(c, 'end'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'skip':
        if (wasRunning) _togglePause();
        _skip();
      case 'end':
        await _endEarly();
      default:
        if (wasRunning) _togglePause();
    }
  }

  Future<bool> _confirmClose() async {
    if (_engine.done) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('结束训练？'),
        content: const Text('本次进度会记为未完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续练'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (ok == true) _record();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final lib = _s.library;
    final p = _phase;
    final e = p.exerciseId == null ? null : lib.tryGet(p.exerciseId!);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmClose()) nav.pop();
      },
      child: Scaffold(
        body: SafeArea(child: _engine.done ? _doneView() : _sessionView(p, e)),
      ),
    );
  }

  Widget _sessionView(SessionPhase p, Exercise? e) {
    final t = _t;
    final left = _engine.secondsLeft(t);
    final progress = p.seconds == 0
        ? 0.0
        : (_engine.elapsedIn(t) / p.seconds).clamp(0.0, 1.0);
    final rest =
        p.kind == PhaseKind.rest ||
        p.kind == PhaseKind.roundRest ||
        p.kind == PhaseKind.prep;
    final color = rest ? SfColors.rest : SfColors.accent;
    final done = _engine.completedExercises;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('close'),
                tooltip: '关闭训练',
                icon: const Icon(Icons.close_rounded),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await _confirmClose()) nav.pop();
                },
              ),
              Expanded(
                child: Text(
                  '${p.blockName}  ·  动作 ${(done + (rest ? 0 : 1)).clamp(1, _occurrences)}/$_occurrences',
                  style: const TextStyle(color: SfColors.muted),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('discomfort'),
                onPressed: _discomfort,
                icon: const Icon(
                  Icons.healing_outlined,
                  size: 18,
                  color: SfColors.warn,
                ),
                label: const Text(
                  '不舒服',
                  style: TextStyle(color: SfColors.warn),
                ),
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: _occurrences == 0 ? 0 : done / _occurrences,
          minHeight: 3,
          backgroundColor: SfColors.surface2,
          color: SfColors.accent,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              if (e != null)
                ExerciseVideo(
                  key: ValueKey('player-${e.id}'),
                  exercise: e,
                  mirrored: p.side == Side.left,
                  paused: _paused,
                ),
              const SizedBox(height: 12),
              Text(switch (p.kind) {
                PhaseKind.prep => '准备 · 第一个动作',
                PhaseKind.rest when p.nextExerciseId != null => '休息 · 下一个动作',
                PhaseKind.rest => '组间休息',
                PhaseKind.roundRest => '这一轮完成 · 休息',
                PhaseKind.switchSide => '换左侧',
                _ => '',
              }, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              Text(
                e?.name ?? '',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _meta(p),
                style: const TextStyle(color: SfColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Center(child: _counter(p, left, progress, color)),
              const SizedBox(height: 14),
              if ((_subtitle ?? (rest ? e?.cue : null)) case final sub?)
                Text(
                  '要领：$sub',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('prev'),
                tooltip: '上一个动作',
                iconSize: 28,
                onPressed: _previous,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton.filled(
                key: const ValueKey('pause'),
                tooltip: _paused ? '继续训练' : '暂停训练',
                iconSize: 40,
                style: IconButton.styleFrom(backgroundColor: SfColors.accent),
                onPressed: _togglePause,
                icon: Icon(
                  _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
              ),
              IconButton.filledTonal(
                key: const ValueKey('skip'),
                tooltip: '跳过动作',
                iconSize: 28,
                onPressed: _skip,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _meta(SessionPhase p) {
    final parts = <String>[];
    if (p.rounds > 0) parts.add('第 ${p.round}/${p.rounds} 轮');
    if (p.sets > 1) parts.add('第 ${p.set}/${p.sets} 组');
    if (p.side != null) parts.add(p.side!.zh);
    final item = p.item;
    if (item != null) parts.add(item.copyWith(sets: 1).doseText());
    return parts.join(' · ');
  }

  Widget _counter(SessionPhase p, int left, double progress, Color color) {
    final reps = p.reps;
    String big;
    String small;
    if (p.isWork && reps != null) {
      final rep = p.repSeconds ?? 3;
      final cur = (_engine.elapsedIn(_t) / rep).floor() + 1;
      big = '${cur.clamp(1, reps)}';
      small = '/ $reps 次';
    } else {
      big = '$left';
      small = p.isWork ? '秒' : '秒后开始';
    }
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 8,
              backgroundColor: SfColors.surface2,
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                big,
                key: const ValueKey('counter'),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(small, style: const TextStyle(color: SfColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doneView() {
    final full =
        !_engine.endedEarly && _engine.completedExercises >= _occurrences;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            full ? Icons.emoji_events_rounded : Icons.flag_rounded,
            size: 72,
            color: full ? SfColors.accent : SfColors.warn,
          ),
          const SizedBox(height: 16),
          Text(
            full ? '训练完成！' : '今天先到这里',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.plan.title} · ${((_endedAt ?? _t) / 60).round()} 分钟 · 完成 ${_engine.completedExercises}/$_occurrences 个动作',
            textAlign: TextAlign.center,
            style: const TextStyle(color: SfColors.muted),
          ),
          const SizedBox(height: 28),
          FilledButton(
            key: const ValueKey('finish'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}
