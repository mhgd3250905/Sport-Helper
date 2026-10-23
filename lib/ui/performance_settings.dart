import 'package:flutter/material.dart';

import '../app/services.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_report.dart';
import 'theme.dart';

const performanceScenarios = <FrameScenario, String>{
  FrameScenario.actionListScroll: '动作库快速滑动',
  FrameScenario.filterSwitch: '筛选切换',
  FrameScenario.actionDetail: '动作详情进出',
  FrameScenario.longChatScroll: '长聊天记录滑动',
  FrameScenario.planExpand: '计划卡展开和收起',
  FrameScenario.trainingActionSwitch: '训练页切换动作',
  FrameScenario.mediaDownloadScroll: '下载和校验中的滑动',
};

/// Internal-only controls. Nothing subscribes to per-frame notifications.
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
  FrameScenario _selected = FrameScenario.actionListScroll;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final scenario = _recorder.currentScenario;
    if (scenario != null && performanceScenarios.containsKey(scenario)) {
      _selected = scenario;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled) return const SizedBox.shrink();
    return Scaffold(
      appBar: const SfTopBar(title: '性能报告'),
      body: ListView(
        padding: const EdgeInsets.all(SfSpace.x4),
        children: [
          const SfSectionTitle('内测帧记录'),
          Text(
            '仅在内存里统计本次打开 App 的帧耗时；重启后清空。'
            '自动按页面分组，不记录聊天内容或动作名称。'
            '请保持相同主题、星尘设置、素材缓存和操作步骤。',
            style: SfType.body,
          ),
          const SizedBox(height: SfSpace.x3),
          Text(_recorder.isRunning ? '记录中' : '记录已暂停', style: SfType.callout),
          Text(
            '当前场景：${performanceScenarios[_recorder.currentScenario] ?? '自动按页面记录'}',
            style: SfType.caption,
          ),
          const SizedBox(height: SfSpace.x3),
          SfPrimaryButton(
            key: const ValueKey('performance-reset'),
            label: '开始新一轮（清空本轮统计）',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _recorder.endScenario();
                    _recorder.reset();
                    _recorder.start();
                    _message = '已开始新一轮；逐个选择场景，全部跑完后再导出。';
                  }),
          ),
          const SfSectionTitle('选择本次场景'),
          DropdownButtonFormField<FrameScenario>(
            key: const ValueKey('performance-scenario'),
            initialValue: _selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '场景'),
            items: [
              for (final entry in performanceScenarios.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _selected = value);
                  },
          ),
          const SizedBox(height: SfSpace.x3),
          SfPrimaryButton(
            key: const ValueKey('performance-start-scenario'),
            label: '开始此场景并返回',
            onPressed: _busy
                ? null
                : () {
                    _recorder.start();
                    _recorder.beginScenario(_selected);
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    setState(
                      () => _message = '已开始：${performanceScenarios[_selected]}',
                    );
                  },
          ),
          SfTextAction(
            key: const ValueKey('performance-end-scenario'),
            label: '结束当前场景',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _recorder.endScenario();
                    _message = '场景已结束；已有统计仍保留。';
                  }),
          ),
          Text(
            '每个场景操作 20–30 秒，再选下一个；不要每换场景就清空。'
            '设置和性能报告页不计入场景，进出目标页的转场可能包含在内。'
            '下载场景需要实际开始下载；此窗口含校验，暂不能独立拆分校验阶段。',
            style: SfType.caption,
          ),
          const SfSectionTitle('导出'),
          SfPrimaryButton(
            key: const ValueKey('performance-export'),
            label: _busy ? '正在准备报告…' : '导出性能报告',
            onPressed: _busy ? null : _share,
          ),
          const SizedBox(height: SfSpace.x2),
          Text(
            '生成 JSON 后打开系统分享，可选择飞书或其他保存方式。'
            '报告包含设备型号、系统、刷新率、版本及 UI/Raster 帧统计。'
            '取消分享不清空统计。模拟器数据只用于相对比较。',
            style: SfType.caption,
          ),
          if (_message != null) ...[
            const SizedBox(height: SfSpace.x3),
            Semantics(
              liveRegion: true,
              child: Text(_message!, style: SfType.body),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Release FrameTiming arrives in batches, roughly once a second. Leave
      // the callback attached while the last scene's batch drains; this page
      // is excluded from scene groups. Do not stop and silently drop the tail.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        // Chat notifications need not rebuild MaterialApp. Read workload size
        // at export rather than reporting a stale count from app startup.
        final services = context
            .getInheritedWidgetOfExactType<AppScope>()
            ?.services;
        if (services != null) {
          _recorder.setMetadata({
            'chatMessageCount': services.chat.messages.length,
            'contentActionCount': services.library.length,
          });
        }
      }
      await _service.share();
      if (mounted) {
        setState(() => _message = '已打开系统分享，请选择接收方。统计仍保留。');
      }
    } on NoPerformanceFrames {
      if (mounted) setState(() => _message = '尚未收到有效帧数据，请返回页面操作后再导出。');
    } on Object {
      if (mounted) setState(() => _message = '报告导出失败；统计仍保留，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
