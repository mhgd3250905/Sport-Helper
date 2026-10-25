import 'package:flutter/material.dart';

import '../diagnostics/action_issue.dart';
import '../diagnostics/action_issue_store.dart';
import 'theme/widgets.dart';

/// The caller captures action/revision/actual video time before opening this.
Future<ActionIssue?> showActionIssueForm(
  BuildContext context, {
  required LocalActionIssueStore store,
  required ActionIssueContext capture,
}) {
  if (!store.enabled) return Future.value();
  return showModalBottomSheet<ActionIssue>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ActionIssueForm(
      store: store,
      capture: capture,
      onSaved: (issue) => Navigator.of(context).pop(issue),
    ),
  );
}

class ActionIssueForm extends StatefulWidget {
  const ActionIssueForm({
    super.key,
    required this.store,
    required this.capture,
    required this.onSaved,
  });

  final LocalActionIssueStore store;
  final ActionIssueContext capture;
  final ValueChanged<ActionIssue> onSaved;

  @override
  State<ActionIssueForm> createState() => _ActionIssueFormState();
}

class _ActionIssueFormState extends State<ActionIssueForm> {
  final _note = TextEditingController();
  final _tags = <ActionIssueTag>{};
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final record = await widget.store.add(
        widget.capture,
        tags: _tags,
        note: _note.text,
      );
      if (mounted) widget.onSaved(record);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.enabled) return const SizedBox.shrink();
    final capture = widget.capture;
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('标记动作问题', style: text.titleLarge),
            const SizedBox(height: 12),
            Text('动作：${capture.actionId}', style: text.bodyMedium),
            Text('修订：${capture.revision ?? '未提供'}', style: text.bodyMedium),
            Text(
              capture.videoSeconds == null
                  ? '视频时间：未记录（${capture.videoPositionUnavailableReason!.label}）'
                  : '视频时间：${capture.videoSeconds!.toStringAsFixed(2)} 秒',
              key: const ValueKey('action-issue-video-time'),
              style: text.bodyMedium,
            ),
            Text(
              '标记时间：${capture.capturedAt.toLocal().toIso8601String()}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('问题类型（可多选，也可不选）', style: text.bodyMedium),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in ActionIssueTag.values)
                  FilterChip(
                    key: ValueKey('action-issue-tag-${tag.code}'),
                    label: Text(tag.label),
                    selected: _tags.contains(tag),
                    onSelected: _busy
                        ? null
                        : (selected) => setState(() {
                            selected ? _tags.add(tag) : _tags.remove(tag);
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('action-issue-note'),
              controller: _note,
              enabled: !_busy,
              maxLength: ActionIssue.noteLimit,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '一句备注（可选）'),
            ),
            if (_failed)
              Semantics(liveRegion: true, child: const Text('保存失败，内容还在，请重试。')),
            const SizedBox(height: 12),
            SfPrimaryButton(
              key: const ValueKey('action-issue-save'),
              label: _busy ? '正在保存…' : '保存标记',
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 8),
            Text('仅保存在本机，可在设置中一键保存 JSON 到下载。', style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
