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
    this.landing = false,
  });

  final TrainingPlan plan;

  /// A card that just arrived: its cover settles from 1.04 to 1 (M7).
  final bool landing;
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

  /// Rows past the first four fade in 30 ms apart when the list opens.
  Widget _rowIn(int i, Widget row) {
    if (i < _collapsed) return row;
    return TweenAnimationBuilder<double>(
      key: ValueKey('row-in-$i'),
      tween: Tween(begin: 0, end: 1),
      duration: SfMotion.medium + Duration(milliseconds: 30 * (i - _collapsed)),
      builder: (_, v, child) {
        final total = 280 + 30 * (i - _collapsed);
        final start = 30 * (i - _collapsed) / total;
        final o = v <= start ? 0.0 : SfMotion.standard.transform((v - start) / (1 - start));
        return Opacity(opacity: o, child: child);
      },
      child: row,
    );
  }

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
                  landing: widget.landing,
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
              // M8: the list grows on the container curve and the extra rows
              // fade in one after another; reduced motion: no height move.
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.x4, 0),
                child: AnimatedSize(
                  duration: SfMotion.reduced(context) ? Duration.zero : SfMotion.medium,
                  curve: SfMotion.container,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      for (var i = 0; i < shown; i++)
                        _rowIn(
                          i,
                          _MoveRow(
                            index: i + 1,
                            item: circuit[i] ? items[i].copyWith(sets: 1) : items[i],
                            exercise: lib.tryGet(items[i].exerciseId),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (items.length > _collapsed || p.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(SfSpace.x3, 2, SfSpace.x4, 0),
                  child: Row(
                    children: [
                      if (items.length > _collapsed)
                        _ExpandAction(
                          key: ValueKey('plan-expand-${p.id}'),
                          expanded: _expanded,
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
    this.landing = false,
    required this.cover,
    required this.title,
    required this.meta,
    required this.start,
    required this.onOpen,
  });
  final bool landing;
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
              child: TweenAnimationBuilder<double>(
                // M7: once, as the card lands, the cover settles into place.
                tween: Tween(begin: landing && !SfMotion.reduced(context) ? 1.04 : 1, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: SfMotion.standard,
                builder: (_, k, img) => k == 1 ? img! : Transform.scale(scale: k, child: img),
                child: Image.asset(
                  cover!.media.poster,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -.15),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
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

/// 「开始」: the card's one prominent action and the app's one raised
/// element (HipLab rule R2): the accent lit from above, a deeper edge of
/// itself, a tight contact shadow — no glow, no gradient halo. It sinks
/// while held. Drawn with the dark accent on the dark stage.
class _StartDisc extends StatelessWidget {
  const _StartDisc({super.key, required this.onTap});
  final VoidCallback onTap;

  static const _size = 68.0;

  @override
  Widget build(BuildContext context) {
    final stage = SfColors.palette;
    final dark = stage.mediaStage.computeLuminance() < .2;
    final accent = dark ? SfPalette.dark.accent : SfPalette.light.accent;
    final on = dark ? SfPalette.dark.onAccent : SfPalette.light.onAccent;
    return SfPressable(
      semanticLabel: '开始训练',
      tooltip: '开始训练',
      onTap: onTap,
      haptic: SfHaptic.medium,
      child: Builder(
        builder: (context) => SfTactile(
          key: const ValueKey('start-disc'),
          style: SfTactileStyle.accent(dark: dark, color: accent),
          pressed: SfPressedScope.of(context),
          circle: true,
          child: SizedBox.square(
            dimension: _size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SfIcon(SfGlyph.play, size: 22, filled: true, color: on),
                const SizedBox(height: 1),
                Text(
                  '开始',
                  style: TextStyle(color: on, fontSize: 12.5, height: 1.15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
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
            style: SfType.label.copyWith(color: SfColors.muted, fontFeatures: SfType.tabular),
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

/// 展开全部 / 收起 with a chevron that turns over (180°) as the list opens.
class _ExpandAction extends StatelessWidget {
  const _ExpandAction({super.key, required this.expanded, required this.label, required this.onPressed});
  final bool expanded;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SfPressable(
    semanticLabel: label,
    onTap: onPressed,
    haptic: SfHaptic.selection,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2, color: SfColors.muted)),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: expanded ? -.25 : .25,
              duration: SfMotion.reduced(context) ? Duration.zero : SfMotion.medium,
              curve: SfMotion.container,
              child: SfIcon(SfGlyph.chevronRight, size: 16, color: SfColors.muted, strokeWidth: 2),
            ),
          ],
        ),
      ),
    ),
  );
}
