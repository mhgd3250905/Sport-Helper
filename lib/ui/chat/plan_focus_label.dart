import 'package:flutter/material.dart';

import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// A presentation of the SDK's current plan; the host owns its selection.
class PlanFocusLabel extends StatefulWidget {
  const PlanFocusLabel({
    super.key,
    required this.title,
    required this.onClear,
    this.bottomGap = 0,
  });

  final String? title;
  final VoidCallback? onClear;

  /// Retained with the outgoing label so the input never closes its gap early.
  final double bottomGap;

  @override
  State<PlanFocusLabel> createState() => _PlanFocusLabelState();
}

class _PlanFocusLabelState extends State<PlanFocusLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibility;
  late final CurvedAnimation _motion;
  String? _displayTitle;
  bool _exiting = false;
  double _exitOffset = 0;

  static String? _title(String? value) {
    final title = value?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  @override
  void initState() {
    super.initState();
    // Empty focus is common. Create its ticker while this element is active,
    // rather than allowing dispose to be the first read of a lazy field.
    _visibility = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 120),
    )..addStatusListener(_statusChanged);
    _motion = CurvedAnimation(
      parent: _visibility,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _displayTitle = _title(widget.title);
    if (_displayTitle != null) _visibility.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _displayTitle = _title(widget.title);
      _visibility.value = _displayTitle == null ? 0 : 1;
    }
  }

  @override
  void didUpdateWidget(PlanFocusLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _title(widget.title);
    if (next == _title(oldWidget.title)) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (next != null) {
      _displayTitle = next;
      _exiting = false;
      if (reduced) {
        _visibility.value = 1;
      } else {
        _visibility.forward();
      }
    } else if (_displayTitle != null) {
      _exitOffset = 8 * (1 - _motion.value);
      _exiting = true;
      if (reduced) {
        _displayTitle = null;
        _visibility.value = 0;
      } else {
        _visibility.reverse();
      }
    }
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        _displayTitle != null &&
        _title(widget.title) == null &&
        mounted) {
      setState(() => _displayTitle = null);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _displayTitle;
    if (title == null) return const SizedBox.shrink();
    final primary = SfColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IgnorePointer(
          ignoring: _title(widget.title) == null,
          child: FadeTransition(
            key: const ValueKey('plan-focus-visibility'),
            opacity: _motion,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, child) => Transform.translate(
                key: const ValueKey('plan-focus-motion'),
                offset: Offset(
                  0,
                  _exiting ? _exitOffset : 8 * (1 - _motion.value),
                ),
                child: child,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).width - 40)
                      .clamp(0.0, double.infinity)
                      .toDouble(),
                ),
                child: Container(
                  key: const ValueKey('plan-focus-label'),
                  height: 28,
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  decoration: BoxDecoration(
                    color: primary.withValues(
                      alpha: SfColors.isDark ? .18 : .10,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SfIcon(SfGlyph.bookmark, size: 14, color: primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AnimatedSwitcher(
                          key: const ValueKey('plan-focus-title'),
                          duration: const Duration(milliseconds: 150),
                          child: Text(
                            '正在讨论：$title',
                            key: ValueKey(title),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SfType.label.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                      SfPressable(
                        key: const ValueKey('plan-focus-clear'),
                        semanticLabel: '取消讨论计划',
                        onTap: widget.onClear,
                        child: SizedBox.square(
                          dimension: 28,
                          child: Center(
                            child: SfIcon(
                              SfGlyph.close,
                              size: 14,
                              color: SfColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.bottomGap > 0) SizedBox(height: widget.bottomGap),
      ],
    );
  }
}
