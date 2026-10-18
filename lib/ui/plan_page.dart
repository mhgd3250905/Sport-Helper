import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/session.dart';
import 'exercise_video.dart';
import 'player_page.dart';
import 'theme.dart';

/// The generated plan as training groups: one live preview on top (the
/// selected move loops), every move below with its dose and key point.
class PlanPage extends StatefulWidget {
  const PlanPage({super.key, required this.plan});
  final TrainingPlan plan;
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
    setState(() {
      _plan = _plan.copyWith(blocks: blocks, notes: [..._plan.notes, '手动把「${e.name}」换成「${alt.name}」']);
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
    return Scaffold(
      appBar: AppBar(title: Text(_plan.title)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('start'),
            onPressed: () async {
              setState(() => _previewOn = false); // free the preview WebView
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => PlayerPage(plan: _plan)),
              );
              if (mounted) setState(() => _previewOn = true);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('开始跟练'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(_plan.summary, style: const TextStyle(color: SfColors.muted, height: 1.5)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pill(Icons.schedule_rounded, minutesZh(seconds)),
              _pill(Icons.fitness_center_rounded, '$count 个动作'),
              _pill(Icons.trending_up_rounded, levelZh(_plan.level)),
              _pill(Icons.place_outlined, _plan.scene == 'office' ? '办公室' : '居家'),
            ],
          ),
          const SizedBox(height: 14),
          if (selected != null) ...[
            ExerciseVideo(
              key: const ValueKey('preview'),
              exercise: selected,
              playing: _previewOn,
            ),
            const SizedBox(height: 8),
            Text(selected.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('要领：${selected.cue}', style: const TextStyle(height: 1.5)),
            Text('目标：${selected.muscles.join('、')}', style: const TextStyle(color: SfColors.muted, fontSize: 13)),
          ],
          if (_plan.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: SfColors.surface, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('已按你的情况调整', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final n in _plan.notes)
                    Text('· $n', style: const TextStyle(color: SfColors.muted, fontSize: 13, height: 1.5)),
                ],
              ),
            ),
          ],
          for (var bi = 0; bi < _plan.blocks.length; bi++) ...[
            const SizedBox(height: 18),
            _blockHeader(_plan.blocks[bi]),
            const SizedBox(height: 8),
            for (var ii = 0; ii < _plan.blocks[bi].items.length; ii++)
              _itemTile(bi, ii, lib),
          ],
          const SizedBox(height: 16),
          for (final n in _plan.safetyNotes)
            Text('⚠ $n', style: const TextStyle(color: SfColors.muted, fontSize: 12, height: 1.6)),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: SfColors.surface2, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: SfColors.accent),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 13)),
    ]),
  );

  Widget _blockHeader(PlanBlock b) {
    final extra = b.type == BlockType.circuit && b.rounds > 1
        ? ' · 循环 ${b.rounds} 轮，轮间休息 ${b.restBetweenRoundsSeconds} 秒'
        : '';
    return Row(children: [
      Container(width: 4, height: 18, decoration: BoxDecoration(color: SfColors.accent, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text('${b.name}$extra', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _itemTile(int bi, int ii, ExerciseLibrary lib) {
    final item = _plan.blocks[bi].items[ii];
    final e = lib.tryGet(item.exerciseId);
    if (e == null) return const SizedBox.shrink();
    final sel = (_selected ?? _plan.items.first.exerciseId) == e.id;
    final circuit = _plan.blocks[bi].type == BlockType.circuit;
    final dose = circuit ? item.copyWith(sets: 1).doseText() : item.doseText();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? SfColors.surface2 : SfColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('item-${e.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = e.id),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(e.media.poster, width: 64, height: 64, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(dose, style: const TextStyle(color: SfColors.accent, fontSize: 14)),
                      Text('${e.category.zh} · ${e.muscles.join('、')}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: SfColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (e.alternative != null)
                  IconButton(
                    tooltip: '换一个',
                    icon: const Icon(Icons.swap_horiz_rounded, color: SfColors.muted),
                    onPressed: () => _swap(bi, ii),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
