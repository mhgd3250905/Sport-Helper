import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/action_issue_export.dart';
import '../diagnostics/action_issue_store.dart';
import 'theme.dart';

class ActionIssueSettings extends StatefulWidget {
  const ActionIssueSettings({
    super.key,
    required this.store,
    this.exporter = const AndroidActionIssueExporter(),
  });

  final LocalActionIssueStore store;
  final ActionIssueExporter exporter;

  @override
  State<ActionIssueSettings> createState() => _ActionIssueSettingsState();
}

class _ActionIssueSettingsState extends State<ActionIssueSettings> {
  late final _service = ActionIssueExportService(
    store: widget.store,
    exporter: widget.exporter,
  );
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await widget.store.load();
    } on Object {
      _message = '读取标记失败，请重试导出。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await _service.saveToDownloads();
      if (mounted) {
        setState(() {
          _message =
              '已保存到下载：${ActionIssueSavedFile.directory}/${saved.displayName}';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _message =
              error is PlatformException &&
                  error.code == 'action_issue_export_unsupported'
              ? '当前 Android 版本不支持直接保存到下载，需要 Android 10 或更新版本。'
              : '保存到下载失败，标记仍保存在本机，请重试。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.enabled) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _loading ? '正在读取本机标记…' : '当前记录 ${widget.store.count} 条',
            style: SfType.callout,
          ),
          const SizedBox(height: 8),
          Text('一键保存 JSON 到“下载/SmartFit”，标记仍保留在本机。', style: SfType.caption),
          const SizedBox(height: 12),
          SfPrimaryButton(
            key: const ValueKey('action-issues-export'),
            label: _busy ? '正在保存…' : '保存动作标记到下载',
            onPressed: _loading || _busy ? null : _save,
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Semantics(liveRegion: true, child: Text(_message!)),
          ],
        ],
      ),
    );
  }
}
