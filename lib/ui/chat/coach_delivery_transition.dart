import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/ui_polish_tokens.dart';

/// A stable conversation entry keeps preparation and delivery in one slot.
/// AnimatedCrossFade uses AnimatedSize for the simultaneous height transition.
class CoachDeliveryTransition extends StatefulWidget {
  const CoachDeliveryTransition({
    super.key,
    required this.preparing,
    required this.child,
  });

  final bool preparing;
  final Widget child;

  @override
  State<CoachDeliveryTransition> createState() =>
      _CoachDeliveryTransitionState();
}

class _CoachDeliveryTransitionState extends State<CoachDeliveryTransition> {
  Widget? _preparation;

  @override
  Widget build(BuildContext context) {
    if (widget.preparing) _preparation = widget.child;
    if (SfMotion.reduced(context) || _preparation == null) return widget.child;
    return AnimatedCrossFade(
      duration: SfGenerationTokens.completionTransition,
      sizeCurve: SfMotion.standard,
      alignment: Alignment.topLeft,
      firstChild: TickerMode(
        enabled: widget.preparing,
        child: IgnorePointer(ignoring: !widget.preparing, child: _preparation!),
      ),
      secondChild: widget.preparing ? const SizedBox.shrink() : widget.child,
      crossFadeState: widget.preparing
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }
}
