import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// The player's countdown (docs/design-audit-2026-10-19.md §1 H3, M10–M12;
/// the ring after HipLab's `HipCountdownRing`):
///
/// * a hairline track, a progress arc that runs from a softer tone at its
///   tail to the full colour at its head, a round tail cap and a small lit
///   knob at the head — nothing at 0 % (no stray dot at the top);
/// * the number rolls over (old one up and out, new one up and in);
/// * in the last seconds ([urgent]) ring and number breathe once per
///   second (1.0 → 1.06 → 1.0) and the number takes the ring colour;
/// * [dim] (paused) fades both to 45 %.
///
/// [progress] is listened to by the painter only, so the page need not
/// rebuild as time runs. Reduced motion: no roll (a quick cross-fade), no
/// breath; colours and the ring still update.
class SfCountdownRing extends StatelessWidget {
  const SfCountdownRing({
    super.key,
    required this.progress,
    required this.value,
    this.caption,
    this.size = 120,
    this.color,
    this.urgent = false,
    this.dim = false,
    this.numberKey,
  });
  final ValueListenable<double> progress;
  final String value;
  final String? caption;
  final double size;
  final Color? color;
  final bool urgent;
  final bool dim;

  /// Key on the number (one widget, even mid-roll).
  final Key? numberKey;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SfColors.accent;
    final still = SfMotion.reduced(context);
    final numberColor = urgent ? (SfColors.isDark ? c : SfColors.accentText) : SfColors.text;
    Widget face = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: SfRingPainter(
          progress,
          track: SfColors.isDark ? SfColors.surfaceHigh : SfColors.line,
          color: c,
          knob: SfColors.isDark ? const Color(0xFFFFFFFF) : SfColors.surface,
          glow: SfColors.isDark,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SfRollingNumber(
                key: numberKey,
                value: value,
                style: SfType.numeral(size * .34, color: numberColor),
              ),
              if (caption != null) ...[
                SizedBox(height: size * .04),
                Text(
                  caption!,
                  style: TextStyle(
                    fontSize: size * .095,
                    height: 1.1,
                    letterSpacing: size * .004,
                    fontWeight: FontWeight.w500,
                    color: SfColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (urgent && !still) {
      face = TweenAnimationBuilder<double>(
        // A fresh breath every second: the tween restarts with the value.
        key: ValueKey('breath-$value'),
        tween: Tween(begin: 0, end: 1),
        duration: SfMotion.breath,
        builder: (_, t, child) => Transform.scale(scale: 1 + .06 * _breath(t), child: child),
        child: face,
      );
    }
    return AnimatedOpacity(
      opacity: dim ? .45 : 1,
      duration: SfMotion.medium,
      curve: SfMotion.standard,
      child: face,
    );
  }

  /// 0 → 1 over the first 40 % (ease out), back to 0 over the rest.
  static double _breath(double t) => t < .4
      ? Curves.easeOut.transform(t / .4)
      : 1 - Curves.easeInOut.transform((t - .4) / .6);
}

class SfRingPainter extends CustomPainter {
  SfRingPainter(this.progress, {required this.track, required this.color, required this.knob, this.glow = true})
    : super(repaint: progress);
  final ValueListenable<double> progress;
  final Color track;
  final Color color;
  final Color knob;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value.clamp(0.0, 1.0);
    final stroke = size.width * .05;
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - stroke / 2 - size.width * .03;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * .42
        ..color = track,
    );
    if (p < .004) return;
    final sweep = math.pi * 2 * p;
    const start = -math.pi / 2;
    final tail = color.withValues(alpha: color.a * .38);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.max(sweep, .001),
          colors: [tail, color],
          transform: const GradientRotation(start),
        ).createShader(rect),
    );
    canvas.drawCircle(center + Offset(math.cos(start), math.sin(start)) * radius, stroke / 2, Paint()..color = tail);
    final head = center + Offset(math.cos(start + sweep), math.sin(start + sweep)) * radius;
    if (glow) {
      canvas.drawCircle(
        head,
        stroke * .95,
        Paint()
          ..color = color.withValues(alpha: color.a * .4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * .6),
      );
    }
    canvas.drawCircle(head, stroke * .5, Paint()..color = color);
    canvas.drawCircle(head, stroke * .24, Paint()..color = knob.withValues(alpha: .92));
  }

  @override
  bool shouldRepaint(SfRingPainter old) =>
      old.progress != progress || old.track != track || old.color != color || old.knob != knob || old.glow != glow;
}

/// A number that rolls over when it changes: the old value rises out and
/// fades, the new one rises in from below ([SfMotion.roll]). Reduced
/// motion: a short cross-fade.
class SfRollingNumber extends StatelessWidget {
  const SfRollingNumber({super.key, required this.value, required this.style});
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final still = SfMotion.reduced(context);
    return AnimatedSwitcher(
      duration: still ? const Duration(milliseconds: 150) : SfMotion.roll,
      switchInCurve: SfMotion.standard,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.center, children: [...previous, ?current]),
      transitionBuilder: (child, a) {
        final fade = FadeTransition(opacity: a, child: child);
        if (still) return fade;
        final incoming = child.key == ValueKey(value);
        return SlideTransition(
          position: a.drive(Tween(begin: Offset(0, incoming ? .42 : -.42), end: Offset.zero)),
          child: fade,
        );
      },
      child: Text(value, key: ValueKey(value), style: style),
    );
  }
}
