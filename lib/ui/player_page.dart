import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
import 'theme/celebration.dart';
import 'theme/countdown.dart';
import 'theme/glass.dart';
import 'theme/media_theme.dart';
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
    this.tick = const Duration(milliseconds: 50),
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
  int _shownGen = -1;

  /// What the page shows that changes with time (seconds left / rep,
  /// phase): the page rebuilds only when this changes, about once a
  /// second; the ring follows [_progress] on its own.
  String _shownKey = '';
  int _hapticSecond = -1;
  int _hapticGen = -1;

  /// The ring's fill, updated every [PlayerPage.tick] (50 ms): only the
  /// ring's painter listens (HipLab: the 33 ms timer repaints the ring,
  /// not the page).
  final _progress = ValueNotifier<double>(0);

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
    _progress.dispose();
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
    final p = _phase;
    _syncProgress(t);
    _haptics(p, t);
    final key = '${_engine.generation}:${_engine.done}:${_counterValue(p, t)}:${_subtitle ?? ''}';
    if (key != _shownKey || _engine.generation != _shownGen) {
      setState(() {
        _shownKey = key;
        _shownGen = _engine.generation;
      });
    }
  }

  /// A medium tap as a working set begins; a selection tick on each of
  /// the last three seconds of a timed phase (M12, M13).
  void _haptics(SessionPhase p, double t) {
    if (_engine.done || _paused) return;
    if (_engine.generation != _hapticGen) {
      _hapticGen = _engine.generation;
      _hapticSecond = -1;
      if (p.isWork && _engine.generation > 0) SfHaptic.medium.play();
    }
    if (p.seconds == 0 || (p.isWork && p.reps != null)) return;
    final left = _engine.secondsLeft(t);
    if (left >= 1 && left <= 3 && left != _hapticSecond) {
      _hapticSecond = left;
      SfHaptic.selection.play();
    }
  }

  /// The big number in the ring: the rep (rep sets) or seconds left.
  String _counterValue(SessionPhase p, double t) {
    final reps = p.reps;
    if (p.isWork && reps != null) {
      final rep = p.repSeconds ?? 3;
      final cur = (_engine.elapsedIn(t) / rep).floor() + 1;
      return '${cur.clamp(1, reps)}';
    }
    return '${_engine.secondsLeft(t)}';
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

  /// Sets the ring to the current phase's fill. [_tick] does this while
  /// running; a manual skip/back while paused calls it too, so the ring
  /// follows the new phase without resuming the clock.
  void _syncProgress(double t) {
    if (_engine.done) return;
    final p = _phase;
    _progress.value = p.seconds == 0 ? 0.0 : (_engine.elapsedIn(t) / p.seconds).clamp(0.0, 1.0);
  }

  void _skip() {
    _queue.cancelAll(_t);
    _runner.skip(_t);
    _subtitle = null;
    _syncProgress(_t);
    _tick();
    setState(() {});
  }

  void _previous() {
    _queue.cancelAll(_t);
    _runner.previous(_t);
    _subtitle = null;
    _syncProgress(_t);
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
      sheetAnimationStyle: SfMotion.sheet,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // A quieter colour field than the chat's, for the glass
                // controls to refract (the video stays the hero).
                const SfGlassField(player: true),
                SafeArea(child: _engine.done ? _doneView() : _sessionView(p, e)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sessionView(SessionPhase p, Exercise? e) {
    final t = _t;
    final still = SfMotion.reduced(context);
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
    final fraction = _occurrences == 0 ? 0.0 : done / _occurrences;
    // Liquid glass budget on the player (docs/liquid-glass-plan.md §4): the
    // close disc, the progress capsule, 不舒服, 下一个 and the control
    // capsule, all ≤ standard quality, sharing one backdrop read where the
    // engine allows it.
    return GlassBackdropGroup(
      child: Column(
      children: [
        // Top bar: close · block + progress · count.
        Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.gutter, SfSpace.x2),
          child: Row(
            children: [
              SfGlassSurface(
                width: 44,
                height: 44,
                quality: SfGlass.overMedia,
                child: SfCircleButton(
                  key: const ValueKey('close'),
                  tooltip: '关闭训练',
                  icon: SfGlyph.close,
                  fill: Colors.transparent,
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    if (await _confirmClose()) nav.pop();
                  },
                ),
              ),
              const SizedBox(width: SfSpace.x3),
              Expanded(
                child: SfGlassSurface(
                  radius: 22,
                  height: 44,
                  quality: SfGlass.overMedia,
                  padding: const EdgeInsets.symmetric(horizontal: SfSpace.x4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SfFadeSwitcher(
                      duration: SfMotion.fast,
                      rise: 0,
                      child: Text(
                        p.blockName,
                        key: ValueKey(p.blockName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SfType.label.copyWith(color: SfColors.accentText, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // M15: the bar eases to the new share instead of jumping.
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: fraction),
                      duration: still ? Duration.zero : SfMotion.slow,
                      curve: SfMotion.standard,
                      builder: (_, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          backgroundColor: SfColors.track,
                          color: SfColors.accent,
                        ),
                      ),
                    ),
                  ],
                        ),
                      ),
                      const SizedBox(width: SfSpace.x3),
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
                    // M13: one move's clip cross-fades into the next.
                    AnimatedSwitcher(
                      duration: SfMotion.slow,
                      switchInCurve: SfMotion.standard,
                      switchOutCurve: Curves.easeIn,
                      layoutBuilder: (current, previous) => Stack(children: [...previous, ?current]),
                      child: ExerciseVideo(
                        key: ValueKey('player-${e.id}'),
                        exercise: e,
                        mirrored: p.side == Side.left,
                        paused: _paused,
                        radius: SfRadius.lg,
                      ),
                    ),
                    Positioned(
                      left: SfSpace.x3,
                      top: SfSpace.x3,
                      child: SfFadeSwitcher(
                        duration: SfMotion.fast,
                        rise: 0,
                        child: _paused
                            ? const SfMediaTag(key: ValueKey('tag-paused'), label: '已暂停')
                            : p.kind == PhaseKind.switchSide
                            ? SfMediaTag(
                                key: const ValueKey('tag-side'),
                                label: '换左侧',
                                icon: SfGlyph.swap,
                                color: SfPalette.dark.caution,
                              )
                            : rest && p.nextExerciseId != null
                            ? const SfMediaTag(key: ValueKey('tag-next'), label: '下一个')
                            : const SizedBox.shrink(key: ValueKey('tag-none')),
                      ),
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
                          // The one glass surface over the video.
                          child: SfGlassSurface(
                            radius: 16,
                            height: 32,
                            quality: SfGlass.overMedia,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SfIcon(SfGlyph.bandage, size: 15, filled: true, color: SfColors.caution),
                                const SizedBox(width: 6),
                                Text(
                                  '不舒服',
                                  style: TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: SfColors.text),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: SfSpace.x5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
                // Fixed slots (H4): the phase label always has its line, the
                // ring sets the row height, so changing phase only changes
                // what is written, never where.
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: _labelSlot,
                            child: SfFadeSwitcher(
                              duration: SfMotion.fast,
                              rise: 0,
                              child: Text(
                                label,
                                key: ValueKey('label-$label'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: SfType.label.copyWith(
                                  color: p.kind == PhaseKind.switchSide ? SfColors.caution : SfColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SfFadeSwitcher(
                            child: Text(
                              e?.name ?? '',
                              key: ValueKey('name-${e?.id}'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SfType.title.copyWith(fontSize: 24, height: 1.25, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SfFadeSwitcher(
                            duration: SfMotion.fast,
                            rise: 0,
                            child: Text(_meta(p), key: ValueKey('meta-${_meta(p)}'), style: SfType.label.copyWith(fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SfSpace.x3),
                    _counter(p, t, working: !rest && p.kind != PhaseKind.switchSide),
                  ],
                ),
              ),
              // Subtitle slot: three lines held whether or not a line is up.
              SizedBox(
                height: _subtitleSlot,
                child: SfFadeSwitcher(
                alignment: Alignment.topLeft,
                child: sub == null
                    ? const SizedBox(key: ValueKey('sub-none'), width: double.infinity)
                    : Padding(
                        key: ValueKey('sub-$sub'),
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
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: SfType.body.copyWith(fontSize: 15, height: 1.55, color: SfColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ),
                ),
              ),
              // 下一个 slot: held at the same height when there is none
              // (resting, the last move).
              SizedBox(
                height: _nextSlot,
                child: SfFadeSwitcher(
                  alignment: Alignment.topCenter,
                  child: (rest ? null : _nextUp(p)) ?? const SizedBox(key: ValueKey('next-none'), width: double.infinity),
                ),
              ),
            ],
          ),
        ),
        // The control capsule: one glass platter; prev / next are clear
        // discs on it, pause stays the screen's one solid accent.
        Padding(
          padding: const EdgeInsets.fromLTRB(40, SfSpace.x2, 40, SfSpace.x5),
          child: SfGlassSurface(
            radius: 46,
            height: 92,
            quality: SfGlass.overMedia,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SfCircleButton(
                key: const ValueKey('prev'),
                tooltip: '上一个动作',
                icon: SfGlyph.skipPrevious,
                size: 56,
                fill: Colors.transparent,
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
                      // M14: play ⇄ pause morph (rotate a quarter + scale
                      // through the swap); reduced motion: a plain fade.
                      child: AnimatedSwitcher(
                        duration: SfMotion.fast,
                        switchInCurve: SfMotion.standard,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, a) => still
                            ? FadeTransition(opacity: a, child: child)
                            : FadeTransition(
                                opacity: a,
                                child: ScaleTransition(
                                  scale: a.drive(Tween(begin: .6, end: 1)),
                                  child: RotationTransition(turns: a.drive(Tween(begin: -.25, end: 0)), child: child),
                                ),
                              ),
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
                fill: Colors.transparent,
                haptic: SfHaptic.selection,
                onPressed: _skip,
              ),
            ],
          ),
          ),
        ),
      ],
      ),
    );
  }

  static const _labelSlot = 22.0;
  static const _subtitleSlot = SfSpace.x4 + 15 * 1.55 * 3 + 2;
  static const _nextSlot = SfSpace.x5 + 60.0;

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
      key: ValueKey('next-${e.id}'),
      padding: const EdgeInsets.only(top: SfSpace.x5),
      // 下一个 peek: a glass strip (the thumbnail inside stays opaque).
      child: SfGlassSurface(
        padding: const EdgeInsets.all(SfSpace.x2),
        radius: SfRadius.md + 2,
        quality: SfGlass.overMedia,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(SfRadius.sm - 2),
              child: SizedBox.square(
                dimension: 44,
                child: ColoredBox(
                  color: sfStageFor(e).mediaStage,
                  child: Image.asset(sfPoster(e), fit: BoxFit.cover,
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

  /// Reps or seconds inside the countdown ring (M10–M12, M14). The ring
  /// is the accent while working; prep / rest count down in a neutral
  /// tone and turn accent for their last three seconds, which breathe.
  /// Paused: ring and number at 45 % (the clip's badge says 已暂停).
  Widget _counter(SessionPhase p, double t, {required bool working}) {
    final reps = p.isWork ? p.reps : null;
    final left = _engine.secondsLeft(t);
    final urgent = reps == null && p.seconds > 0 && left >= 1 && left <= 3 && !_paused;
    // Paused is said once, by the badge on the clip; the ring just dims.
    final caption = reps != null
        ? '/ $reps 次'
        : p.isWork
        ? '秒'
        : '秒后开始';
    return SfCountdownRing(
      progress: _progress,
      value: _counterValue(p, t),
      numberKey: const ValueKey('counter'),
      caption: caption,
      size: 112,
      color: working || urgent ? SfColors.accent : SfColors.text.withValues(alpha: .55),
      urgent: urgent,
      dim: _paused,
    );
  }

  Widget _doneView() {
    final full =
        !_engine.endedEarly && _engine.completedExercises >= _occurrences;
    final minutes = ((_endedAt ?? _t) / 60).round();
    final numeral = SfType.title.copyWith(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: SfType.tabular);
    return SfFinishTimeline(
      full: full,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SfSpace.x6, 0, SfSpace.x6, SfSpace.x5),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SfFinishMark(full: full),
                      const SizedBox(height: SfSpace.x2),
                      SfFinishReveal(
                        beginMs: 420,
                        child: Text(full ? '训练完成！' : '今天先到这里', style: SfType.display),
                      ),
                      const SizedBox(height: SfSpace.x2),
                      SfFinishReveal(
                        beginMs: 480,
                        child: Text(
                          widget.plan.title,
                          textAlign: TextAlign.center,
                          style: SfType.body.copyWith(color: SfColors.muted),
                        ),
                      ),
                      const SizedBox(height: SfSpace.x8),
                      Row(
                        children: [
                          Expanded(
                            child: SfFinishReveal(
                              beginMs: 540,
                              child: _stat(
                                SfFinishCount(values: [minutes], format: (v) => '${v[0]}', style: numeral),
                                '分钟',
                              ),
                            ),
                          ),
                          const SizedBox(width: SfSpace.x3),
                          Expanded(
                            child: SfFinishReveal(
                              beginMs: 600,
                              child: _stat(
                                SfFinishCount(
                                  values: [_engine.completedExercises],
                                  format: (v) => '${v[0]}/$_occurrences',
                                  style: numeral,
                                ),
                                '完成动作',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SfFinishReveal(
              beginMs: 660,
              child: SfPrimaryButton(
                key: const ValueKey('finish'),
                label: '完成',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(Widget value, String label) => SfPanel(
    padding: const EdgeInsets.symmetric(vertical: SfSpace.x4),
    radius: SfRadius.md + 2,
    child: Column(
      children: [
        value,
        const SizedBox(height: 2),
        Text(label, style: SfType.label),
      ],
    ),
  );
}
