import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../domain/session.dart';
import '../theme.dart' show levelZh;
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'expand_route.dart';

/// The assistant's plan reply, one card with one prominent action:
///
/// * a cover stage (the first move's render on its own dark stage) with
///   the title and the meta line laid over its lower edge, and the accent
///   「开始」 disc in the corner — the card's only accent;
/// * the numbered moves (so "换掉第 3 个" has something to point at), four
///   shown, the rest behind 展开全部;
/// * a quiet footer: 保存 · 详情 (tertiary text actions).
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

  /// 开始训练; [from] says where the card is, for the grow-into-player move.
  final void Function(OriginRect from) onStart;
  final VoidCallback onSave;

  /// Details (the plan page: preview, every move, swaps).
  final VoidCallback onOpen;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<PlanCard> {
  static const _collapsed = 4;
  bool _expanded = false;
  final _card = GlobalKey();

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
    // Only gear people may not have; mat / chair / wall count as at hand.
    const extra = {Equipment.band, Equipment.dumbbell, Equipment.slider};
    final gear = <Equipment>{
      for (final e in moves) ...e.equipment.where(extra.contains),
    };
    final gearText = gear.isEmpty ? '徒手' : gear.map((q) => q.zh).join('、');
    final secs = SessionBuilder(lib).planSeconds(p);
    final minutes = (secs / 60).round();
    final meta = [
      minutes < 1 ? '不到 1 分钟' : '$minutes 分钟',
      '${items.length} 个动作',
      gearText,
      levelZh(p.level),
    ].join(' · ');
    final shown = _expanded ? items.length : items.length.clamp(0, _collapsed);
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(280.0, 400.0);

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        key: _card,
        width: width,
        child: SfPanel(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(SfSpace.x2),
                child: _CoverStage(
                  cover: moves.firstOrNull,
                  title: p.title,
                  meta: meta,
                  onOpen: widget.onOpen,
                  start: _StartDisc(
                    key: ValueKey('plan-start-${p.id}'),
                    onTap: () => widget.onStart(() => rectOf(_card.currentContext)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.x4, 0),
                child: Column(
                  children: [
                    for (var i = 0; i < shown; i++)
                      _MoveRow(
                        index: i + 1,
                        item: circuit[i] ? items[i].copyWith(sets: 1) : items[i],
                        exercise: lib.tryGet(items[i].exerciseId),
                      ),
                  ],
                ),
              ),
              if (items.length > _collapsed || p.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SfSpace.x3, 2, SfSpace.x4, 0),
                  child: Row(
                    children: [
                      if (items.length > _collapsed)
                        SfTextAction(
                          key: ValueKey('plan-expand-${p.id}'),
                          label: _expanded ? '收起' : '展开全部 ${items.length} 个动作',
                          onPressed: () => setState(() => _expanded = !_expanded),
                        ),
                      const Spacer(),
                      if (p.notes.isNotEmpty)
                        Flexible(
                          flex: 4,
                          child: Text(
                            '已按你的情况调整 ${p.notes.length} 处',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: SfType.caption,
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.x2, SfSpace.x1, SfSpace.x2, SfSpace.x1),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: SfColors.isDark ? SfColors.surfaceHigh : SfColors.line)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: SfSpace.x2),
                  child: Row(
                    children: [
                      SfTextAction(
                        key: ValueKey('plan-save-${p.id}'),
                        icon: SfGlyph.bookmark,
                        iconFilled: widget.saved,
                        color: widget.saved ? SfColors.accentText : SfColors.text,
                        label: widget.saved ? '已保存' : '保存',
                        onPressed: widget.saved ? null : widget.onSave,
                      ),
                      const Spacer(),
                      SfPressable(
                        key: ValueKey('plan-open-${p.id}'),
                        semanticLabel: '计划详情',
                        onTap: widget.onOpen,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('详情', style: SfType.callout.copyWith(fontSize: 14, color: SfColors.muted)),
                              const SizedBox(width: 2),
                              SfIcon(SfGlyph.chevronRight, size: 16, color: SfColors.muted, strokeWidth: 2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The first move's render on its dark stage, title and meta over the
/// lower edge (a scrim keeps them readable), the start disc in the corner.
class _CoverStage extends StatelessWidget {
  const _CoverStage({
    required this.cover,
    required this.title,
    required this.meta,
    required this.start,
    required this.onOpen,
  });
  final Exercise? cover;
  final String title;
  final String meta;
  final Widget start;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(SfRadius.lg - SfSpace.x2),
    child: AspectRatio(
      aspectRatio: 16 / 11,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: SfColors.mediaStage),
          if (cover != null)
            GestureDetector(
              onTap: onOpen,
              child: Image.asset(
                cover!.media.poster,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.15),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          // Lower scrim: transparent → stage, under the text only.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [.38, 1],
                  colors: [SfColors.mediaStage.withValues(alpha: 0), SfColors.mediaStage.withValues(alpha: .92)],
                ),
              ),
            ),
          ),
          Positioned(
            left: SfSpace.x4,
            right: 96,
            bottom: SfSpace.x4,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: SfSpace.x1),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xB8FFFFFF),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(right: SfSpace.x3, bottom: SfSpace.x3, child: start),
        ],
      ),
    ),
  );
}

/// 「开始」: the card's one prominent action. A flat accent disc with a
/// tight contact shadow to sit it on the stage (no glow, no gradient).
class _StartDisc extends StatelessWidget {
  const _StartDisc({super.key, required this.onTap});
  final VoidCallback onTap;

  static const _size = 68.0;

  @override
  Widget build(BuildContext context) {
    // On the dark stage the dark-theme accent reads best in both themes.
    const accent = Color(0xFF3CCFA4);
    const on = Color(0xFF07261D);
    return SfPressable(
      semanticLabel: '开始训练',
      tooltip: '开始训练',
      onTap: onTap,
      child: Builder(
        builder: (context) {
          final down = SfPressedScope.of(context);
          return AnimatedContainer(
            duration: down ? SfMotion.press : SfMotion.release,
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: down ? Color.lerp(accent, Colors.black, .1) : accent,
              boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SfIcon(SfGlyph.play, size: 22, filled: true, color: on),
                SizedBox(height: 1),
                Text(
                  '开始',
                  style: TextStyle(color: on, fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({required this.index, required this.item, required this.exercise});
  final int index;
  final PlanItem item;
  final Exercise? exercise;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            '$index',
            style: SfType.label.copyWith(color: SfColors.faint, fontFeatures: SfType.tabular),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(SfRadius.xs + 2),
          child: SizedBox.square(
            dimension: 36,
            child: ColoredBox(
              color: SfColors.mediaStage,
              child: exercise == null
                  ? null
                  : Image.asset(
                      exercise!.media.poster,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ),
        ),
        const SizedBox(width: SfSpace.x3),
        Expanded(
          child: Text(
            exercise?.name ?? item.exerciseId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SfType.callout,
          ),
        ),
        const SizedBox(width: SfSpace.x2),
        Text(item.doseText(), style: SfType.label.copyWith(fontFeatures: SfType.tabular)),
      ],
    ),
  );
}
