import 'package:flutter/material.dart';

import '../../domain/saved_plan.dart';

/// Keeps deleted plan snapshots mounted while their space and opacity leave.
class SavedPlanAnimatedList extends StatefulWidget {
  const SavedPlanAnimatedList({
    super.key,
    required this.plans,
    required this.itemBuilder,
  });

  final List<SavedPlan> plans;
  final Widget Function(BuildContext context, SavedPlan plan) itemBuilder;

  @override
  State<SavedPlanAnimatedList> createState() => _SavedPlanAnimatedListState();
}

class _SavedPlanAnimatedListState extends State<SavedPlanAnimatedList> {
  static const _removalDuration = Duration(milliseconds: 240);
  final _listKey = GlobalKey<SliverAnimatedListState>();
  late List<SavedPlan> _visible;

  @override
  void initState() {
    super.initState();
    _visible = List.of(widget.plans);
  }

  @override
  void didUpdateWidget(SavedPlanAnimatedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final list = _listKey.currentState;
    if (list == null) {
      _visible = List.of(widget.plans);
      return;
    }

    final nextIds = {for (final plan in widget.plans) plan.id};
    final removedItemBuilder = oldWidget.itemBuilder;
    for (var index = _visible.length - 1; index >= 0; index--) {
      if (nextIds.contains(_visible[index].id)) continue;
      final removed = _visible.removeAt(index);
      list.removeItem(
        index,
        (context, animation) => _item(
          context,
          removed,
          animation: animation,
          removing: true,
          itemBuilder: removedItemBuilder,
        ),
        duration: _removalDuration,
      );
    }

    final visibleIds = {for (final plan in _visible) plan.id};
    for (var index = 0; index < widget.plans.length; index++) {
      final plan = widget.plans[index];
      if (!visibleIds.add(plan.id)) continue;
      _visible.insert(index, plan);
      list.insertItem(index, duration: Duration.zero);
    }

    // Stable keys remap existing children; renames/reorders do not remount cards.
    _visible = List.of(widget.plans);
  }

  Widget _item(
    BuildContext context,
    SavedPlan plan, {
    required Animation<double> animation,
    required bool removing,
    required Widget Function(BuildContext, SavedPlan) itemBuilder,
  }) {
    // The list reverses 1 -> 0. This gives easeOutCubic over elapsed exit time.
    final factor = removing
        ? animation.drive(CurveTween(curve: Curves.easeInCubic))
        : kAlwaysCompleteAnimation;
    return KeyedSubtree(
      key: _SavedPlanItemKey(plan.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizeTransition(
            key: ValueKey('saved-entry-${plan.id}'),
            sizeFactor: factor,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: factor,
              child: IgnorePointer(
                ignoring: removing,
                child: ExcludeSemantics(
                  excluding: removing,
                  child: itemBuilder(context, plan),
                ),
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: factor,
            alignment: Alignment.topCenter,
            child: const SizedBox(height: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverAnimatedList(
    key: _listKey,
    initialItemCount: _visible.length,
    findChildIndexCallback: (key) {
      if (key is! _SavedPlanItemKey) return null;
      final index = _visible.indexWhere((plan) => plan.id == key.value);
      return index < 0 ? null : index;
    },
    itemBuilder: (context, index, animation) => _item(
      context,
      _visible[index],
      animation: animation,
      removing: false,
      itemBuilder: widget.itemBuilder,
    ),
  );
}

class _SavedPlanItemKey extends ValueKey<String> {
  const _SavedPlanItemKey(super.value);
}
