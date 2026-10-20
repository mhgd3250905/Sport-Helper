import 'package:flutter/material.dart';

import 'tokens.dart';

/// Push / pop of a plain page (docs/design-audit-2026-10-19.md M2, after
/// HipLab's `hip_routes.dart`): the new page slides in from the right edge
/// on [SfMotion.enter] (400 ms), back out on [SfMotion.exit] (340 ms);
/// the page it covers drifts 25 % left and dims a little — one large
/// move per transition, no scaling. The card → player container transform
/// is its own route ([CardExpandRoute]) and does not move the chat.
///
/// Reduced motion: a plain cross-fade.
class SfPageTransitionsBuilder extends PageTransitionsBuilder {
  const SfPageTransitionsBuilder();

  @override
  Duration get transitionDuration => SfMotion.page;

  @override
  Duration get reverseTransitionDuration => SfMotion.pageReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (SfMotion.reduced(context)) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    }
    return SfPageSlide(animation: animation, secondaryAnimation: secondaryAnimation, child: child);
  }
}

class SfPageSlide extends StatelessWidget {
  const SfPageSlide({super.key, required this.animation, required this.secondaryAnimation, required this.child});
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final incoming = CurvedAnimation(parent: animation, curve: SfMotion.enter, reverseCurve: SfMotion.exit);
    final covered = CurvedAnimation(parent: secondaryAnimation, curve: SfMotion.enter, reverseCurve: SfMotion.exit);
    final dim = SfColors.isDark ? .35 : .08;
    return SlideTransition(
      position: covered.drive(Tween(begin: Offset.zero, end: const Offset(-.25, 0))),
      child: AnimatedBuilder(
        animation: covered,
        child: SlideTransition(
          position: incoming.drive(Tween(begin: const Offset(1, 0), end: Offset.zero)),
          child: DecoratedBox(
            // The edge of the arriving page, so it reads as a sheet of paper.
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: SfColors.isDark ? .35 : .08), blurRadius: 16)],
            ),
            child: child,
          ),
        ),
        builder: (context, page) {
          final v = covered.value;
          if (v == 0) return page!;
          return Stack(
            fit: StackFit.passthrough,
            children: [
              page!,
              Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: dim * v))),
              ),
            ],
          );
        },
      ),
    );
  }
}
