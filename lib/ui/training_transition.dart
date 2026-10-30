part of 'training_route.dart';

/// UI timing only. A canceled gate stays pending: errors also start the SDK.
class TrainingTransitionMotion extends ChangeNotifier {
  TrainingTransitionMotion({
    required TickerProvider vsync,
    required this.reduced,
  }) : entrance = AnimationController(
         vsync: vsync,
         duration: Duration(milliseconds: reduced ? 150 : 560),
         animationBehavior: AnimationBehavior.preserve,
       ),
       _exit = AnimationController(
         vsync: vsync,
         value: 1,
         duration: Duration(milliseconds: reduced ? 150 : 250),
         animationBehavior: AnimationBehavior.preserve,
       ) {
    _entryChrome = CurvedAnimation(
      parent: entrance,
      curve: reduced ? Curves.linear : const Interval(.5, 1),
    );
    chrome = ProxyAnimation(_entryChrome);
    entrance.addListener(_entryTick);
  }
  final bool reduced;
  final AnimationController entrance;
  final AnimationController _exit;
  late final CurvedAnimation _entryChrome;
  late final ProxyAnimation chrome;
  final _start = Completer<void>();
  final mediaKey = GlobalKey(debugLabel: 'training-stage-media');
  Future<void> _exitMotion = Future.value();
  Exercise? exercise;
  Rect? entryFrom, entryStage;
  Rect? _lastMediaRect;
  bool mirrored = false, entered = false, exiting = false;
  bool saveFailed = false, aborted = false, _disposed = false;
  bool interrupted = false;
  bool exitingFromCompletion = false;
  Timer? _savingDelay;
  bool showSaving = false;

  Future<void> get startGate => _start.future;
  bool get canPlay => entered && !exiting && !saveFailed && !aborted;

  void _entryTick() {
    if (entrance.value < 1 || entered || aborted || exiting) return;
    entered = true;
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
    RuntimeLog.instance.record('training.transition.entry.completed');
    notifyListeners();
    if (!_start.isCompleted) _start.complete();
  }

  void reportMedia(Exercise value, {required bool mirrored}) {
    exercise = value;
    this.mirrored = mirrored;
  }

  Rect? get mediaRect {
    final box = mediaKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      _lastMediaRect = box.localToGlobal(Offset.zero) & box.size;
    }
    // Natural completion and save failures replace the media with the done
    // view. Retain the measured stage so Finish uses the same return motion.
    return _lastMediaRect;
  }

  void rememberStage() {
    mediaRect;
  }

  Future<void> enter() async {
    FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteEntry);
    RuntimeLog.instance.record(
      'training.transition.entry.started',
      fields: {'reduced': reduced, 'durationMs': reduced ? 150 : 560},
    );
    try {
      await entrance.forward().orCancel;
    } on TickerCanceled {
      // Return or lifecycle cancellation owns the terminal state.
    }
  }

  void exitStarted({bool fromCompletion = false}) {
    if (exiting || aborted) return;
    if (!entered) {
      abort();
      return;
    }
    final from = chrome.value;
    exitingFromCompletion = fromCompletion;
    exiting = true;
    saveFailed = false;
    _exit.value = from;
    chrome.parent = _exit;
    FrameRecorder.instance.beginScenario(FrameScenario.trainingRouteExit);
    RuntimeLog.instance.record('training.transition.exit.started');
    _exitMotion = _reverse();
    if (reduced) {
      _savingDelay = Timer(const Duration(milliseconds: 400), () {
        if (_disposed || interrupted || saveFailed) return;
        showSaving = true;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> _reverse() async {
    try {
      await _exit.reverse().orCancel;
    } on TickerCanceled {
      // A failed save or interruption releases the presentation gate.
    }
  }

  Future<void> beforeExitPop() {
    _savingDelay?.cancel();
    showSaving = false;
    return _exitMotion;
  }

  void exitSaveFailed() {
    if (_disposed) return;
    saveFailed = true;
    _savingDelay?.cancel();
    showSaving = false;
    _exit.stop(canceled: true);
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteExit);
    notifyListeners();
  }

  void replay() {
    if (_disposed) return;
    exiting = false;
    exitingFromCompletion = false;
    saveFailed = false;
    _exit.value = 1;
    chrome.parent = _exit;
    notifyListeners();
  }

  void abort() {
    if (_disposed || aborted) return;
    aborted = true;
    _savingDelay?.cancel();
    showSaving = false;
    entrance.stop(canceled: true);
    _exit.stop(canceled: true);
    FrameRecorder.instance
      ..endScenario(FrameScenario.trainingRouteEntry)
      ..endScenario(FrameScenario.trainingRouteExit);
    notifyListeners();
  }

  void finishExitNow() {
    interrupted = true;
    _savingDelay?.cancel();
    showSaving = false;
    if (!_disposed) _exit.value = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _savingDelay?.cancel();
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteEntry);
    entrance.removeListener(_entryTick);
    chrome.parent = null;
    _entryChrome.dispose();
    entrance.dispose();
    _exit.dispose();
    super.dispose();
  }
}

class TrainingTransitionScope extends InheritedWidget {
  const TrainingTransitionScope({
    super.key,
    required this.motion,
    required super.child,
  });
  final TrainingTransitionMotion motion;
  static TrainingTransitionMotion? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TrainingTransitionScope>()
      ?.motion;
  @override
  bool updateShouldNotify(TrainingTransitionScope oldWidget) =>
      motion != oldWidget.motion;
}

class _TrainingTransitionHost extends StatefulWidget {
  const _TrainingTransitionHost({required this.route, required this.builder});
  final TrainingRoute route;
  final WidgetBuilder builder;
  @override
  State<_TrainingTransitionHost> createState() =>
      _TrainingTransitionHostState();
}

class _TrainingTransitionHostState extends State<_TrainingTransitionHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TrainingTransitionMotion motion;
  bool _ready = false;
  Rect? _from, _stage;
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.route._host = this;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;
    motion = TrainingTransitionMotion(
      vsync: this,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || motion.aborted) return;
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) {
        motion.abort();
        if (widget.route.isCurrent) widget.route.navigator?.pop();
        return;
      }
      final box = context.findRenderObject() as RenderBox;
      _origin = box.localToGlobal(Offset.zero);
      _stage = motion.mediaRect?.shift(-_origin);
      _from = widget.route.source?.initialRect ?? widget.route.source?.rect();
      if (_from != null && !_visible(_from!, _origin & box.size)) {
        _from = null;
      }
      _from = _from?.shift(-_origin);
      motion.entryFrom = _from?.shift(_origin);
      motion.entryStage = motion.mediaRect;
      if (_from != null && !motion.reduced) widget.route.source?.show(0);
      setState(() {});
      unawaited(motion.enter());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !mounted) return;
    if (!motion.entered) {
      motion.abort();
      if (widget.route.isCurrent) widget.route.navigator?.pop();
    } else if (motion.exiting) {
      motion.finishExitNow();
    }
  }

  void prepareReturn() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final owner = widget.route._sourceRoute;
    if (!motion.entered ||
        motion.aborted ||
        !motion.exiting ||
        motion.interrupted ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed) ||
        (owner != null &&
            (!owner.isActive || owner.navigator != widget.route.navigator))) {
      motion.abort();
      widget.route._finishVisual();
      return;
    }
    final overlay = widget.route.navigator?.overlay;
    if (motion.reduced) {
      // The page and chrome already cross-faded together during exit A.
      // Adding another post-pop fade would double the specified 150ms.
      widget.route._finishVisual();
      return;
    }
    final exercise = motion.exercise;
    final stage = motion.mediaRect;
    if (overlay == null || exercise == null || stage == null) {
      widget.route._finishVisual();
      return;
    }
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final origin = overlayBox.localToGlobal(Offset.zero);
    final target = widget.route.source?.rect();
    final visible =
        target != null && _visible(target, origin & overlayBox.size);
    final source = visible ? widget.route.source : null;
    source?.show(motion.reduced ? 1 : 0);
    final theme = Theme.of(context);
    final query = MediaQuery.of(context);
    final stageColor = SmartFitTrainerTheme.of(context).mediaStage;
    widget.route._returning = true;
    final entry = OverlayEntry(
      builder: (_) => Theme(
        data: theme,
        child: MediaQuery(
          data: query,
          child: _ReturningPoster(
            from: stage.shift(-origin),
            to: visible ? target.shift(-origin) : null,
            source: source,
            exercise: exercise,
            mirrored: motion.mirrored,
            background: stageColor,
            reduced: motion.reduced,
            onDone: widget.route._finishVisual,
          ),
        ),
      ),
    );
    widget.route._returnEntry = entry;
    final history = LocalHistoryEntry(onRemove: widget.route._finishVisual);
    widget.route._returnHistory = history;
    widget.route._sourceRoute?.addLocalHistoryEntry(history);
    overlay.insert(entry);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.route._host = null;
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = TrainingTransitionScope(
      motion: motion,
      child: Builder(builder: widget.builder),
    );
    final view = AnimatedBuilder(
      animation: Listenable.merge([motion.entrance, motion.chrome, motion]),
      child: child,
      builder: (context, child) {
        final elapsed = motion.entrance.value * (motion.reduced ? 150 : 560);
        if (motion.reduced) {
          final opacity = motion.saveFailed
              ? 1.0
              : motion.entered && motion.exiting
              ? motion.chrome.value
              : motion.entrance.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              FadeTransition(
                opacity: AlwaysStoppedAnimation(opacity),
                child: child,
              ),
              if (motion.showSaving && !motion.saveFailed)
                Center(
                  child: SizedBox.square(
                    key: const ValueKey('training-reduced-saving'),
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SmartFitTrainerTheme.of(context).accent,
                    ),
                  ),
                ),
            ],
          );
        }
        final stage = _stage;
        final exercise = motion.exercise;
        final e = Curves.easeInOutCubicEmphasized.transform(
          (elapsed / 420).clamp(0.0, 1.0),
        );
        final background = Curves.easeOutCubic.transform(
          (elapsed / 280).clamp(0.0, 1.0),
        );
        final posterRect = stage == null
            ? null
            : _from == null
            ? stage
            : Rect.lerp(_from, stage, e)!;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              key: const ValueKey('training-entry-background'),
              color: SmartFitTrainerTheme.of(
                context,
              ).mediaStage.withValues(alpha: background),
            ),
            // SDK floor forces alpha=1. Keep real layout from frame zero and start
            // painting at 280ms, when background=1 and chrome is still exactly 0.
            Offstage(offstage: elapsed < 280, child: child!),
            if (!motion.entered &&
                elapsed < 280 &&
                posterRect != null &&
                exercise != null)
              Positioned.fromRect(
                rect: posterRect,
                child: IgnorePointer(
                  child: _from != null
                      ? TrainingTransitionPoster(
                          key: const ValueKey('training-morph-poster'),
                          exercise: exercise,
                          mirrored: motion.mirrored,
                          radius: 20 * (1 - e),
                          cacheWidth:
                              (stage!.width *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                        )
                      : Transform.scale(
                          key: const ValueKey('training-entry-fallback'),
                          scale:
                              1.04 -
                              .04 *
                                  Curves.easeOutCubic.transform(
                                    (elapsed / 320).clamp(0.0, 1.0),
                                  ),
                          child: Opacity(
                            opacity: Curves.easeOutCubic.transform(
                              (elapsed / 320).clamp(0.0, 1.0),
                            ),
                            child: TrainingTransitionPoster(
                              exercise: exercise,
                              mirrored: motion.mirrored,
                              cacheWidth:
                                  (stage!.width *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .round(),
                            ),
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && motion.entered && motion.exiting && !motion.saveFailed) {
          motion.finishExitNow();
        }
      },
      child: Listener(
        onPointerDown: (_) {
          if (!motion.entered && !motion.aborted) {
            motion.abort();
            if (widget.route.isCurrent) widget.route.navigator?.pop();
          } else if (motion.exiting && !motion.saveFailed) {
            motion.finishExitNow();
          }
        },
        child: view,
      ),
    );
  }
}

bool _visible(Rect rect, Rect viewport) =>
    rect.width > 0 && rect.height > 0 && rect.overlaps(viewport);

/// From 280ms onward this host-owned flight is painted in the public SDK media
/// slot: above the floor and below all real chrome. Keeping a full-size poster
/// above TrainerPlayer would cover its cue and pendant entrance until 560ms.
class TrainingEntranceMedia extends StatelessWidget {
  const TrainingEntranceMedia({
    super.key,
    required this.motion,
    required this.exercise,
    required this.mirrored,
  });
  final TrainingTransitionMotion motion;
  final Exercise exercise;
  final bool mirrored;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion.entrance,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final stage = motion.entryStage;
        if (motion.reduced || stage == null) {
          return TrainingTransitionPoster(
            exercise: exercise,
            mirrored: mirrored,
          );
        }
        final elapsed = motion.entrance.value * 560;
        final e = Curves.easeInOutCubicEmphasized.transform(
          (elapsed / 420).clamp(0.0, 1.0),
        );
        final from = motion.entryFrom;
        final global = from == null ? stage : Rect.lerp(from, stage, e)!;
        final rect = global.shift(-stage.topLeft);
        Widget poster = TrainingTransitionPoster(
          key: ValueKey(
            from == null ? 'training-entry-fallback' : 'training-morph-poster',
          ),
          exercise: exercise,
          mirrored: mirrored,
          radius: from == null ? 0 : 20 * (1 - e),
          cacheWidth: (stage.width * MediaQuery.devicePixelRatioOf(context))
              .round(),
        );
        if (from == null) {
          final t = Curves.easeOutCubic.transform(
            (elapsed / 320).clamp(0.0, 1.0),
          );
          poster = Transform.scale(
            scale: 1.04 - .04 * t,
            child: Opacity(opacity: t, child: poster),
          );
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [Positioned.fromRect(rect: rect, child: poster)],
        );
      },
    ),
  );
}

class _ReturningPoster extends StatefulWidget {
  const _ReturningPoster({
    required this.from,
    required this.to,
    required this.source,
    required this.exercise,
    required this.mirrored,
    required this.background,
    required this.reduced,
    required this.onDone,
  });
  final Rect from;
  final Rect? to;
  final TrainingTransitionSource? source;
  final Exercise exercise;
  final bool mirrored;
  final Color background;
  final bool reduced;
  final VoidCallback onDone;
  @override
  State<_ReturningPoster> createState() => _ReturningPosterState();
}

class _ReturningPosterState extends State<_ReturningPoster>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: widget.reduced
          ? 150
          : widget.to == null
          ? 260
          : 500,
    ),
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _done = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation.addListener(_tick);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      scheduleMicrotask(_finish);
      return;
    }
    unawaited(_animation.forward());
  }

  void _tick() {
    if (!widget.reduced && widget.to != null && _animation.value >= .76) {
      widget.source?.show(1);
    }
    if (_animation.value == 1) _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _finish();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (_, _) => _finish(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, _) {
          final value = _animation.value;
          final fallback = widget.to == null;
          final ms =
              value *
              (widget.reduced
                  ? 150
                  : fallback
                  ? 260
                  : 500);
          final morph = Curves.easeInOutCubicEmphasized.transform(
            (ms / 380).clamp(0.0, 1.0),
          );
          final rect = widget.reduced || fallback
              ? widget.from
              : Rect.lerp(widget.from, widget.to, morph)!;
          Widget layer = Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: widget.background.withValues(
                  alpha: widget.reduced || fallback
                      ? 1
                      : 1 -
                            Curves.easeInCubic.transform(
                              (ms / 240).clamp(0.0, 1.0),
                            ),
                ),
              ),
              Positioned.fromRect(
                rect: rect,
                child: Opacity(
                  opacity: widget.reduced || fallback
                      ? 1
                      : 1 - ((ms - 380) / 120).clamp(0.0, 1.0),
                  child: TrainingTransitionPoster(
                    key: const ValueKey('training-return-poster'),
                    exercise: widget.exercise,
                    mirrored: widget.mirrored,
                    radius: widget.reduced || fallback ? 0 : 20 * morph,
                    cacheWidth:
                        (widget.from.width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                  ),
                ),
              ),
            ],
          );
          if (widget.reduced || fallback) {
            final t = Curves.easeInCubic.transform(value);
            layer = Opacity(
              opacity: 1 - t,
              child: Transform.scale(
                scale: widget.reduced ? 1 : 1 - .06 * t,
                child: layer,
              ),
            );
          }
          return KeyedSubtree(
            key: ValueKey(
              fallback ? 'training-return-fallback' : 'training-return-morph',
            ),
            child: layer,
          );
        },
      ),
    ),
  );
}
