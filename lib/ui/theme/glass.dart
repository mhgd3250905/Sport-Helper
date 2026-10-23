import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../diagnostics/performance_lab.dart';
import 'adaptive_glass.dart';
import 'tokens.dart';
import 'widgets.dart' show SfControlInk, SfPressedScope;

/// Liquid glass, the SmartFit way (docs/liquid-glass-plan.md).
///
/// Glass is only the navigation and control layer: bars, chips, floating
/// buttons, sheets, toasts, and the chat's tappable cards (raised). Text
/// bubbles, lists and the video stay flat and
/// opaque. Every glass surface goes through [SfGlassSurface] so the
/// material (iOS 27 regular, light or dark to match the palette) and the
/// quality policy live in one place.
abstract final class SfGlass {
  /// Forces every SmartFit glass surface to this quality. The test harness
  /// sets [GlassQuality.minimal] (BackdropFilter only, no fragment shaders),
  /// since the test renderer cannot run the glass shaders.
  static GlassQuality? qualityOverride;

  /// iOS 27 `glassEffect(.regular)` for the palette in effect. These
  /// presets lean on the Impeller-native material (frost, rim light) and
  /// switch the 2D Fresnel rim off, so they are only used where the
  /// premium shader actually runs.
  static LiquidGlassSettings get material => SfColors.isDark
      ? LiquidGlassSettings.ios27Dark
      : LiquidGlassSettings.ios27Light;

  /// The single-pass (Skia / Web / standard) material: the package's own
  /// calibrated light/dark variants with the Fresnel rim and the specular
  /// kept on, so the capsule reads as a lens (bright upper-left rim, soft
  /// body) instead of a flat frosted pill.
  static LiquidGlassSettings get standardMaterial => SfColors.isDark
      ? const LiquidGlassSettings(
          thickness: 24,
          blur: 1.2,
          glassColor: Color.fromRGBO(255, 255, 255, 0.02),
          lightAngle: 2.356,
          lightIntensity: 1.1,
          ambientStrength: 0.03,
          refractiveIndex: 1.4,
          saturation: 1.15,
          chromaticAberration: 0.03,
          fresnelStrength: 1.3,
        )
      : const LiquidGlassSettings(
          thickness: 24,
          blur: 1.5,
          glassColor: Color.fromRGBO(255, 255, 255, 0.06),
          lightAngle: 2.356,
          lightIntensity: 1.2,
          ambientStrength: 0.05,
          refractiveIndex: 1.4,
          saturation: 1.1,
          chromaticAberration: 0.03,
          fresnelStrength: 1.2,
          edgeAbsorption: 0.02,
        );

  /// The material for a surface drawn at [q]: the iOS 27 preset only where
  /// the premium (Impeller) shader can run; the web is capped at standard.
  static LiquidGlassSettings materialFor(GlassQuality q) =>
      standardMaterial; // clear glass everywhere (user, 2026-10-21)

  /// The persisted adaptive tier to start from. `minimal` is never carried
  /// across launches (one slow session must not pin a good device, or the
  /// web, to flat frost for good): the monitor can still drop to it this
  /// session. The web starts at standard, its ceiling.
  static GlassQuality? initialQuality(String? persisted) {
    final q = parse(persisted);
    if (q == null || q == GlassQuality.minimal) {
      return kIsWeb ? GlassQuality.standard : null;
    }
    if (kIsWeb && q == GlassQuality.premium) return GlassQuality.standard;
    return q;
  }

  /// Persistent bars (the chat input): premium when the device allows it.
  static const bar = GlassQuality.premium;

  /// Chips, floating buttons, toasts: the single-pass shader.
  static const control = GlassQuality.standard;

  /// Over the workout video: never more than standard (the adaptive scope
  /// may still drop it to minimal on a slow device).
  static const overMedia = GlassQuality.standard;

  static GlassQuality resolve(GlassQuality q, {BuildContext? context}) {
    final requested = qualityOverride ?? q;
    if (PerformanceLab.buildEnabled && context != null) {
      return SfAdaptiveGlassData.maybeOf(context)?.cap(requested) ?? requested;
    }
    return requested;
  }

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
    this.control = false,
  });

  /// A tappable control (quick-reply chip). Dark: painted with
  /// [SfControlInk] (tinted fill, top highlight, 40 % rim) and following
  /// the pressed state, so idle reads as a button. Light: unchanged.
  final bool control;

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
    if (PerformanceLab.buildEnabled) {
      return ListenableBuilder(
        listenable: PerformanceLab.instance,
        builder: (context, _) => _surface(context),
      );
    }
    return _surface(context);
  }

  Widget _surface(BuildContext context) {
    final LiquidShape shape = radius == null
        ? const LiquidOval()
        : LiquidRoundedSuperellipse(borderRadius: radius!);
    final q = SfGlass.resolve(quality, context: context);
    final Widget glass;
    if (PerformanceLab.buildEnabled && !PerformanceLab.instance.glassEnabled) {
      glass = Container(
        key: const ValueKey('performance-opaque-glass'),
        width: width,
        height: height,
        padding: padding,
        decoration: ShapeDecoration(
          color: SfColors.surface.withValues(alpha: 1),
          shape: radius == null
              ? const StadiumBorder()
              : RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(radius!),
                ),
        ),
        child: child,
      );
    } else {
      glass = GlassContainer(
        useOwnLayer: true,
        settings: SfGlass.materialFor(q),
        quality: q,
        shape: shape,
        width: width,
        height: height,
        padding: padding,
        child: child,
      );
    }
    if (!SfColors.isDark) return glass;
    if (control) {
      final down = SfPressedScope.of(context);
      final side = SfControlInk.side(down);
      return Stack(
        fit: StackFit.passthrough,
        children: [
          glass,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                key: const ValueKey('sf-control-face'),
                duration: down ? SfMotion.press : SfMotion.release,
                curve: Curves.easeOut,
                decoration: ShapeDecoration(
                  shape: radius == null
                      ? StadiumBorder(side: side)
                      : RoundedSuperellipseBorder(
                          borderRadius: BorderRadius.circular(radius!),
                          side: side,
                        ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .5],
                    colors: down
                        ? const [
                            SfControlInk.pressedTop,
                            SfControlInk.pressedFill,
                          ]
                        : const [SfControlInk.fillTop, SfControlInk.fill],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    // Dark: a calm hairline rim so clear glass still has an edge on the
    // neutral sky (light mode unchanged).
    return Stack(
      fit: StackFit.passthrough,
      children: [
        glass,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: radius == null
                    ? const StadiumBorder(
                        side: BorderSide(color: Color(0x1FFFFFFF), width: .8),
                      )
                    : RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(radius!),
                        side: const BorderSide(
                          color: Color(0x1FFFFFFF),
                          width: .8,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Capture is part of the glass treatment and must also disappear in its
/// control condition. Production retains the original background source.
class SfGlassBackgroundSource extends StatelessWidget {
  const SfGlassBackgroundSource({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PerformanceLab.buildEnabled) {
      return GlassBackgroundSource(child: child);
    }
    return ListenableBuilder(
      listenable: PerformanceLab.instance,
      child: child,
      builder: (_, child) => PerformanceLab.instance.glassEnabled
          ? GlassBackgroundSource(child: child!)
          : child!,
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
    if (player) {
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
            ],
          ),
        ),
      );
    }
    // Chat: more depth and contrast so the glass has something to bend —
    // a deep jade pool bottom-left, a sky pool right under the chips, a
    // faint jade band across the input zone and a cool wash up top. Light
    // mode uses deeper, more saturated stops (pale pools vanish on paper).
    const skyDeep = Color(0xFF3F6FB0);
    // Dark (round 4): no jade/sky field — the colour pools read muddy on a
    // deep sky. Two near-invisible neutral lifts keep a little for the glass
    // to bend; the rim hairline (SfGlassSurface) does the rest.
    if (dark) {
      return IgnorePointer(
        child: RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              pool(const Alignment(0, 1.1), 1.1, Colors.white, .045),
              pool(const Alignment(-.8, -.9), .9, Colors.white, .025),
            ],
          ),
        ),
      );
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            pool(const Alignment(-1.0, 1.0), 1.15, accent, dark ? .42 : .38),
            pool(
              const Alignment(1.1, .72),
              .95,
              dark ? coolDark : skyDeep,
              dark ? .48 : .30,
            ),
            pool(
              const Alignment(.15, .98),
              .55,
              dark ? const Color(0xFF7FE0C0) : accent,
              dark ? .20 : .22,
            ),
            pool(
              const Alignment(-.9, -.55),
              .9,
              dark ? coolDark : coolLight,
              dark ? .18 : .34,
            ),
            pool(const Alignment(.85, -1.0), .7, accent, dark ? .12 : .14),
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

void showSfGlassToast(
  BuildContext context,
  String text, {
  required Widget icon,
  double bottom = 96,
}) {
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
  const _SfToastHost({
    required this.text,
    required this.icon,
    required this.bottom,
    required this.onDone,
  });
  final String text;
  final Widget icon;
  final double bottom;
  final VoidCallback onDone;

  @override
  State<_SfToastHost> createState() => _SfToastHostState();
}

class _SfToastHostState extends State<_SfToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SfMotion.medium,
    reverseDuration: SfMotion.fast,
  )..forward();
  late final CurvedAnimation _a = CurvedAnimation(
    parent: _c,
    curve: SfMotion.standard,
  );
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
    final inset =
        MediaQuery.viewPaddingOf(context).bottom +
        MediaQuery.viewInsetsOf(context).bottom;
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
            child: Transform.translate(
              offset: Offset(0, still ? 0 : 8 * (1 - a.value)),
              child: child,
            ),
          ),
          child: Center(
            child: PerformanceLab.buildEnabled
                ? ListenableBuilder(
                    listenable: PerformanceLab.instance,
                    builder: (context, _) => _message(context),
                  )
                : _message(context),
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context) {
    if (PerformanceLab.buildEnabled && !PerformanceLab.instance.glassEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: ShapeDecoration(
          color: SfColors.surface.withValues(alpha: 1),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.icon,
            const SizedBox(width: 8),
            Flexible(child: Text(widget.text)),
          ],
        ),
      );
    }
    final quality = SfGlass.resolve(SfGlass.control, context: context);
    return GlassToast(
      message: widget.text,
      icon: widget.icon,
      type: GlassToastType.success,
      dismissible: false,
      settings: SfGlass.materialFor(quality),
      quality: quality,
    );
  }
}

/// Reports its child's laid-out size after each layout where it changed
/// (used to pad scrolling content under a floating glass dock).
class SfMeasureSize extends SingleChildRenderObjectWidget {
  const SfMeasureSize({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMeasureSize).onSize = onSize;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
