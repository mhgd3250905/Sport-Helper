import 'dart:async';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_fixture.dart';
import '../diagnostics/performance_lab.dart';
import '../diagnostics/performance_report.dart';
import 'chat/plan_glass_prewarm.dart';
import 'performance_lab_page.dart';
import 'theme.dart';
import 'theme/fixed_glass_policy.dart';

const fixedGlassConfigurations = <String, String>{
  'baseline': '计划卡基线 · 无显式预热',
  'input_static': '仅输入框改静态仿玻璃',
  'suggestions_static': '仅建议条改静态仿玻璃',
  'no_saturation': '只去饱和度 · 保留模糊',
  'half_blur': '只将模糊强度减半',
  'no_saturation_half_blur': '去饱和度 + 模糊减半',
  'all_static': '全部固定玻璃改静态仿玻璃',
  'baseline_prewarmed': '计划卡基线 · 进入前显式预热',
  'chat_baseline': '聊天对照 · 保持真玻璃',
};

const _presentRoles = {SfFixedGlassRole.input, SfFixedGlassRole.suggestions};

/// One configuration per cell. The old glass/starfield matrix stays available
/// independently and exports in the same JSON document.
class FixedGlassLabPage extends StatefulWidget {
  const FixedGlassLabPage({
    super.key,
    this.service,
    this.prewarm = PlanGlassPrewarmer.prepare,
  });
  final PerformanceReportService? service;
  final PlanGlassPrewarmCallback prewarm;

  @override
  State<FixedGlassLabPage> createState() => _FixedGlassLabPageState();
}

class _FixedGlassLabPageState extends State<FixedGlassLabPage> {
  PerformanceReportService get _service =>
      widget.service ?? PerformanceReportService.instance;
  FrameRecorder get _recorder => _service.recorder;
  PerformanceLab get _lab => PerformanceLab.instance;
  late final bool _previousFreeze;
  late final PerformanceLabOverrides _previousOverrides;
  SfFixedGlassPolicy _custom = SfFixedGlassPolicy.baseline;
  bool _customPrewarm = false;
  bool _busy = false;
  bool _prewarming = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _previousFreeze = _lab.freezeAdaptation;
    _previousOverrides = _lab.snapshotOverrides();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _recorder.enabled) _lab.setFreezeAdaptation(true);
    });
  }

  @override
  void dispose() {
    scheduleMicrotask(() {
      _lab.restoreOverrides(_previousOverrides);
      _lab.setFreezeAdaptation(_previousFreeze);
    });
    super.dispose();
  }

  Future<void> _sample(String id) async {
    if (_busy) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _message = '请先关闭系统“移除动画”，再使用相同设置采样。');
      return;
    }
    final prior = _lab.snapshotOverrides();
    PerformanceFixture? fixture;
    var pushed = false;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.initialize();
      await _service.refreshDeviceInfo();
      if (!mounted) return;
      final metadata = _recorder.snapshot()['metadata'] as Map;
      final renderer = '${metadata['renderer']}'.toLowerCase();
      if ((renderer != 'impeller' && renderer != 'skia') ||
          metadata['rendererVerified'] != true) {
        setState(() => _message = '实际 renderer 尚未确认，未开始本格。请刷新后重试。');
        return;
      }
      final source = AppServices.of(context);
      final scenario = id == 'chat_baseline'
          ? FrameScenario.longChatScroll
          : FrameScenario.planCardScroll;
      fixture = PerformanceFixture.create(
        library: source.library,
        scenario: scenario,
        starfield: source.store.starfield,
        appearance: source.store.appearance,
      );
      if (fixture.controller.suggestions.isEmpty) {
        setState(() => _message = '固定测试会话没有建议条，本配置不适用，未开始采样。');
        return;
      }
      _lab.setFixedGlassContext(
        isPlanContext: scenario == FrameScenario.planCardScroll,
        presentRoles: _presentRoles,
      );
      _lab.applyFixedGlassConfiguration(id);
      if (id == 'custom_plan') {
        _lab.setFixedGlassPolicy(_custom);
        _lab.setPrewarmEnabled(_customPrewarm);
      }
      if (_lab.prewarmEnabled) {
        setState(() => _prewarming = true);
        final warmed = await widget.prewarm(
          context: context,
          fixture: fixture,
          library: source.library,
          policy: _lab.fixedGlassPolicy,
        );
        _lab.setPrewarmStatus(
          warmed.status,
          durationMs: warmed.durationMs,
          logicalWidth: warmed.logicalWidth,
          logicalHeight: warmed.logicalHeight,
          pixelRatio: warmed.pixelRatio,
        );
        if (!mounted) return;
        setState(() => _prewarming = false);
      }
      final policy = _lab.fixedGlassPolicy;
      final variant = _lab.variantFor(source.store.starfield);
      // PerformanceConditions must publish the actual policy before the entry
      // request. Entry timings begin with the first target-page frame, while
      // the runner starts the unchanged 32-second scrolling sample later.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _recorder.start();
      final targetPage = scenario == FrameScenario.longChatScroll
          ? 'performance_chat'
          : 'performance_plan_cards';
      if (!_recorder.beginFixedGlassEntry(
        configId: id,
        targetPage: targetPage,
      )) {
        setState(() => _message = '未能建立本格进入记录，未开始采样。');
        return;
      }
      pushed = true;
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: RouteSettings(name: targetPage),
          builder: (_) => PerformanceCaseRunner(
            fixture: fixture!,
            source: source,
            recorder: _recorder,
            variant: variant,
            scenario: scenario,
            fixedGlassConfigurationId: id,
            fixedGlassPolicy: policy,
            variantLabel: fixedGlassConfigurations[id] ?? '手动计划卡配置',
          ),
        ),
      );
      if (mounted) {
        setState(
          () => _message = completed == true
              ? '本格结束。请检查有效性，逐格完成后导出同一份 JSON。'
              : '本格中断，未标记为有效。可以单独重跑此格。',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '本格未完成：$error');
    } finally {
      if (!pushed) fixture?.dispose();
      _lab.restoreOverrides(prior);
      if (mounted) {
        setState(() {
          _busy = false;
          _prewarming = false;
        });
      }
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.share();
      if (mounted) setState(() => _message = '已打开系统分享，报告包含固定玻璃实验和原八格。');
    } on NoPerformanceFrames {
      if (mounted) setState(() => _message = '还没有有效帧，请先完成一格采样。');
    } on Object {
      if (mounted) setState(() => _message = '导出失败，统计已保留，可以重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled || !PerformanceLab.buildEnabled) {
      return const SizedBox.shrink();
    }
    final cells = _recorder.snapshot()['fixedGlassCases'] as Map? ?? const {};
    final stars = AppServices.of(context).store.starfield;
    return PopScope<void>(
      canPop: !_prewarming,
      child: Scaffold(
        appBar: const SfTopBar(title: '固定玻璃拆分采样'),
        body: ListView(
          padding: const EdgeInsets.all(SfSpace.x4),
          children: [
            Text(
              '每格使用原有 72 条测试会话，自动滑动 32 秒。'
              '列表卡片固定静态、全局玻璃开启；星尘保持你的偏好（${stars ? '开' : '关'}）。'
              '玻璃档位在本页整轮锁定；保持同一主题、刷新率、方向和字体大小。',
              style: SfType.body,
            ),
            const SizedBox(height: SfSpace.x3),
            Text(
              '这里测的是聊天里的计划卡列表。它没有独立的顶栏或底栏玻璃，'
              '所以两项记为 N/A，不创建空开关的归因数据。实际固定玻璃为输入框和建议条。',
              style: SfType.caption,
            ),
            const SfSectionTitle('固定配置 · 逐格采样'),
            for (final entry in fixedGlassConfigurations.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: SfSpace.x3),
                child: SfPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(entry.value, style: SfType.title),
                      const SizedBox(height: SfSpace.x2),
                      Text(
                        _result(cells[_cellId(entry.key)]),
                        style: SfType.caption,
                      ),
                      SfPrimaryButton(
                        key: ValueKey('fixed-glass-case-${entry.key}'),
                        label: cells.containsKey(_cellId(entry.key))
                            ? '重跑此配置 · 32 秒'
                            : '采样此配置 · 32 秒',
                        onPressed: _busy ? null : () => _sample(entry.key),
                      ),
                    ],
                  ),
                ),
              ),
            const SfSectionTitle('首次进入与预热'),
            Text(
              '每格分别记录真正进入目标页的前 2 秒，以及滑动开始后的前 2 秒/稳态，互不替代。'
              '显式预热会在进入目标页之前实际离屏绘制并栅格化一次组件，报告单列成功、失败或不可用及耗时。'
              '它不等于证明发生过着色器编译。',
              style: SfType.caption,
            ),
            Text(
              '比较首次进入：重启 App 后，先只跑“无显式预热基线”并导出；'
              '再重启 App，先只跑“进入前显式预热”并另行导出。'
              '一轮九格中后跑的页面早已进入过，不能据此声称冷/暖首入改善。',
              key: const ValueKey('fixed-glass-cold-warm-instructions'),
              style: SfType.caption,
            ),
            const SfSectionTitle('临时手动开关 · 只作用于计划卡场景'),
            SwitchListTile(
              key: const ValueKey('fixed-glass-top-bar'),
              title: const Text('顶栏真玻璃 · N/A'),
              subtitle: const Text('此测试页没有该玻璃元素'),
              value: false,
              onChanged: null,
            ),
            SwitchListTile(
              key: const ValueKey('fixed-glass-bottom-bar'),
              title: const Text('底栏真玻璃 · N/A'),
              subtitle: const Text('输入框单独记录；此页没有另一块底栏玻璃'),
              value: false,
              onChanged: null,
            ),
            SwitchListTile(
              key: const ValueKey('fixed-glass-input'),
              title: const Text('输入框真玻璃'),
              value: _custom.input,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _custom = _custom.copyWith(input: value),
                    ),
            ),
            SwitchListTile(
              key: const ValueKey('fixed-glass-suggestions'),
              title: const Text('建议条真玻璃'),
              value: _custom.suggestions,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () => _custom = _custom.copyWith(suggestions: value),
                    ),
            ),
            SwitchListTile(
              key: const ValueKey('fixed-glass-no-saturation'),
              title: const Text('只去饱和度过滤'),
              subtitle: const Text('保留模糊，不改变其他材料参数'),
              value: !_custom.saturationEnabled,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () =>
                          _custom = _custom.copyWith(saturationEnabled: !value),
                    ),
            ),
            SwitchListTile(
              key: const ValueKey('fixed-glass-half-blur'),
              title: const Text('模糊强度减半'),
              value: _custom.blurScale == .5,
              onChanged: _busy
                  ? null
                  : (value) => setState(
                      () =>
                          _custom = _custom.copyWith(blurScale: value ? .5 : 1),
                    ),
            ),
            CheckboxListTile(
              key: const ValueKey('fixed-glass-custom-prewarm'),
              title: const Text('本手动配置进入前显式预热'),
              value: _customPrewarm,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _customPrewarm = value ?? false),
            ),
            SfPrimaryButton(
              key: const ValueKey('fixed-glass-case-custom_plan'),
              label: '采样手动计划卡配置 · 32 秒',
              onPressed: _busy ? null : () => _sample('custom_plan'),
            ),
            Text(
              '手动配置单独存一格，重跑会覆盖此格。聊天对照始终使用原真玻璃，'
              '不采用计划卡手动设置。预热是本次实验的可选项，未默认用于生产。',
              style: SfType.caption,
            ),
            const SfSectionTitle('本轮报告'),
            SfPrimaryButton(
              key: const ValueKey('fixed-glass-export'),
              label: '导出固定玻璃实验 JSON',
              onPressed: _busy ? null : _share,
            ),
            TextButton(
              key: const ValueKey('fixed-glass-reset'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _recorder.endScenario();
                      _recorder.reset();
                      _recorder.start();
                      _message = '已清空本轮统计（含原八格）。清空不会清除 GPU 缓存或重新制造冷启动。';
                    }),
              child: const Text('开始新一轮（清空全部性能统计）'),
            ),
            if (_message case final message?)
              Text(
                message,
                key: const ValueKey('fixed-glass-message'),
                style: SfType.caption,
              ),
          ],
        ),
      ),
    );
  }

  String _cellId(String id) =>
      '${id}__${id == 'chat_baseline' ? 'longChatScroll' : 'planCardScroll'}';

  String _result(Object? value) {
    if (value is! Map) return '未采样';
    final ready = value['comparisonReady'] == true;
    final issues = value['comparisonIssues'];
    final steady = value['steadyState'];
    final raster = steady is Map ? steady['raster'] : null;
    final status = ready
        ? '可用于同场景对照'
        : '暂不可对照：${issues is List ? issues.join('、') : '条件未满足'}';
    if (raster is! Map) return status;
    String ms(String key) =>
        raster[key] is num ? (raster[key] as num).toStringAsFixed(2) : '—';
    final ratio = raster['overBudgetRatio'];
    final percent = ratio is num ? (ratio * 100).toStringAsFixed(2) : '—';
    return '$status\nRaster 均值 ${ms('averageMs')} ms · P99 ${ms('p99Ms')} ms · 超预算 $percent%';
  }
}
