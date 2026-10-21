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
///   name · dose · one cue on the right, tags on the bottom line;
/// * a set → [_SetBody], 240 px: the first move as the hero with title,
///   duration and move count over it, one bottom row with the other moves
///   as thumbnails (as many as fit, then +N).
///
/// The one start control is an icon-only round ▶ (Semantics 「开始训练」)
/// anchored to the card's bottom-right corner: at the end of the bottom
/// row when compact, on the 保存 row when unfolded; there is never a
/// second start.
///
/// Unfolding ([_Timeline]): one clip grows the card; the visible strip
/// thumbnails fly on straight lines into their rows (transform only,
/// ~20 ms apart), moves hidden behind +N fade in place, rows' text fades
/// up only after every thumbnail has landed; ▶ / 保存 fade out and back in
/// at their slots instead of travelling. Animated cutouts hold their still
/// cover during the move. Collapsing mirrors it. Reduced motion: a plain
/// cross-fade.
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

/// Timeline of the unfold on one linear controller value t ∈ [0, 1]
/// (expand 320 ms; collapse plays it backwards in 240 ms).
///
/// Order, so nothing ever overlaps mid-flight:
/// 1. ▶ (and the +N chip) fade / shrink out where they are (first ~80 ms);
///    the clip starts growing at once and has revealed every destination
///    row before a thumbnail arrives there;
/// 2. only the visible strip thumbnails fly, on straight lines, ~20 ms
///    apart; no row text is visible yet, so they never cross text;
/// 3. once the last one has landed, the rows' text fades up (top first);
/// 4. ▶ and 保存 fade / scale in at the bottom row's slots.
/// Collapsing mirrors it: text, ▶ and 保存 are gone before any thumbnail
/// moves.
class _Timeline {
  const _Timeline({required this.flyers, required this.rows});
  final int flyers;
  final int rows;

  static const expandMs = 320;
  static const collapseMs = 240;
  static const flight = .42;

  double get _stagger => flyers <= 1 ? 0 : math.min(20 / expandMs, .18 / (flyers - 1));
  double flyStart(int k) => k * _stagger;

  /// When the last thumbnail has landed (≤ .6).
  double get landed => flyers == 0 ? .3 : flyStart(flyers - 1) + flight;

  /// Thumbnail k's flight progress (0 → 1).
  double fly(int k, double t) => ((t - flyStart(k)) / flight).clamp(0.0, 1.0);

  /// Row [i]'s text (and the hero row's thumbnail): after every flyer has
  /// landed, top row first.
  Interval text(int i) {
    final step = rows <= 1 ? 0.0 : math.min(.025, .15 / (rows - 1));
    final b = landed + i * step;
    return Interval(b, math.min(1, b + .25), curve: SfMotion.standard);
  }

  /// Rows whose move hid behind +N: their thumbnail fades in place (nothing
  /// flies over those rows, they sit under every destination).
  static const inPlace = Interval(.25, .55, curve: SfMotion.standard);

  /// The card height (clip): emphasized decelerate over the first half.
  static const height = Interval(0, .5, curve: Cubic(.05, .7, .1, 1));

  /// ▶ / +N leaving, and ▶ / 保存 / note arriving.
  static const out = Interval(0, .25, curve: Curves.easeIn);
  static const arrive = Interval(.8, 1, curve: SfMotion.standard);
}

/// 1 only once the controller rests at 1: the rows' own thumbnails take
/// over from the flyers when they have landed.
class _AtEnd extends Animatable<double> {
  const _AtEnd();
  @override
  double transform(double t) => t >= 1 ? 1 : 0;
}

/// 1 only at rest folded: the strip's own thumbnails.
class _AtStart extends Animatable<double> {
  const _AtStart();
  @override
  double transform(double t) => t <= 0 ? 1 : 0;
}

class _PlanCardState extends State<PlanCard> with SingleTickerProviderStateMixin {
  final _card = GlobalKey();
  static const _inset = 6.0;

  late final AnimationController _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _Timeline.expandMs),
    reverseDuration: const Duration(milliseconds: _Timeline.collapseMs),
  )..addStatusListener(_onStatus);
  late final Animation<double> _height = CurvedAnimation(parent: _expand, curve: _Timeline.height);
  bool _expanded = false;

  /// True while the card unfolds / folds: animated cutouts show their still
  /// cover meanwhile (no WebP frame decoding during the move).
  bool _moving = false;
  bool _precached = false;

  void _onStatus(AnimationStatus s) {
    final moving = s == AnimationStatus.forward || s == AnimationStatus.reverse;
    if (moving != _moving && mounted) setState(() => _moving = moving);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Decode every thumbnail (and the still cutouts) up front, so the first
    // unfold never decodes an image mid-flight.
    for (final i in widget.plan.items) {
      final e = widget.library.tryGet(i.exerciseId);
      if (e == null) continue;
      final paths = [sfPoster(e), if (SfCutouts.has(e)) SfCutouts.asset(e, still: true)];
      for (final a in paths) {
        precacheImage(AssetImage(a), context, onError: (_, _) {});
      }
    }
  }

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
    final compactH = height - _inset * 2;
    final innerW = width - _inset * 2;

    // The strip: the moves after the hero, as many as fit before the ▶.
    final rest = [for (var i = 1; i < items.length; i++) i];
    final fit = _SetBody.fitCount(innerW);
    final shownCount = single ? 0 : (rest.length <= fit ? rest.length : fit - 1);
    final more = rest.length - shownCount;
    final cues = single ? (moves.firstOrNull?.cues ?? const <String>[]) : const <String>[];
    final timeline = _Timeline(flyers: shownCount, rows: single ? cues.length : items.length);

    final toggle = _ExpandToggle(
      key: ValueKey('plan-expand-${p.id}'),
      expanded: _expanded,
      turns: _height,
      onMedia: !single && !SfCutouts.has(moves.firstOrNull),
      onTap: _toggle,
    );
    final stripThumbs = reduced
        ? ReverseAnimation(CurvedAnimation(parent: _expand, curve: const Interval(0, .45)))
        : _expand.drive(const _AtStart());
    final Widget body = single
        ? _ExerciseBody(
            exercise: moves.firstOrNull,
            item: items.first,
            fallbackName: p.title,
            duration: duration,
            tags: [gearText, if (moves.firstOrNull case final e?) e.category.zh, levelZh(p.level)],
            landing: widget.landing,
            still: _moving,
          )
        : _SetBody(
            cover: lib.tryGet(items.first.exerciseId) ?? moves.firstOrNull,
            shown: [for (final i in rest.take(shownCount)) lib.tryGet(items[i].exerciseId)],
            more: more,
            title: p.title,
            meta: [duration, '${items.length} 个动作', gearText].join(' · '),
            landing: widget.landing,
            still: _moving,
            thumbs: stripThumbs,
            // The +N chip fades in place (its moves fade into their rows).
            chip: reduced
                ? stripThumbs
                : ReverseAnimation(CurvedAnimation(parent: _expand, curve: _Timeline.out)),
          );

    final atEnd = _expand.drive(const _AtEnd());
    Animation<double> textOf(int i) =>
        reduced ? _expand : CurvedAnimation(parent: _expand, curve: timeline.text(i));
    final arrive = reduced ? _expand : CurvedAnimation(parent: _expand, curve: _Timeline.arrive);
    final details = _Details(
      t: _expand,
      height: _height,
      fade: arrive,
      reduced: reduced,
      rows: [
        if (single)
          for (final (i, c) in cues.indexed)
            _CueRow(index: i + 1, text: c, anim: textOf(i), reduced: reduced)
        else
          for (var i = 0; i < items.length; i++)
            _MoveRow(
              key: ValueKey('plan-row-$i'),
              index: i + 1,
              item: circuit[i] ? items[i].copyWith(sets: 1) : items[i],
              exercise: lib.tryGet(items[i].exerciseId),
              text: textOf(i),
              // Rows 1…shown receive a flyer and show their own thumbnail
              // once it has landed; the hero's row arrives with its text;
              // rows hidden behind +N fade in place.
              thumb: reduced
                  ? _expand
                  : i == 0
                  ? textOf(0)
                  : i <= shownCount
                  ? atEnd
                  : CurvedAnimation(parent: _expand, curve: _Timeline.inPlace),
              reduced: reduced,
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
            boxed: true,
          ),
          const Spacer(),
          // The ▶ appears here (it is laid over the card, anchored bottom-right).
          const SizedBox(width: _PlayButton.size),
        ],
      ),
    );

    final start = _PlayButton(
      key: ValueKey('plan-start-${p.id}'),
      onTap: () => widget.onStart(() => rectOf(_card.currentContext)),
    );

    // Flyers: strip slot → row thumbnail, in card coords; each one is a
    // fixed-size row thumbnail moved only by a transform (no layout).
    Offset stripSlot(int k) => Offset(
      SfSpace.x1 + k * (_SetBody.thumb + _SetBody.gap),
      compactH - _SetBody.stripHeight + _SetBody.stripTop + (_SetBody.stripHeight - _SetBody.stripTop - _SetBody.thumb) / 2,
    );
    Offset rowSlot(int i) => Offset(
      _Details.pad + _MoveRow.indexWidth,
      compactH + _Details.pad + _MoveRow.height * i + (_MoveRow.height - _MoveRow.thumbSize) / 2,
    );
    final flyerThumbs = [
      for (var k = 0; k < shownCount; k++)
        RepaintBoundary(child: _MoveRow.thumbFor(lib.tryGet(items[rest[k]].exerciseId))),
    ];
    final flyers = single || reduced || shownCount == 0
        ? const SizedBox.shrink()
        : Positioned.fill(
            child: IgnorePointer(
              // Clipped to the card's current height: a thumbnail is only
              // ever seen inside the part already revealed.
              child: ClipRect(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _expand,
                    builder: (context, _) {
                      final t = _expand.value;
                      if (t <= 0 || t >= 1) return const SizedBox.shrink();
                      return Stack(
                        children: [
                          for (var k = 0; k < shownCount; k++)
                            _flyer(
                              key: ValueKey('fly-$k'),
                              child: flyerThumbs[k],
                              from: stripSlot(k),
                              to: rowSlot(rest[k]),
                              p: timeline.fly(k, t),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          );

    // ▶ never travels over the rows: it fades / shrinks out at its folded
    // slot, and back in at the open one (and the reverse on fold).
    final collapsedRight = single ? 0.0 : SfSpace.x1;
    final collapsedBottom = single ? 0.0 : 1.0;
    final play = AnimatedBuilder(
      animation: _expand,
      builder: (context, child) {
        final t = _expand.value;
        final open = t >= .5;
        final double o = reduced
            ? (t < .5 ? 1 - 2 * t : 2 * t - 1).clamp(0.0, 1.0)
            : open
            ? _Timeline.arrive.transform(t)
            : 1 - _Timeline.out.transform(t);
        return Positioned(
          right: open ? _Details.pad : collapsedRight,
          bottom: open ? _Details.footerBottom : collapsedBottom,
          child: IgnorePointer(
            ignoring: o < .5,
            child: Opacity(
              key: const ValueKey('plan-start-fade'),
              opacity: o,
              child: reduced || o == 1 ? child : Transform.scale(scale: .7 + .3 * o, child: child),
            ),
          ),
        );
      },
      child: start,
    );

    Widget card = SfGlassSurface(
      radius: SfRadius.lg,
      width: width,
      padding: const EdgeInsets.all(_inset),
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The compact card: fixed height by type. The whole of it
              // opens the plan page; the toggle sits on top as its own
              // button (own semantics node).
              SizedBox(
                height: compactH,
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
                        child: RepaintBoundary(child: body),
                      ),
                    ),
                    if (single)
                      Positioned(right: 0, top: 0, child: toggle)
                    else
                      Positioned(right: SfSpace.x1, top: SfSpace.x1, child: toggle),
                  ],
                ),
              ),
              details,
            ],
          ),
          flyers,
          play,
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

  /// One flying thumbnail at flight progress [p]: a straight line on the
  /// emphasized curve, growing from the strip size to the row size. Moved
  /// by a transform only.
  Widget _flyer({required Key key, required Widget child, required Offset from, required Offset to, required double p}) {
    final e = Curves.easeInOutCubicEmphasized.transform(p);
    const s0 = _SetBody.thumb / _MoveRow.thumbSize;
    final o = Offset.lerp(from, to, e)!;
    final s = s0 + (1 - s0) * e;
    return Positioned(
      key: key,
      left: 0,
      top: 0,
      width: _MoveRow.thumbSize,
      height: _MoveRow.thumbSize,
      child: Transform(
        transform: Matrix4.translationValues(o.dx, o.dy, 0)..scaleByDouble(s, s, 1, 1),
        child: child,
      ),
    );
  }
}

/// The in-place details: the full move list (or a move's cues), notes and
/// the 保存 footer (the ▶ is laid over its right end). The clip grows on
/// [height]; each row animates itself (text after its thumbnail lands).
/// Reduced motion: no height move, the whole block fades.
class _Details extends StatelessWidget {
  const _Details({
    required this.t,
    required this.height,
    required this.fade,
    required this.reduced,
    required this.rows,
    required this.footer,
    this.note,
  });
  final Animation<double> t;
  final Animation<double> height;

  /// Note and the 保存 row: in at the end, out first on fold.
  final Animation<double> fade;
  final bool reduced;
  final List<Widget> rows;
  final Widget footer;
  final String? note;

  /// Side / top padding of the list.
  static const pad = SfSpace.x2;

  /// Divider → footer row, and footer row → card content edge.
  static const footerTop = 14.0;
  static const footerBottom = 4.0;
  static const footerRow = 48.0;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(pad, pad, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...rows,
          if (note != null)
            FadeTransition(
              opacity: fade,
              child: Padding(
                padding: const EdgeInsets.only(top: SfSpace.x1),
                child: Text(note!, style: SfType.caption),
              ),
            ),
          FadeTransition(
            opacity: fade,
            child: Container(
              margin: const EdgeInsets.only(top: SfSpace.x2),
              padding: const EdgeInsets.only(top: footerTop, bottom: footerBottom),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: SfColors.text.withValues(alpha: .08))),
              ),
              child: SizedBox(height: footerRow, child: footer),
            ),
          ),
        ],
      ),
    );
    if (reduced) content = FadeTransition(opacity: t, child: content);

    return AnimatedBuilder(
      animation: height,
      builder: (context, child) {
        if (t.value == 0) return const SizedBox(width: double.infinity);
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: reduced ? 1 : height.value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: RepaintBoundary(child: content),
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
    final glass = SfColors.isDark && !onMedia;
    final fg = onMedia ? Colors.white : glass ? SfColors.text : SfColors.muted;
    final label = expanded ? '收起' : '展开';
    return SfPressable(
      semanticLabel: expanded ? '收起详情' : '展开详情',
      expanded: expanded,
      haptic: SfHaptic.selection,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        child: Center(
          child: _toggleFace(
            glass: glass,
            onMedia: onMedia,
            child: Padding(
              padding: glass ? const EdgeInsets.fromLTRB(12, 9, 9, 9) : const EdgeInsets.fromLTRB(10, 5, 7, 5),
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

/// Dark on the glass card: the idle control face; otherwise the quiet tonal
/// pill (light) or the scrim pill over media.
Widget _toggleFace({required bool glass, required bool onMedia, required Widget child}) => glass
    ? SfControlFace(padding: EdgeInsets.zero, minHeight: 0, child: child)
    : DecoratedBox(
        decoration: ShapeDecoration(
          color: onMedia ? const Color(0x66000000) : SfColors.text.withValues(alpha: SfColors.isDark ? .10 : .06),
          shape: const StadiumBorder(),
        ),
        child: child,
      );

class _CueRow extends StatelessWidget {
  const _CueRow({required this.index, required this.text, required this.anim, required this.reduced});
  final int index;
  final String text;
  final Animation<double> anim;
  final bool reduced;

  @override
  Widget build(BuildContext context) => _rowIn(
    anim: anim,
    reduced: reduced,
    child: Padding(
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
    ),
  );
}

/// A row's text arriving: fade + a short slide from the left (none under
/// reduced motion, where the whole details block fades instead).
Widget _rowIn({Key? key, required Animation<double> anim, required bool reduced, required Widget child}) => reduced
    ? child
    : FadeTransition(
        key: key,
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(-.04, 0), end: Offset.zero).animate(anim),
          child: child,
        ),
      );

/// The cover image on its stage colour; settles from 1.04 as a card lands.
class _Media extends StatelessWidget {
  const _Media({required this.exercise, this.landing = false, this.cutout = false, this.still = false});
  final Exercise? exercise;
  final bool landing;

  /// Show the cutout's still cover (while the card unfolds / folds).
  final bool still;

  /// The keyed figure straight on the glass (no stage box), when [exercise]
  /// has one ([SfCutouts]); otherwise the boxed cover as before.
  final bool cutout;

  @override
  Widget build(BuildContext context) {
    final e = exercise;
    if (cutout && e != null && SfCutouts.has(e)) {
      final reduced = SfMotion.reduced(context);
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: landing && !reduced ? 1.04 : 1, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: SfMotion.standard,
        builder: (_, k, img) => k == 1 ? img! : Transform.scale(scale: k, child: img),
        child: Image.asset(
          SfCutouts.asset(e, still: reduced || still),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: e.name,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );
    }
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

/// One move: square preview left; name, dose, one cue right, tags on the
/// bottom line beside 开始训练.
class _ExerciseBody extends StatelessWidget {
  const _ExerciseBody({
    required this.exercise,
    required this.item,
    required this.fallbackName,
    required this.duration,
    required this.tags,
    this.landing = false,
    this.still = false,
  });
  final bool still;
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
          child: SfCutouts.has(e)
              ? _Media(exercise: e, landing: landing, cutout: true, still: still)
              : ClipRRect(
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
                if (cue.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    cue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SfType.caption.copyWith(color: SfColors.muted),
                  ),
                ],
                const Spacer(),
                // Tags share the bottom line with the ▶ (its 48 px disc
                // sits on the card's bottom edge; centres line up).
                Padding(
                  padding: const EdgeInsets.only(right: _PlayButton.reserve, bottom: 9),
                  child: _Tags(tags),
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
/// lower edge), the other moves as a strip of thumbnails under it. The
/// card lays the ▶ over the strip's right end and flies the thumbnails
/// into the list as it unfolds ([thumbs] / [chip] hide them meanwhile).
class _SetBody extends StatelessWidget {
  const _SetBody({
    required this.cover,
    required this.shown,
    required this.more,
    required this.title,
    required this.meta,
    required this.thumbs,
    required this.chip,
    this.landing = false,
    this.still = false,
  });
  final bool still;
  final Exercise? cover;
  final List<Exercise?> shown;
  final int more;
  final Animation<double> thumbs;
  final Animation<double> chip;
  final String title;
  final String meta;
  final bool landing;

  static const stripHeight = 52.0;
  static const stripTop = 6.0;
  static const thumb = 36.0;
  static const gap = 6.0;

  /// Slots in the strip for a card content width (the last one turns
  /// into +N when some moves don't fit).
  static int fitCount(double width) {
    final room = width - SfSpace.x1 - _PlayButton.reserve - SfSpace.x1;
    return ((room + gap) / (thumb + gap)).floor().clamp(1, 99);
  }

  @override
  Widget build(BuildContext context) {
    final cover = this.cover;
    final stage = sfStageFor(cover);
    // A keyed figure stands straight on the glass: no stage box, no scrim,
    // the title in the page's own ink under it.
    final fused = SfCutouts.has(cover);
    final titleColor = fused ? SfColors.text : stage.onStage;
    final metaColor = fused ? SfColors.muted : stage.onStageMuted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: fused
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: SfSpace.x4,
                      right: SfSpace.x4,
                      top: SfSpace.x1,
                      bottom: 50,
                      child: _Media(exercise: cover, landing: landing, cutout: true, still: still),
                    ),
                    Positioned(
                      left: SfSpace.x4,
                      right: SfSpace.x4,
                      bottom: SfSpace.x3,
                      child: _HeroTitle(title: title, meta: meta, titleColor: titleColor, metaColor: metaColor),
                    ),
                  ],
                )
              : ClipRRect(
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
                  right: SfSpace.x4,
                  bottom: SfSpace.x3,
                  child: _HeroTitle(title: title, meta: meta, titleColor: titleColor, metaColor: metaColor),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: stripHeight,
          child: Padding(
            padding: const EdgeInsets.only(top: stripTop, left: SfSpace.x1),
            child: Row(
              children: [
                for (final e in shown) ...[
                  FadeTransition(opacity: thumbs, child: _Thumb(size: thumb, child: _Media(exercise: e))),
                  const SizedBox(width: gap),
                ],
                if (more > 0)
                  FadeTransition(
                    opacity: chip,
                    child: _Thumb(
                      size: thumb,
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
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.title, required this.meta, required this.titleColor, required this.metaColor});
  final String title;
  final String meta;
  final Color titleColor;
  final Color metaColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: titleColor, fontSize: 19, height: 1.25, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 2),
      Text(
        meta,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: metaColor, fontSize: 13, height: 1.35, fontWeight: FontWeight.w500),
      ),
    ],
  );
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
  const _MoveRow({
    super.key,
    required this.index,
    required this.item,
    required this.exercise,
    required this.text,
    required this.thumb,
    required this.reduced,
  });
  final int index;
  final PlanItem item;
  final Exercise? exercise;

  /// The number, name and dose arriving (after the thumbnail lands).
  final Animation<double> text;

  /// The row's own thumbnail (hidden while its flyer is in the air).
  final Animation<double> thumb;
  final bool reduced;

  static const height = 48.0;
  static const indexWidth = 20.0;
  static const thumbSize = 40.0;

  /// The row's thumbnail (also what flies in from the strip).
  static Widget thumbFor(Exercise? e) => ClipRRect(
    borderRadius: BorderRadius.circular((SfRadius.xs + 2) * thumbSize / _SetBody.thumb),
    child: SizedBox.square(dimension: thumbSize, child: _Media(exercise: e)),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      children: [
        _rowIn(
          anim: text,
          reduced: reduced,
          child: SizedBox(
            width: indexWidth,
            child: Text('$index', style: SfType.label.copyWith(color: SfColors.muted, fontFeatures: SfType.tabular)),
          ),
        ),
        FadeTransition(opacity: thumb, child: thumbFor(exercise)),
        const SizedBox(width: SfSpace.x3),
        Expanded(
          child: _rowIn(
            key: const ValueKey('row-text'),
            anim: text,
            reduced: reduced,
            child: Row(
              children: [
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
          ),
        ),
      ],
    ),
  );
}

/// ▶ 开始训练: the card's one prominent action and the app's one raised
/// element (HipLab rule R2): an icon-only round accent button, lit from
/// above, a deeper edge of itself, a tight contact shadow — no glow, no
/// halo. It sinks while held. 48 px visual = 48 px tap box; Semantics and
/// tooltip 「开始训练」. Drawn with the dark accent on the dark stage.
class _PlayButton extends StatelessWidget {
  const _PlayButton({super.key, required this.onTap});
  final VoidCallback onTap;

  static const size = 48.0;

  /// Width the bottom line keeps clear for it (button + breathing room).
  static const reserve = size + SfSpace.x2;

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
      child: SizedBox.square(
        dimension: size,
        child: Builder(
          builder: (context) => SfTactile(
            key: const ValueKey('start-disc'),
            style: SfTactileStyle.accent(dark: dark, color: accent),
            pressed: SfPressedScope.of(context),
            radius: size / 2,
            child: Center(
              // Optically centred: a triangle's mass sits left of its box.
              child: Padding(
                padding: const EdgeInsets.only(left: 2),
                child: SfIcon(SfGlyph.play, size: 18, filled: true, color: on),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
