import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// Presentation of SDK node snapshots. No progress is inferred from text.
class CoachTaskBubble extends StatefulWidget {
  const CoachTaskBubble({
    super.key,
    this.task,
    this.waiting = false,
    this.onCancel,
  });

  final coach.CoachTaskState? task;
  final bool waiting;
  final VoidCallback? onCancel;

  @override
  State<CoachTaskBubble> createState() => _CoachTaskBubbleState();
}

class _CoachTaskBubbleState extends State<CoachTaskBubble> {
  bool _expanded = false;

  bool get _completed =>
      widget.task?.nodes.any((node) => node.id == 'output' && _done(node)) ??
      false;

  static bool _done(coach.CoachNodeState node) =>
      node.status == 'done' || node.status == 'updated';

  static String _label(String id) => switch (id) {
    'understand' => '理解目标',
    'parameters' => '确认条件',
    'actions' => '挑选动作',
    'planning' => '编排训练',
    'review' => '核对方案',
    'output' => '交付卡片',
    _ => id,
  };

  @override
  Widget build(BuildContext context) {
    final nodes = widget.task?.nodes ?? const <coach.CoachNodeState>[];
    final folded = _completed && !widget.waiting && !_expanded;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SfPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _completed ? '已完成' : '教练待办',
                      style: SfType.label,
                    ),
                  ),
                  if (_completed && !widget.waiting)
                    TextButton(
                      key: const ValueKey('coach-task-toggle'),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(folded ? '展开' : '收起'),
                    ),
                  if (widget.waiting && widget.onCancel != null)
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('取消'),
                    ),
                ],
              ),
              if (!folded)
                for (final node in nodes)
                  Padding(
                    key: ValueKey('coach-node-${node.id}'),
                    padding: const EdgeInsets.symmetric(vertical: SfSpace.x2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _done(node)
                              ? Icons.check_circle_rounded
                              : node.status == 'current'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _done(node) || node.status == 'current'
                              ? SfColors.accent
                              : SfColors.muted,
                        ),
                        const SizedBox(width: SfSpace.x2),
                        Expanded(
                          child: Text(
                            node.stamp?.isNotEmpty == true
                                ? node.stamp!
                                : _label(node.id),
                            style: SfType.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
              if (nodes.isEmpty && widget.waiting)
                Text('…', style: SfType.body),
            ],
          ),
        ),
      ),
    );
  }
}
