import 'dart:async';

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_storeChanged);
  }

  @override
  void didUpdateWidget(SavedPlansPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store == widget.store) return;
    oldWidget.store.removeListener(_storeChanged);
    widget.store.addListener(_storeChanged);
    _cancelReveal();
    if (!widget.store.savedPlans.any((plan) => plan.id == _expandedId)) {
      _expandedId = null;
    }
  }

  void _storeChanged() {
    _cancelReveal();
    if (!widget.store.savedPlans.any((plan) => plan.id == _expandedId)) {
      _expandedId = null;
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

  Widget _entry(SavedPlan saved) {
    return SizedBox(
      key: ValueKey('saved-entry-${saved.id}'),
      child: _SavedPlanEntry(
        key: _entryKeys.putIfAbsent(saved.id, GlobalKey.new),
        saved: saved,
        library: widget.library,
        expanded: _expandedId == saved.id,
        onToggle: () => _toggle(saved),
        onShow: _show,
        onStart: _start,
        onRename: (plan) => _rename(context, plan),
        onDelete: (plan) => _delete(context, plan),
        onDetails: _details,
      ),
    );
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _revealTimer?.cancel();
    _revealEpoch++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                padding: const EdgeInsets.fromLTRB(
                  SfSpace.x6,
                  SfSpace.x3,
                  SfSpace.x6,
                  SfSpace.x4,
                ),
                child: Text(
                  '${widget.store.savedPlans.length} 套',
                  style: SfType.label,
                ),
              ),
            ),
            if (widget.store.savedPlans.isEmpty)
              SliverToBoxAdapter(child: _Empty(onCompose: widget.onCompose))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  SfSpace.x4,
                  0,
                  SfSpace.x4,
                  SfSpace.x4,
                ),
                sliver: SliverList.separated(
                  itemCount: widget.store.savedPlans.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: SfSpace.x2),
                  itemBuilder: (context, i) =>
                      _entry(widget.store.savedPlans[i]),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Future<void> _rename(BuildContext context, SavedPlan p) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSavedPlanDialog(name: p.name),
    );
    if (mounted && name != null && name.trim().isNotEmpty) {
      await widget.store.renamePlan(p.id, name);
    }
  }

  Future<void> _delete(BuildContext context, SavedPlan p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除「${p.name}」？'),
        content: const Text('删除后可以在对话里重新生成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('取消', style: TextStyle(color: SfColors.muted)),
          ),
          TextButton(
            key: const ValueKey('delete-ok'),
            onPressed: () => Navigator.pop(c, true),
            child: Text('删除', style: TextStyle(color: SfColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.deletePlan(p.id);
  }
}

class _RenameSavedPlanDialog extends StatefulWidget {
  const _RenameSavedPlanDialog({required this.name});
  final String name;

  @override
  State<_RenameSavedPlanDialog> createState() => _RenameSavedPlanDialogState();
}

class _RenameSavedPlanDialogState extends State<_RenameSavedPlanDialog> {
  late final _text = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('重命名'),
    content: TextField(
      key: const ValueKey('rename-field'),
      controller: _text,
      autofocus: true,
      maxLength: 20,
      decoration: const InputDecoration(hintText: '计划名称'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('取消', style: TextStyle(color: SfColors.muted)),
      ),
      TextButton(
        key: const ValueKey('rename-ok'),
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('确定'),
      ),
    ],
  );
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

  @override
  State<_SavedPlanEntry> createState() => _SavedPlanEntryState();
}

class _SavedPlanEntryState extends State<_SavedPlanEntry> {
  late Widget _header;
  late Widget _summary;

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
      onShow: () => widget.onShow(widget.saved),
      onRename: () => widget.onRename(widget.saved),
      onDelete: () => widget.onDelete(widget.saved),
    );
    _summary = _SavedPlanSummary(
      key: ValueKey('saved-summary-${widget.saved.id}'),
      saved: widget.saved,
      library: widget.library,
      onStart: (from) => widget.onStart(widget.saved, from),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.saved;
    final routine = toCoachRoutine(saved.plan, widget.library);
    final alpha = SfAlphaCards.enabledOf(context);
    return withSmartfitSavedPlanUi(
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
        header: _header,
        collapsedSummary: _summary,
        expanded: widget.expanded,
        onToggle: widget.onToggle,
        onCollapse: widget.onToggle,
        actionIcon: CoachGlyph.chevronRight,
        actionLabel: '查看详情',
        onAction: () => widget.onDetails(saved),
        onStart: (from) => widget.onStart(saved, from),
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
    required this.onShow,
    required this.onRename,
    required this.onDelete,
  });

  final SavedPlan saved;
  final VoidCallback onShow;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Row(
    key: ValueKey('saved-${saved.id}'),
    children: [
      Expanded(
        child: Text(
          saved.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: SfCardTokens.title,
        ),
      ),
      PopupMenuButton<String>(
        key: ValueKey('saved-menu-${saved.id}'),
        tooltip: '更多',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: SfSpace.x6 * 5),
        icon: SfIcon(SfGlyph.more, color: SfColors.muted, size: SfSpace.x5),
        onSelected: (value) {
          switch (value) {
            case 'show':
              onShow();
            case 'rename':
              onRename();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'show', child: Text('点一下在对话里调出')),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          PopupMenuItem(
            value: 'delete',
            child: Text('删除', style: TextStyle(color: SfColors.danger)),
          ),
        ],
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
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SfRadius.lg - SfSpace.x2),
          child: SizedBox.square(
            dimension: SfSpace.x8 + SfSpace.x6,
            child: first == null
                ? null
                : Image.asset(
                    sfPoster(first),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          ),
        ),
        const SizedBox(width: SfSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${planDurationLabel(p, library)} · ${p.items.length} 个动作',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SfCardTokens.metadata,
              ),
              if (used.isNotEmpty)
                Text(used, maxLines: 1, style: SfType.caption),
            ],
          ),
        ),
        const SizedBox(width: SfSpace.x2),
        SfCircleButton(
          key: ValueKey('saved-start-${saved.id}'),
          tooltip: '开始训练',
          size: SfSpace.x5 * 2,
          icon: SfGlyph.play,
          fill: SfColors.isDark ? SfColors.surface : SfColors.surfaceHigh,
          iconColor: SfColors.accentText,
          haptic: SfHaptic.medium,
          onPressed: () {
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
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays >= 1) return '${d.inDays} 天前';
    if (d.inHours >= 1) return '${d.inHours} 小时前';
    return '刚刚';
  }
}
