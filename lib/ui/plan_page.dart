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

/// The generated plan as training groups: one live preview on top (the
/// selected move loops), every move below with its dose and key point.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key, required this.plan, this.request, this.returnPlanOnStart = false});
  final TrainingPlan plan;
  final ScenarioRequest? request;
  /// Chat details return the edited plan so the home owns the workout
  /// and its completion summary, just like the card's start button.
  final bool returnPlanOnStart;
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late TrainingPlan _plan = widget.plan;
  String? _selected;
  bool _previewOn = true;

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
      workSeconds: d.mode == DoseMode.time ? (item.workSeconds ?? d.seconds) : null,
      perSide: alt.unilateral,
      restSeconds: item.restSeconds,
      replacedFrom: e.id,
    );
    blocks[bi] = blocks[bi].copyWith(items: items);
    final updated = _plan.copyWith(blocks: blocks, notes: [..._plan.notes, '手动把「${e.name}」换成「${alt.name}」']);
    final request = widget.request ?? ScenarioRequest(
      scene: _plan.scene,
      equipment: _plan.equipment.map(Equipment.byName).toSet(),
      level: _plan.level,
      avoid: _plan.avoid,
    );
    final issues = PlanValidator(s.library).validate(updated, request);
    if (alt.level > request.level + 1) issues.add('替代动作难度偏高');
    if (issues.isNotEmpty) {
      showSfToast(context, '暂不能替换：${issues.first}', icon: SfGlyph.info, bottom: 24);
      return;
    }
    setState(() {
      _plan = updated.copyWith(id: '${updated.id.split('~').first}~${DateTime.now().microsecondsSinceEpoch}');
      _selected = alt.id;
    });
    s.store.rememberPlan(_plan);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    final lib = s.library;
    final seconds = SessionBuilder(lib).planSeconds(_plan);
    final count = _plan.items.length;
    final selected = lib.tryGet(_selected ?? _plan.items.first.exerciseId);
    final meta = [
      minutesZh(seconds),
      '$count 个动作',
      levelZh(_plan.level),
      _plan.scene == 'office' ? '办公室' : '居家',
    ].join(' · ');
    return Scaffold(
      appBar: SfTopBar(title: _plan.title, caption: meta),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.x4, SfSpace.x3),
          child: SfPrimaryButton(
            key: const ValueKey('start'),
            icon: SfGlyph.play,
            label: '开始跟练',
            onPressed: () async {
              if (!s.store.trainingAllowed) {
                showSfToast(
                  context,
                  s.store.safetyAccepted ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。' : '请先在对话里完成安全确认，再开始训练。',
                  icon: SfGlyph.shield,
                  bottom: 24,
                );
                return;
              }
              if (widget.returnPlanOnStart) {
                Navigator.of(context).pop(_plan);
                return;
              }
              setState(() => _previewOn = false); // free the preview WebView
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PlayerPage(plan: _plan)),
              );
              if (mounted) setState(() => _previewOn = true);
            },
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x6),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
            child: Text(_plan.summary, style: SfType.body.copyWith(fontSize: 15, color: SfColors.muted)),
          ),
          const SizedBox(height: SfSpace.x4),
          if (selected != null) ...[
            ExerciseVideo(
              key: const ValueKey('preview'),
              exercise: selected,
              playing: _previewOn,
              radius: SfRadius.lg,
            ),
            const SizedBox(height: SfSpace.x3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SfFadeSwitcher(
                    child: Column(
                      key: ValueKey(selected.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selected.name, style: SfType.title.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(selected.muscles.join('、'), style: SfType.label),
                        const SizedBox(height: SfSpace.x2),
                        // 要领: one line with the subtitle glyph, no prefix.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: SfIcon(SfGlyph.subtitles, size: 18, color: SfColors.faint),
                            ),
                            const SizedBox(width: SfSpace.x2),
                            Expanded(
                              child: Text(selected.cue, style: SfType.body.copyWith(fontSize: 15, height: 1.55, color: SfColors.muted)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_plan.notes.isNotEmpty) ...[
            const SizedBox(height: SfSpace.x4),
            SfPanel(
              padding: const EdgeInsets.all(SfSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已按你的情况调整', style: SfType.label.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: SfSpace.x1),
                  for (final n in _plan.notes) Text('· $n', style: SfType.label.copyWith(height: 1.6)),
                ],
              ),
            ),
          ],
          for (var bi = 0; bi < _plan.blocks.length; bi++) ...[
            _blockHeader(_plan.blocks[bi]),
            for (var ii = 0; ii < _plan.blocks[bi].items.length; ii++) _itemTile(bi, ii, lib),
          ],
          const SizedBox(height: SfSpace.x3),
          for (final n in _plan.safetyNotes)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: SfIcon(SfGlyph.shield, size: 14, color: SfColors.faint)),
                  const SizedBox(width: SfSpace.x2),
                  Expanded(child: Text(n, style: SfType.caption.copyWith(color: SfColors.muted, height: 1.6))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _blockHeader(PlanBlock b) {
    final extra = b.type == BlockType.circuit && b.rounds > 1
        ? ' · 循环 ${b.rounds} 轮，轮间休息 ${b.restBetweenRoundsSeconds} 秒'
        : '';
    return SfSectionTitle('${b.name}$extra');
  }

  Widget _itemTile(int bi, int ii, ExerciseLibrary lib) {
    final item = _plan.blocks[bi].items[ii];
    final e = lib.tryGet(item.exerciseId);
    if (e == null) return const SizedBox.shrink();
    final sel = (_selected ?? _plan.items.first.exerciseId) == e.id;
    final circuit = _plan.blocks[bi].type == BlockType.circuit;
    final dose = circuit ? item.copyWith(sets: 1).doseText() : item.doseText();
    return Padding(
      padding: const EdgeInsets.only(bottom: SfSpace.x2),
      // The row and its "换一个" are two separate accessible actions: the
      // swap button sits over the row as a sibling, because the row's
      // pressable excludes its own subtree from semantics.
      child: Stack(
        children: [
          SfPressable(
            key: ValueKey('item-${e.id}'),
            semanticLabel: e.name,
            selected: sel,
            haptic: SfHaptic.selection,
            scale: .985,
            onTap: () => setState(() => _selected = e.id),
            child: AnimatedContainer(
              duration: SfMotion.medium,
              curve: SfMotion.standard,
              padding: const EdgeInsets.all(SfSpace.x2),
              decoration: BoxDecoration(
                color: sel ? SfColors.accentSoft : SfColors.surface,
                borderRadius: BorderRadius.circular(SfRadius.lg),
                border: Border.all(color: sel ? SfColors.accent.withValues(alpha: .5) : (SfColors.isDark ? Colors.transparent : SfColors.line)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SfRadius.lg - SfSpace.x2),
                    child: SizedBox.square(
                      dimension: 60,
                      child: ColoredBox(
                        color: sfStageFor(e).mediaStage,
                        child: Image.asset(sfPoster(e), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      ),
                    ),
                  ),
                  const SizedBox(width: SfSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: SfType.callout.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(dose, style: SfType.label.copyWith(color: SfColors.accentText, fontWeight: FontWeight.w600, fontFeatures: SfType.tabular)),
                        Text('${e.category.zh} · ${e.muscles.join('、')}', maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.caption.copyWith(color: SfColors.muted)),
                      ],
                    ),
                  ),
                  if (e.alternative != null) const SizedBox(width: 40),
                ],
              ),
            ),
          ),
          if (e.alternative != null)
            Positioned(
              top: 0,
              bottom: 0,
              right: SfSpace.x2,
              child: Center(
                child: SfCircleButton(
                  key: ValueKey('swap-${e.id}'),
                  tooltip: '换一个',
                  icon: SfGlyph.swap,
                  size: 40,
                  filled: false,
                  fill: Colors.transparent,
                  iconColor: SfColors.muted,
                  haptic: SfHaptic.selection,
                  onPressed: () => _swap(bi, ii),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
