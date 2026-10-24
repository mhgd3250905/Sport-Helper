import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import '../domain/session.dart';
import 'exercise_video.dart';
import 'player_page.dart';
import 'theme.dart';
import 'training_route.dart';

/// A sectioned training article with explicit, independently paused previews.
/// App validation, replacements and training navigation stay here.
class PlanPage extends StatefulWidget {
  const PlanPage({
    super.key,
    required this.plan,
    this.request,
    this.returnPlanOnStart = false,
  });
  final TrainingPlan plan;
  final ScenarioRequest? request;

  /// Chat details return the edited plan so the home owns the workout
  /// and its completion summary, just like the card's start button.
  final bool returnPlanOnStart;
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> with WidgetsBindingObserver {
  late TrainingPlan _plan = widget.plan;
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _videos = <String, GlobalKey>{};
  final _started = <String>{};
  String? _active;
  bool _measurementQueued = false;
  bool _previewOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_measureAfterLayout);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _measureAfterLayout();
  }

  @override
  void didChangeMetrics() => _measureAfterLayout();

  void _measureAfterLayout() {
    if (_measurementQueued || !mounted) return;
    _measurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementQueued = false;
      if (!mounted) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final view = viewport.localToGlobal(Offset.zero) & viewport.size;
      final outside = <String>[];
      for (final slot in _started) {
        final box = _videos[slot]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) {
          outside.add(slot);
          continue;
        }
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (!rect.overlaps(view)) outside.add(slot);
      }
      // Scrolling can stop a preview, but never starts one. Measure the video
      // rectangle rather than its long article section below it.
      if (outside.isNotEmpty) {
        setState(() {
          _started.removeAll(outside);
          if (outside.contains(_active)) _active = null;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  void _togglePreview(String slot) {
    if (!_previewOn) return;
    setState(() {
      if (_active == slot) {
        _active = null;
      } else {
        _started.add(slot);
        _active = slot;
      }
    });
    _measureAfterLayout();
  }

  void _swap(int bi, int ii) {
    final s = AppServices.of(context);
    final item = _plan.blocks[bi].items[ii];
    final e = s.library[item.exerciseId];
    final alt = e.alternative == null ? null : s.library.tryGet(e.alternative!);
    if (alt == null) return;
    final d = alt.dose;
    final blocks = [..._plan.blocks];
    final items = [...blocks[bi].items];
    items[ii] = PlanItem(
      exerciseId: alt.id,
      mode: d.mode,
      sets: item.sets,
      reps: d.mode == DoseMode.reps ? (item.reps ?? d.reps) : null,
      workSeconds: d.mode == DoseMode.time
          ? (item.workSeconds ?? d.seconds)
          : null,
      perSide: alt.unilateral,
      restSeconds: item.restSeconds,
      replacedFrom: e.id,
    );
    blocks[bi] = blocks[bi].copyWith(items: items);
    final updated = _plan.copyWith(
      blocks: blocks,
      notes: [..._plan.notes, '手动把「${e.name}」换成「${alt.name}」'],
    );
    final request =
        widget.request ??
        ScenarioRequest(
          scene: _plan.scene,
          equipment: _plan.equipment.map(Equipment.byName).toSet(),
          level: _plan.level,
          avoid: _plan.avoid,
        );
    final issues = PlanValidator(s.library).validate(updated, request);
    if (alt.level > request.level + 1) issues.add('替代动作难度偏高');
    if (issues.isNotEmpty) {
      showSfToast(
        context,
        '暂不能替换：${issues.first}',
        icon: SfGlyph.info,
        bottom: 24,
      );
      return;
    }
    setState(() {
      final slot = '$bi:$ii';
      _started.remove(slot);
      if (_active == slot) _active = null;
      _plan = updated.copyWith(
        id: '${updated.id.split('~').first}~${DateTime.now().microsecondsSinceEpoch}',
      );
    });
    _measureAfterLayout();
    s.store.rememberPlan(_plan);
    s.prefetchPlan(_plan);
  }

  Future<void> _startTraining(AppServices s) async {
    if (!s.store.trainingAllowed) {
      showSfToast(
        context,
        s.store.safetyAccepted
            ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。'
            : '请先在对话里完成安全确认，再开始训练。',
        icon: SfGlyph.shield,
        bottom: 24,
      );
      return;
    }
    // The trainer must not mount while an article preview still owns playback,
    // including a chat-owned workout launched during this route's pop animation.
    setState(() {
      _previewOn = false;
      _active = null;
      _started.clear();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (widget.returnPlanOnStart) {
      Navigator.of(context).pop(_plan);
      return;
    }
    s.prefetchPlan(_plan);
    await Navigator.of(context).push(
      TrainingRoute<void>(
        settings: const RouteSettings(name: 'player'),
        builder: (_) => PlayerPage(plan: _plan),
      ),
    );
    if (mounted) setState(() => _previewOn = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    final lib = s.library;
    if (_plan.items.isEmpty ||
        _plan.items.any((item) => !lib.contains(item.exerciseId))) {
      return const Scaffold(
        appBar: SfTopBar(title: '训练图文'),
        body: Center(child: Text('计划包含尚未可用的动作。已保存计划仍保留。')),
      );
    }
    final textSize = MediaQuery.textScalerOf(context).scale(17);
    final buttonHeight = math.max(52.0, textSize * 1.2 + 24);
    final buttonWidth = math.min(
      MediaQuery.sizeOf(context).width - 32,
      math.max(160.0, textSize * 4 + 76),
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    var ordinal = 0;
    return Scaffold(
      appBar: const SfTopBar(title: '训练图文'),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SizedBox(
        width: buttonWidth,
        child: SfPrimaryButton(
          key: const ValueKey('start'),
          icon: SfGlyph.play,
          label: '前往训练',
          height: buttonHeight,
          emphasized: true,
          onPressed: () => _startTraining(s),
        ),
      ),
      body: SizedBox.expand(
        key: _viewport,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _measureAfterLayout();
            return false;
          },
          child: ListView(
            key: const ValueKey('plan-article'),
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              SfSpace.x4,
              0,
              SfSpace.x4,
              buttonHeight + bottomInset + SfSpace.x6 + SfSpace.x4,
            ),
            children: [
              _intro(lib),
              for (var bi = 0; bi < _plan.blocks.length; bi++) ...[
                _blockHeader(_plan.blocks[bi]),
                for (var ii = 0; ii < _plan.blocks[bi].items.length; ii++)
                  _moveArticle(bi, ii, ++ordinal, lib),
              ],
              if (_plan.safetyNotes.isNotEmpty) ...[
                const SfSectionTitle('训练提醒'),
                for (final note in _plan.safetyNotes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SfSpace.x2),
                    child: Text(note, style: SfType.label),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(ExerciseLibrary lib) => Padding(
    key: const ValueKey('plan-introduction'),
    padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _plan.title,
          style: SfType.title.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: SfSpace.x2),
        Wrap(
          spacing: SfSpace.x3,
          runSpacing: SfSpace.x1,
          children: [
            Text(
              minutesZh(SessionBuilder(lib).planSeconds(_plan)),
              style: SfType.label,
            ),
            Text('${_plan.items.length} 个动作', style: SfType.label),
            Text(levelZh(_plan.level), style: SfType.label),
            Text(_plan.scene == 'office' ? '办公室' : '居家', style: SfType.label),
          ],
        ),
        const SizedBox(height: SfSpace.x3),
        Text(
          '安排说明',
          style: SfType.callout.copyWith(fontWeight: FontWeight.w600),
        ),
        if (_plan.summary.isNotEmpty) ...[
          const SizedBox(height: SfSpace.x1),
          Text(
            _plan.summary,
            style: SfType.body.copyWith(color: SfColors.muted, height: 1.5),
          ),
        ],
        for (final note in _plan.notes)
          Padding(
            padding: const EdgeInsets.only(top: SfSpace.x2),
            child: Text(note, style: SfType.label.copyWith(height: 1.5)),
          ),
      ],
    ),
  );

  Widget _blockHeader(PlanBlock block) {
    final extra = block.type == BlockType.circuit && block.rounds > 1
        ? ' · 循环 ${block.rounds} 轮，轮间休息 ${block.restBetweenRoundsSeconds} 秒'
        : '';
    return SfSectionTitle('${block.name}$extra');
  }

  Widget _moveArticle(int bi, int ii, int ordinal, ExerciseLibrary lib) {
    final block = _plan.blocks[bi];
    final item = block.items[ii];
    final exercise = lib[item.exerciseId];
    final slot = '$bi:$ii';
    final videoKey = _videos.putIfAbsent(slot, GlobalKey.new);
    final light = Theme.of(context).brightness == Brightness.light;
    final available = exercise.media.videoAvailableFor(light: light);
    final active = _previewOn && _active == slot;
    final dose = block.type == BlockType.circuit
        ? item.copyWith(sets: 1).doseText()
        : item.doseText();
    return Padding(
      key: ValueKey('plan-move-$slot'),
      padding: const EdgeInsets.only(bottom: SfSpace.x8),
      child: SizeChangedLayoutNotifier(
        child: Semantics(
          key: ValueKey('item-${exercise.id}'),
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '$ordinal. ${exercise.name}',
                      style: SfType.title.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (exercise.alternative != null) ...[
                    const SizedBox(width: SfSpace.x2),
                    SfCircleButton(
                      key: ValueKey('swap-${exercise.id}'),
                      tooltip: '换一个',
                      icon: SfGlyph.swap,
                      size: 40,
                      filled: false,
                      fill: Colors.transparent,
                      iconColor: SfColors.muted,
                      haptic: SfHaptic.selection,
                      onPressed: () => _swap(bi, ii),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: SfSpace.x3),
              SizedBox(
                key: videoKey,
                child: AspectRatio(
                  key: ValueKey('article-video-$slot'),
                  aspectRatio: 1,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ExerciseVideo(
                        key: ValueKey('plan-demo-$slot-${exercise.id}'),
                        exercise: exercise,
                        playing: _previewOn && _started.contains(slot),
                        paused: !active,
                        radius: SfRadius.sm,
                      ),
                      if (available)
                        Center(
                          child: SfCircleButton(
                            key: ValueKey('article-video-toggle-$slot'),
                            tooltip:
                                '${active ? '暂停' : '播放'}${exercise.name}示范',
                            icon: active ? SfGlyph.pause : SfGlyph.play,
                            size: 60,
                            fill: (light ? Colors.white : Colors.black)
                                .withValues(alpha: .76),
                            iconColor: light
                                ? SfPalette.light.text
                                : SfPalette.dark.text,
                            haptic: SfHaptic.selection,
                            onPressed: _previewOn
                                ? () => _togglePreview(slot)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: SfSpace.x3),
              Text(
                dose,
                key: ValueKey('plan-dose-$slot'),
                style: SfType.callout.copyWith(
                  color: SfColors.accentText,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: SfSpace.x2),
              Text(
                '目标肌群 · ${exercise.muscles.join('、')}',
                style: SfType.label.copyWith(height: 1.5),
              ),
              const SizedBox(height: SfSpace.x3),
              Text(
                '怎么做',
                style: SfType.callout.copyWith(fontWeight: FontWeight.w600),
              ),
              for (var i = 0; i < exercise.cues.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: SfSpace.x1),
                  child: Text(
                    '${i + 1}. ${exercise.cues[i]}',
                    style: SfType.body.copyWith(height: 1.5),
                  ),
                ),
              if (exercise.cautions.isNotEmpty || item.note != null) ...[
                const SizedBox(height: SfSpace.x3),
                Text(
                  '注意要点',
                  style: SfType.callout.copyWith(fontWeight: FontWeight.w600),
                ),
                if (exercise.cautions.isNotEmpty) ...[
                  const SizedBox(height: SfSpace.x1),
                  Text(
                    '留意部位：${exercise.cautions.join('、')}',
                    style: SfType.body.copyWith(height: 1.5),
                  ),
                ],
                if (item.note case final note?) ...[
                  const SizedBox(height: SfSpace.x1),
                  Text(note, style: SfType.body.copyWith(height: 1.5)),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
