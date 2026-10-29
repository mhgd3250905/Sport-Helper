import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import '../../data/app_store.dart';
import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../domain/saved_plan.dart';
import '../alpha_artwork.dart';
import '../plan_page.dart';
import '../plan_presentation.dart';
import '../theme/media_theme.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/ui_polish_tokens.dart';
import '../theme/widgets.dart';
import 'coach_ui_adapter.dart';
import 'expand_route.dart';
import 'saved_plan_actions.dart';
import 'saved_plan_animated_list.dart';

/// One saved plan expands in place through the SDK's shared presentation.
class SavedPlansPage extends StatefulWidget {
  const SavedPlansPage({
    super.key,
    required this.store,
    required this.library,
    required this.onShow,
    required this.onStart,
    this.onCompose,
  });

  final AppStore store;
  final ExerciseLibrary library;
  final void Function(SavedPlan) onShow;
  final void Function(SavedPlan, OriginRect from) onStart;
  final VoidCallback? onCompose;

  @override
  State<SavedPlansPage> createState() => _SavedPlansPageState();
}

class _SavedPlansPageState extends State<SavedPlansPage> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _entryKeys = <String, GlobalKey>{};
  String? _expandedId;
  Timer? _revealTimer;
  int _revealEpoch = 0;
  bool _autoRevealing = false;
  Timer? _emptyTimer;
  late bool _emptyReady;

  @override
  void initState() {
    super.initState();
    _emptyReady = widget.store.savedPlans.isEmpty;
    widget.store.addListener(_storeChanged);
  }

  @override
  void didUpdateWidget(SavedPlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.removeListener(_storeChanged);
    widget.store.addListener(_storeChanged);
    _cancelReveal();
    _emptyTimer?.cancel();
    _emptyReady = widget.store.savedPlans.isEmpty;
    if (!widget.store.savedPlans.any((plan) => plan.id == _expandedId)) {
      _expandedId = null;
    }
  }

  void _storeChanged() {
    _cancelReveal();
    if (!widget.store.savedPlans.any((plan) => plan.id == _expandedId)) {
      _expandedId = null;
    }
    _emptyTimer?.cancel();
    if (widget.store.savedPlans.isEmpty) {
      _emptyTimer = Timer(SfSavedPlanTokens.removal, () {
        if (mounted && widget.store.savedPlans.isEmpty) {
          setState(() => _emptyReady = true);
        }
      });
    } else {
      _emptyReady = false;
    }
    setState(() {});
  }

  void _cancelReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealEpoch++;
    if (_autoRevealing && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.offset);
    }
    _autoRevealing = false;
  }

  void _toggle(SavedPlan plan) {
    _cancelReveal();
    final expand = _expandedId != plan.id;
    setState(() => _expandedId = expand ? plan.id : null);
    if (!expand) return;
    final epoch = _revealEpoch;
    final reduced = SfMotion.reduced(context);
    _revealTimer = Timer(
      reduced ? Duration.zero : SfPlanPolishTokens.expansion,
      () {
        _revealTimer = null;
        // The SDK has no onEnd. Measure only after its last layout frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || epoch != _revealEpoch || _expandedId != plan.id) {
            return;
          }
          final entryContext = _entryKeys[plan.id]?.currentContext;
          final entry = entryContext?.findRenderObject();
          final viewport = _viewport.currentContext?.findRenderObject();
          if (entryContext == null ||
              entry is! RenderBox ||
              viewport is! RenderBox ||
              !entry.hasSize ||
              !viewport.hasSize ||
              !widget.store.savedPlans.any((saved) => saved.id == plan.id)) {
            return;
          }
          final bottom =
              entry.localToGlobal(Offset.zero).dy + entry.size.height;
          final viewportBottom =
              viewport.localToGlobal(Offset.zero).dy + viewport.size.height;
          if (bottom <= viewportBottom) return;
          _autoRevealing = true;
          unawaited(
            Scrollable.ensureVisible(
              entryContext,
              alignment: 1,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              duration: reduced
                  ? Duration.zero
                  : SfPlanPolishTokens.revealScroll,
              curve: SfMotion.standard,
            ).whenComplete(() {
              if (mounted && epoch == _revealEpoch) _autoRevealing = false;
            }),
          );
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      },
    );
  }

  void _show(SavedPlan plan) {
    _cancelReveal();
    widget.onShow(plan);
  }

  void _start(SavedPlan plan, OriginRect from) {
    _cancelReveal();
    widget.onStart(plan, from);
  }

  void _details(SavedPlan saved) {
    _cancelReveal();
    // A saved name is presentation only; the original plan ID/doses are intact.
    final displayPlan = TrainingPlan.fromJson({
      ...saved.plan.toJson(),
      'title': saved.name,
    });
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'plan'),
          builder: (_) => PlanPage(plan: displayPlan),
        ),
      ),
    );
  }

  Widget _entry(SavedPlan saved, {required bool expanded}) {
    return _SavedPlanEntry(
      key: _entryKeys.putIfAbsent(saved.id, GlobalKey.new),
      saved: saved,
      library: widget.library,
      expanded: expanded,
      onToggle: () => _toggle(saved),
      onShow: _show,
      onStart: _start,
      onRename: (plan) => _rename(context, plan),
      onDelete: (plan) => _delete(context, plan),
      onDetails: _details,
      onInteract: _cancelReveal,
    );
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _revealTimer?.cancel();
    _emptyTimer?.cancel();
    _revealEpoch++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A removed item's old builder must retain its expanded snapshot while
    // the list animates its removal, rather than starting an SDK collapse too.
    final expandedId = _expandedId;
    return Scaffold(
      backgroundColor: SfColors.background,
      appBar: AppBar(
        title: const Text('我的计划'),
        backgroundColor: SfColors.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SizedBox.expand(
          key: _viewport,
          child: CustomScrollView(
            key: const ValueKey('saved-plans-scroll'),
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${widget.store.savedPlans.length} 套',
                        style: SfType.label.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: SfSavedPlanTokens.secondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '长按可编辑',
                        style: SfType.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: SfSavedPlanTokens.tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.store.savedPlans.isEmpty && _emptyReady)
                SliverToBoxAdapter(child: _Empty(onCompose: widget.onCompose)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                sliver: SavedPlanAnimatedList(
                  plans: List.of(widget.store.savedPlans),
                  itemBuilder: (_, plan) =>
                      _entry(plan, expanded: expandedId == plan.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, SavedPlan p) async {
    final name = await renameSavedPlan(context, p.name);
    if (mounted && name != null && name.trim().isNotEmpty) {
      await widget.store.renamePlan(p.id, name);
    }
  }

  Future<void> _delete(BuildContext context, SavedPlan p) async {
    final ok = await confirmDeleteSavedPlan(context, p.name);
    if (mounted && ok == true) await widget.store.deletePlan(p.id);
  }
}

/// Stable slots let the SDK retain one surface and header through reversals.
class _SavedPlanEntry extends StatefulWidget {
  const _SavedPlanEntry({
    super.key,
    required this.saved,
    required this.library,
    required this.expanded,
    required this.onToggle,
    required this.onShow,
    required this.onStart,
    required this.onRename,
    required this.onDelete,
    required this.onDetails,
    required this.onInteract,
  });
  final SavedPlan saved;
  final ExerciseLibrary library;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<SavedPlan> onShow;
  final void Function(SavedPlan, OriginRect) onStart;
  final ValueChanged<SavedPlan> onRename;
  final ValueChanged<SavedPlan> onDelete;
  final ValueChanged<SavedPlan> onDetails;
  final VoidCallback onInteract;

  @override
  State<_SavedPlanEntry> createState() => _SavedPlanEntryState();
}

class _SavedPlanEntryState extends State<_SavedPlanEntry>
    with SingleTickerProviderStateMixin {
  late Widget _header;
  late Widget _summary;
  late final _press = AnimationController(
    vsync: this,
    value: 1,
    lowerBound: .98,
    upperBound: 1.01,
  );
  bool _menuVisible = false;

  @override
  void initState() {
    super.initState();
    _updateSlots();
  }

  @override
  void didUpdateWidget(_SavedPlanEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.saved != widget.saved ||
        oldWidget.library != widget.library) {
      _updateSlots();
    }
  }

  void _updateSlots() {
    // Cache slot widgets, not styled Text/colour values. Each slot reads theme
    // tokens in build; callbacks always consult this entry's latest widget.
    _header = _SavedPlanHeader(
      key: ValueKey('saved-header-${widget.saved.id}'),
      saved: widget.saved,
      onMenu: () => unawaited(_openMenu()),
    );
    _summary = _SavedPlanSummary(
      key: ValueKey('saved-summary-${widget.saved.id}'),
      saved: widget.saved,
      library: widget.library,
      onStart: (from) => widget.onStart(widget.saved, from),
    );
  }

  void _down(PointerDownEvent _) {
    if (_menuVisible) return;
    widget.onInteract();
    _press.animateTo(
      .98,
      duration: SfSavedPlanTokens.press,
      curve: Curves.easeOut,
    );
  }

  void _up(PointerEvent _) {
    if (!_menuVisible) _release();
  }

  void _release() => _press.animateTo(
    1,
    duration: SfSavedPlanTokens.rebound,
    curve: Curves.easeOutBack,
  );

  Rect _bounds() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Rect _highlightBounds() {
    final bounds = _bounds();
    return Rect.fromCenter(
      center: bounds.center,
      width: bounds.width * _press.value,
      height: bounds.height * _press.value,
    );
  }

  Future<void> _openMenu() async {
    if (_menuVisible) return;
    widget.onInteract();
    _menuVisible = true;
    unawaited(HapticFeedback.mediumImpact());
    _release();
    final action = await showSavedPlanMenu(
      context,
      cardRect: _bounds,
      highlightRect: _highlightBounds,
      cardAnimation: _press,
    );
    if (!mounted) return;
    _menuVisible = false;
    switch (action) {
      case SavedPlanAction.show:
        widget.onShow(widget.saved);
      case SavedPlanAction.rename:
        widget.onRename(widget.saved);
      case SavedPlanAction.delete:
        widget.onDelete(widget.saved);
      case null:
        break;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.saved;
    final routine = toCoachRoutine(saved.plan, widget.library);
    final alpha = SfAlphaCards.enabledOf(context);
    final card = withSmartfitSavedPlanUi(
      context,
      CoachPlanExpanded(
        key: ValueKey('saved-expanded-${saved.id}'),
        plan: CoachRoutine(
          id: routine.id,
          title: saved.name,
          items: routine.items,
          durationLabel: routine.durationLabel,
          gearLabel: routine.gearLabel,
          levelLabel: routine.levelLabel,
          metaLabel: routine.metaLabel,
          adjustmentsLabel: routine.adjustmentsLabel,
        ),
        library: CoachExerciseLibrary([
          for (final id in saved.plan.exerciseIds)
            if (widget.library.tryGet(id) case final exercise?)
              toCoachExercise(exercise, alphaCards: alpha),
        ]),
        header: widget.expanded ? _header : const SizedBox.shrink(),
        collapsedSummary: _summary,
        expanded: widget.expanded,
        onToggle: widget.onToggle,
        onCollapse: widget.onToggle,
        actionIcon: CoachGlyph.chevronRight,
        actionLabel: '查看详情',
        onAction: () => widget.onDetails(saved),
        onStart: (from) => widget.onStart(saved, from),
      ),
      compact: !widget.expanded,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _openMenu,
      // During the SDK's outgoing-body/summary handoff the summary temporarily
      // ignores input. Keep the compact card tappable for a quick reversal;
      // nested play/header controls still win their own gesture arena.
      onTap: widget.expanded ? null : widget.onToggle,
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: AnimatedBuilder(
          animation: _press,
          child: card,
          builder: (_, child) =>
              Transform.scale(scale: _press.value, child: child),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onCompose});
  final VoidCallback? onCompose;
  @override
  Widget build(BuildContext context) => SfEmptyState(
    icon: SfGlyph.bookmark,
    title: '还没有保存的计划',
    body: '在计划卡片上点「保存」，下次在这里一键开始，或者直接说「上次那个」。',
    action: onCompose == null ? null : '去排一套',
    onAction: onCompose,
  );
}

class _SavedPlanHeader extends StatelessWidget {
  const _SavedPlanHeader({
    super.key,
    required this.saved,
    required this.onMenu,
  });

  final SavedPlan saved;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Row(
    key: ValueKey('saved-open-header-${saved.id}'),
    children: [
      Expanded(
        child: Text(
          saved.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SfCardTokens.title,
        ),
      ),
      IconButton(
        key: ValueKey('saved-menu-${saved.id}'),
        tooltip: '更多',
        padding: EdgeInsets.zero,
        icon: SfIcon(SfGlyph.more, color: SfColors.muted, size: SfSpace.x5),
        onPressed: onMenu,
      ),
    ],
  );
}

class _SavedPlanSummary extends StatelessWidget {
  const _SavedPlanSummary({
    super.key,
    required this.saved,
    required this.library,
    required this.onStart,
  });

  final SavedPlan saved;
  final ExerciseLibrary library;
  final ValueChanged<OriginRect> onStart;

  @override
  Widget build(BuildContext context) {
    final p = saved.plan;
    final first = p.items
        .map((i) => library.tryGet(i.exerciseId))
        .whereType<Exercise>()
        .firstOrNull;
    final used = saved.lastUsedAt == null ? '' : '${_ago(saved.lastUsedAt!)}练过';
    // The SDK supplies 6px at its surface. These 10px complete the requested
    // 16px inset without changing its expanded-body width or measurement.
    return Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        key: ValueKey('saved-${saved.id}'),
        height: 76,
        child: Row(
          children: [
            Container(
              key: ValueKey('saved-thumbnail-${saved.id}'),
              width: 76,
              height: 76,
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: SfSavedPlanTokens.insetFill,
                borderRadius: BorderRadius.circular(14),
              ),
              child: first == null
                  ? null
                  : Image.asset(
                      toCoachRecommendationExercise(first).stillCutout ??
                          sfPoster(first),
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    saved.name,
                    key: ValueKey('saved-title-${saved.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SfType.body.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: SfColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${planDurationLabel(p, library)} · ${p.items.length} 个动作',
                    key: ValueKey('saved-meta-${saved.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SfType.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: SfSavedPlanTokens.secondary,
                    ),
                  ),
                  if (used.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      used,
                      key: ValueKey('saved-used-${saved.id}'),
                      maxLines: 1,
                      style: SfType.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: SfSavedPlanTokens.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              key: ValueKey('saved-start-${saved.id}'),
              button: true,
              label: '开始训练',
              child: Tooltip(
                message: '开始训练',
                child: InkResponse(
                  onTap: () {
                    unawaited(HapticFeedback.mediumImpact());
                    // Where the tile is now; once this page is gone the
                    // player folds back into the middle of the chat.
                    final at = rectOf(context);
                    var first = true;
                    onStart(() {
                      if (!first) return null;
                      first = false;
                      return at;
                    });
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SfColors.accent.withValues(
                        alpha: SfColors.isDark ? .20 : .12,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: SfIcon(
                      SfGlyph.play,
                      size: 20,
                      color: SfColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays >= 1) return '${d.inDays} 天前';
    if (d.inHours >= 1) return '${d.inHours} 小时前';
    return '刚刚';
  }
}
