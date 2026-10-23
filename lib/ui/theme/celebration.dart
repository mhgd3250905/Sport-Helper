import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'sf_icons.dart';
import 'tokens.dart';

/// The finish screen's one moment (docs/design-audit-2026-10-19.md M16),
/// kept small on purpose: the check draws itself, one thin accent ring
/// goes out once and fades, then the title, the plan name and the stats
/// fade in one after another and the numbers count up. No confetti, no
/// loop, one medium tap. An early end gets no ring and no tap. Reduced
/// motion: everything is simply there.
///
/// One controller drives the whole timeline ([SfFinishTimeline]); children
/// read their slice with [SfFinishTimeline.of].
class SfFinishTimeline extends StatefulWidget {
  const SfFinishTimeline({super.key, required this.full, required this.child});

  /// A finished workout (ring + tap); false for an early end.
  final bool full;
  final Widget child;

  /// Total length: check 0–520, ring 360–1260, texts from 420, count-up
  /// 640–1340.
  static const total = Duration(milliseconds: 1400);

  static Animation<double> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FinishScope>()?.t ?? kAlwaysCompleteAnimation;

  /// [t] mapped onto [begin, end] ms of the timeline, eased.
  static Animation<double> slice(Animation<double> t, int begin, int end, {Curve curve = SfMotion.standard}) {
    final ms = total.inMilliseconds;
    return CurvedAnimation(parent: t, curve: Interval(begin / ms, end / ms, curve: curve));
  }

  @override
  State<SfFinishTimeline> createState() => _SfFinishTimelineState();
}

class _SfFinishTimelineState extends State<SfFinishTimeline> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: SfFinishTimeline.total);
  bool _begun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    if (widget.full) SfHaptic.medium.play();
    if (SfMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FinishScope(t: _c, child: widget.child);
}

class _FinishScope extends InheritedWidget {
  const _FinishScope({required this.t, required super.child});
  final Animation<double> t;
  @override
  bool updateShouldNotify(_FinishScope old) => old.t != t;
}

/// The mark at the top: a tinted disc with a check drawn stroke by stroke
/// (or the stop glyph for an early end), and — finished only — one ring
/// expanding out of the disc and fading.
class SfFinishMark extends StatelessWidget {
  const SfFinishMark({super.key, required this.full, this.size = 80});
  final bool full;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = SfFinishTimeline.of(context);
    final draw = SfFinishTimeline.slice(t, 0, 520);
    final ring = SfFinishTimeline.slice(t, 360, 1260, curve: Curves.easeOutCubic);
    final disc = SfFinishTimeline.slice(t, 0, 360);
    return SizedBox.square(
      dimension: size * 1.9,
      child: AnimatedBuilder(
        animation: t,
        builder: (_, _) => CustomPaint(
          painter: full
              ? _RipplePainter(
                  progress: ring.value,
                  color: SfColors.emphasis,
                  inner: size / 2,
                )
              : null,
          child: Center(
            child: Opacity(
              opacity: disc.value,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: full ? SfColors.emphasisSoft : SfColors.surfaceHigh,
                ),
                alignment: Alignment.center,
                child: full
                    ? CustomPaint(
                        size: Size.square(size * .5),
                        painter: _CheckPainter(draw.value, SfColors.emphasisText),
                      )
                    : SfIcon(SfGlyph.stop, size: size * .47, strokeWidth: 2.2, color: SfColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final s = size.width / 24;
    final path = Path()
      ..moveTo(5 * s, 12.6 * s)
      ..lineTo(9.8 * s, 17.2 * s)
      ..lineTo(19 * s, 7.4 * s);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (t >= 1) {
      canvas.drawPath(path, paint);
      return;
    }
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (a, PathMetric m) => a + m.length);
    var left = total * t;
    for (final m in metrics) {
      final take = left.clamp(0.0, m.length);
      canvas.drawPath(m.extractPath(0, take), paint);
      left -= take;
      if (left <= 0) break;
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress, required this.color, required this.inner});
  final double progress;
  final Color color;
  final double inner;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final outer = size.width / 2;
    final r = inner + (outer - inner) * progress;
    canvas.drawCircle(
      size.center(Offset.zero),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * (1 - progress) + .6
        ..color = color.withValues(alpha: .55 * (1 - progress)),
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.progress != progress || old.color != color;
}

/// A child fading in (and rising 8 px) at [beginMs] of the finish timeline.
class SfFinishReveal extends StatelessWidget {
  const SfFinishReveal({super.key, required this.beginMs, required this.child});
  final int beginMs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = SfFinishTimeline.slice(SfFinishTimeline.of(context), beginMs, beginMs + 280);
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (_, c) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, 8 * (1 - a.value)), child: c),
      ),
    );
  }
}

/// Whole numbers counting up from 0 over the finish timeline's count-up
/// slice; [format] lays them out ('12', '9/10').
class SfFinishCount extends StatelessWidget {
  const SfFinishCount({super.key, required this.values, required this.format, required this.style});
  final List<int> values;
  final String Function(List<int>) format;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final a = SfFinishTimeline.slice(SfFinishTimeline.of(context), 640, 1340);
    return AnimatedBuilder(
      animation: a,
      builder: (_, _) => Text(
        format([for (final v in values) (v * a.value).round()]),
        style: style,
      ),
    );
  }
}
