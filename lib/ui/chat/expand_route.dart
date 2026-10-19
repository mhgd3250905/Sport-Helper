import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'cosmos.dart';

/// Where a card sits on screen right now, or null when it is gone (the
/// drawer closed, the card was removed). Read when the route opens and
/// again when it closes, so the page folds back to wherever the card is
/// (or into the middle of the chat when it is gone).
typedef OriginRect = Rect? Function();

/// The global rect of [context]'s render box, if it is still on screen.
Rect? rectOf(BuildContext? context) {
  if (context == null || !context.mounted) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  try {
    return box.localToGlobal(Offset.zero) & box.size;
  } on Object {
    return null; // not laid out under the current overlay (offstage)
  }
}

/// Container transform: the tapped card grows into a full-screen page
/// (rounded glass rect → screen, sky fill first, page fading in on top),
/// and shrinks back into the card on the way out. Without an origin it
/// grows from a card-sized rect in the middle. With the system's reduced
/// motion it is a plain cross-fade.
class CardExpandRoute<T> extends PageRoute<T> {
  CardExpandRoute({
    required this.builder,
    this.origin,
    this.radius = SfRadius.lg,
    super.settings,
  });

  final WidgetBuilder builder;
  final OriginRect? origin;
  final double radius;

  Rect? _openedFrom;

  @override
  Duration get transitionDuration => SfMotion.expand;
  @override
  Duration get reverseTransitionDuration => SfMotion.expandReverse;
  @override
  bool get opaque => true; // once open, the chat underneath stops drawing
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  @override
  TickerFuture didPush() {
    _openedFrom = origin?.call();
    return super.didPush();
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return FadeTransition(opacity: animation, child: child);
    }
    return _ExpandTransition(
      animation: animation,
      // Closing: fold back to where the card is now (it may have moved).
      origin: () => animation.status == AnimationStatus.reverse ? origin?.call() : _openedFrom,
      radius: radius,
      child: child,
    );
  }
}

class _ExpandTransition extends StatelessWidget {
  const _ExpandTransition({
    required this.animation,
    required this.origin,
    required this.radius,
    required this.child,
  });

  final Animation<double> animation;
  final Rect? Function() origin;
  final double radius;
  final Widget child;

  // One move (HipLab transition audit): the card's bounds grow on the
  // container curve; the chat underneath only dims, never scales.
  static final _grow = CurveTween(curve: SfMotion.container);
  // The sky fills the card's face first, so the card reads as lifting.
  static final _fill = CurveTween(curve: const Interval(0, .3, curve: Curves.easeOut));
  // The page fades in over the second half of the growth, scaled with it.
  static final _content = CurveTween(curve: const Interval(.3, .8, curve: Curves.easeOut));
  static final _scrim = CurveTween(curve: const Interval(0, .6, curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final full = Offset.zero & box.biggest;
      final palette = SfColors.palette;
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, page) {
          final v = animation.value;
          if (v >= 1) return page!;
          final from = origin() ?? _centred(full);
          final g = _grow.transform(v);
          final rect = Rect.lerp(from, full, g)!;
          final r = radius * (1 - g);
          final scale = rect.width / full.width;
          return Stack(
            children: [
              // The chat dims as the card takes over.
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: (palette.isDark ? .45 : .14) * _scrim.transform(v)),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(r),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(opacity: _fill.transform(v), child: SkyFill(palette: palette)),
                      // The page is laid out at full size and scaled with
                      // the card's width, so nothing reflows mid-move.
                      Opacity(
                        opacity: _content.transform(v),
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: full.width,
                          maxWidth: full.width,
                          minHeight: full.height,
                          maxHeight: full.height,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            child: SizedBox.fromSize(size: full.size, child: page),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  static Rect _centred(Rect full) {
    final w = (full.width * .88).clamp(260.0, 380.0);
    return Rect.fromCenter(center: full.center, width: w, height: w * 1.2);
  }
}
