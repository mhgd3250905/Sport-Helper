import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/training_transition_timings.dart';
import '../diagnostics/performance_report.dart';
import 'theme.dart';

enum _ExportAction { copy, share }

/// A small internal-only viewer; opening it never starts or clears a sample.
class TrainingTransitionTimingsPage extends StatefulWidget {
  const TrainingTransitionTimingsPage({super.key, this.recorder});
  final TrainingTransitionTimings? recorder;

  @override
  State<TrainingTransitionTimingsPage> createState() =>
      _TrainingTransitionTimingsPageState();
}

class _TrainingTransitionTimingsPageState
    extends State<TrainingTransitionTimingsPage> {
  late final TrainingTransitionTimings _recorder;
  _ExportAction? _exporting;
  String? _message;
  Future<void>? _refreshingEnvironment;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? TrainingTransitionTimings.instance;
    if (_recorder.enabled) {
      unawaited(_recorder.initialize());
      _refreshingEnvironment = _refreshEnvironment();
    }
  }

  Future<void> _refreshEnvironment() async {
    final service = PerformanceReportService.instance;
    // Native own-engine evidence may arrive after the first cold transition.
    // Querying it on this diagnostics page never delays app/route startup.
    await service.refreshDeviceInfo();
    _recorder.setEnvironment(
      renderer: service.renderer,
      rendererBackend: service.rendererBackend,
      rendererVerified: service.rendererVerified,
    );
    if (mounted) setState(() {});
  }

  Future<void> _export(_ExportAction action) async {
    if (_exporting != null) return;
    setState(() {
      _exporting = action;
      _message = null;
    });
    try {
      await _refreshingEnvironment;
      if (!mounted) return;
      final json = await _recorder.exportJson();
      if (!mounted) return;
      if (action == _ExportAction.copy) {
        await Clipboard.setData(ClipboardData(text: json));
        if (mounted) setState(() => _message = '已复制最近10次训练过渡JSON');
      } else {
        await const AndroidPerformanceReportPlatform().share(
          filename: performanceReportFilename(DateTime.now()),
          contents: json,
        );
        if (mounted) {
          setState(() => _message = '系统分享已打开，可选择飞书；取消分享不会清空统计。');
        }
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = action == _ExportAction.copy
              ? '复制未完成，请重试；已有采样保留。'
              : '分享未打开，请重试；已有采样保留。',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled) return const SizedBox.shrink();
    return Scaffold(
      appBar: const SfTopBar(title: '训练进出帧耗时'),
      body: ListenableBuilder(
        listenable: _recorder,
        builder: (context, _) {
          final results = _recorder.results;
          final canExport =
              _exporting == null &&
              (results.isNotEmpty || _recorder.hasPendingResults);
          return ListView(
            key: const ValueKey('transition-timings-results'),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '自动保留最近10次进入/退出。对话计划卡、我的计划、图文详情，'
                '各测浅色和深色，共6组。每组进出3次，包含提前结束、完成和系统返回。'
                '每组测完立即分享，避免最近10次滚动覆盖之前的结果。'
                '引擎帧可能延迟回传约1秒，复制和分享会等待已结束的采样补齐。',
                style: SfType.body,
              ),
              const SizedBox(height: 12),
              SfPrimaryButton(
                key: const ValueKey('transition-timings-copy'),
                label: _exporting == _ExportAction.copy
                    ? '正在准备JSON…'
                    : '复制最近10次JSON',
                onPressed: canExport ? () => _export(_ExportAction.copy) : null,
              ),
              const SizedBox(height: 8),
              SfSecondaryButton(
                key: const ValueKey('transition-timings-share'),
                label: _exporting == _ExportAction.share
                    ? '正在准备分享…'
                    : '分享最近10次JSON',
                onPressed: canExport
                    ? () => _export(_ExportAction.share)
                    : null,
              ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(_message!, style: SfType.callout),
                ),
              ],
              if (_recorder.persistenceFailed) ...[
                const SizedBox(height: 8),
                Text('本地JSON保存未完成，当前内存结果仍可复制和分享。', style: SfType.caption),
              ],
              const SizedBox(height: 16),
              if (_recorder.pendingResultCount > 0)
                Text(
                  '正在等待${_recorder.pendingResultCount}次过渡的引擎帧回传…',
                  style: SfType.caption,
                ),
              if (results.isEmpty)
                Text('尚未收到已结束的真实过渡帧；不会用0ms代替未测结果。', style: SfType.body),
              for (final result in results) _TimingResultCard(result: result),
              const SizedBox(height: 8),
              Text(
                '统计为Flutter引擎的build/raster线程耗时，P90使用最近秩法。'
                '超16ms帧指build或raster任一超过16ms，不是两者相加。'
                '首次会单独标记；未测、减少动效和中断会明确显示，不自动判断真机验收是否通过。'
                '渲染后端以实际引擎证据为准；未验证时不会推断Skia或Impeller。',
                style: SfType.caption,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TimingResultCard extends StatelessWidget {
  const _TimingResultCard({required this.result});
  final Map<String, Object?> result;

  String ms(String key) {
    final value = result[key];
    return value is num && value.isFinite
        ? '${value.toStringAsFixed(2)}ms'
        : '未测';
  }

  @override
  Widget build(BuildContext context) {
    final run = result['runInProcess'];
    final first = result['firstAfterProcessStart'] == true;
    final rendererVerified = result['rendererVerified'] == true;
    final outcome = result['outcome'];
    final label = result['kind'] == 'entry' ? '进入' : '退出';
    return Card(
      key: ValueKey('transition-result-${result['id']}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label · 本次启动第$run次${first ? '（首次）' : ''}',
              style: SfType.headline,
            ),
            const SizedBox(height: 6),
            Text(switch (result['sourceEntry']) {
              'chat' => '入口：对话计划卡',
              'saved_plan' => '入口：我的计划',
              'guide' => '入口：图文详情',
              _ => '入口：未记录',
            }, style: SfType.caption),
            Text(
              '${result['buildMode']} · ${result['theme']} · ${result['frameCount']}帧',
              style: SfType.caption,
            ),
            const SizedBox(height: 8),
            Text(
              'Build：P90 ${ms('buildP90Ms')} / 最大 ${ms('buildMaxMs')}',
              style: SfType.callout,
            ),
            Text(
              'Raster：P90 ${ms('rasterP90Ms')} / 最大 ${ms('rasterMaxMs')}',
              style: SfType.callout,
            ),
            Text(
              '超过16ms：${result['over16msFrames']}帧'
              '（build ${result['buildOver16ms']} / raster ${result['rasterOver16ms']}）',
              style: SfType.callout,
            ),
            const SizedBox(height: 8),
            Text(
              rendererVerified
                  ? '渲染后端：${result['renderer']} / ${result['rendererBackend']}（已验证）'
                  : '渲染后端：未验证',
              style: SfType.caption,
            ),
            Text(
              result['transitionStyle'] != 'horizontal_slide'
                  ? '历史记录未标记为本次滑动转场，请分开比较。'
                  : result['reducedMotion'] == true
                  ? '移除动画已开启，本次为直接切换。'
                  : outcome != 'completed'
                  ? '过渡中断或保存失败，保留已收到的真实帧。'
                  : result['truncated'] == true
                  ? '采样达到容量上限，数据已截断。'
                  : result['hasMeasuredFrames'] != true
                  ? '尚无真实帧，耗时保持未测。'
                  : '滑动转场记录，保留实测值供对比。',
              style: SfType.caption,
            ),
            Text('${result['startedAtUtc']}', style: SfType.caption),
          ],
        ),
      ),
    );
  }
}
