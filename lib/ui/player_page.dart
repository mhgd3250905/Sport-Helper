import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../core/platform/screen_awake.dart';
import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import '../voice/session_runner.dart';
import '../voice/voice_cue.dart';
import '../voice/voice_queue.dart';
import 'chat/cosmos.dart';
import 'chat/glass.dart';
import 'exercise_video.dart';

/// Full-screen follow-along: clip, set / side / round, rep counter or
/// countdown, rests with a next-move preview, voice coaching. Drawn in the
/// chat's sky (held still) with glass panels; the clip itself is never
/// blurred or tinted.
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
      backgroundColor: const Color(0xF5121733),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: CosmosColors.edge, width: .7),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '哪里不舒服？',
                style: TextStyle(color: CosmosColors.text, fontSize: 19, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                '出现刺痛、麻木、头晕或胸闷，请立即停止训练。轻微酸胀可以减小幅度、放慢速度。',
                style: TextStyle(color: CosmosColors.muted, height: 1.55, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _SheetOption(
                icon: Icons.compress_rounded,
                label: '减小幅度，继续',
                onTap: () => Navigator.pop(c, 'continue'),
              ),
              _SheetOption(
                icon: Icons.skip_next_rounded,
                label: '跳过这个动作',
                onTap: () => Navigator.pop(c, 'skip'),
              ),
              _SheetOption(
                icon: Icons.stop_circle_outlined,
                color: CosmosColors.warn,
                label: '结束今天的训练',
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
        backgroundColor: const Color(0xFF151A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: CosmosColors.edge, width: .7),
        ),
        title: const Text('结束训练？', style: TextStyle(color: CosmosColors.text)),
        content: const Text('本次进度会记为未完成。', style: TextStyle(color: CosmosColors.textSoft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续练'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('结束', style: TextStyle(color: CosmosColors.muted)),
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: CosmosColors.skyBottom,
        ),
        child: Scaffold(
          backgroundColor: CosmosColors.skyBottom,
          // The chat's sky, held still: no star drift during a workout.
          body: CosmosBackground(
            animate: false,
            child: SafeArea(
              child: BackdropGroup(
                child: _engine.done ? _doneView() : _sessionView(p, e),
              ),
            ),
          ),
        ),
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
    final color = rest ? CosmosColors.rest : CosmosColors.accent;
    final done = _engine.completedExercises;
    final label = switch (p.kind) {
      PhaseKind.prep => '准备 · 第一个动作',
      PhaseKind.rest when p.nextExerciseId != null => '休息 · 下一个动作',
      PhaseKind.rest => '组间休息',
      PhaseKind.roundRest => '这一轮完成 · 休息',
      PhaseKind.switchSide => '换左侧',
      _ => '',
    };
    final labelColor = p.kind == PhaseKind.switchSide ? CosmosColors.warn : color;
    final sub = _subtitle ?? (rest ? e?.cue : null);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _RoundGlassButton(
                key: const ValueKey('close'),
                tooltip: '关闭训练',
                icon: Icons.close_rounded,
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await _confirmClose()) nav.pop();
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Glass(
                  radius: BorderRadius.circular(22),
                  padding: const EdgeInsets.fromLTRB(16, 9, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${p.blockName}  ·  动作 ${(done + (rest ? 0 : 1)).clamp(1, _occurrences)}/$_occurrences',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CosmosColors.textSoft, fontSize: 13, height: 1.3),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _occurrences == 0 ? 0 : done / _occurrences,
                          minHeight: 3,
                          backgroundColor: CosmosColors.track,
                          color: CosmosColors.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Glass(
                radius: BorderRadius.circular(22),
                child: InkWell(
                  key: const ValueKey('discomfort'),
                  onTap: _discomfort,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.healing_outlined, size: 18, color: CosmosColors.warn),
                        SizedBox(width: 6),
                        Text('不舒服', style: TextStyle(color: CosmosColors.warn, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              if (e != null)
                // The clip stays sharp: a plain frame (no blur) around it.
                Glass(
                  blur: 0,
                  radius: BorderRadius.circular(26),
                  padding: const EdgeInsets.all(5),
                  child: Stack(
                    children: [
                      ExerciseVideo(
                        key: ValueKey('player-${e.id}'),
                        exercise: e,
                        mirrored: p.side == Side.left,
                        paused: _paused,
                        radius: 21,
                      ),
                      if (_paused)
                        const Positioned(left: 12, top: 12, child: _Badge('已暂停')),
                      if (p.kind == PhaseKind.switchSide)
                        const Positioned(right: 12, top: 12, child: _Badge('换左侧', color: CosmosColors.warn)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Glass(
                radius: BorderRadius.circular(24),
                padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (label.isNotEmpty) ...[
                                Text(
                                  label,
                                  style: TextStyle(color: labelColor, fontSize: 13.5, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                e?.name ?? '',
                                style: const TextStyle(
                                  color: CosmosColors.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _meta(p),
                                style: const TextStyle(color: CosmosColors.muted, fontSize: 14, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _counter(p, left, progress, color),
                      ],
                    ),
                    if (sub != null) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1, thickness: .6, color: CosmosColors.edge),
                      ),
                      Text(
                        '要领：$sub',
                        style: const TextStyle(color: CosmosColors.textSoft, fontSize: 14.5, height: 1.55),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 4, 40, 14),
          child: Glass(
            radius: BorderRadius.circular(44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundGlassButton(
                  key: const ValueKey('prev'),
                  tooltip: '上一个动作',
                  icon: Icons.skip_previous_rounded,
                  size: 52,
                  iconSize: 28,
                  onPressed: _previous,
                ),
                Tooltip(
                  message: _paused ? '继续训练' : '暂停训练',
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x55FF7A45), blurRadius: 22, spreadRadius: -4)],
                    ),
                    child: Material(
                      color: CosmosColors.accent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('pause'),
                        onTap: _togglePause,
                        child: SizedBox.square(
                          dimension: 68,
                          child: Icon(
                            _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                            size: 38,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _RoundGlassButton(
                  key: const ValueKey('skip'),
                  tooltip: '跳过动作',
                  icon: Icons.skip_next_rounded,
                  size: 52,
                  iconSize: 28,
                  onPressed: _skip,
                ),
              ],
            ),
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
      width: 116,
      height: 116,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: CosmosColors.track,
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
                  fontSize: 40,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(small, style: const TextStyle(color: CosmosColors.muted, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doneView() {
    final full =
        !_engine.endedEarly && _engine.completedExercises >= _occurrences;
    final tone = full ? CosmosColors.accent : CosmosColors.warn;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Glass(
          radius: BorderRadius.circular(28),
          glow: const Color(0x14BFD0FF),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: .14),
                  border: Border.all(color: tone.withValues(alpha: .4), width: .7),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Icon(
                    full ? Icons.emoji_events_rounded : Icons.flag_rounded,
                    size: 44,
                    color: tone,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                full ? '训练完成！' : '今天先到这里',
                style: const TextStyle(color: CosmosColors.text, fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.plan.title} · ${((_endedAt ?? _t) / 60).round()} 分钟 · 完成 ${_engine.completedExercises}/$_occurrences 个动作',
                textAlign: TextAlign.center,
                style: const TextStyle(color: CosmosColors.muted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('finish'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CosmosColors.accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round glass button (close, previous, skip).
class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 46,
    this.iconSize = 22,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Glass(
      radius: BorderRadius.circular(size / 2),
      tint: CosmosColors.glassHi,
      child: InkResponse(
        onTap: onPressed,
        radius: size / 2,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: iconSize, color: CosmosColors.text),
        ),
      ),
    ),
  );
}

/// A small dark glass label over the clip (已暂停 / 换左侧).
class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.color = CosmosColors.text});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xB3070A16),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: CosmosColors.edge, width: .7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w500)),
    ),
  );
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: Icon(icon, color: color ?? CosmosColors.textSoft),
    title: Text(label, style: TextStyle(color: color ?? CosmosColors.text, fontSize: 15.5)),
    onTap: onTap,
  );
}
