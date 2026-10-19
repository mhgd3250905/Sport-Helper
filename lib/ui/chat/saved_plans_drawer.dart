import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../domain/exercise.dart';
import '../../domain/saved_plan.dart';
import '../../domain/session.dart';
import '../theme.dart' show minutesZh;
import 'cosmos.dart';

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
  final void Function(SavedPlan) onStart;

  /// Entries under the list (动作库, 关于与设置…).
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width * .84).clamp(280.0, 360.0);
    return Drawer(
      width: width,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xE6121733), Color(0xF0070A16)],
            ),
            border: Border(right: BorderSide(color: CosmosColors.edge, width: .7)),
          ),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
                    child: Text(
                      '我的计划',
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        color: CosmosColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Text(
                      store.savedPlans.isEmpty
                          ? '保存的计划会出现在这里'
                          : '${store.savedPlans.length} 套 · 点一下在对话里调出',
                      style: const TextStyle(color: CosmosColors.muted, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: store.savedPlans.isEmpty
                        ? const _Empty()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: store.savedPlans.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                    const Divider(height: 1, thickness: .6, color: CosmosColors.edge, indent: 20, endIndent: 20),
                    const SizedBox(height: 6),
                    ...footer,
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
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
        backgroundColor: const Color(0xFF151A2E),
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
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
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
        backgroundColor: const Color(0xFF151A2E),
        title: Text('删除「${p.name}」？'),
        content: const Text('删除后可以在对话里重新生成。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
            key: const ValueKey('delete-ok'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFFF8A80))),
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(28, 40, 28, 0),
    child: Column(
      children: [
        Icon(Icons.bookmarks_outlined, color: CosmosColors.faint, size: 36),
        SizedBox(height: 14),
        Text(
          '还没有保存的计划',
          style: TextStyle(color: CosmosColors.textSoft, fontSize: 15),
        ),
        SizedBox(height: 6),
        Text(
          '在计划卡片上点「保存」，下次在这里一键开始，或者直接说「上次那个」。',
          textAlign: TextAlign.center,
          style: TextStyle(color: CosmosColors.muted, fontSize: 13, height: 1.6),
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
  final void Function(SavedPlan) onStart;
  final void Function(SavedPlan) onRename;
  final void Function(SavedPlan) onDelete;

  @override
  Widget build(BuildContext context) {
    final p = plan.plan;
    final first = p.items.map((i) => library.tryGet(i.exerciseId)).whereType<Exercise>().firstOrNull;
    final secs = SessionBuilder(library).planSeconds(p);
    final used = plan.lastUsedAt == null ? '' : '\n${_ago(plan.lastUsedAt!)}练过';
    return Material(
      color: const Color(0x0DFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x14FFFFFF), width: .7),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('saved-${plan.id}'),
        onTap: () => onShow(plan),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 52,
                  child: ColoredBox(
                    color: const Color(0xFF101013),
                    child: first == null
                        ? null
                        : Image.asset(first.media.poster, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CosmosColors.text, fontSize: 15.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${minutesZh(secs)} · ${p.items.length} 个动作$used',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CosmosColors.muted, fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: ValueKey('saved-start-${plan.id}'),
                visualDensity: VisualDensity.compact,
                tooltip: '开始训练',
                onPressed: () => onStart(plan),
                icon: const DecoratedBox(
                  decoration: BoxDecoration(color: CosmosColors.accent, shape: BoxShape.circle),
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('saved-menu-${plan.id}'),
                tooltip: '更多',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                color: const Color(0xFF1A2038),
                icon: const Icon(Icons.more_vert_rounded, color: CosmosColors.muted, size: 20),
                onSelected: (v) => v == 'rename' ? onRename(plan) : onDelete(plan),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
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
