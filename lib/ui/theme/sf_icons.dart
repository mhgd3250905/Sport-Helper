import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// SmartFit's icon set: HipLab's glyphs (mhgd3250905/HipLab
/// lib/hip/ui/hip_icons.dart, same author) plus the few SmartFit needs
/// (skipPrevious, bookmark, arrowUp, more, grid, sliders, swap, clock,
/// sparkle), drawn on the same grid so the app has one icon language.
///
/// One visual system: a 24-unit grid with a 2-unit safe margin, 1.75-unit
/// strokes with round caps and joins, corner radii from the same small set
/// (1.5 / 3 / 4.5), and every glyph drawn in two states: outline (default)
/// and filled ([SfIcon.filled]) — e.g. the selected bottom tab. Solid
/// glyphs (play, pause, skip, bolt) are filled in both states. Play
/// triangles are rounded and shifted for optical centring.
enum SfGlyph {
  play,
  pause,
  skipNext,
  close,
  back,
  chevronRight,
  check,
  checkCircle,
  loop,
  chair,
  home,
  flame,
  today,
  checkup,
  progress,
  radar,
  bolt,
  pinch,
  volume,
  volumeLow,
  subtitles,
  info,
  clipboard,
  copy,
  shield,
  bell,
  voice,
  contrast,
  stop,
  figure,
  dancer,
  person,
  bandage,
  skipPrevious,
  bookmark,
  arrowUp,
  more,
  grid,
  sliders,
  swap,
  clock,
  sparkle,
}

/// Draws a [SfGlyph]. Size and colour default to the ambient [IconTheme],
/// so it drops in wherever an `Icon` was (buttons, list tiles).
class SfIcon extends StatelessWidget {
  const SfIcon(
    this.glyph, {
    super.key,
    this.size,
    this.color,
    this.filled = false,
    this.strokeWidth,
    this.semanticLabel,
  });

  final SfGlyph glyph;
  final double? size;
  final Color? color;
  final bool filled;

  /// Stroke in grid units (default 1.75 of 24).
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    var c = color ?? theme.color ?? const Color(0xff000000);
    final opacity = theme.opacity;
    if (color == null && opacity != null && opacity < 1) {
      c = c.withValues(alpha: c.a * opacity);
    }
    final icon = SizedBox.square(
      dimension: s,
      child: CustomPaint(
        painter: SfIconPainter(
          glyph,
          color: c,
          filled: filled,
          strokeWidth: strokeWidth ?? 1.75,
        ),
      ),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: icon)
        : Semantics(
            label: semanticLabel,
            child: ExcludeSemantics(child: icon),
          );
  }
}

class SfIconPainter extends CustomPainter {
  SfIconPainter(
    this.glyph, {
    required this.color,
    this.filled = false,
    this.strokeWidth = 1.75,
  });
  final SfGlyph glyph;
  final Color color;
  final bool filled;
  final double strokeWidth;

  late Paint _stroke;
  late Paint _fill;

  /// Paints over what is already in the layer with transparency (knockouts
  /// in filled glyphs: the play triangle cut out of a solid disc, etc.).
  late Paint _cutStroke;
  late Paint _cutFill;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 24;
    canvas.save();
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    // Never thinner than ~1.1 device-independent px at tiny sizes.
    final sw = math.max(strokeWidth, 1.1 / k);
    _stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color
      ..isAntiAlias = true;
    _fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color
      ..isAntiAlias = true;
    _cutStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.dstOut;
    _cutFill = Paint()..blendMode = BlendMode.dstOut;
    canvas.saveLayer(const Rect.fromLTWH(-2, -2, 28, 28), Paint());
    _draw(canvas);
    canvas.restore();
    canvas.restore();
  }

  void _draw(Canvas c) {
    switch (glyph) {
      case SfGlyph.play:
        // Rounded triangle; its box sits 1.4 right of centre so the visual
        // mass (≈ the centroid) lands on the centre line.
        final p = roundedPolygon(const [
          Offset(8, 5.4),
          Offset(8, 18.6),
          Offset(18.9, 12),
        ], 2.4);
        c.drawPath(p, _fill);
        c.drawPath(p, _stroke);
      case SfGlyph.pause:
        for (final x in [6.6, 13.4]) {
          final r = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, 5.2, 4, 13.6),
            const Radius.circular(1.6),
          );
          c.drawRRect(r, _fill);
        }
      case SfGlyph.skipNext:
        final p = roundedPolygon(const [
          Offset(5.6, 6.2),
          Offset(5.6, 17.8),
          Offset(14.6, 12),
        ], 2.1);
        c.drawPath(p, _fill);
        c.drawPath(p, _stroke);
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(16.3, 6, 2.8, 12),
            const Radius.circular(1.4),
          ),
          _fill,
        );
      case SfGlyph.close:
        c.drawLine(const Offset(6.5, 6.5), const Offset(17.5, 17.5), _stroke);
        c.drawLine(const Offset(17.5, 6.5), const Offset(6.5, 17.5), _stroke);
      case SfGlyph.back:
        c.drawPath(
          _poly(const [Offset(14.5, 5.5), Offset(8, 12), Offset(14.5, 18.5)]),
          _stroke,
        );
      case SfGlyph.chevronRight:
        c.drawPath(
          _poly(const [Offset(9.5, 5.5), Offset(16, 12), Offset(9.5, 18.5)]),
          _stroke,
        );
      case SfGlyph.check:
        c.drawPath(
          _poly(const [Offset(5, 12.6), Offset(9.8, 17.2), Offset(19, 7.4)]),
          _stroke,
        );
      case SfGlyph.checkCircle:
        final check = _poly(const [
          Offset(8, 12.4),
          Offset(10.9, 15.2),
          Offset(16.2, 9.4),
        ]);
        if (filled) {
          c.drawCircle(const Offset(12, 12), 9.6, _fill);
          c.drawPath(check, _cutStroke);
        } else {
          c.drawCircle(const Offset(12, 12), 9, _stroke);
          c.drawPath(check, _stroke);
        }
      case SfGlyph.loop:
        c.drawPath(
          Path()
            ..moveTo(4.5, 12.5)
            ..lineTo(4.5, 10)
            ..arcToPoint(const Offset(8.5, 6), radius: const Radius.circular(4))
            ..lineTo(18.5, 6),
          _stroke,
        );
        c.drawPath(
          _poly(const [Offset(15.6, 3.1), Offset(18.5, 6), Offset(15.6, 8.9)]),
          _stroke,
        );
        c.drawPath(
          Path()
            ..moveTo(19.5, 11.5)
            ..lineTo(19.5, 14)
            ..arcToPoint(
              const Offset(15.5, 18),
              radius: const Radius.circular(4),
            )
            ..lineTo(5.5, 18),
          _stroke,
        );
        c.drawPath(
          _poly(const [Offset(8.4, 15.1), Offset(5.5, 18), Offset(8.4, 20.9)]),
          _stroke,
        );
      case SfGlyph.chair:
        // Office chair in profile: tall back, seat, gas lift, castors.
        final back = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.6, 3.4, 4.4, 9.8),
          const Radius.circular(2.2),
        );
        final seat = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.6, 11.4, 12.8, 3.4),
          const Radius.circular(1.7),
        );
        if (filled) {
          c.drawRRect(back, _fill);
          c.drawRRect(seat, _fill);
        }
        c.drawRRect(back, _stroke);
        c.drawRRect(seat, _stroke);
        c.drawLine(const Offset(12.6, 14.8), const Offset(12.6, 18.2), _stroke);
        c.drawLine(const Offset(7.6, 18.2), const Offset(17.6, 18.2), _stroke);
        for (final x in [7.6, 17.6]) {
          final wheel = Offset(x, 20.4);
          if (filled) c.drawCircle(wheel, 1.2, _fill);
          c.drawCircle(wheel, filled ? 1.2 : .9, filled ? _fill : _stroke);
        }
      case SfGlyph.home:
        final house = Path()
          ..moveTo(12, 4.4)
          ..lineTo(18.6, 9.9)
          ..lineTo(18.6, 17.9)
          ..arcToPoint(
            const Offset(16.6, 19.9),
            radius: const Radius.circular(2),
          )
          ..lineTo(7.4, 19.9)
          ..arcToPoint(
            const Offset(5.4, 17.9),
            radius: const Radius.circular(2),
          )
          ..lineTo(5.4, 9.9)
          ..close();
        final door = Path()
          ..moveTo(10, 19.9)
          ..lineTo(10, 16.2)
          ..arcToPoint(const Offset(14, 16.2), radius: const Radius.circular(2))
          ..lineTo(14, 19.9);
        if (filled) {
          c.drawPath(house, _fill);
          c.drawPath(house, _stroke);
          c.drawPath(door..close(), _cutFill);
        } else {
          c.drawPath(
            Path()
              ..moveTo(3.6, 11.4)
              ..lineTo(12, 4.4)
              ..lineTo(20.4, 11.4),
            _stroke,
          );
          c.drawPath(
            Path()
              ..moveTo(5.4, 9.9)
              ..lineTo(5.4, 17.9)
              ..arcToPoint(
                const Offset(7.4, 19.9),
                radius: const Radius.circular(2),
                clockwise: false,
              )
              ..lineTo(16.6, 19.9)
              ..arcToPoint(
                const Offset(18.6, 17.9),
                radius: const Radius.circular(2),
                clockwise: false,
              )
              ..lineTo(18.6, 9.9),
            _stroke,
          );
          c.drawPath(door, _stroke);
        }
      case SfGlyph.flame:
        final outer = Path()
          ..moveTo(12, 3)
          ..cubicTo(14.8, 5.6, 18.5, 9.2, 18.5, 13.8)
          ..cubicTo(18.5, 17.6, 15.6, 20.6, 12, 20.6)
          ..cubicTo(8.4, 20.6, 5.5, 17.6, 5.5, 13.8)
          ..cubicTo(5.5, 11.2, 6.7, 9.1, 8.3, 7.7)
          ..cubicTo(8.5, 9.5, 9.4, 10.8, 10.6, 11.3)
          ..cubicTo(10.3, 8.4, 10.9, 5.5, 12, 3)
          ..close();
        final inner = Path()
          ..moveTo(12, 18.6)
          ..cubicTo(10.9, 18.6, 10.1, 17.7, 10.1, 16.6)
          ..cubicTo(10.1, 15.4, 11, 14.5, 12, 13.4)
          ..cubicTo(13, 14.5, 13.9, 15.4, 13.9, 16.6)
          ..cubicTo(13.9, 17.7, 13.1, 18.6, 12, 18.6)
          ..close();
        if (filled) {
          c.drawPath(outer, _fill);
          c.drawPath(outer, _stroke);
          c.drawPath(inner, _cutFill);
        } else {
          c.drawPath(outer, _stroke);
          c.drawPath(inner, _stroke);
        }
      case SfGlyph.today:
        final tri = roundedPolygon(const [
          Offset(10.2, 8.7),
          Offset(10.2, 15.3),
          Offset(15.9, 12),
        ], 1.4);
        if (filled) {
          c.drawCircle(const Offset(12, 12), 9.6, _fill);
          c.drawPath(tri, _cutFill);
          c.drawPath(tri, _cutStroke..strokeWidth = 1);
        } else {
          c.drawCircle(const Offset(12, 12), 9, _stroke);
          c.drawPath(tri, _fill);
          c.drawPath(tri, _stroke..strokeWidth = 1);
        }
      case SfGlyph.checkup:
        final box = RRect.fromRectAndRadius(
          const Rect.fromLTWH(3.5, 4.5, 17, 15),
          const Radius.circular(4.5),
        );
        final pulse = _poly(const [
          Offset(7, 12.4),
          Offset(9.2, 12.4),
          Offset(10.7, 9.2),
          Offset(13.2, 15.6),
          Offset(14.7, 12.4),
          Offset(17, 12.4),
        ]);
        if (filled) {
          c.drawRRect(box.inflate(.6), _fill);
          c.drawPath(pulse, _cutStroke);
        } else {
          c.drawRRect(box, _stroke);
          c.drawPath(pulse, _stroke);
        }
      case SfGlyph.progress:
        for (final (x, top) in [(4.6, 12.6), (10.2, 8.2), (15.8, 4.6)]) {
          final r = RRect.fromRectAndRadius(
            Rect.fromLTRB(x, top, x + 3.6, 19.4),
            const Radius.circular(1.6),
          );
          if (filled) c.drawRRect(r.inflate(.4), _fill);
          c.drawRRect(r, _stroke);
        }
      case SfGlyph.radar:
        const center = Offset(12, 12.3);
        Offset at(int i, double r) {
          final a = -math.pi / 2 + i * math.pi / 3;
          return center + Offset(math.cos(a), math.sin(a)) * r;
        }

        final hex = Path()
          ..addPolygon([for (var i = 0; i < 6; i++) at(i, 9)], true);
        const f = [.78, .52, .82, .42, .64, .5];
        final shape = Path()
          ..addPolygon([for (var i = 0; i < 6; i++) at(i, 9 * f[i])], true);
        c.drawPath(hex, _stroke..strokeWidth = _stroke.strokeWidth * .8);
        c.drawPath(
          shape,
          Paint()
            ..color = color.withValues(alpha: color.a * (filled ? .9 : .28)),
        );
        c.drawPath(shape, _stroke..strokeWidth = _stroke.strokeWidth / .8);
      case SfGlyph.bolt:
        final p = roundedPolygon(const [
          Offset(13.6, 2.8),
          Offset(5.4, 13.4),
          Offset(11.5, 13.4),
          Offset(10.4, 21.2),
          Offset(18.6, 10.6),
          Offset(12.5, 10.6),
        ], 1.0);
        c.drawPath(p, _fill);
        c.drawPath(p, _stroke);
      case SfGlyph.pinch:
        c.drawLine(const Offset(4, 12), const Offset(20, 12), _stroke);
        c.drawLine(const Offset(12, 2.8), const Offset(12, 8.4), _stroke);
        c.drawPath(
          _poly(const [Offset(9, 5.6), Offset(12, 8.6), Offset(15, 5.6)]),
          _stroke,
        );
        c.drawLine(const Offset(12, 21.2), const Offset(12, 15.6), _stroke);
        c.drawPath(
          _poly(const [Offset(9, 18.4), Offset(12, 15.4), Offset(15, 18.4)]),
          _stroke,
        );
      case SfGlyph.volume:
      case SfGlyph.volumeLow:
        final body = roundedPolygon(const [
          Offset(3.6, 9.2),
          Offset(7.2, 9.2),
          Offset(11.6, 5.2),
          Offset(11.6, 18.8),
          Offset(7.2, 14.8),
          Offset(3.6, 14.8),
        ], 1.0);
        if (filled) c.drawPath(body, _fill);
        c.drawPath(body, _stroke);
        const a = 50 * math.pi / 180;
        c.drawArc(
          Rect.fromCircle(center: const Offset(12.2, 12), radius: 3.8),
          -a,
          2 * a,
          false,
          _stroke,
        );
        if (glyph == SfGlyph.volume) {
          c.drawArc(
            Rect.fromCircle(center: const Offset(12.2, 12), radius: 7.6),
            -a,
            2 * a,
            false,
            _stroke,
          );
        }
      case SfGlyph.subtitles:
        final box = RRect.fromRectAndRadius(
          const Rect.fromLTWH(3.5, 5.5, 17, 13),
          const Radius.circular(3.5),
        );
        final lines = [
          (const Offset(7, 11.4), const Offset(12.4, 11.4)),
          (const Offset(14.6, 11.4), const Offset(17, 11.4)),
          (const Offset(7, 14.8), const Offset(9.4, 14.8)),
          (const Offset(11.6, 14.8), const Offset(17, 14.8)),
        ];
        if (filled) {
          c.drawRRect(box.inflate(.6), _fill);
          for (final (a, b) in lines) {
            c.drawLine(a, b, _cutStroke);
          }
        } else {
          c.drawRRect(box, _stroke);
          for (final (a, b) in lines) {
            c.drawLine(a, b, _stroke);
          }
        }
      case SfGlyph.info:
        if (filled) {
          c.drawCircle(const Offset(12, 12), 9.6, _fill);
          c.drawLine(const Offset(12, 11), const Offset(12, 16.4), _cutStroke);
          c.drawCircle(const Offset(12, 7.9), 1.15, _cutFill);
        } else {
          c.drawCircle(const Offset(12, 12), 9, _stroke);
          c.drawLine(const Offset(12, 11), const Offset(12, 16.4), _stroke);
          c.drawCircle(const Offset(12, 7.9), 1.15, _fill);
        }
      case SfGlyph.copy:
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3.5, 3, 12.5, 15),
            const Radius.circular(2.5),
          ),
          _stroke,
        );
        final front = RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 7, 12.5, 14),
          const Radius.circular(2.5),
        );
        c.drawRRect(front.inflate(1), _cutFill);
        c.drawRRect(front, filled ? _fill : _stroke);
      case SfGlyph.clipboard:
        final board = RRect.fromRectAndRadius(
          const Rect.fromLTWH(5, 4.6, 14, 16.4),
          const Radius.circular(3),
        );
        final tab = RRect.fromRectAndRadius(
          const Rect.fromLTWH(9, 2.9, 6, 3.4),
          const Radius.circular(1.5),
        );
        if (filled) {
          c.drawRRect(board.inflate(.6), _fill);
          c.drawLine(
            const Offset(12, 10.6),
            const Offset(12, 16.4),
            _cutStroke,
          );
          c.drawLine(
            const Offset(9.1, 13.5),
            const Offset(14.9, 13.5),
            _cutStroke,
          );
          c.drawRRect(tab.inflate(1.2), _cutFill);
          c.drawRRect(tab, _fill);
        } else {
          c.drawRRect(board, _stroke);
          c.drawRRect(tab.inflate(1.0), _cutFill);
          c.drawRRect(tab, _stroke);
          c.drawLine(const Offset(12, 10.6), const Offset(12, 16.4), _stroke);
          c.drawLine(
            const Offset(9.1, 13.5),
            const Offset(14.9, 13.5),
            _stroke,
          );
        }
      case SfGlyph.shield:
        final shield = Path()
          ..moveTo(12, 3.2)
          ..lineTo(19, 5.9)
          ..lineTo(19, 11.4)
          ..cubicTo(19, 15.9, 16, 19.4, 12, 20.8)
          ..cubicTo(8, 19.4, 5, 15.9, 5, 11.4)
          ..lineTo(5, 5.9)
          ..close();
        final check = _poly(const [
          Offset(9, 12.1),
          Offset(11.2, 14.3),
          Offset(15.2, 10.1),
        ]);
        if (filled) {
          c.drawPath(shield, _fill);
          c.drawPath(shield, _stroke);
          c.drawPath(check, _cutStroke);
        } else {
          c.drawPath(shield, _stroke);
          c.drawPath(check, _stroke);
        }
      case SfGlyph.bell:
        final body = Path()
          ..moveTo(5.2, 17.4)
          ..cubicTo(6.3, 16.3, 6.8, 14.9, 6.8, 13.4)
          ..lineTo(6.8, 11)
          ..cubicTo(6.8, 8.1, 9.1, 5.8, 12, 5.8)
          ..cubicTo(14.9, 5.8, 17.2, 8.1, 17.2, 11)
          ..lineTo(17.2, 13.4)
          ..cubicTo(17.2, 14.9, 17.7, 16.3, 18.8, 17.4)
          ..close();
        if (filled) c.drawPath(body, _fill);
        c.drawPath(body, _stroke);
        c.drawLine(const Offset(12, 3.6), const Offset(12, 5.8), _stroke);
        c.drawPath(
          Path()
            ..moveTo(10, 20)
            ..quadraticBezierTo(12, 21.8, 14, 20),
          _stroke,
        );
      case SfGlyph.voice:
        if (filled) {
          c.drawCircle(const Offset(9.4, 8.8), 3.6, _fill);
        }
        c.drawCircle(const Offset(9.4, 8.8), 3.4, _stroke);
        final shoulders = Path()
          ..moveTo(3.4, 19.8)
          ..cubicTo(3.4, 16.4, 6.1, 14.2, 9.4, 14.2)
          ..cubicTo(12.7, 14.2, 15.4, 16.4, 15.4, 19.8);
        if (filled) c.drawPath(Path.from(shoulders)..close(), _fill);
        c.drawPath(shoulders, _stroke);
        const a = 52 * math.pi / 180;
        c.drawArc(
          Rect.fromCircle(center: const Offset(14.6, 8.8), radius: 3),
          -a,
          2 * a,
          false,
          _stroke,
        );
        c.drawArc(
          Rect.fromCircle(center: const Offset(14.6, 8.8), radius: 6),
          -a,
          2 * a,
          false,
          _stroke,
        );
      case SfGlyph.contrast:
        c.drawCircle(const Offset(12, 12), 8.6, _stroke);
        c.drawPath(
          Path()
            ..moveTo(12, 3.4)
            ..arcToPoint(
              const Offset(12, 20.6),
              radius: const Radius.circular(8.6),
            )
            ..close(),
          _fill,
        );
      case SfGlyph.stop:
        final oct = roundedPolygon([
          for (var i = 0; i < 8; i++)
            const Offset(12, 12) +
                Offset(
                      math.cos(math.pi / 8 + i * math.pi / 4),
                      math.sin(math.pi / 8 + i * math.pi / 4),
                    ) *
                    9.4,
        ], 1.4);
        if (filled) {
          c.drawPath(oct, _fill);
          c.drawPath(oct, _stroke);
          c.drawLine(const Offset(8.4, 12), const Offset(15.6, 12), _cutStroke);
        } else {
          c.drawPath(oct, _stroke);
          c.drawLine(const Offset(8.4, 12), const Offset(15.6, 12), _stroke);
        }
      case SfGlyph.figure:
        c.drawCircle(const Offset(12, 4.9), 2.2, filled ? _fill : _stroke);
        c.drawPath(
          Path()
            ..moveTo(5, 9)
            ..cubicTo(8, 10, 9.8, 10.2, 12, 10.2)
            ..cubicTo(14.2, 10.2, 16, 10, 19, 9),
          _stroke,
        );
        c.drawLine(const Offset(12, 10.2), const Offset(12, 14.6), _stroke);
        c.drawPath(
          _poly(const [
            Offset(8.8, 20.6),
            Offset(12, 14.6),
            Offset(15.2, 20.6),
          ]),
          _stroke,
        );
      case SfGlyph.dancer:
        c.drawCircle(const Offset(15.6, 4.8), 2.1, filled ? _fill : _stroke);
        c.drawLine(const Offset(14.4, 8.1), const Offset(11, 12.6), _stroke);
        c.drawLine(const Offset(14.1, 8.5), const Offset(18.9, 10.8), _stroke);
        c.drawLine(const Offset(13.2, 9.7), const Offset(8.6, 7.6), _stroke);
        c.drawPath(
          _poly(const [
            Offset(11, 12.6),
            Offset(15.2, 15.3),
            Offset(14.6, 20.6),
          ]),
          _stroke,
        );
        c.drawLine(const Offset(11, 12.6), const Offset(4.8, 15.8), _stroke);
      case SfGlyph.person:
        final head = Rect.fromCircle(center: const Offset(12, 8), radius: 3.6);
        final body = Path()
          ..moveTo(5, 20)
          ..cubicTo(5, 16.4, 8.1, 14, 12, 14)
          ..cubicTo(15.9, 14, 19, 16.4, 19, 20);
        if (filled) {
          c.drawOval(head, _fill);
          c.drawPath(Path.from(body)..close(), _fill);
        }
        c.drawOval(head, _stroke);
        c.drawPath(body, _stroke);
      case SfGlyph.bandage:
        c.save();
        c.translate(12, 12);
        c.rotate(-math.pi / 4);
        final band = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 19, height: 8),
          const Radius.circular(4),
        );
        if (filled) {
          c.drawRRect(band, _fill);
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 5.6, height: 5),
              const Radius.circular(1.5),
            ),
            _cutFill,
          );
        } else {
          c.drawRRect(band, _stroke);
          c.drawLine(const Offset(-3, -4), const Offset(-3, 4), _stroke);
          c.drawLine(const Offset(3, -4), const Offset(3, 4), _stroke);
          c.drawCircle(const Offset(0, -1.4), .7, _fill);
          c.drawCircle(const Offset(0, 1.4), .7, _fill);
        }
        c.restore();
      case SfGlyph.skipPrevious:
        c.save();
        c.translate(24, 0);
        c.scale(-1, 1);
        final p = roundedPolygon(const [
          Offset(5.6, 6.2),
          Offset(5.6, 17.8),
          Offset(14.6, 12),
        ], 2.1);
        c.drawPath(p, _fill);
        c.drawPath(p, _stroke);
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(16.3, 6, 2.8, 12),
            const Radius.circular(1.4),
          ),
          _fill,
        );
        c.restore();
      case SfGlyph.bookmark:
        final b = Path()
          ..moveTo(6.5, 6)
          ..quadraticBezierTo(6.5, 3.6, 9, 3.6)
          ..lineTo(15, 3.6)
          ..quadraticBezierTo(17.5, 3.6, 17.5, 6)
          ..lineTo(17.5, 19.4)
          ..quadraticBezierTo(17.5, 20.6, 16.4, 20)
          ..lineTo(12, 16.6)
          ..lineTo(7.6, 20)
          ..quadraticBezierTo(6.5, 20.6, 6.5, 19.4)
          ..close();
        if (filled) c.drawPath(b, _fill);
        c.drawPath(b, _stroke);
      case SfGlyph.arrowUp:
        c.drawLine(const Offset(12, 19), const Offset(12, 5.5), _stroke);
        c.drawPath(
          _poly(const [Offset(6.5, 11), Offset(12, 5.5), Offset(17.5, 11)]),
          _stroke,
        );
      case SfGlyph.more:
        for (final x in [6.0, 12.0, 18.0]) {
          c.drawCircle(Offset(x, 12), 1.6, _fill);
        }
      case SfGlyph.grid:
        for (final o in const [Offset(4, 4), Offset(13, 4), Offset(4, 13), Offset(13, 13)]) {
          final r = RRect.fromRectAndRadius(o & const Size(7, 7), const Radius.circular(2));
          if (filled) c.drawRRect(r, _fill);
          c.drawRRect(r, _stroke);
        }
      case SfGlyph.sliders:
        for (final (y, x) in const [(7.0, 15.0), (17.0, 9.0)]) {
          c.drawLine(Offset(4, y), Offset(20, y), _stroke);
          c.drawCircle(Offset(x, y), 3.2, _cutFill);
          c.drawCircle(Offset(x, y), 2.6, filled ? _fill : _stroke);
        }
      case SfGlyph.swap:
        c.drawLine(const Offset(5, 8.5), const Offset(18, 8.5), _stroke);
        c.drawPath(_poly(const [Offset(14.5, 5), Offset(18, 8.5), Offset(14.5, 12)]), _stroke);
        c.drawLine(const Offset(19, 15.5), const Offset(6, 15.5), _stroke);
        c.drawPath(_poly(const [Offset(9.5, 12), Offset(6, 15.5), Offset(9.5, 19)]), _stroke);
      case SfGlyph.clock:
        if (filled) {
          c.drawCircle(const Offset(12, 12), 9.6, _fill);
          c.drawPath(_poly(const [Offset(12, 7.4), Offset(12, 12), Offset(15.2, 14)]), _cutStroke);
        } else {
          c.drawCircle(const Offset(12, 12), 9, _stroke);
          c.drawPath(_poly(const [Offset(12, 7.4), Offset(12, 12), Offset(15.2, 14)]), _stroke);
        }
      case SfGlyph.sparkle:
        final p = Path()
          ..moveTo(12, 3.5)
          ..quadraticBezierTo(13, 11, 20.5, 12)
          ..quadraticBezierTo(13, 13, 12, 20.5)
          ..quadraticBezierTo(11, 13, 3.5, 12)
          ..quadraticBezierTo(11, 11, 12, 3.5)
          ..close();
        c.drawPath(p, _fill);
        c.drawPath(p, _stroke);
    }
  }

  static Path _poly(List<Offset> pts) => Path()..addPolygon(pts, false);

  @override
  bool shouldRepaint(SfIconPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.filled != filled ||
      old.strokeWidth != strokeWidth;
}

/// A closed polygon whose corners are rounded: each corner is replaced by a
/// quadratic curve starting [d] units before the vertex and ending [d] after
/// it (clamped to half of the shorter adjacent edge).
Path roundedPolygon(List<Offset> pts, double d) {
  final n = pts.length;
  final path = Path();
  for (var i = 0; i < n; i++) {
    final prev = pts[(i - 1 + n) % n];
    final cur = pts[i];
    final next = pts[(i + 1) % n];
    final inLen = (cur - prev).distance;
    final outLen = (next - cur).distance;
    final r = math.min(d, math.min(inLen, outLen) / 2);
    final a = cur - (cur - prev) / inLen * r;
    final b = cur + (next - cur) / outLen * r;
    if (i == 0) {
      path.moveTo(a.dx, a.dy);
    } else {
      path.lineTo(a.dx, a.dy);
    }
    path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
  }
  return path..close();
}
