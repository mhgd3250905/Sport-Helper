import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../domain/exercise.dart';
import '../../domain/saved_plan.dart';
import '../../domain/session.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'expand_route.dart';

/// Drawer from the input's left icon: the saved plans (tap = show it in
/// the chat, ▶ = start now, ⋯ = rename / delete), then app entries.
class SavedPlansDrawer extends StatelessWidget {
  const SavedPlansDrawer({
    super.key,
    required this.store,
    required this.library,
    required this.onShow,
    required this.onStart,
    this.footer = const [],
  });

  final AppStore store;
  final ExerciseLibrary library;
  final void Function(SavedPlan) onShow;

  /// ▶; [from] is the tile, which the player grows out of.
  final void Function(SavedPlan, OriginRect from) onStart;

  /// Entries under the list (动作库, 关于与设置…).
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * .84).clamp(280.0, 360.0);
    return Drawer(
      width: width,
      backgroundColor: SfColors.isDark ? SfColors.surface : SfColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(SfRadius.xl)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.x6, SfSpace.x6, SfSpace.x6, SfSpace.x1),
                child: Text('我的计划', style: SfType.title.copyWith(fontSize: 24)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.x6, 0, SfSpace.x6, SfSpace.x4),
                child: Text(
                  store.savedPlans.isEmpty
                      ? '保存的计划会出现在这里'
                      : '${store.savedPlans.length} 套 · 点一下在对话里调出',
                  style: SfType.label,
                ),
              ),
              Expanded(
                child: store.savedPlans.isEmpty
                    ? const _Empty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x4),
                        itemCount: store.savedPlans.length,
                        separatorBuilder: (_, _) => const SizedBox(height: SfSpace.x2),
                        itemBuilder: (context, i) => _SavedTile(
                          plan: store.savedPlans[i],
                          library: library,
                          onShow: onShow,
                          onStart: onStart,
                          onRename: (p) => _rename(context, p),
                          onDelete: (p) => _delete(context, p),
                        ),
                      ),
              ),
              if (footer.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SfSpace.x6),
                  child: Divider(color: SfColors.isDark ? SfColors.surfaceHigh : SfColors.line),
                ),
                const SizedBox(height: SfSpace.x2),
                ...footer,
                const SizedBox(height: SfSpace.x3),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, SavedPlan p) async {
    final text = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          key: const ValueKey('rename-field'),
          controller: text,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '计划名称'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('取消', style: TextStyle(color: SfColors.muted)),
          ),
          TextButton(
            key: const ValueKey('rename-ok'),
            onPressed: () => Navigator.pop(c, text.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    text.dispose();
    if (name != null && name.trim().isNotEmpty) await store.renamePlan(p.id, name);
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
    if (ok == true) await store.deletePlan(p.id);
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
    child: Column(
      children: [
        SfIcon(SfGlyph.bookmark, color: SfColors.faint, size: 36),
        const SizedBox(height: 14),
        Text('还没有保存的计划', style: SfType.callout),
        const SizedBox(height: 6),
        Text(
          '在计划卡片上点「保存」，下次在这里一键开始，或者直接说「上次那个」。',
          textAlign: TextAlign.center,
          style: SfType.label.copyWith(height: 1.6),
        ),
      ],
    ),
  );
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.plan,
    required this.library,
    required this.onShow,
    required this.onStart,
    required this.onRename,
    required this.onDelete,
  });

  final SavedPlan plan;
  final ExerciseLibrary library;
  final void Function(SavedPlan) onShow;
  final void Function(SavedPlan, OriginRect from) onStart;
  final void Function(SavedPlan) onRename;
  final void Function(SavedPlan) onDelete;

  @override
  Widget build(BuildContext context) {
    final p = plan.plan;
    final first = p.items.map((i) => library.tryGet(i.exerciseId)).whereType<Exercise>().firstOrNull;
    final secs = SessionBuilder(library).planSeconds(p);
    final used = plan.lastUsedAt == null ? '' : '${_ago(plan.lastUsedAt!)}练过';
    return Material(
      color: SfColors.isDark ? SfColors.surfaceHigh : SfColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SfRadius.md),
        side: SfColors.cardEdge,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('saved-${plan.id}'),
        onTap: () => onShow(plan),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SfSpace.x2, SfSpace.x2, 0, SfSpace.x2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(SfRadius.sm),
                child: SizedBox.square(
                  dimension: 56,
                  child: ColoredBox(
                    color: SfColors.mediaStage,
                    child: first == null
                        ? null
                        : Image.asset(first.media.poster, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                ),
              ),
              const SizedBox(width: SfSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SfType.callout.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(secs / 60).round().clamp(1, 999)} 分钟 · ${p.items.length} 个动作',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SfType.label.copyWith(fontSize: 12.5),
                    ),
                    if (used.isNotEmpty)
                      Text(used, maxLines: 1, style: SfType.caption),
                  ],
                ),
              ),
              const SizedBox(width: SfSpace.x2),
              SfCircleButton(
                key: ValueKey('saved-start-${plan.id}'),
                tooltip: '开始训练',
                size: 40,
                icon: SfGlyph.play,
                fill: SfColors.isDark ? SfColors.surface : SfColors.surfaceHigh,
                iconColor: SfColors.accentText,
                onPressed: () {
                  // Where the tile is now; once the drawer is gone the
                  // player folds back into the middle of the chat.
                  final at = rectOf(context);
                  var first = true;
                  onStart(plan, () {
                    if (!first) return null;
                    first = false;
                    return at;
                  });
                },
              ),
              PopupMenuButton<String>(
                key: ValueKey('saved-menu-${plan.id}'),
                tooltip: '更多',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 120),
                icon: SfIcon(SfGlyph.more, color: SfColors.muted, size: 20),
                onSelected: (v) => v == 'rename' ? onRename(plan) : onDelete(plan),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: SfColors.danger))),
                ],
              ),
            ],
          ),
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

/// A quiet row at the bottom of the drawer (动作库, 关于与设置…).
class DrawerEntry extends StatelessWidget {
  const DrawerEntry({super.key, required this.icon, required this.label, this.hint, required this.onTap});
  final SfGlyph icon;
  final String label;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: SfSpace.x6, vertical: 10),
      child: Row(
        children: [
          SfIcon(icon, size: 20, color: SfColors.muted),
          const SizedBox(width: SfSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SfType.callout.copyWith(fontWeight: FontWeight.w400)),
                if (hint != null)
                  Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.caption),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
