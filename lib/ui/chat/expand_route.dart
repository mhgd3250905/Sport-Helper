import 'package:flutter/material.dart';

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
    this.radius = 24,
    super.settings,
  });

  final WidgetBuilder builder;
  final OriginRect? origin;
  final double radius;

  Rect? _openedFrom;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 460);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 400);
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

  static final _grow = CurveTween(curve: Curves.easeInOutCubicEmphasized);
  // The page appears once the card is a good way open; the sky fill and
  // the card's glass edge carry the first part of the move.
  static final _content = CurveTween(curve: const Interval(.18, .75, curve: Curves.easeOut));
  static final _scrim = CurveTween(curve: const Interval(0, .6, curve: Curves.easeOut));
  // The sky fill comes in over the card's own face, so the card is seen
  // lifting before it opens.
  static final _fill = CurveTween(curve: const Interval(0, .25, curve: Curves.easeOut));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final full = Offset.zero & box.biggest;
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
                  child: ColoredBox(color: Color.fromRGBO(2, 3, 10, .55 * _scrim.transform(v))),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(r),
                    boxShadow: [
                      BoxShadow(color: Color.fromRGBO(0, 0, 0, .35 * (1 - g)), blurRadius: 30, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(r),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Opacity(opacity: _fill.transform(v), child: const _SkyFill()),
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
                        // The card's hairline edge, fading as it opens.
                        IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(r),
                              border: Border.all(
                                color: CosmosColors.edge.withValues(alpha: CosmosColors.edge.a * (1 - g)),
                                width: .7,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

/// The same sky the player sits in, painted flat while the card grows.
class _SkyFill extends StatelessWidget {
  const _SkyFill();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF151B33), CosmosColors.skyMid, CosmosColors.skyBottom],
        stops: [0, .55, 1],
      ),
    ),
  );
}
