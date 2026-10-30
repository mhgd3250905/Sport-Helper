import 'dart:async';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import 'guide_media.dart';
import 'guide_layout_tokens.dart';
import 'plan_presentation.dart';
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
  final _coordinator = GuidePreviewCoordinator();
  bool _measurementQueued = false;
  String? _releasingSlot;
  bool _previewOn = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_measureAfterLayout);
    _coordinator.addListener(_measureAfterLayout);
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
      final slot = _coordinator.activeSlot;
      if (slot == null || slot == _releasingSlot) return;
      final viewport = _viewport.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      final covered =
          SfGuideTokens.buttonHeight +
          SfGuideTokens.buttonBottom +
          MediaQuery.paddingOf(context).bottom;
      final view = Rect.fromLTRB(
        bounds.left,
        bounds.top,
        bounds.right,
        bounds.bottom - covered,
      );
      final box = _videos[slot]?.currentContext?.findRenderObject();
      var visible = 0.0;
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final area = rect.width * rect.height;
        final intersection = rect.intersect(view);
        if (area > 0 && intersection.width > 0 && intersection.height > 0) {
          visible = intersection.width * intersection.height / area;
        }
      }
      // Only the active media rectangle is measured. Long instructions below
      // it must not keep an offscreen decoder alive.
      if (visible >= .2) return;
      _releasingSlot = slot;
      unawaited(
        _coordinator.release(slot).whenComplete(() {
          if (_releasingSlot == slot) _releasingSlot = null;
        }),
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coordinator.removeListener(_measureAfterLayout);
    _coordinator.dispose();
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
    // Commit against the current plan synchronously. Playback retirement stays
    // in the coordinator's queue, ahead of any subsequent preview claim.
    unawaited(_coordinator.release('$bi:$ii'));
    setState(() {
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
    setState(() => _previewOn = false);
    await _coordinator.stop();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (widget.returnPlanOnStart) {
      Navigator.of(context).pop(_plan);
      return;
    }
    s.prefetchPlan(_plan);
    final route = TrainingRoute<void>(
      context: context,
      settings: const RouteSettings(name: 'player'),
      builder: (_) => PlayerPage(plan: _plan),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    if (mounted) setState(() => _previewOn = true);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final library = services.library;
    if (_plan.items.isEmpty ||
        _plan.items.any((item) => !library.contains(item.exerciseId))) {
      return const Scaffold(
        appBar: SfTopBar(title: '训练图文'),
        body: Center(child: Text('计划包含尚未可用的动作。已保存计划仍保留。')),
      );
    }
    final rows = _articleRows();
    final rowIndices = {
      for (var index = 0; index < rows.length; index++)
        ValueKey(rows[index].id): index,
    };
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: const SfTopBar(title: '训练图文'),
      body: Stack(
        children: [
          SizedBox.expand(
            key: _viewport,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                _measureAfterLayout();
                return false;
              },
              child: ListView.builder(
                key: const ValueKey('plan-article'),
                controller: _scroll,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                padding: EdgeInsets.fromLTRB(
                  SfGuideTokens.pageInset,
                  0,
                  SfGuideTokens.pageInset,
                  SfGuideTokens.bottomSpace + safeBottom,
                ),
                itemCount: rows.length,
                findChildIndexCallback: (key) => rowIndices[key],
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final child = switch (row.kind) {
                    _GuideRowKind.intro => _intro(library),
                    _GuideRowKind.section => _blockHeader(
                      _plan.blocks[row.block],
                    ),
                    _GuideRowKind.move => _moveArticle(
                      row.block,
                      row.item,
                      row.ordinal,
                      library,
                    ),
                    _GuideRowKind.safetyTitle => _sectionLabel('训练提醒'),
                    _GuideRowKind.safetyNote => Padding(
                      padding: EdgeInsets.only(
                        bottom: row.item < _plan.safetyNotes.length - 1 ? 8 : 0,
                      ),
                      child: Text(row.note, style: SfGuideTokens.step),
                    ),
                  };
                  return KeyedSubtree(key: ValueKey(row.id), child: child);
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _trainingBar(services, safeBottom),
          ),
        ],
      ),
    );
  }

  List<_GuideRow> _articleRows() {
    final rows = <_GuideRow>[const _GuideRow(_GuideRowKind.intro, 'intro')];
    var ordinal = 0;
    for (var bi = 0; bi < _plan.blocks.length; bi++) {
      rows.add(_GuideRow(_GuideRowKind.section, 'section-$bi', block: bi));
      for (var ii = 0; ii < _plan.blocks[bi].items.length; ii++) {
        rows.add(
          _GuideRow(
            _GuideRowKind.move,
            'move-$bi:$ii',
            block: bi,
            item: ii,
            ordinal: ++ordinal,
          ),
        );
      }
    }
    if (_plan.safetyNotes.isNotEmpty) {
      rows.add(const _GuideRow(_GuideRowKind.safetyTitle, 'safety-title'));
      for (var index = 0; index < _plan.safetyNotes.length; index++) {
        rows.add(
          _GuideRow(
            _GuideRowKind.safetyNote,
            'safety-$index',
            item: index,
            note: _plan.safetyNotes[index],
          ),
        );
      }
    }
    return rows;
  }

  Widget _trainingBar(AppServices services, double safeBottom) => Column(
    key: const ValueKey('guide-training-bar'),
    mainAxisSize: MainAxisSize.min,
    children: [
      IgnorePointer(
        child: SizedBox(
          height: SfGuideTokens.footerFade,
          width: double.infinity,
          child: DecoratedBox(
            key: const ValueKey('guide-training-gradient'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  SfColors.background.withValues(alpha: 0),
                  SfColors.background,
                ],
              ),
            ),
          ),
        ),
      ),
      ColoredBox(
        color: SfColors.background,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            SfGuideTokens.pageInset,
            0,
            SfGuideTokens.pageInset,
            SfGuideTokens.buttonBottom + safeBottom,
          ),
          child: SfPressable(
            key: const ValueKey('start'),
            semanticLabel: '前往训练',
            haptic: SfHaptic.light,
            onTap: () => unawaited(_startTraining(services)),
            child: Container(
              key: const ValueKey('guide-training-button'),
              height: SfGuideTokens.buttonHeight,
              decoration: BoxDecoration(
                color: SfColors.accent,
                borderRadius: BorderRadius.circular(SfGuideTokens.buttonRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SfIcon(
                    SfGlyph.play,
                    size: 20,
                    filled: true,
                    color: SfColors.onAccent,
                  ),
                  const SizedBox(width: 8),
                  Text('前往训练', style: SfGuideTokens.button),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _intro(ExerciseLibrary library) => Column(
    key: const ValueKey('plan-introduction'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _plan.title,
        key: const ValueKey('guide-title'),
        style: SfGuideTokens.title,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: SfGuideTokens.tagGap,
        runSpacing: SfGuideTokens.tagGap,
        children: [
          _tag(planDurationLabel(_plan, library), 0),
          _tag('${_plan.items.length} 个动作', 1),
          _tag(levelZh(_plan.level), 2),
          _tag(_plan.scene == 'office' ? '办公室' : '居家', 3),
        ],
      ),
      if (_plan.summary.trim().isNotEmpty &&
          _plan.summary.trim() != _plan.title.trim()) ...[
        const SizedBox(height: 12),
        Text('安排说明', style: SfGuideTokens.caption),
        const SizedBox(height: 4),
        Text(
          _plan.summary,
          style: SfGuideTokens.step.copyWith(color: SfColors.muted),
        ),
        for (final note in _plan.notes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              note,
              style: SfGuideTokens.muscles.copyWith(height: 1.5),
            ),
          ),
      ],
    ],
  );

  Widget _tag(String text, int index) => Container(
    key: ValueKey('guide-tag-$index'),
    height: SfGuideTokens.tagHeight,
    padding: SfGuideTokens.tagPadding,
    decoration: BoxDecoration(
      color: SfColors.surfaceHigh,
      borderRadius: BorderRadius.circular(SfGuideTokens.tagRadius),
    ),
    child: Center(widthFactor: 1, child: Text(text, style: SfGuideTokens.tag)),
  );

  Widget _sectionLabel(String label, {Key? key}) => Padding(
    key: key,
    padding: SfGuideTokens.sectionPadding,
    child: Text(label, style: SfGuideTokens.section),
  );

  Widget _blockHeader(PlanBlock block) {
    final protocolName = block.name.trim().toLowerCase();
    final mainName =
        const {
          'main',
          'main_set',
          'main-set',
          'workout',
        }.contains(protocolName) ||
        (protocolName.isEmpty && block.type == BlockType.main);
    final title = mainName ? '主训' : planSectionLabel(block);
    final extra = block.type == BlockType.circuit && block.rounds > 1
        ? ' · 循环 ${block.rounds} 轮，轮间休息 ${block.restBetweenRoundsSeconds} 秒'
        : '';
    return _sectionLabel(
      '$title$extra',
      key: ValueKey('guide-section-${block.id}'),
    );
  }

  Widget _moveArticle(int bi, int ii, int ordinal, ExerciseLibrary library) {
    final block = _plan.blocks[bi];
    final item = block.items[ii];
    final exercise = library[item.exerciseId];
    final slot = '$bi:$ii';
    final videoKey = _videos.putIfAbsent(slot, GlobalKey.new);
    final dose = block.type == BlockType.circuit
        ? item.copyWith(sets: 1).doseText()
        : item.doseText();
    return Padding(
      key: ValueKey('plan-move-$slot'),
      padding: EdgeInsets.only(
        bottom: ii < block.items.length - 1 ? SfGuideTokens.cardGap : 0,
      ),
      child: RepaintBoundary(
        key: ValueKey('guide-repaint-$slot'),
        child: SizeChangedLayoutNotifier(
          child: Semantics(
            key: ValueKey('item-${exercise.id}'),
            container: true,
            explicitChildNodes: true,
            child: DecoratedBox(
              key: ValueKey('guide-card-$slot'),
              decoration: BoxDecoration(
                color: SfGuideTokens.cardFill(context),
                borderRadius: BorderRadius.circular(SfGuideTokens.cardRadius),
                boxShadow: SfGuideTokens.cardShadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SfGuideTokens.cardRadius),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: videoKey,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(SfGuideTokens.cardRadius),
                        ),
                        child: AspectRatio(
                          key: ValueKey('article-video-$slot'),
                          aspectRatio: SfGuideTokens.mediaRatio,
                          child: GuideMedia(
                            key: ValueKey('plan-demo-$slot-${exercise.id}'),
                            exercise: exercise,
                            slot: slot,
                            coordinator: _coordinator,
                            enabled: _previewOn,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      key: ValueKey('guide-body-$slot'),
                      padding: SfGuideTokens.bodyPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _moveNumber(ordinal, slot),
                              const SizedBox(width: SfGuideTokens.nameGap),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, constraints) => Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              exercise.name,
                                              key: ValueKey('guide-name-$slot'),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: SfGuideTokens.name,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  constraints.maxWidth / 2,
                                            ),
                                            child: _dose(dose, slot),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(
                                      height: SfGuideTokens.muscleGap,
                                    ),
                                    Text(
                                      exercise.muscles.join('、'),
                                      key: ValueKey('guide-muscles-$slot'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: SfGuideTokens.muscles,
                                      semanticsLabel:
                                          '目标肌群：${exercise.muscles.join('、')}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: SfGuideTokens.dividerGap),
                          SizedBox(
                            key: ValueKey('guide-divider-$slot'),
                            height: 1,
                            child: ColoredBox(
                              color: SfColors.line.withValues(alpha: .6),
                            ),
                          ),
                          const SizedBox(height: SfGuideTokens.instructionGap),
                          Text('怎么做', style: SfGuideTokens.caption),
                          const SizedBox(height: SfGuideTokens.instructionGap),
                          for (
                            var index = 0;
                            index < exercise.cues.length;
                            index++
                          ) ...[
                            if (index > 0)
                              const SizedBox(height: SfGuideTokens.stepGap),
                            _step(exercise.cues[index], index + 1, slot),
                          ],
                          if (exercise.cautions.isNotEmpty ||
                              item.note != null ||
                              exercise.alternative != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '注意要点',
                                    style: SfGuideTokens.caption,
                                  ),
                                ),
                                if (exercise.alternative != null)
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
                            ),
                            if (exercise.cautions.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '留意部位：${exercise.cautions.join('、')}',
                                style: SfGuideTokens.step,
                              ),
                            ],
                            if (item.note case final note?) ...[
                              const SizedBox(height: 4),
                              Text(note, style: SfGuideTokens.step),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _moveNumber(int ordinal, String slot) => Container(
    key: ValueKey('guide-number-$slot'),
    width: SfGuideTokens.numberSize,
    height: SfGuideTokens.numberSize,
    decoration: BoxDecoration(
      color: SfColors.accent.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(SfGuideTokens.numberRadius),
    ),
    alignment: Alignment.center,
    child: Text('$ordinal', style: SfGuideTokens.number),
  );

  Widget _dose(String text, String slot) => Tooltip(
    message: text,
    child: Container(
      key: ValueKey('guide-dose-chip-$slot'),
      height: SfGuideTokens.tagHeight,
      padding: SfGuideTokens.tagPadding,
      decoration: BoxDecoration(
        color: SfGuideTokens.doseFill,
        borderRadius: BorderRadius.circular(SfGuideTokens.tagRadius),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          key: ValueKey('plan-dose-$slot'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SfGuideTokens.dose,
        ),
      ),
    ),
  );

  Widget _step(String text, int ordinal, String slot) => Row(
    key: ValueKey('guide-step-$slot-$ordinal'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        key: ValueKey('guide-step-number-$slot-$ordinal'),
        width: SfGuideTokens.stepSize,
        height: SfGuideTokens.stepSize,
        decoration: BoxDecoration(
          color: SfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(SfGuideTokens.stepSize / 2),
        ),
        alignment: Alignment.center,
        child: Text('$ordinal', style: SfGuideTokens.stepNumber),
      ),
      const SizedBox(width: SfGuideTokens.stepGap),
      Expanded(
        child: Text(
          text,
          key: ValueKey('guide-step-text-$slot-$ordinal'),
          style: SfGuideTokens.step,
        ),
      ),
    ],
  );
}

enum _GuideRowKind { intro, section, move, safetyTitle, safetyNote }

class _GuideRow {
  const _GuideRow(
    this.kind,
    this.id, {
    this.block = 0,
    this.item = 0,
    this.ordinal = 0,
    this.note = '',
  });
  final _GuideRowKind kind;
  final String id;
  final int block, item, ordinal;
  final String note;
}
