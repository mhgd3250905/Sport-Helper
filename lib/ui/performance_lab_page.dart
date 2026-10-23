import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_fixture.dart';
import '../diagnostics/performance_lab.dart';
import '../diagnostics/performance_report.dart';
import 'chat/chat_home_page.dart';
import 'theme.dart';
import 'theme/fixed_glass_policy.dart';

/// Fixed workload shared by all eight cells: 800 logical pixels/second,
/// reversing every four seconds over the same 3,200-pixel range.
abstract final class PerformanceScrollProtocol {
  static const sampleDuration = Duration(seconds: 32);
  static const legDuration = Duration(seconds: 4);
  static const tailDeliveryDelay = Duration(milliseconds: 1200);
  static const distance = 3200.0;
  static const curve = Curves.linear;
}

const _variants = <String, String>{
  'glass_on_stars_on': '玻璃开 · 星尘开',
  'glass_on_stars_off': '玻璃开 · 星尘关',
  'glass_off_stars_on': '玻璃关 · 星尘开',
  'glass_off_stars_off': '玻璃关 · 星尘关',
};
const _scenarios = <FrameScenario, String>{
  FrameScenario.longChatScroll: '聊天滑动',
  FrameScenario.planCardScroll: '计划卡滑动',
};

/// Internal-only entry point; the production settings omit this route.
class PerformanceLabPage extends StatefulWidget {
  const PerformanceLabPage({super.key, this.service});
  final PerformanceReportService? service;

  @override
  State<PerformanceLabPage> createState() => _PerformanceLabPageState();
}

class _PerformanceLabPageState extends State<PerformanceLabPage> {
  PerformanceReportService get _service =>
      widget.service ?? PerformanceReportService.instance;
  FrameRecorder get _recorder => _service.recorder;
  bool _busy = false;
  String? _message;
  late final bool _previousFreeze;

  @override
  void initState() {
    super.initState();
    _previousFreeze = PerformanceLab.instance.freezeAdaptation;
    // The adaptive scope is an ancestor of this route. Notify it after this
    // build, rather than trying to mark an ancestor dirty during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _recorder.enabled) {
        PerformanceLab.instance.setFreezeAdaptation(true);
      }
    });
  }

  @override
  void dispose() {
    // Navigator finalization locks the widget tree during route disposal.
    scheduleMicrotask(() {
      PerformanceLab.instance.setFreezeAdaptation(_previousFreeze);
    });
    super.dispose();
  }

  Future<void> _sample(String variant, FrameScenario scenario) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _message = '系统“移除动画”已开启，不能用于星尘开关对照。请关闭后重新采样。');
      return;
    }
    final previousOverrides = PerformanceLab.instance.snapshotOverrides();
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
        setState(() => _message = '尚未确认实际 renderer，未开始采样。请刷新设备信息后重试。');
        return;
      }
      final original = AppServices.of(context);
      final fixture = PerformanceFixture.create(
        library: original.library,
        scenario: scenario,
        starfield: original.store.starfield,
        appearance: original.store.appearance,
      );
      PerformanceLab.instance.setVariant(variant);
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          settings: RouteSettings(
            name: scenario == FrameScenario.longChatScroll
                ? 'performance_chat'
                : 'performance_plan_cards',
          ),
          builder: (_) => PerformanceCaseRunner(
            fixture: fixture,
            source: original,
            recorder: _recorder,
            variant: variant,
            scenario: scenario,
          ),
        ),
      );
      if (mounted) {
        setState(
          () => _message = completed == true
              ? '本格采样结束。有效性以每格状态为准；完成八格后导出同一份 JSON。'
              : '本格未完成，已保留为无效采样。其他格保持原样。',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _message = '未完成采样：$error');
    } finally {
      PerformanceLab.instance.restoreOverrides(previousOverrides);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _service.initialize();
    await _service.refreshDeviceInfo();
    if (!mounted) return;
    final metadata = _recorder.snapshot()['metadata'] as Map;
    setState(() {
      _busy = false;
      _message = '实际 renderer：${metadata['renderer'] ?? 'unknown'}。';
    });
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await _service.share();
      if (mounted) setState(() => _message = '系统分享已打开，请保存或发送报告。');
    } on NoPerformanceFrames {
      if (mounted) setState(() => _message = '还没有收到帧，请先完成至少一格采样。');
    } on Object {
      if (mounted) setState(() => _message = '导出失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled) return const SizedBox.shrink();
    final cases = _recorder.snapshot()['cases'] as Map? ?? const {};
    return Scaffold(
      appBar: const SfTopBar(title: 'Raster 对照采样'),
      body: ListView(
        padding: const EdgeInsets.all(SfSpace.x4),
        children: [
          Text(
            '固定 72 条测试消息，使用正式聊天和计划卡组件，不读取或改写你的对话。'
            '每格自动滑动 32 秒，前 2 秒与稳态分开统计，再等待尾帧交付。'
            '请保持同一主题、屏幕方向、字体大小和设备状态。采样时不用手滑。',
            style: SfType.body,
          ),
          const SizedBox(height: SfSpace.x3),
          ListenableBuilder(
            listenable: PerformanceLab.instance,
            builder: (context, _) => Text(
              '列表卡片：${PerformanceLab.instance.scrollingGlassEnabled ? '真玻璃对照' : '静态仿玻璃（默认）'}。'
              '下方玻璃开/关指全局开关；卡片模式另记入每格条件。'
              '更换卡片模式后请开始新一轮，避免混合两种模式。',
              key: const ValueKey('performance-scroll-card-mode'),
              style: SfType.caption,
            ),
          ),
          Text(
            '点击任意一格即生成独立测试会话；重新采样只替换本格。'
            '矩阵采样固定进入时的玻璃档位，离开此页后恢复自适应。'
            '每格结束后恢复进入前的玻璃和星尘设置。中途退出、后台或尺寸变化会使本格无效。',
            style: SfType.caption,
          ),
          for (final variant in _variants.entries) ...[
            SfSectionTitle(variant.value),
            for (final scenario in _scenarios.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: SfSpace.x2),
                child: SfPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(scenario.value, style: SfType.title),
                      const SizedBox(height: SfSpace.x2),
                      Text(
                        _result(cases['${variant.key}__${scenario.key.name}']),
                        style: SfType.caption,
                      ),
                      const SizedBox(height: SfSpace.x2),
                      SfPrimaryButton(
                        key: ValueKey(
                          'performance-case-${variant.key}-${scenario.key.name}',
                        ),
                        label:
                            cases.containsKey(
                              '${variant.key}__${scenario.key.name}',
                            )
                            ? '重新生成测试会话并采样'
                            : '生成测试会话并采样',
                        onPressed: _busy
                            ? null
                            : () => _sample(variant.key, scenario.key),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SfSectionTitle('本轮报告'),
          SfPrimaryButton(
            key: const ValueKey('performance-lab-export'),
            label: '导出八格性能报告 JSON',
            onPressed: _busy ? null : _share,
          ),
          TextButton(
            onPressed: _busy ? null : _refresh,
            child: const Text('刷新设备信息 / renderer'),
          ),
          TextButton(
            key: const ValueKey('performance-lab-reset'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    _recorder.endScenario();
                    _recorder.reset();
                    _recorder.start();
                    _message = '已清空本轮全部统计和八格结果。';
                  }),
            child: const Text('开始新一轮（清空全部八格和本轮统计）'),
          ),
          if (_message case final message?)
            Text(message, style: SfType.caption),
        ],
      ),
    );
  }

  String _result(Object? value) {
    if (value is! Map) return '未采样';
    final ready = value['comparisonReady'] == true;
    final steady = value['steadyState'];
    final raster = steady is Map ? steady['raster'] : null;
    final issues = value['comparisonIssues'];
    final reason = issues is List ? issues.join('、') : '条件未满足';
    final status = ready ? '可用于同场景对照' : '暂不可对照：$reason';
    if (raster is! Map) return status;
    String ms(String key) =>
        raster[key] is num ? (raster[key] as num).toStringAsFixed(2) : '—';
    final ratio = raster['overBudgetRatio'];
    final percent = ratio is num ? (ratio * 100).toStringAsFixed(2) : '—';
    final groups = value['conditions'];
    final actual = groups is List && groups.length == 1 && groups.single is Map
        ? (groups.single as Map)['condition']
        : null;
    final cards = actual is Map ? actual['scrollCardGlassEnabled'] : null;
    final cardMode = switch (cards) {
      true => '真玻璃',
      false => '静态仿玻璃',
      _ => '未记录',
    };
    return '$status · 卡片：$cardMode\nRaster 均值 ${ms('averageMs')} ms · '
        'P90 ${ms('p90Ms')} ms · P99 ${ms('p99Ms')} ms · 超预算 $percent%';
  }
}

/// Uses the real ChatHomePage with an isolated store/controller. The runner's
/// timer updates only its tiny HUD once a second; scrolling never rebuilds it.
class PerformanceCaseRunner extends StatefulWidget {
  const PerformanceCaseRunner({
    super.key,
    required this.fixture,
    required this.source,
    required this.recorder,
    required this.variant,
    required this.scenario,
    this.sampleDuration = PerformanceScrollProtocol.sampleDuration,
    this.tailDelay = PerformanceScrollProtocol.tailDeliveryDelay,
    this.fixedGlassConfigurationId,
    this.fixedGlassPolicy = SfFixedGlassPolicy.baseline,
    this.variantLabel,
  });

  final PerformanceFixture fixture;
  final AppServices source;
  final FrameRecorder recorder;
  final String variant;
  final FrameScenario scenario;
  final String? fixedGlassConfigurationId;
  final SfFixedGlassPolicy fixedGlassPolicy;
  final String? variantLabel;

  /// Short durations are useful in widget tests; they cannot produce a valid
  /// 30-second steady-state comparison in the recorder.
  final Duration sampleDuration;
  final Duration tailDelay;

  @override
  State<PerformanceCaseRunner> createState() => _PerformanceCaseRunnerState();
}

class _PerformanceCaseRunnerState extends State<PerformanceCaseRunner>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _status = ValueNotifier<String>('正在准备固定测试会话…');
  Timer? _timer;
  late final AppServices _services;
  Size? _initialSize;
  bool _caseStarted = false;
  bool _aborted = false;
  String? _startedCaseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _services = AppServices(
      library: widget.source.library,
      catalog: widget.source.catalog,
      store: widget.fixture.store,
      voiceLibrary: widget.source.voiceLibrary,
      voiceOutput: widget.source.voiceOutput,
      chatReplyDelay: Duration.zero,
      // No media repository: the fixture cannot prefetch/download a video.
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _initialSize ??= size;
    if (_startedCaseId != null && MediaQuery.disableAnimationsOf(context)) {
      _abort('系统“移除动画”已开启，本格无效，请关闭后重新采样。');
    } else if (_startedCaseId != null &&
        (size != _initialSize || ModalRoute.of(context)?.isCurrent == false)) {
      _abort('页面或屏幕尺寸发生变化，本格无效，请返回重新采样。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _abort('采样进入后台，本格无效，请返回重新采样。');
    }
  }

  @override
  void didChangeMetrics() {
    if (_startedCaseId != null) _abort('屏幕尺寸发生变化，本格无效，请返回重新采样。');
  }

  Future<void> _run() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && !animation.isCompleted) {
      final ready = Completer<void>();
      void changed(AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (!ready.isCompleted) ready.complete();
        }
      }

      animation.addStatusListener(changed);
      await ready.future;
      animation.removeStatusListener(changed);
    }
    if (!mounted || _aborted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _aborted) return;
    if (!_scroll.hasClients ||
        _scroll.position.maxScrollExtent < PerformanceScrollProtocol.distance) {
      _abort('测试列表长度不足，未开始采样；请保持标准字体和竖屏后重试。');
      return;
    }
    _scroll.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _aborted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _abort('系统“移除动画”已开启，未开始星尘对照采样。请关闭后重试。');
      return;
    }
    _initialSize = MediaQuery.sizeOf(context);
    widget.recorder.start();
    final fixedConfiguration = widget.fixedGlassConfigurationId;
    _caseStarted = fixedConfiguration == null
        ? widget.recorder.beginCase(
            variant: widget.variant,
            scenario: widget.scenario,
            fixtureId: widget.fixture.id,
            messageCount: widget.fixture.controller.messages.length,
          )
        : widget.recorder.beginFixedGlassCase(
            configId: fixedConfiguration,
            scenario: widget.scenario,
            fixtureId: widget.fixture.id,
            messageCount: widget.fixture.controller.messages.length,
          );
    if (!_caseStarted) {
      _abort('记录器未能开始采样，请返回重试。');
      return;
    }
    _startedCaseId =
        '${fixedConfiguration ?? widget.variant}__${widget.scenario.name}';
    final stopwatch = Stopwatch()..start();
    _status.value = '正在采样 · 0 / ${widget.sampleDuration.inSeconds} 秒';
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _aborted) return;
      _status.value =
          '正在采样 · ${stopwatch.elapsed.inSeconds} / '
          '${widget.sampleDuration.inSeconds} 秒';
    });
    var remaining = widget.sampleDuration.inMicroseconds;
    var forward = true;
    while (remaining > 0 && mounted && !_aborted) {
      final leg = math.min(
        remaining,
        PerformanceScrollProtocol.legDuration.inMicroseconds,
      );
      final fraction =
          leg / PerformanceScrollProtocol.legDuration.inMicroseconds;
      final target = forward
          ? PerformanceScrollProtocol.distance * fraction
          : PerformanceScrollProtocol.distance * (1 - fraction);
      await _scroll.animateTo(
        target,
        duration: Duration(microseconds: leg),
        curve: PerformanceScrollProtocol.curve,
      );
      remaining -= leg;
      forward = !forward;
    }
    _timer?.cancel();
    if (!mounted || _aborted) return;
    // Close at the end of movement. Delayed batches still carry their original
    // frame labels, while the idle tail never dilutes the measured case.
    widget.recorder.endCase();
    _caseStarted = false;
    _status.value = '滑动结束，正在接收尾帧…';
    await Future<void>.delayed(widget.tailDelay);
    if (mounted && !_aborted) {
      _startedCaseId = null;
      Navigator.of(context).pop(true);
    }
  }

  void _abort(String message) {
    if (_aborted) return;
    _aborted = true;
    _timer?.cancel();
    if (_caseStarted) {
      widget.recorder.endCase(completed: false);
    } else if (_startedCaseId case final id?) {
      widget.recorder.invalidateCase(id);
    }
    _caseStarted = false;
    _startedCaseId = null;
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
    _status.value = message;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (_caseStarted) {
      widget.recorder.endCase(completed: false);
    } else if (_startedCaseId case final id?) {
      widget.recorder.invalidateCase(id);
    }
    _startedCaseId = null;
    _aborted = true;
    _scroll.dispose();
    _status.dispose();
    // _services shares only read-only assets/voice references. Disposing it
    // would dispose the app's voice output, so only fixture-owned state ends.
    widget.fixture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop && _startedCaseId != null) _abort('采样中途退出，本格无效。');
    },
    child: AppScope(
      services: _services,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: SfFixedGlassScope(
              isPlanContext: widget.scenario == FrameScenario.planCardScroll,
              policy: widget.fixedGlassPolicy,
              child: ChatHomePage(
                controller: widget.fixture.controller,
                scrollController: _scroll,
              ),
            ),
          ),
          Positioned(
            left: SfSpace.x3,
            right: SfSpace.x3,
            top: MediaQuery.paddingOf(context).top + SfSpace.x2,
            child: RepaintBoundary(
              child: Material(
                color: SfColors.surface,
                borderRadius: BorderRadius.circular(SfRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.all(SfSpace.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '测试会话 · ${_scenarios[widget.scenario]} · 72 条',
                              style: SfType.caption,
                            ),
                            Text(
                              widget.variantLabel ?? _variants[widget.variant]!,
                              style: SfType.caption,
                            ),
                            ValueListenableBuilder<String>(
                              valueListenable: _status,
                              builder: (_, status, _) =>
                                  Text(status, style: SfType.caption),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('performance-runner-exit'),
                        onPressed: () {
                          _abort('采样中途退出，本格无效。');
                          Navigator.of(context).pop(false);
                        },
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
