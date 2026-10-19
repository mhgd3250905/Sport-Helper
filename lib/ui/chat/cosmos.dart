import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The chat home's palette: a deep blue-black sky, cool glass, one warm
/// accent (the app's coral) for the user's voice and the main action.
class CosmosColors {
  static const skyTop = Color(0xFF0B1022);
  static const skyMid = Color(0xFF070A16);
  static const skyBottom = Color(0xFF03040A);
  static const nebulaViolet = Color(0xFF2D2766);
  static const nebulaTeal = Color(0xFF0E3A52);

  static const text = Color(0xFFEFF1F8);
  static const textSoft = Color(0xFFC9CDDC);
  static const muted = Color(0xFF8C93AB);
  static const faint = Color(0xFF5E6580);

  /// Glass: a whisper of white over the sky, a hairline edge.
  static const glass = Color(0x14FFFFFF);
  static const glassHi = Color(0x22FFFFFF);
  static const edge = Color(0x24FFFFFF);

  static const accent = Color(0xFFFF7A45);
  static const accentGlass = Color(0x38FF7A45);
  static const accentEdge = Color(0x66FFB08A);

  /// The user's bubble: warm, nearly opaque glass (coral → rose).
  static const userFill = [Color(0xD9FF8A57), Color(0xCCEB5F6E)];

  /// Player states: rest / prep in a cool sky blue, the side switch and
  /// 不舒服 in a soft amber (both readable on the glass at 4.5:1+).
  static const rest = Color(0xFF7CC8FF);
  static const warn = Color(0xFFFFC857);
  static const track = Color(0x1FFFFFFF);
}

/// Sky gradient + two faint nebulae + slowly drifting star dust.
///
/// Low power by design: ~70 points, repainted at most ~30 times a second
/// on its own layer; the ticker stops when [animate] is off, when the
/// system asks for reduced motion, when the app is in the background, and
/// when a page covers the chat (TickerMode), e.g. during a workout.
class CosmosBackground extends StatefulWidget {
  const CosmosBackground({super.key, this.animate = true, this.child});
  final bool animate;
  final Widget? child;

  @override
  State<CosmosBackground> createState() => _CosmosBackgroundState();
}

class _CosmosBackgroundState extends State<CosmosBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  double _base = 0;
  Duration _lastFrame = Duration.zero;
  bool _foreground = true;
  bool _reduceMotion = false;
  static final _stars = _Star.field(72, seed: 20261019);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(CosmosBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final want = widget.animate && _foreground && !_reduceMotion;
    if (want && !_ticker.isActive) {
      _base = _time.value;
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!want && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    if (elapsed - _lastFrame < const Duration(milliseconds: 33)) return;
    _lastFrame = elapsed;
    _time.value = _base + elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _Sky(),
      RepaintBoundary(
        child: CustomPaint(
          painter: _StarPainter(_stars, _time),
          isComplex: false,
          willChange: true,
        ),
      ),
      ?widget.child,
    ],
  );
}

class _Sky extends StatelessWidget {
  const _Sky();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CosmosColors.skyTop, CosmosColors.skyMid, CosmosColors.skyBottom],
        stops: [0, .55, 1],
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(.85, -.8),
              radius: .95,
              colors: [Color(0x552D2766), Color(0x002D2766)],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.05, .3),
              radius: .8,
              colors: [Color(0x380E3A52), Color(0x000E3A52)],
            ),
          ),
        ),
        // A warm breath of light where the conversation happens.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, 1.25),
              radius: .75,
              colors: [Color(0x16FF7A45), Color(0x00FF7A45)],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Star {
  const _Star(this.x, this.y, this.r, this.alpha, this.vx, this.vy, this.freq, this.phase);
  final double x, y, r, alpha, vx, vy, freq, phase;

  /// Fixed seed: the same sky every launch. Nearer (bigger) stars drift a
  /// little faster for a hint of depth.
  static List<_Star> field(int n, {required int seed}) {
    final rnd = math.Random(seed);
    return List.generate(n, (i) {
      final depth = math.pow(rnd.nextDouble(), 2.2).toDouble(); // most are far
      final r = .35 + depth * 1.35;
      return _Star(
        rnd.nextDouble(),
        rnd.nextDouble(),
        r,
        .16 + depth * .5 + rnd.nextDouble() * .12,
        (.0012 + depth * .0035) * (rnd.nextBool() ? 1 : -.6),
        -(.0022 + depth * .006),
        .08 + rnd.nextDouble() * .35,
        rnd.nextDouble() * math.pi * 2,
      );
    });
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.time) : super(repaint: time);
  final List<_Star> stars;
  final ValueListenable<double> time;

  final _dot = Paint()..isAntiAlias = true;
  final _glow = Paint()
    ..isAntiAlias = true
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    for (final s in stars) {
      final x = ((s.x + s.vx * t) % 1 + 1) % 1 * size.width;
      final y = ((s.y + s.vy * t) % 1 + 1) % 1 * size.height;
      final tw = .7 + .3 * math.sin(t * s.freq * math.pi * 2 + s.phase);
      final a = (s.alpha * tw).clamp(0.0, 1.0);
      if (s.r > 1.1) {
        _glow.color = Color.fromRGBO(190, 205, 255, a * .45);
        canvas.drawCircle(Offset(x, y), s.r * 2.6, _glow);
      }
      _dot.color = Color.fromRGBO(225, 232, 255, a);
      canvas.drawCircle(Offset(x, y), s.r, _dot);
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.stars != stars;
}
