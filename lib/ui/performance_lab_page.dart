import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/services.dart';
import '../diagnostics/frame_recorder.dart';
import '../diagnostics/performance_fixture.dart';
import '../diagnostics/performance_report.dart';
import 'chat/chat_home_page.dart';
import 'theme.dart';

abstract final class PerformanceScrollProtocol {
  static const sampleDuration = Duration(seconds: 32);
  static const legDuration = Duration(seconds: 4);
  static const tailDeliveryDelay = Duration(milliseconds: 1200);
  static const distance = 3200.0;
  static const curve = Curves.linear;
}

const performanceScenarios = <FrameScenario, String>{
  FrameScenario.planCardScroll: '计划卡滚动',
  FrameScenario.longChatScroll: '长聊天滚动',
  FrameScenario.pageEntry: '进入动作库页面',
  FrameScenario.bottomBarSwitch: '底栏入口 → 抽屉 → 动作库 → 返回',
  FrameScenario.trainingPlayback: '真实训练播放页',
};

/// Ten real-workload cells. Appearance and the user's starfield preference
/// remain controlled by the normal App settings.
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

  Future<void> _sample(String theme, FrameScenario scenario) async {
    if (Theme.of(context).brightness.name != theme) {
      setState(() => _message = '请先在设置中切到对应主题，再采这一格。');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.initialize();
      await _service.refreshDeviceInfo();
      if (!mounted) return;
      if (!_service.rendererVerified) {
        setState(() => _message = '实际 renderer 尚未验证，未开始采样。');
        return;
      }
      _recorder.start();
      if (scenario != FrameScenario.longChatScroll &&
          scenario != FrameScenario.planCardScroll) {
        if (!_recorder.armCase(theme: theme, scenario: scenario)) {
          setState(() => _message = '未能准备采样，请先结束当前格。');
          return;
        }
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      final original = AppServices.of(context);
      final fixture = PerformanceFixture.create(
        library: original.library,
        scenario: scenario,
        starfield: original.store.starfield,
        appearance: original.store.appearance,
      );
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
            theme: theme,
            scenario: scenario,
          ),
        ),
      );
      if (mounted) {
        setState(
          () => _message = completed == true
              ? '已保留本格原始帧；以导出后的有效性和精确分位为准。'
              : '采样未完成，原始结果已保留。',
        );
      }
    } on Object {
      if (mounted) setState(() => _message = '未能完成采样，请检查场景素材和设备状态。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_recorder.enabled) return const SizedBox.shrink();
    final recorded = (_recorder.status()['caseIds'] as List).cast<String>();
    return Scaffold(
      appBar: const SfTopBar(title: '实色界面性能采样'),
      body: ListView(
        padding: const EdgeInsets.all(SfSpace.x4),
        children: [
          Text(
            '材质固定 solid；浅深主题各五个真实场景。保留原星尘设置、字体和缓存。'
            '120Hz Raster P99 必须低于8.33ms；无真机样本不显示通过。',
            style: SfType.body,
          ),
          const SizedBox(height: SfSpace.x3),
          Text(
            '两个滚动格使用正式聊天和计划卡组件、72条隔离测试消息、32秒自动往返，'
            '不会写入你的对话。进页格：返回后点动作库，进入后记录3秒。'
            '底栏格：返回后用既有底栏入口打开抽屉、进入动作库并返回，持续20秒；这不是Tab导航。'
            '播放格：返回后按正常安全门禁进入真实训练页，记录22秒；不要在统计时完成或保存测试训练。',
            style: SfType.caption,
          ),
          for (final theme in const ['light', 'dark']) ...[
            const SizedBox(height: SfSpace.x4),
            SfSectionTitle(theme == 'light' ? '浅色' : '深色'),
            for (final item in performanceScenarios.entries) ...[
              Text(item.value, style: SfType.callout),
              Text(
                recorded.contains('${theme}__${item.key.name}')
                    ? '已有一格；重新采样只替换这一格。'
                    : '尚未采集。',
                style: SfType.caption,
              ),
              SfPrimaryButton(
                key: ValueKey('performance-case-$theme-${item.key.name}'),
                label: '采集${item.value}',
                onPressed: _busy ? null : () => _sample(theme, item.key),
              ),
              const SizedBox(height: SfSpace.x3),
            ],
          ],
          SfTextAction(label: '取消待开始的场景', onPressed: _recorder.cancelArmedCase),
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

/// Uses the real ChatHomePage with an isolated store/controller. The runner's
/// timer updates only its tiny HUD once a second; scrolling never rebuilds it.
class PerformanceCaseRunner extends StatefulWidget {
  const PerformanceCaseRunner({
    super.key,
    required this.fixture,
    required this.source,
    required this.recorder,
    required this.theme,
    required this.scenario,
    this.sampleDuration = PerformanceScrollProtocol.sampleDuration,
    this.tailDelay = PerformanceScrollProtocol.tailDeliveryDelay,
  });

  final PerformanceFixture fixture;
  final AppServices source;
  final FrameRecorder recorder;
  final String theme;
  final FrameScenario scenario;

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
    _caseStarted = widget.recorder.beginCase(
      theme: widget.theme,
      scenario: widget.scenario,
      fixtureId: widget.fixture.id,
      messageCount: widget.fixture.controller.messages.length,
    );
    if (!_caseStarted) {
      _abort('记录器未能开始采样，请返回重试。');
      return;
    }
    _startedCaseId = '${widget.theme}__${widget.scenario.name}';
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
          IgnorePointer(child: _conversation()),
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
                              '测试会话 · ${performanceScenarios[widget.scenario]} · 72 条',
                              style: SfType.caption,
                            ),
                            Text(
                              '${widget.theme} · ${performanceScenarios[widget.scenario]}',
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

  Widget _conversation() => ChatHomePage(
    controller: widget.fixture.controller,
    scrollController: _scroll,
  );
}
