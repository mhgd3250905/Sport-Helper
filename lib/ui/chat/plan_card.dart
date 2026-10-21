import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../domain/session.dart';
import '../theme.dart' show levelZh;
import '../theme/glass.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/media_theme.dart';
import '../theme/widgets.dart';
import 'expand_route.dart';

/// The assistant's plan reply: a compact, fixed-height card (like a link
/// share in a messenger), raised on liquid glass because it is tappable;
/// the media inside stays opaque and rounded.
///
/// * one move → [_ExerciseBody], 130 px: a square preview on the left,
///   name · dose · tags · one cue on the right, 「开始」 bottom-right;
/// * a set → [_SetBody], 240 px: the first move as the hero with title,
///   duration and move count over it, a row of thumbnails for the other
///   moves (five, then +N), 「开始」 on the hero.
///
/// Tapping the card opens the plan page (every move, swaps); 保存 stays on
/// the card as a small pill. The full move list lives on the plan page.
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

  /// Fixed card heights by type.
  static const exerciseHeight = 130.0;
  static const setHeight = 240.0;

  @override
  State<PlanCard> createState() => _PlanCardState();
}

/// A critically damped spring as a curve: x(t) = 1 − (1 + ωt)·e^(−ωt),
/// normalised so it ends exactly at 1 — no overshoot, a soft settle.
class _CriticalSpring extends Curve {
  const _CriticalSpring();
  static const omega = 9.0;

  double _x(double t) => 1 - (1 + omega * t) * math.exp(-omega * t);

  @override
  double transformInternal(double t) => _x(t) / _x(1);
}

class _PlanCardState extends State<PlanCard> with SingleTickerProviderStateMixin {
  final _card = GlobalKey();
  static const _inset = 6.0;

  /// Expand: height + content cross-fade on a critically damped spring
  /// (350 ms); collapse reverses faster (250 ms). Reduced motion: the
  /// height jumps and only the contents fade.
  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    reverseDuration: const Duration(milliseconds: 250),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _expand,
    curve: const _CriticalSpring(),
    reverseCurve: Curves.easeInCubic,
  );
  bool _expanded = false;

  @override
  void dispose() {
    _expand.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (SfMotion.reduced(context)) {
      _expand.animateTo(_expanded ? 1 : 0, duration: const Duration(milliseconds: 200));
    } else if (_expanded) {
      _expand.forward();
    } else {
      _expand.reverse();
    }
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
    final duration = minutes < 1 ? '不到 1 分钟' : '$minutes 分钟';
    final single = items.length == 1;
    final height = single ? PlanCard.exerciseHeight : PlanCard.setHeight;
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(280.0, 400.0);
    final reduced = SfMotion.reduced(context);

    final start = _StartDisc(
      key: ValueKey('plan-start-${p.id}'),
      size: single ? 48 : 56,
      onTap: () => widget.onStart(() => rectOf(_card.currentContext)),
    );
    final toggle = _ExpandToggle(
      key: ValueKey('plan-expand-${p.id}'),
      expanded: _expanded,
      turns: _t,
      onMedia: !single,
      onTap: _toggle,
    );
    final Widget body = single
        ? _ExerciseBody(
            exercise: moves.firstOrNull,
            item: items.first,
            fallbackName: p.title,
            duration: duration,
            tags: [gearText, if (moves.firstOrNull case final e?) e.category.zh, levelZh(p.level)],
            landing: widget.landing,
          )
        : _SetBody(
            moves: moves,
            title: p.title,
            meta: [duration, '${items.length} 个动作', gearText].join(' · '),
            landing: widget.landing,
            // The thumbnail strip hands over to the full list as it opens.
            stripFade: ReverseAnimation(CurvedAnimation(parent: _expand, curve: const Interval(0, .45))),
          );

    final details = _Details(
      t: _t,
      reduced: reduced,
      rows: [
        if (single)
          for (final (i, c) in (moves.firstOrNull?.cues ?? const <String>[]).indexed)
            _CueRow(index: i + 1, text: c)
        else
          for (var i = 0; i < items.length; i++)
            _MoveRow(
              index: i + 1,
              item: circuit[i] ? items[i].copyWith(sets: 1) : items[i],
              exercise: lib.tryGet(items[i].exerciseId),
            ),
      ],
      note: p.notes.isEmpty ? null : '已按你的情况调整 ${p.notes.length} 处',
      footer: Row(
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
            key: ValueKey('plan-details-${p.id}'),
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
    );

    Widget card = SfGlassSurface(
      radius: SfRadius.lg,
      width: width,
      padding: const EdgeInsets.all(_inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The compact card: fixed height by type. The whole of it opens
          // the plan page; the toggle and 开始 sit on top as their own
          // buttons (own semantics nodes).
          SizedBox(
            height: height - _inset * 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: SfPressable(
                    key: ValueKey('plan-open-${p.id}'),
                    semanticLabel: '计划详情：${p.title}',
                    scale: 1,
                    haptic: SfHaptic.selection,
                    onTap: widget.onOpen,
                    child: body,
                  ),
                ),
                if (single) ...[
                  Positioned(right: 0, top: 0, child: toggle),
                  Positioned(right: SfSpace.x1, bottom: SfSpace.x1, child: start),
                ] else ...[
                  Positioned(right: SfSpace.x1, top: SfSpace.x1, child: toggle),
                  Positioned(right: SfSpace.x3, bottom: _SetBody.stripHeight + SfSpace.x3, child: start),
                ],
              ],
            ),
          ),
          details,
        ],
      ),
    );
    // Landing: the glass rim's highlight settles as the card arrives.
    // (The Stack is always there so the glass subtree keeps its identity
    // when the landing flag clears.)
    {
      card = Stack(
        children: [
          card,
          if (widget.landing && !reduced)
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: 0),
                duration: const Duration(milliseconds: 700),
                curve: SfMotion.standard,
                builder: (_, k, _) => k == 0
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: RoundedSuperellipseBorder(
                            borderRadius: BorderRadius.circular(SfRadius.lg),
                            side: BorderSide(color: Colors.white.withValues(alpha: .45 * k), width: 1.2),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(key: _card, width: width, child: card),
    );
  }
}

/// The in-place details: the full move list (or a move's cues), notes and
/// the 保存 · 详情 footer. Height grows on [t]; the contents cross-fade in
/// and the rows follow each other ~25 ms apart. Reduced motion: no height
/// move, fade only.
class _Details extends StatelessWidget {
  const _Details({required this.t, required this.reduced, required this.rows, required this.footer, this.note});
  final Animation<double> t;
  final bool reduced;
  final List<Widget> rows;
  final Widget footer;
  final String? note;

  @override
  Widget build(BuildContext context) {
    // 350 ms forward: each row starts 25 ms after the one before.
    const span = 350.0;
    Widget staggered(int i, Widget row) {
      final start = (60 + 25.0 * i).clamp(0, span * .7) / span;
      final a = CurvedAnimation(parent: t, curve: Interval(start, math.min(1, start + .45), curve: SfMotion.standard));
      if (reduced) return FadeTransition(opacity: t, child: row);
      return FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -.18), end: Offset.zero).animate(a),
          child: row,
        ),
      );
    }

    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        if (t.value == 0) return const SizedBox(width: double.infinity);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: reduced ? 1 : t.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x2, SfSpace.x2, SfSpace.x2, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, r) in rows.indexed) staggered(i, r),
              if (note != null)
                staggered(
                  rows.length,
                  Padding(
                    padding: const EdgeInsets.only(top: SfSpace.x1),
                    child: Text(note!, style: SfType.caption),
                  ),
                ),
              FadeTransition(
                opacity: CurvedAnimation(parent: t, curve: const Interval(.3, 1)),
                child: Container(
                  margin: const EdgeInsets.only(top: SfSpace.x1),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: SfColors.text.withValues(alpha: .08))),
                  ),
                  child: footer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 展开 / 收起: a small disclosure pill; the chevron turns over as the card
/// opens. Exposes expanded / collapsed to TalkBack.
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({super.key, required this.expanded, required this.turns, required this.onMedia, required this.onTap});
  final bool expanded;
  final Animation<double> turns;
  final bool onMedia;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = onMedia ? Colors.white : SfColors.muted;
    final label = expanded ? '收起' : '展开';
    return SfPressable(
      semanticLabel: expanded ? '收起详情' : '展开详情',
      expanded: expanded,
      haptic: SfHaptic.selection,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: onMedia ? const Color(0x66000000) : SfColors.text.withValues(alpha: SfColors.isDark ? .10 : .06),
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 7, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(color: fg, fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  // Down when closed, up when open.
                  AnimatedBuilder(
                    animation: turns,
                    builder: (_, child) => Transform.rotate(angle: math.pi * (.5 - turns.value), child: child),
                    child: SfIcon(SfGlyph.chevronRight, size: 14, color: fg, strokeWidth: 2.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CueRow extends StatelessWidget {
  const _CueRow({required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Text('$index', style: SfType.label.copyWith(color: SfColors.muted, fontFeatures: SfType.tabular)),
        ),
        Expanded(child: Text(text, style: SfType.callout)),
      ],
    ),
  );
}

/// The cover image on its stage colour; settles from 1.04 as a card lands.
class _Media extends StatelessWidget {
  const _Media({required this.exercise, this.landing = false});
  final Exercise? exercise;
  final bool landing;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: sfStageFor(e).mediaStage),
        if (e != null)
          TweenAnimationBuilder<double>(
            // M7: once, as the card lands, the cover settles into place.
            tween: Tween(begin: landing && !SfMotion.reduced(context) ? 1.04 : 1, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: SfMotion.standard,
            builder: (_, k, img) => k == 1 ? img! : Transform.scale(scale: k, child: img),
            child: Image.asset(
              sfPoster(e),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -.15),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

/// One move: square preview left; name, dose, tags, one cue right.
class _ExerciseBody extends StatelessWidget {
  const _ExerciseBody({
    required this.exercise,
    required this.item,
    required this.fallbackName,
    required this.duration,
    required this.tags,
    this.landing = false,
  });
  final Exercise? exercise;
  final PlanItem item;
  final String fallbackName;
  final String duration;
  final List<String> tags;
  final bool landing;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    final cue = e == null || e.cues.isEmpty ? '' : e.cues.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SfRadius.lg - 6),
            child: _Media(exercise: e, landing: landing),
          ),
        ),
        const SizedBox(width: SfSpace.x3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, SfSpace.x1, 0, SfSpace.x1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 72), // clear of 展开
                  child: Text(
                    e?.name ?? fallbackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SfType.callout.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.doseText()} · $duration',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SfType.label.copyWith(fontFeatures: SfType.tabular),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 52), // clear of 开始
                  child: _Tags(tags),
                ),
                const Spacer(),
                if (cue.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 56),
                    child: Text(
                      cue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SfType.caption.copyWith(color: SfColors.muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Small flat tags (equipment · body part · level); one line, clipped.
class _Tags extends StatelessWidget {
  const _Tags(this.tags);
  final List<String> tags;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 22,
    child: ClipRect(
      child: Wrap(
        spacing: SfSpace.x1,
        clipBehavior: Clip.hardEdge,
        children: [
          for (final t in tags)
            DecoratedBox(
              decoration: ShapeDecoration(
                color: SfColors.text.withValues(alpha: SfColors.isDark ? .10 : .06),
                shape: const StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(t, style: TextStyle(fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w500, color: SfColors.muted)),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A set: the first move as the hero (title, duration, move count over its
/// lower edge), the other moves as a strip of thumbnails under it.
class _SetBody extends StatelessWidget {
  const _SetBody({required this.moves, required this.title, required this.meta, required this.stripFade, this.landing = false});
  final Animation<double> stripFade;
  final List<Exercise> moves;
  final String title;
  final String meta;
  final bool landing;

  static const stripHeight = 52.0;
  static const _maxThumbs = 5;

  @override
  Widget build(BuildContext context) {
    final cover = moves.firstOrNull;
    final stage = sfStageFor(cover);
    final rest = moves.skip(1).toList();
    final shown = rest.take(_maxThumbs).toList();
    final more = rest.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SfRadius.lg - 6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Media(exercise: cover, landing: landing),
                // Lower scrim: transparent → stage, under the text only.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [.35, 1],
                      colors: [stage.mediaStage.withValues(alpha: 0), stage.mediaStage.withValues(alpha: .92)],
                    ),
                  ),
                ),
                Positioned(
                  left: SfSpace.x4,
                  right: 84,
                  bottom: SfSpace.x3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: stage.onStage, fontSize: 19, height: 1.25, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: stage.onStageMuted, fontSize: 13, height: 1.35, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: stripHeight,
          child: FadeTransition(
          opacity: stripFade,
          child: LayoutBuilder(
            builder: (context, c) {
              const gap = 6.0;
              final slots = shown.length + (more > 0 ? 1 : 0);
              final size = slots == 0 ? 0.0 : ((c.maxWidth - gap * (_maxThumbs)) / (_maxThumbs + 1)).clamp(28.0, 40.0);
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    for (final e in shown) ...[
                      _Thumb(size: size, child: _Media(exercise: e)),
                      const SizedBox(width: gap),
                    ],
                    if (more > 0)
                      _Thumb(
                        size: size,
                        child: ColoredBox(
                          color: SfColors.text.withValues(alpha: SfColors.isDark ? .12 : .07),
                          child: Center(
                            child: Text(
                              '+$more',
                              style: SfType.label.copyWith(fontWeight: FontWeight.w600, fontFeatures: SfType.tabular),
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text('详情', style: SfType.callout.copyWith(fontSize: 13, color: SfColors.muted)),
                    SfIcon(SfGlyph.chevronRight, size: 15, color: SfColors.muted, strokeWidth: 2),
                    const SizedBox(width: SfSpace.x1),
                  ],
                ),
              );
            },
          ),
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(SfRadius.xs + 2),
    child: SizedBox.square(dimension: size, child: child),
  );
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
          child: Text('$index', style: SfType.label.copyWith(color: SfColors.muted, fontFeatures: SfType.tabular)),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(SfRadius.xs + 2),
          child: SizedBox.square(dimension: 36, child: _Media(exercise: exercise)),
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

/// 「开始」: the card's one prominent action and the app's one raised
/// element (HipLab rule R2): the accent lit from above, a deeper edge of
/// itself, a tight contact shadow — no glow, no gradient halo. It sinks
/// while held. Drawn with the dark accent on the dark stage.
class _StartDisc extends StatelessWidget {
  const _StartDisc({super.key, required this.onTap, this.size = 56});
  final VoidCallback onTap;
  final double size;

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
            dimension: size,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SfIcon(SfGlyph.play, size: size * .32, filled: true, color: on),
                const SizedBox(height: 1),
                Text(
                  '开始',
                  style: TextStyle(color: on, fontSize: size < 52 ? 10.5 : 12, height: 1.15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

