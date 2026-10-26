import 'package:flutter/material.dart';
import '../app/services.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_report.dart';
import 'performance_lab_page.dart';
import 'theme.dart';

export 'performance_lab_page.dart' show performanceScenarios;

/// Generic internal report controls remain available after material cleanup.
class PerformanceSettingsPage extends StatefulWidget {
  const PerformanceSettingsPage({super.key, this.service});
  final PerformanceReportService? service;
  @override
  State<PerformanceSettingsPage> createState() =>
      _PerformanceSettingsPageState();
}

class _PerformanceSettingsPageState extends State<PerformanceSettingsPage> {
  PerformanceReportService get _service =>
      widget.service ?? PerformanceReportService.instance;
  FrameRecorder get _recorder => _service.recorder;
  bool _busy = false;
  String? _message;

  Future<void> _share() async {
    if (_busy) return;
    if (_recorder.currentCaseId != null) {
      setState(() => _message = '当前格仍在采样，请完成后再导出。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      final source = context
          .getInheritedWidgetOfExactType<AppScope>()
          ?.services;
      if (source != null) {
        _recorder.setMetadata({
          'contentActionCount': source.library.length,
          'chatMessageCount': source.chat.messages.length,
        });
      }
      await _service.share();
      if (mounted) setState(() => _message = '系统分享已打开；取消分享不会清空统计。');
    } on NoPerformanceFrames {
      if (mounted) setState(() => _message = '还没有收到真实帧，未生成性能结论。');
    } on PerformanceReportTooLarge {
      if (mounted) setState(() => _message = '报告超过64MiB，请使用本地逐格导出；原始统计仍保留。');
    } on Object {
      if (mounted) setState(() => _message = '导出未完成，请稍后重试；已有统计仍保留。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled) return const SizedBox.shrink();
    final status = _recorder.status();
    return Scaffold(
      appBar: const SfTopBar(title: '性能报告'),
      body: ListView(
        padding: const EdgeInsets.all(SfSpace.x4),
        children: [
          const SfSectionTitle('内测原始帧记录'),
          Text(
            '仅在内存中保留本次打开App的原始FrameTiming；重启后清空。'
            '材质固定solid，沿用原星尘设置，不记录聊天内容、动作名称或密钥。'
            '分位由原始整数微秒精确计算，容量不足时明确无效。',
            style: SfType.body,
          ),
          const SizedBox(height: SfSpace.x3),
          SfPrimaryButton(
            key: const ValueKey('performance-open-lab'),
            label: '浅深主题 × 五场景 · 十格采样',
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: 'performance_lab'),
                      builder: (_) => PerformanceLabPage(service: _service),
                    ),
                  ),
          ),
          const SizedBox(height: SfSpace.x3),
          Text(
            '当前格：${status['currentCaseId'] ?? '无'}；待开始：${status['armedCaseId'] ?? '无'}。',
            style: SfType.caption,
          ),
          SfTextAction(
            key: const ValueKey('performance-end-scenario'),
            label: '结束当前格',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _recorder.endCase();
                    _recorder.endScenario();
                    _recorder.cancelArmedCase();
                    _message = '已有原始帧已保留；时长不足或条件不一致的格会标为无效。';
                  }),
          ),
          SfPrimaryButton(
            key: const ValueKey('performance-export'),
            label: _busy ? '正在准备报告…' : '导出性能报告',
            onPressed: _busy ? null : _share,
          ),
          const SizedBox(height: SfSpace.x3),
          SfTextAction(
            key: const ValueKey('performance-reset'),
            label: '开始新一轮（清空本轮统计）',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _recorder.endScenario();
                    _recorder.reset();
                    _recorder.start();
                    _message = '只清空本次内存统计；你的偏好、聊天和历史不变。';
                  }),
          ),
          Text(
            '报告包括每帧engine编号、各phase原始时间、真实刷新率与独立UI/Raster耗时。'
            '120Hz P99严格低于8.33ms；超8.33ms与精确刷新周期计数分别保留。'
            '这些统计不等于屏幕实际呈现帧率或硬件GPU完成时间。',
            style: SfType.caption,
          ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(_message!, style: SfType.body),
            ),
        ],
      ),
    );
  }
}
