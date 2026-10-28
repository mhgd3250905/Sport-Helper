import 'package:flutter/material.dart';

import 'ui_polish_tokens.dart';
import 'tokens.dart';
import 'widgets.dart';

/// The one card surface for this UI batch. Media draws on its transparent child.
class SfPolishCard extends StatelessWidget {
  const SfPolishCard({
    super.key,
    required this.child,
    this.padding = SfCardTokens.padding,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(SfCardTokens.radius),
    child: Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(color: SfCardTokens.fill),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SfCardTokens.radius),
        border: Border.all(
          color: SfCardTokens.edge,
          width: SfCardTokens.edgeWidth,
        ),
      ),
      child: child,
    ),
  );
}

/// Both plan states use the same face; the SDK owns its placement.
class SfPlanToggleButton extends StatelessWidget {
  const SfPlanToggleButton({
    super.key,
    required this.expanded,
    required this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.haptic = SfHaptic.selection,
  });

  final bool expanded;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;
  final SfHaptic haptic;

  @override
  Widget build(BuildContext context) => SfPressable(
    semanticLabel: semanticLabel ?? (expanded ? '收起详情' : '展开详情'),
    tooltip: tooltip,
    expanded: expanded,
    onTap: onPressed,
    haptic: haptic,
    child: Align(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        height: SfPlanPolishTokens.toggleHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SfColors.surfaceHigh,
            borderRadius: BorderRadius.circular(
              SfPlanPolishTokens.toggleRadius,
            ),
          ),
          child: Padding(
            padding: SfPlanPolishTokens.togglePadding,
            child: Center(
              widthFactor: 1,
              child: Text(
                expanded ? '收起' : '展开',
                style: SfPlanPolishTokens.toggle,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
