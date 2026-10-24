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

/// A sectioned stream of move cards; only the card nearest the viewport centre
/// plays. App validation, replacements and training navigation stay here.
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
  final _cards = <String, GlobalKey>{};
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
      String? nearest;
      var distance = double.infinity;
      for (final entry in _cards.entries) {
        final box = entry.value.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (!rect.overlaps(view)) continue;
        final delta = (rect.center.dy - view.center.dy).abs();
        if (delta < distance) {
          distance = delta;
          nearest = entry.key;
        }
      }
      if (_active != nearest) setState(() => _active = nearest);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
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
      _plan = updated.copyWith(
        id: '${updated.id.split('~').first}~${DateTime.now().microsecondsSinceEpoch}',
      );
    });
    _measureAfterLayout();
    s.store.rememberPlan(_plan);
    s.prefetchPlan(_plan);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    final lib = s.library;
    if (_plan.items.isEmpty ||
        _plan.items.any((item) => !lib.contains(item.exerciseId))) {
      return const Scaffold(
        appBar: SfTopBar(title: '训练组详情'),
        body: Center(child: Text('计划包含尚未可用的动作。已保存计划仍保留。')),
      );
    }
    return Scaffold(
      appBar: const SfTopBar(title: '训练组详情'),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            SfSpace.x4,
            SfSpace.x2,
            SfSpace.x4,
            SfSpace.x3,
          ),
          child: SfPrimaryButton(
            key: const ValueKey('start'),
            icon: SfGlyph.play,
            label: '开始跟练',
            emphasized: true,
            onPressed: () async {
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
              // Retire this route's playback before a trainer can be mounted,
              // including the chat-owned workout started during pop animation.
              setState(() => _previewOn = false);
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted || !context.mounted) return;
              if (widget.returnPlanOnStart) {
                Navigator.of(context).pop(_plan);
                return;
              }
              s.prefetchPlan(_plan);
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'player'),
                  builder: (_) => PlayerPage(plan: _plan),
                ),
              );
              if (mounted) {
                setState(() => _previewOn = true);
                _measureAfterLayout();
              }
            },
          ),
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
            key: const ValueKey('plan-card-stream'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(
              SfSpace.x4,
              0,
              SfSpace.x4,
              SfSpace.x6,
            ),
            children: [
              _intro(lib),
              for (var bi = 0; bi < _plan.blocks.length; bi++) ...[
                _blockHeader(_plan.blocks[bi]),
                for (var ii = 0; ii < _plan.blocks[bi].items.length; ii++)
                  _moveCard(bi, ii, lib),
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

  Widget _moveCard(int bi, int ii, ExerciseLibrary lib) {
    final block = _plan.blocks[bi];
    final item = block.items[ii];
    final exercise = lib[item.exerciseId];
    final slot = '$bi:$ii';
    final key = _cards.putIfAbsent(slot, GlobalKey.new);
    final dose = block.type == BlockType.circuit
        ? item.copyWith(sets: 1).doseText()
        : item.doseText();
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: SfSpace.x3),
      child: SizeChangedLayoutNotifier(
        child: Semantics(
          key: ValueKey('item-${exercise.id}'),
          container: true,
          explicitChildNodes: true,
          child: SfPanel(
            padding: const EdgeInsets.all(SfSpace.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExerciseVideo(
                  key: ValueKey('plan-demo-$slot-${exercise.id}'),
                  exercise: exercise,
                  playing: _previewOn && _active == slot,
                  radius: SfRadius.md,
                ),
                const SizedBox(height: SfSpace.x3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: SfType.title.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                const SizedBox(height: SfSpace.x2),
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
                if (item.note case final note?) ...[
                  const SizedBox(height: SfSpace.x2),
                  Text(
                    note,
                    style: SfType.label.copyWith(
                      color: SfColors.accentText,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: SfSpace.x3),
                Text(
                  '动作要点',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
