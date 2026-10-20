// Light skeuomorphic ("tactile") faces, adapted from HipLab
// `lib/hip/ui/hip_tactile.dart` (@2d47520, read-only reference) and its
// rules in `docs/tactile-design-rationale-2026-10-19.md` there.
//
// SmartFit's budget (docs/design-audit-2026-10-19.md §1 H2), checked by
// test/aesthetic_budget_test.dart:
//
// * [SfTactileStyle.accent] — the plan card's 开始 disc only: the one hero
//   action, sitting on a media stage (R2);
// * [SfTactileStyle.neutral] — the sliding thumb of [SfSegmented] only: the
//   one control part that really moves along a track (R1).
//
// Everything else stays flat or tonal: emphasis by colour, not height.
// Shadows are stacked inflated shapes instead of a blur filter (same look
// on device and in widget-test screenshots, no offscreen blur pass).
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

@immutable
class SfTactileShadow {
  const SfTactileShadow(this.color, {required this.blur, this.dy = 0});
  final Color color;
  final double blur;
  final double dy;

  SfTactileShadow scaled({double alpha = 1, double blur = 1, double dy = 1}) => SfTactileShadow(
    color.withValues(alpha: (color.a * alpha).clamp(0.0, 1.0)),
    blur: this.blur * blur,
    dy: this.dy * dy,
  );

  static SfTactileShadow lerp(SfTactileShadow a, SfTactileShadow b, double t) => SfTactileShadow(
    Color.lerp(a.color, b.color, t)!,
    blur: lerpDouble(a.blur, b.blur, t)!,
    dy: lerpDouble(a.dy, b.dy, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is SfTactileShadow && other.color == color && other.blur == blur && other.dy == dy;

  @override
  int get hashCode => Object.hash(color, blur, dy);
}

/// One tactile material: a fill lit from above, a 1 px inner highlight on
/// the top edge, a hairline stroke, a tight contact shadow plus a small
/// ambient one. No coloured glow, no large halo.
@immutable
class SfTactileStyle {
  const SfTactileStyle({
    required this.base,
    this.lighten = 0,
    this.darken = 0,
    this.highlight = const Color(0x00FFFFFF),
    this.stroke = const Color(0x00000000),
    this.strokeBottom,
    this.shadows = const [],
  });

  final Color base;
  final double lighten;
  final double darken;
  final Color highlight;
  final Color stroke;
  final Color? strokeBottom;
  final List<SfTactileShadow> shadows;

  Color get top => Color.lerp(base, const Color(0xFFFFFFFF), lighten)!;
  Color get bottom => Color.lerp(base, const Color(0xFF000000), darken)!;

  /// The segmented thumb (R1). Dark: a tile one step above the track with
  /// an 8 % top light; light: white, hairline edge, ink (never coloured)
  /// shadow.
  factory SfTactileStyle.neutral([SfPalette? palette]) {
    final p = palette ?? SfColors.palette;
    return p.isDark
        ? SfTactileStyle(
            base: p.thumb,
            lighten: .08,
            darken: .10,
            highlight: const Color(0x24FFFFFF),
            stroke: const Color(0x0FFFFFFF),
            strokeBottom: const Color(0x05FFFFFF),
            shadows: const [
              SfTactileShadow(Color(0x73000000), blur: 2, dy: 1),
              SfTactileShadow(Color(0x40000000), blur: 6, dy: 3),
            ],
          )
        : const SfTactileStyle(
            base: Color(0xFFFFFFFF),
            darken: .035,
            highlight: Color(0xFFFFFFFF),
            stroke: Color(0x120D2A20),
            strokeBottom: Color(0x240D2A20),
            shadows: [
              SfTactileShadow(Color(0x240D2A20), blur: 2, dy: 1),
              SfTactileShadow(Color(0x140D2A20), blur: 7, dy: 3),
            ],
          );
  }

  /// The 开始 disc (R2): the accent with a deeper edge of itself instead of
  /// a glow. Light keeps lower shadow opacity than dark (R6).
  factory SfTactileStyle.accent({required bool dark, required Color color}) {
    final c = color;
    return dark
        ? SfTactileStyle(
            base: c,
            lighten: .16,
            darken: .10,
            highlight: const Color(0x73FFFFFF),
            stroke: Color.lerp(c, const Color(0xFF000000), .30)!.withValues(alpha: .55),
            strokeBottom: Color.lerp(c, const Color(0xFF000000), .45)!.withValues(alpha: .75),
            shadows: const [
              SfTactileShadow(Color(0x80000000), blur: 2, dy: 1.5),
              SfTactileShadow(Color(0x47000000), blur: 7, dy: 3.5),
            ],
          )
        : SfTactileStyle(
            base: c,
            lighten: .14,
            darken: .08,
            highlight: const Color(0x66FFFFFF),
            stroke: Color.lerp(c, const Color(0xFF000000), .25)!.withValues(alpha: .45),
            strokeBottom: Color.lerp(c, const Color(0xFF000000), .40)!.withValues(alpha: .55),
            shadows: const [
              SfTactileShadow(Color(0x470D2A20), blur: 2, dy: 1),
              SfTactileShadow(Color(0x1F0D2A20), blur: 7, dy: 3),
            ],
          );
  }

  /// Pushed in: the top light and highlight mostly gone, the contact shadow
  /// tucked under, the ambient one gone, the fill a touch darker.
  SfTactileStyle pressed() => SfTactileStyle(
    base: Color.lerp(base, const Color(0xFF000000), .05)!.withValues(alpha: base.a),
    lighten: lighten * .3,
    darken: darken,
    highlight: highlight.withValues(alpha: highlight.a * .35),
    stroke: stroke,
    strokeBottom: strokeBottom,
    shadows: [
      for (final (i, s) in shadows.indexed)
        i == 0 ? s.scaled(blur: .6, dy: .4) : s.scaled(alpha: 0, dy: .5),
    ],
  );

  static SfTactileStyle lerp(SfTactileStyle a, SfTactileStyle b, double t) {
    if (t == 0) return a;
    if (t == 1) return b;
    final n = math.max(a.shadows.length, b.shadows.length);
    SfTactileShadow at(List<SfTactileShadow> l, int i) =>
        i < l.length ? l[i] : const SfTactileShadow(Color(0x00000000), blur: 0);
    return SfTactileStyle(
      base: Color.lerp(a.base, b.base, t)!,
      lighten: lerpDouble(a.lighten, b.lighten, t)!,
      darken: lerpDouble(a.darken, b.darken, t)!,
      highlight: Color.lerp(a.highlight, b.highlight, t)!,
      stroke: Color.lerp(a.stroke, b.stroke, t)!,
      strokeBottom: Color.lerp(a.strokeBottom ?? a.stroke, b.strokeBottom ?? b.stroke, t),
      shadows: [for (var i = 0; i < n; i++) SfTactileShadow.lerp(at(a.shadows, i), at(b.shadows, i), t)],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SfTactileStyle &&
      other.base == base &&
      other.lighten == lighten &&
      other.darken == darken &&
      other.highlight == highlight &&
      other.stroke == stroke &&
      other.strokeBottom == strokeBottom &&
      _eq(other.shadows, shadows);

  static bool _eq(List<SfTactileShadow> a, List<SfTactileShadow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(base, lighten, darken, highlight, stroke, strokeBottom, Object.hashAll(shadows));
}

/// Paints [style] behind [child] (a stadium / rounded rect of [radius], or
/// a disc with [circle]); sinks over [SfMotion.press] while [pressed].
class SfTactile extends StatelessWidget {
  const SfTactile({
    super.key,
    required this.style,
    required this.pressed,
    this.radius = 14,
    this.circle = false,
    this.child,
  });
  final SfTactileStyle style;
  final bool pressed;
  final double radius;
  final bool circle;
  final Widget? child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: pressed ? 1 : 0),
    duration: pressed ? SfMotion.press : SfMotion.release,
    curve: pressed ? Curves.easeOut : Curves.easeOutCubic,
    builder: (context, t, child) => CustomPaint(
      painter: SfTactilePainter(SfTactileStyle.lerp(style, style.pressed(), t), radius: radius, circle: circle),
      child: child,
    ),
    child: child,
  );
}

class SfTactilePainter extends CustomPainter {
  SfTactilePainter(this.style, {this.radius = 14, this.circle = false});
  final SfTactileStyle style;
  final double radius;
  final bool circle;

  static int layersFor(double blur) => (blur * 1.2).ceil().clamp(2, 8);

  RRect _shape(Rect r) => RRect.fromRectAndRadius(
    r,
    Radius.circular(circle ? r.shortestSide / 2 : math.min(radius, r.shortestSide / 2)),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shape = _shape(rect);
    final s = style;
    for (final sh in s.shadows) {
      if (sh.color.a <= 0 || sh.blur < 0) continue;
      final n = layersFor(sh.blur);
      final a = 1 - math.pow(1 - sh.color.a, 1 / n).toDouble();
      final paint = Paint()..color = sh.color.withValues(alpha: a);
      for (var i = 0; i < n; i++) {
        final grow = sh.blur * (i + .5) / n - sh.blur * .35;
        canvas.drawRRect(shape.shift(Offset(0, sh.dy)).inflate(grow), paint);
      }
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.top, s.base, s.bottom],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    final bottom = s.strokeBottom ?? s.stroke;
    if (s.stroke.a > 0 || bottom.a > 0) {
      canvas.drawRRect(
        shape.deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.stroke, bottom],
          ).createShader(rect),
      );
    }
    if (s.highlight.a > 0) {
      final reach = math.min(size.height * .5, math.max(shape.tlRadiusY, 8));
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRRect(
        shape.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.highlight, s.highlight.withValues(alpha: 0)],
            stops: [0, (reach / size.height).clamp(.05, 1.0)],
          ).createShader(rect),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SfTactilePainter old) =>
      old.style != style || old.radius != radius || old.circle != circle;
}
