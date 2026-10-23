import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diagnostics/log_export.dart';
import '../diagnostics/runtime_log.dart';
import 'theme.dart';

class RuntimeLogSettings extends StatefulWidget {
  const RuntimeLogSettings({
    super.key,
    this.log,
    this.exporter = const PlatformRuntimeLogExporter(),
  });

  final RuntimeLog? log;
  final RuntimeLogExporter exporter;

  @override
  State<RuntimeLogSettings> createState() => _RuntimeLogSettingsState();
}

class _RuntimeLogSettingsState extends State<RuntimeLogSettings> {
  bool _busy = false;
  String? _message;
  RuntimeLog get _log => widget.log ?? RuntimeLog.instance;

  @override
  Widget build(BuildContext context) {
    if (!_log.enabled) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('内测运行日志已开启', style: SfType.callout),
        const SizedBox(height: SfSpace.x1),
        Text(
          '关键运行节点会自动保存在本机，重新打开 App 后仍保留。'
          '保留最近 7 天、最多 1500 条或 512 KB，达到上限时覆盖最旧记录。'
          '日志包含 AI 路由、耗时、回退、训练和媒体状态，不包含密钥、设备标识或完整聊天内容。',
          style: SfType.caption,
        ),
        const SizedBox(height: SfSpace.x2),
        Text('当前记录 ${_log.entryCount} 条', style: SfType.caption),
        if (_log.persistenceFailed)
          Text('本机持久保存暂时失败，请尽快导出当前日志。', style: SfType.caption),
        const SizedBox(height: SfSpace.x3),
        SfPrimaryButton(
          key: const ValueKey('runtime-log-save'),
          label: _busy ? '正在保存…' : (kIsWeb ? '下载运行日志' : '保存日志到手机'),
          onPressed: _busy ? null : _save,
        ),
        const SizedBox(height: SfSpace.x2),
        Text(
          kIsWeb
              ? '遇到问题后下载 JSON 文件，再把文件发给开发者。'
              : '遇到问题后点保存，在系统文件窗口选择“下载”或其他文件夹，再把 JSON 文件发给开发者。',
          style: SfType.caption,
        ),
        if (_message != null) ...[
          const SizedBox(height: SfSpace.x2),
          Semantics(
            liveRegion: true,
            child: Text(_message!, style: SfType.body),
          ),
        ],
      ],
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final operation = _log.newOperation('export');
    _log.record('diagnostics.export_started', operation: operation);
    try {
      await _log.flush();
      final filename = runtimeLogFilename(DateTime.now());
      final result = await widget.exporter.save(
        filename: filename,
        contents: _log.exportJson(),
      );
      _log.record(
        'diagnostics.export_completed',
        operation: operation,
        fields: {'status': result.name},
      );
      if (mounted) {
        setState(() {
          _message = switch (result) {
            LogExportResult.saved => '日志已保存：$filename',
            LogExportResult.cancelled => '已取消保存；日志仍保存在 App 中。',
            LogExportResult.downloadStarted => '已发起下载：$filename。请在浏览器下载记录中确认。',
          };
        });
      }
    } on Object catch (error) {
      _log.record(
        'diagnostics.export_failed',
        operation: operation,
        fields: {'errorType': error.runtimeType.toString()},
      );
      if (mounted) setState(() => _message = '日志保存失败，请换一个文件夹后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
