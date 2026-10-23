import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// App-owned adaptation uses the display's exact (double) frame budget.
/// The third-party scope accepts an integer budget, so internal comparisons
/// use this scope without changing that package or either training SDK.
class SfAdaptiveGlassController extends ChangeNotifier {
  SfAdaptiveGlassController({
    GlassQuality? initialQuality,
    double refreshRateHz = 60,
    this.isWeb = kIsWeb,
    bool? shaderFiltersSupported,
    DateTime Function()? clock,
  }) : _shadersSupported =
           shaderFiltersSupported ?? ImageFilter.isShaderFilterSupported,
       _clock = clock ?? DateTime.now {
    _refreshRateHz = _validHz(refreshRateHz) ? refreshRateHz : 60;
    _quality = _clamp(initialQuality ?? GlassQuality.premium);
    _phase =
        _terminalPhase ?? (initialQuality == null ? 'skipping' : 'runtime');
  }

  static const skipFrames = 90;
  static const warmupFrames = 180;
  static const runtimeWindowFrames = 120;
  static const _qualityOrder = [
    GlassQuality.minimal,
    GlassQuality.standard,
    GlassQuality.premium,
  ];

  final bool isWeb;
  final bool _shadersSupported;
  final DateTime Function() _clock;
  // One fixed buffer is reused for warmup and runtime; nothing grows with time.
  final _samples = Int64List(warmupFrames);
  late GlassQuality _quality;
  late String _phase;
  late double _refreshRateHz;
  String? _phaseBeforeFreeze;
  int _skippedFrames = 0;
  int _sampleCount = 0;
  int _overBudgetWindows = 0;
  int _underBudgetWindows = 0;
  DateTime? _lastQualityChange;

  GlassQuality get effectiveQuality => _quality;
  String get phase => _phase;
  double get refreshRateHz => _refreshRateHz;
  double get targetFrameMs => 1000 / _refreshRateHz;
  bool get isFrozen => _phaseBeforeFreeze != null;

  @visibleForTesting
  int get retainedSampleCount => _sampleCount;

  @visibleForTesting
  int get sampleCapacity => _samples.length;

  String? get _terminalPhase => isWeb
      ? 'web_standard'
      : !_shadersSupported
      ? 'unsupported'
      : null;

  static bool _validHz(double hz) => hz.isFinite && hz >= 10 && hz <= 1000;

  GlassQuality _clamp(GlassQuality quality) {
    if (isWeb) return GlassQuality.standard;
    if (!_shadersSupported) return GlassQuality.minimal;
    return quality;
  }

  GlassQuality cap(GlassQuality requested) =>
      _qualityOrder.indexOf(requested) <= _qualityOrder.indexOf(_quality)
      ? requested
      : _quality;

  void setRefreshRateHz(double hz) {
    if (!_validHz(hz) || _refreshRateHz == hz) return;
    _refreshRateHz = hz;
    _clearWindows();
    notifyListeners();
  }

  /// Locks the same ceiling for the entire eight-cell comparison matrix.
  /// Low-load glass-off cells therefore cannot upgrade later glass-on cells.
  void setFrozen(bool frozen) {
    if (frozen == isFrozen) return;
    _clearWindows();
    if (frozen) {
      _phaseBeforeFreeze = _phase;
      _phase = 'comparison_locked';
    } else {
      _phase = _phaseBeforeFreeze!;
      _phaseBeforeFreeze = null;
    }
    notifyListeners();
  }

  /// Resuming must not join old thermal/timing windows to a new session.
  void resetOnResume() {
    _clearWindows();
    _skippedFrames = 0;
    _lastQualityChange = null;
    final nextPhase = _terminalPhase ?? 'skipping';
    if (isFrozen) {
      _phaseBeforeFreeze = nextPhase;
      return;
    }
    if (_phase == nextPhase) return;
    _phase = nextPhase;
    notifyListeners();
  }

  void _clearWindows() {
    _sampleCount = 0;
    _overBudgetWindows = 0;
    _underBudgetWindows = 0;
  }

  void addTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      addSample(
        buildUs: timing.buildDuration.inMicroseconds,
        rasterUs: timing.rasterDuration.inMicroseconds,
      );
    }
  }

  /// Fixed-memory accumulation. Only a completed window can change the tier;
  /// no notification or file operation occurs for ordinary frames.
  @visibleForTesting
  void addSample({required int buildUs, required int rasterUs}) {
    if (isFrozen || _terminalPhase != null || buildUs < 0 || rasterUs < 0) {
      return;
    }
    if (_phase == 'skipping') {
      _skippedFrames++;
      if (_skippedFrames == skipFrames) {
        _phase = 'warmup';
        notifyListeners();
      }
      return;
    }
    _samples[_sampleCount++] = rasterUs;
    if (_phase == 'warmup') {
      if (_sampleCount < warmupFrames) return;
      final p75 = _percentile(.75) / 1000;
      final next = p75 < targetFrameMs * 1.25
          ? GlassQuality.premium
          : p75 <= targetFrameMs * 1.75
          ? GlassQuality.standard
          : GlassQuality.minimal;
      _quality = _clamp(next);
      _phase = 'runtime';
      _lastQualityChange = _clock();
      _clearWindows();
      notifyListeners();
      return;
    }
    if (_sampleCount < runtimeWindowFrames) return;
    final p95 = _percentile(.95) / 1000;
    _sampleCount = 0;
    if (p95 > targetFrameMs * 1.5) {
      if (_overBudgetWindows < 2) _overBudgetWindows++;
      _underBudgetWindows = 0;
    } else if (p95 < targetFrameMs * .6) {
      if (_underBudgetWindows < 10) _underBudgetWindows++;
      _overBudgetWindows = 0;
    } else {
      _overBudgetWindows = 0;
      _underBudgetWindows = 0;
    }
    final now = _clock();
    if (_lastQualityChange != null &&
        now.difference(_lastQualityChange!) < const Duration(seconds: 8)) {
      return;
    }
    final position = _qualityOrder.indexOf(_quality);
    final GlassQuality? next;
    if (_overBudgetWindows >= 2 && position > 0) {
      next = _qualityOrder[position - 1];
    } else if (_underBudgetWindows >= 10 && position < 2) {
      next = _qualityOrder[position + 1];
    } else {
      next = null;
    }
    if (next == null || next == _quality) return;
    _quality = next;
    _lastQualityChange = now;
    _clearWindows();
    notifyListeners();
  }

  int _percentile(double fraction) {
    // At most 180 entries, once per complete window; no per-frame allocation.
    final sorted = _samples.sublist(0, _sampleCount)..sort();
    return sorted[(_sampleCount * fraction).ceil() - 1];
  }
}

@immutable
class SfAdaptiveGlassData {
  const SfAdaptiveGlassData({
    required this.effectiveQuality,
    required this.phase,
    required this.targetFrameMs,
    required this.refreshRateHz,
  });

  final GlassQuality effectiveQuality;
  final String phase;
  final double targetFrameMs;
  final double refreshRateHz;

  GlassQuality cap(GlassQuality requested) =>
      SfAdaptiveGlassController._qualityOrder.indexOf(requested) <=
          SfAdaptiveGlassController._qualityOrder.indexOf(effectiveQuality)
      ? requested
      : effectiveQuality;

  static SfAdaptiveGlassData? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SfInheritedAdaptiveGlass>()
      ?.data;
}

class SfAdaptiveGlass extends StatefulWidget {
  const SfAdaptiveGlass({
    super.key,
    required this.child,
    required this.initialQuality,
    required this.onQualityChanged,
    this.freezeListenable,
    this.freezeAdaptation,
    this.controller,
  });

  final Widget child;
  final GlassQuality? initialQuality;
  final void Function(GlassQuality from, GlassQuality to) onQualityChanged;
  final Listenable? freezeListenable;
  final bool Function()? freezeAdaptation;
  final SfAdaptiveGlassController? controller;

  @override
  State<SfAdaptiveGlass> createState() => _SfAdaptiveGlassState();
}

class _SfAdaptiveGlassState extends State<SfAdaptiveGlass>
    with WidgetsBindingObserver {
  late SfAdaptiveGlassController _controller;
  late GlassQuality _lastQuality;
  bool _attached = false;
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        SfAdaptiveGlassController(initialQuality: widget.initialQuality);
    _lastQuality = _controller.effectiveQuality;
    _syncFreeze();
    _controller.addListener(_changed);
    widget.freezeListenable?.addListener(_syncFreeze);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) _attach();
  }

  @override
  void didUpdateWidget(SfAdaptiveGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      widget.controller == oldWidget.controller,
      'Replace SfAdaptiveGlass with a new key to replace its controller.',
    );
    if (oldWidget.freezeListenable != widget.freezeListenable) {
      oldWidget.freezeListenable?.removeListener(_syncFreeze);
      widget.freezeListenable?.addListener(_syncFreeze);
    }
    _syncFreeze();
  }

  void _syncFreeze() =>
      _controller.setFrozen(widget.freezeAdaptation?.call() ?? false);

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_refreshScheduled) return;
      _refreshScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _refreshScheduled = false;
        if (!mounted) return;
        _flushControllerChange();
        SchedulerBinding.instance.ensureVisualUpdate();
      });
      return;
    }
    _flushControllerChange();
  }

  void _flushControllerChange() {
    final current = _controller.effectiveQuality;
    if (_lastQuality != current) {
      final previous = _lastQuality;
      _lastQuality = current;
      widget.onQualityChanged(previous, current);
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _readRefreshRate();
  }

  void _readRefreshRate() {
    final view = View.maybeOf(context);
    if (view != null) _controller.setRefreshRateHz(view.display.refreshRate);
  }

  @override
  void didChangeMetrics() => _readRefreshRate();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resetOnResume();
      _readRefreshRate();
      _attach();
    } else {
      _detach();
    }
  }

  void _attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_controller.addTimings);
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_controller.addTimings);
  }

  @override
  void dispose() {
    _detach();
    WidgetsBinding.instance.removeObserver(this);
    widget.freezeListenable?.removeListener(_syncFreeze);
    _controller.removeListener(_changed);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SfInheritedAdaptiveGlass(
    data: SfAdaptiveGlassData(
      effectiveQuality: _controller.effectiveQuality,
      phase: _controller.phase,
      targetFrameMs: _controller.targetFrameMs,
      refreshRateHz: _controller.refreshRateHz,
    ),
    child: widget.child,
  );
}

class _SfInheritedAdaptiveGlass extends InheritedWidget {
  const _SfInheritedAdaptiveGlass({required this.data, required super.child});

  final SfAdaptiveGlassData data;

  @override
  bool updateShouldNotify(_SfInheritedAdaptiveGlass oldWidget) =>
      data.effectiveQuality != oldWidget.data.effectiveQuality ||
      data.phase != oldWidget.data.phase ||
      data.targetFrameMs != oldWidget.data.targetFrameMs ||
      data.refreshRateHz != oldWidget.data.refreshRateHz;
}
