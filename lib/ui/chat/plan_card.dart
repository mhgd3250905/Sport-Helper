import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../domain/session.dart';
import '../theme.dart' show levelZh, minutesZh;
import 'cosmos.dart';
import 'glass.dart';

/// The assistant's plan reply: covers of the first moves, title, length,
/// move count, gear, the numbered moves (so "换掉第 3 个" has something to
/// point at), and the two actions — 开始训练 / 保存.
class PlanCard extends StatefulWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.library,
    required this.saved,
    required this.onStart,
    required this.onSave,
    required this.onOpen,
  });

  final TrainingPlan plan;
  final ExerciseLibrary library;
  final bool saved;
  final VoidCallback onStart;
  final VoidCallback onSave;

  /// Details (the plan page: preview, every move, swaps).
  final VoidCallback onOpen;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  static const _collapsed = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final lib = widget.library;
    final items = p.items.toList();
    final circuit = [
      for (final b in p.blocks)
        for (final _ in b.items) b.type == BlockType.circuit,
    ];
    final moves = [for (final i in items) lib.tryGet(i.exerciseId)].whereType<Exercise>().toList();
    final covers = <Exercise>[];
    for (final e in moves) {
      if (covers.every((c) => c.id != e.id)) covers.add(e);
      if (covers.length == 4) break;
    }
    final unique = moves.map((e) => e.id).toSet().length;
    // Only gear people may not have; mat / chair / wall count as at hand.
    const extra = {Equipment.band, Equipment.dumbbell, Equipment.slider};
    final gear = <Equipment>{
      for (final e in moves) ...e.equipment.where(extra.contains),
    };
    final gearText = gear.isEmpty ? '徒手' : gear.map((q) => q.zh).join('、');
    final secs = SessionBuilder(lib).planSeconds(p);
    final shown = _expanded ? items.length : items.length.clamp(0, _collapsed);
    final width = (MediaQuery.sizeOf(context).width * .88).clamp(260.0, 380.0);
    final label = Theme.of(context).textTheme.labelLarge!;

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        child: Glass(
          radius: BorderRadius.circular(24),
          glow: const Color(0x10BFD0FF),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: ValueKey('plan-open-${p.id}'),
                onTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < 4; i++) ...[
                            if (i > 0) const SizedBox(width: 6),
                            Expanded(
                              child: _Cover(
                                exercise: i < covers.length ? covers[i] : null,
                                more: i == 3 && unique > 4 ? unique - 4 : 0,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                p.title,
                                style: const TextStyle(
                                  color: CosmosColors.text,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 3, left: 6),
                              child: Icon(Icons.chevron_right_rounded, size: 20, color: CosmosColors.muted),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: Text(
                          [minutesZh(secs), '${items.length} 个动作', gearText, levelZh(p.level)].join('  ·  '),
                          style: const TextStyle(color: CosmosColors.muted, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    for (var i = 0; i < shown; i++) _MoveRow(
                        index: i + 1,
                        item: circuit[i] ? items[i].copyWith(sets: 1) : items[i],
                        exercise: lib.tryGet(items[i].exerciseId),
                      ),
                    if (items.length > _collapsed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: ValueKey('plan-expand-${p.id}'),
                          style: TextButton.styleFrom(
                            foregroundColor: CosmosColors.muted,
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                            minimumSize: const Size(0, 32),
                            textStyle: label.copyWith(fontSize: 13, fontWeight: FontWeight.w400),
                          ),
                          onPressed: () => setState(() => _expanded = !_expanded),
                          child: Text(_expanded ? '收起' : '展开全部 ${items.length} 个动作'),
                        ),
                      ),
                  ],
                ),
              ),
              if (p.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    '已按你的情况调整 ${p.notes.length} 处，详情里可以看',
                    style: const TextStyle(color: CosmosColors.faint, fontSize: 12, height: 1.4),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: ValueKey('plan-start-${p.id}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: CosmosColors.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: const StadiumBorder(),
                          textStyle: label.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
                        ),
                        onPressed: widget.onStart,
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('开始训练'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      key: ValueKey('plan-save-${p.id}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.saved ? CosmosColors.muted : CosmosColors.text,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: const StadiumBorder(),
                        side: const BorderSide(color: CosmosColors.edge),
                        backgroundColor: CosmosColors.glass,
                        textStyle: label.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      onPressed: widget.saved ? null : widget.onSave,
                      icon: Icon(
                        widget.saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        size: 19,
                        color: widget.saved ? CosmosColors.accent : CosmosColors.textSoft,
                      ),
                      label: Text(widget.saved ? '已保存' : '保存'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.exercise, this.more = 0});
  final Exercise? exercise;
  final int more;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF101013)),
          if (exercise != null)
            Image.asset(
              exercise!.media.poster,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (more > 0)
            ColoredBox(
              color: const Color(0x99070A16),
              child: Center(
                child: Text(
                  '+$more',
                  style: const TextStyle(color: CosmosColors.text, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.index, required this.item, required this.exercise});
  final int index;
  final PlanItem item;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$index',
            style: const TextStyle(
              color: CosmosColors.faint,
              fontSize: 12.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: Text(
            exercise?.name ?? item.exerciseId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: CosmosColors.textSoft, fontSize: 14, height: 1.3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.doseText(),
          style: const TextStyle(color: CosmosColors.muted, fontSize: 12.5, height: 1.3),
        ),
      ],
    ),
  );
}
