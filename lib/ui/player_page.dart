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
import 'chat/cosmos.dart';
import 'exercise_video.dart';
import 'theme/app_theme.dart';
import 'theme/sf_icons.dart';
import 'theme/tokens.dart';
import 'theme/widgets.dart';

/// Full-screen follow-along: clip, set / side / round, rep counter or
/// countdown, rests with a next-move preview, voice coaching. Drawn in the
/// chat's sky (held still); layout after HipLab's player: top bar, the clip
/// on its stage, the move, the ring, three controls. One accent: the ring
/// while working and the pause / continue disc.
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
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.gutter, 0, SfSpace.gutter, SfSpace.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('哪里不舒服？', style: SfType.title),
              const SizedBox(height: SfSpace.x2),
              Text(
                '出现刺痛、麻木、头晕或胸闷，请立即停止训练。轻微酸胀可以减小幅度、放慢速度。',
                style: SfType.body.copyWith(fontSize: 15, color: SfColors.muted),
              ),
              const SizedBox(height: SfSpace.x5),
              SfSheetOption(
                icon: SfGlyph.pinch,
                label: '减小幅度，继续',
                onTap: () => Navigator.pop(c, 'continue'),
              ),
              SfSheetOption(
                icon: SfGlyph.skipNext,
                label: '跳过这个动作',
                onTap: () => Navigator.pop(c, 'skip'),
              ),
              SfSheetOption(
                icon: SfGlyph.stop,
                color: SfColors.danger,
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
        title: const Text('结束训练？'),
        content: const Text('本次进度会记为未完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('结束', style: TextStyle(color: SfColors.muted, fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('继续练'),
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
      child: AnnotatedRegion(
        value: sfOverlay,
        child: Scaffold(
          backgroundColor: SfColors.skyBottom,
          // The chat's sky, held still: no star drift during a workout.
          body: CosmosBackground(
            animate: false,
            child: SafeArea(child: _engine.done ? _doneView() : _sessionView(p, e)),
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
    final done = _engine.completedExercises;
    final label = switch (p.kind) {
      PhaseKind.prep => '准备 · 第一个动作',
      PhaseKind.rest when p.nextExerciseId != null => '休息 · 下一个动作',
      PhaseKind.rest => '组间休息',
      PhaseKind.roundRest => '这一轮完成 · 休息',
      PhaseKind.switchSide => '换左侧',
      _ => '',
    };
    final sub = _subtitle ?? (rest ? e?.cue : null);
    final current = (done + (rest ? 0 : 1)).clamp(1, _occurrences);
    return Column(
      children: [
        // Top bar: close · block + progress · count.
        Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.gutter, SfSpace.x2),
          child: Row(
            children: [
              SfCircleButton(
                key: const ValueKey('close'),
                tooltip: '关闭训练',
                icon: SfGlyph.close,
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await _confirmClose()) nav.pop();
                },
              ),
              const SizedBox(width: SfSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.blockName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SfType.label.copyWith(color: SfColors.accentText, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: _occurrences == 0 ? 0 : done / _occurrences,
                        minHeight: 4,
                        backgroundColor: SfColors.track,
                        color: SfColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SfSpace.x4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '$current', style: SfType.callout.copyWith(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' / $_occurrences', style: SfType.label),
                ]),
                style: const TextStyle(fontFeatures: SfType.tabular),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.x4, SfSpace.x2),
            children: [
              if (e != null)
                Stack(
                  children: [
                    ExerciseVideo(
                      key: ValueKey('player-${e.id}'),
                      exercise: e,
                      mirrored: p.side == Side.left,
                      paused: _paused,
                      radius: SfRadius.lg,
                    ),
                    if (_paused)
                      const Positioned(left: SfSpace.x3, top: SfSpace.x3, child: SfMediaTag(label: '已暂停'))
                    else if (p.kind == PhaseKind.switchSide)
                      Positioned(
                        left: SfSpace.x3,
                        top: SfSpace.x3,
                        child: SfMediaTag(label: '换左侧', icon: SfGlyph.swap, color: SfColors.palette.isDark ? SfColors.caution : SfPalette.dark.caution),
                      ),
                    Positioned(
                      right: SfSpace.x2,
                      top: SfSpace.x2,
                      child: SfPressable(
                        key: const ValueKey('discomfort'),
                        semanticLabel: '不舒服',
                        onTap: _discomfort,
                        child: Padding(
                          padding: const EdgeInsets.all(SfSpace.x1),
                          child: SfMediaTag(label: '不舒服', icon: SfGlyph.bandage, color: SfPalette.dark.caution),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: SfSpace.x5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (label.isNotEmpty) ...[
                            Text(
                              label,
                              style: SfType.label.copyWith(
                                color: p.kind == PhaseKind.switchSide ? SfColors.caution : SfColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: SfSpace.x1),
                          ],
                          Text(
                            e?.name ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: SfType.title.copyWith(fontSize: 24, height: 1.25),
                          ),
                          const SizedBox(height: 6),
                          Text(_meta(p), style: SfType.label.copyWith(fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(width: SfSpace.x3),
                    _counter(p, left, progress, !rest && p.kind != PhaseKind.switchSide),
                  ],
                ),
              ),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SfSpace.x1, SfSpace.x4, SfSpace.x1, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SfIcon(SfGlyph.subtitles, size: 18, color: SfColors.faint),
                      ),
                      const SizedBox(width: SfSpace.x2),
                      Expanded(
                        child: Text(
                          sub,
                          style: SfType.body.copyWith(fontSize: 15, height: 1.55, color: SfColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!rest) ?_nextUp(p),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(48, SfSpace.x2, 48, SfSpace.x5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SfCircleButton(
                key: const ValueKey('prev'),
                tooltip: '上一个动作',
                icon: SfGlyph.skipPrevious,
                size: 56,
                haptic: SfHaptic.selection,
                onPressed: _previous,
              ),
              SfPressable(
                key: const ValueKey('pause'),
                tooltip: _paused ? '继续训练' : '暂停训练',
                semanticLabel: _paused ? '继续训练' : '暂停训练',
                onTap: _togglePause,
                haptic: SfHaptic.light,
                scale: .94,
                child: Builder(
                  builder: (context) {
                    final down = SfPressedScope.of(context);
                    return AnimatedContainer(
                      duration: down ? SfMotion.press : SfMotion.release,
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: down ? Color.lerp(SfColors.accent, Colors.black, .1) : SfColors.accent,
                      ),
                      child: AnimatedSwitcher(
                        duration: SfMotion.fast,
                        child: SfIcon(
                          _paused ? SfGlyph.play : SfGlyph.pause,
                          key: ValueKey(_paused),
                          size: 32,
                          filled: true,
                          color: SfColors.onAccent,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SfCircleButton(
                key: const ValueKey('skip'),
                tooltip: '跳过动作',
                icon: SfGlyph.skipNext,
                size: 56,
                haptic: SfHaptic.selection,
                onPressed: _skip,
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

  /// While working: the move after this one (HipLab's 下一个 strip).
  Widget? _nextUp(SessionPhase p) {
    final phases = _engine.phases;
    SessionPhase? next;
    for (var i = _engine.index + 1; i < phases.length; i++) {
      final q = phases[i];
      if (q.kind == PhaseKind.work && q.exerciseId != null && q.exerciseId != p.exerciseId) {
        next = q;
        break;
      }
    }
    final e = next == null ? null : _s.library.tryGet(next.exerciseId!);
    if (next == null || e == null) return null;
    final dose = next.item?.copyWith(sets: 1).doseText();
    return Padding(
      padding: const EdgeInsets.only(top: SfSpace.x6),
      child: SfPanel(
        padding: const EdgeInsets.all(SfSpace.x2),
        radius: SfRadius.md + 2,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(SfRadius.sm - 2),
              child: SizedBox.square(
                dimension: 44,
                child: ColoredBox(
                  color: SfColors.mediaStage,
                  child: Image.asset(e.media.poster, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
            ),
            const SizedBox(width: SfSpace.x3),
            Text('下一个', style: SfType.label),
            const SizedBox(width: SfSpace.x2),
            Expanded(
              child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.callout),
            ),
            if (dose != null) ...[
              const SizedBox(width: SfSpace.x2),
              Text(dose, style: SfType.label),
            ],
            const SizedBox(width: SfSpace.x2),
          ],
        ),
      ),
    );
  }

  /// Reps or seconds inside a ring. The ring is the accent only while
  /// working; prep / rest count down in a neutral tone.
  Widget _counter(SessionPhase p, int left, double progress, bool working) {
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
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: SfColors.track,
              color: working ? SfColors.accent : SfColors.text.withValues(alpha: .55),
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
                  color: SfColors.text,
                  fontFeatures: SfType.tabular,
                ),
              ),
              Text(small, style: SfType.caption.copyWith(color: SfColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doneView() {
    final full =
        !_engine.endedEarly && _engine.completedExercises >= _occurrences;
    final minutes = ((_endedAt ?? _t) / 60).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(SfSpace.x6, 0, SfSpace.x6, SfSpace.x5),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: full ? SfColors.accentSoft : SfColors.surfaceHigh,
                      ),
                      alignment: Alignment.center,
                      child: SfIcon(
                        full ? SfGlyph.check : SfGlyph.stop,
                        size: 38,
                        strokeWidth: 2.2,
                        color: full ? SfColors.accentText : SfColors.muted,
                      ),
                    ),
                    const SizedBox(height: SfSpace.x6),
                    Text(full ? '训练完成！' : '今天先到这里', style: SfType.display),
                    const SizedBox(height: SfSpace.x2),
                    Text(
                      widget.plan.title,
                      textAlign: TextAlign.center,
                      style: SfType.body.copyWith(color: SfColors.muted),
                    ),
                    const SizedBox(height: SfSpace.x8),
                    Row(
                      children: [
                        Expanded(child: _stat('$minutes', '分钟')),
                        const SizedBox(width: SfSpace.x3),
                        Expanded(child: _stat('${_engine.completedExercises}/$_occurrences', '完成动作')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SfPrimaryButton(
            key: const ValueKey('finish'),
            label: '完成',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => SfPanel(
    padding: const EdgeInsets.symmetric(vertical: SfSpace.x4),
    radius: SfRadius.md + 2,
    child: Column(
      children: [
        Text(
          value,
          style: SfType.title.copyWith(fontSize: 26, fontFeatures: SfType.tabular),
        ),
        const SizedBox(height: 2),
        Text(label, style: SfType.label),
      ],
    ),
  );
}
