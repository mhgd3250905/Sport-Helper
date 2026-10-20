import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'tokens.dart';

/// Liquid glass, the SmartFit way (docs/liquid-glass-plan.md).
///
/// Glass is only the navigation and control layer: bars, chips, floating
/// buttons, sheets, toasts. Content (plan cards, lists, the video) stays
/// opaque. Every glass surface goes through [SfGlassSurface] so the
/// material (iOS 27 regular, light or dark to match the palette) and the
/// quality policy live in one place.
abstract final class SfGlass {
  /// Forces every SmartFit glass surface to this quality. The test harness
  /// sets [GlassQuality.minimal] (BackdropFilter only, no fragment shaders),
  /// since the test renderer cannot run the glass shaders.
  static GlassQuality? qualityOverride;

  /// iOS 27 `glassEffect(.regular)` for the palette in effect.
  static LiquidGlassSettings get material => SfColors.isDark
      ? LiquidGlassSettings.ios27Dark
      : LiquidGlassSettings.ios27Light;

  /// Persistent bars (the chat input): premium when the device allows it.
  static const bar = GlassQuality.premium;

  /// Chips, floating buttons, toasts: the single-pass shader.
  static const control = GlassQuality.standard;

  /// Over the workout video: never more than standard (the adaptive scope
  /// may still drop it to minimal on a slow device).
  static const overMedia = GlassQuality.standard;

  static GlassQuality resolve(GlassQuality q) => qualityOverride ?? q;

  /// Persisted quality names (AppStore.glassQuality) ⇄ enum.
  static GlassQuality? parse(String? name) {
    for (final q in GlassQuality.values) {
      if (q.name == name) return q;
    }
    return null;
  }
}

/// One glass platter. The child keeps its own controls, semantics and
/// haptics; this only paints the material behind it. Never nest one inside
/// another (double refraction).
class SfGlassSurface extends StatelessWidget {
  const SfGlassSurface({
    super.key,
    required this.child,
    this.radius,
    this.padding,
    this.width,
    this.height,
    this.quality = SfGlass.control,
  });

  /// Circle / capsule when null with a fixed size; otherwise a rounded
  /// superellipse with this corner radius.
  final double? radius;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final LiquidShape shape = radius == null
        ? const LiquidOval()
        : LiquidRoundedSuperellipse(borderRadius: radius!);
    return GlassContainer(
      useOwnLayer: true,
      settings: SfGlass.material,
      quality: SfGlass.resolve(quality),
      shape: shape,
      width: width,
      height: height,
      padding: padding,
      child: child,
    );
  }
}

/// A soft colour field behind glass: a flat colour gives the glass nothing
/// to refract and it reads as invisible. Two or three very large, very low
/// alpha radial pools from the existing tokens (the jade accent and the
/// sky's cool light), weighted towards the bottom where the bars float.
/// Static and cheap: gradients only, no blur filter, no ticker.
class SfGlassField extends StatelessWidget {
  const SfGlassField({super.key, this.player = false});

  /// The player keeps the field lower and quieter (the video is the hero).
  final bool player;

  @override
  Widget build(BuildContext context) {
    final dark = SfColors.isDark;
    final accent = SfColors.accent;
    // Cool counter-light: dark sky blue / pale mist on paper.
    const coolDark = Color(0xFF5B6CA8);
    const coolLight = Color(0xFF9DB8D6);
    final k = player ? .6 : 1.0;
    Widget pool(Alignment c, double r, Color color, double a) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: c,
          radius: r,
          colors: [
            color.withValues(alpha: a * k),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            pool(const Alignment(-1.1, 1.05), 1.0, accent, dark ? .22 : .20),
            pool(
              const Alignment(1.15, .55),
              .9,
              dark ? coolDark : coolLight,
              dark ? .26 : .30,
            ),
            if (!player)
              pool(const Alignment(.2, -.35), .8, accent, dark ? .07 : .06),
          ],
        ),
      ),
    );
  }
}

/// The app's toast on glass (replaces the SnackBar): a [GlassToast] capsule
/// floating [bottom] px above the safe area, where the v2 toast sat (above
/// the chat input), on the v2 motion (M18: in with an 8 px rise, out fast;
/// reduced motion: the fade only). It never takes taps, so it cannot cover
/// a control. A new toast replaces the one on screen.
OverlayEntry? _toastEntry;

void showSfGlassToast(BuildContext context, String text, {required Widget icon, double bottom = 96}) {
  _toastEntry?.remove();
  _toastEntry = null;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SfToastHost(
      text: text,
      icon: icon,
      bottom: bottom,
      onDone: () {
        if (_toastEntry == entry) {
          entry.remove();
          _toastEntry = null;
        }
      },
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _SfToastHost extends StatefulWidget {
  const _SfToastHost({required this.text, required this.icon, required this.bottom, required this.onDone});
  final String text;
  final Widget icon;
  final double bottom;
  final VoidCallback onDone;

  @override
  State<_SfToastHost> createState() => _SfToastHostState();
}

class _SfToastHostState extends State<_SfToastHost> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SfMotion.medium,
    reverseDuration: SfMotion.fast,
  )..forward();
  late final CurvedAnimation _a = CurvedAnimation(parent: _c, curve: SfMotion.standard);
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _hold = Timer(const Duration(seconds: 2), () async {
      if (!mounted) return;
      await _c.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = SfMotion.reduced(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom + MediaQuery.viewInsetsOf(context).bottom;
    final a = _a;
    return Positioned(
      left: SfSpace.x6,
      right: SfSpace.x6,
      bottom: inset + widget.bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: a,
          builder: (_, child) => Opacity(
            opacity: a.value,
            child: Transform.translate(offset: Offset(0, still ? 0 : 8 * (1 - a.value)), child: child),
          ),
          child: Center(
            child: GlassToast(
              message: widget.text,
              icon: widget.icon,
              type: GlassToastType.success,
              dismissible: false,
              settings: SfGlass.material,
              quality: SfGlass.resolve(SfGlass.control),
            ),
          ),
        ),
      ),
    );
  }
}
