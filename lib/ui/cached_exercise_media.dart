import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/guide_poster_cache.dart';
import '../app/posehub_media_repository.dart';
import '../app/posehub_media_repository_types.dart';
import '../app/services.dart';
import '../domain/exercise.dart';
import 'guide_cached_poster.dart';
import 'theme.dart';

typedef CachedMediaStatus = ({
  bool loading,
  bool failed,
  bool revealed,
  double? progress,
});

/// A decrease within one decoder, across distinct high/low positions, is the
/// evidence for a loop. Null inspections and small decoder jitter are not loops.
bool observedVideoWrap(double previous, double current) =>
    previous.isFinite &&
    current.isFinite &&
    previous >= .25 &&
    current >= 0 &&
    current < previous / 2 &&
    previous - current >= .25;

/// The SDK standing index binds all 219 images to sourceVideo.frameIndex=0.
/// The packaging gate verifies its catalog/video SHA before including them.
/// Legacy covers have their own explicit frame-zero fields.
class ExerciseFrameZero extends StatefulWidget {
  const ExerciseFrameZero({
    super.key,
    required this.exercise,
    this.extractMissing = false,
    this.verifiedSource,
  });
  final Exercise exercise;
  final bool extractMissing;
  final Uri? verifiedSource;

  @override
  State<ExerciseFrameZero> createState() => _ExerciseFrameZeroState();
}

class _ExerciseFrameZeroState extends State<ExerciseFrameZero> {
  Future<String?>? _missingPoster;
  Brightness? _brightness;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) _missingPoster = null;
    _brightness = brightness;
  }

  @override
  void didUpdateWidget(ExerciseFrameZero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id ||
        oldWidget.exercise.media != widget.exercise.media ||
        oldWidget.extractMissing != widget.extractMissing ||
        (widget.verifiedSource != null &&
            oldWidget.verifiedSource != widget.verifiedSource)) {
      _missingPoster = null;
    }
  }

  Future<String?> _extractMissing() async {
    final exercise = widget.exercise;
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    VoidCallback? release;
    try {
      if (action != null) {
        final access = switch (services?.poseHubMedia) {
          final PoseHubVideoCacheAccess cache => cache,
          _ => null,
        };
        if (access == null) return null;
        // Missing images may inspect an already verified local video. They
        // never prepare/download it or allocate a decoder while scrolling.
        release = access.retainVideo(exercise.id);
        final source = await access.cachedVideo(exercise.id);
        if (!mounted || source == null || source.scheme != 'file') return null;
        return await GuidePosterCache.shared.frameZero(
          source: source,
          revision: action.video.sha256,
          packedAlpha: true,
        );
      }
      final media = exercise.media;
      final light = _brightness == Brightness.light;
      final packed = media.packedAlphaVideo?.isNotEmpty == true;
      final legacy = services?.media ?? TrainingMediaScope.maybeOf(context);
      if (legacy != null) {
        final available = await legacy.availableVideo(
          exercise.id,
          theme: light ? 'light' : 'dark',
        );
        final cached = available?.cachePath;
        if (!mounted || cached == null) return null;
        return await GuidePosterCache.shared.frameZero(
          source: Uri.file(cached),
          revision: media.revision ?? media.source,
          packedAlpha: packed,
        );
      }
      final asset = packed
          ? media.packedAlphaVideo!
          : light
          ? media.lightVideo ?? ''
          : media.video;
      if (asset.isEmpty || !media.videoAvailableFor(light: light)) return null;
      return await GuidePosterCache.shared.frameZero(
        source: Uri(scheme: 'asset', host: '', path: '/$asset'),
        revision: media.revision ?? media.source,
        packedAlpha: packed,
      );
    } on Object {
      return null;
    } finally {
      release?.call();
    }
  }

  Widget _image(List<String> candidates, int index, int cacheWidth) {
    if (index < candidates.length) {
      return Image.asset(
        candidates[index],
        key: ValueKey('exercise-frame-zero-${widget.exercise.id}'),
        cacheWidth: cacheWidth,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => _image(candidates, index + 1, cacheWidth),
      );
    }
    if (!widget.extractMissing) return const SizedBox.expand();
    return FutureBuilder<String?>(
      future: _missingPoster ??= _extractMissing(),
      builder: (_, snapshot) => snapshot.data == null
          ? const SizedBox.expand()
          : guideCachedPoster(
              snapshot.data!,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final exercise = widget.exercise;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    final light = Theme.of(context).brightness == Brightness.light;
    final media = exercise.media;
    final candidates = {
      if (action != null)
        'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${action.id}.webp',
      if (media.alphaPlaybackPoster?.isNotEmpty == true)
        media.alphaPlaybackPoster!,
      media.playbackPosterFor(light: light),
    }.where((asset) => asset.isNotEmpty).toList();
    return LayoutBuilder(
      builder: (context, constraints) => _image(
        candidates,
        0,
        (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(1, 0x7fffffff),
      ),
    );
  }
}

/// Owns only media presentation. Training clocks, speech and records remain in
/// TrainerPlayer. The surface uses exported SDK widgets and controllers only.
class CachedExerciseMedia extends StatefulWidget {
  const CachedExerciseMedia({
    super.key,
    required this.exercise,
    this.playing = true,
    this.paused = false,
    this.mirrored = false,
    this.radius = 16,
    this.waitForLoopOnMiss = false,
    this.mediaPreparer,
    this.playbackHandle,
    this.onStatus,
    this.slot,
    this.extractMissingPoster = false,
    this.stageColor,
    this.retainWhenCovered = false,
  });
  final Exercise exercise;
  final bool playing, paused, mirrored, waitForLoopOnMiss;
  final double radius;
  final PoseHubMediaPreparer? mediaPreparer;
  final DrillMediaPlaybackHandle? playbackHandle;
  final ValueChanged<CachedMediaStatus>? onStatus;
  final String? slot;
  final bool extractMissingPoster;
  final Color? stageColor;

  /// The trainer freezes its existing media with paused=true and TickerMode
  /// disabled while an early-exit save is pending. A dialog or this frozen
  /// subtree must not discard its last video frame. PlayerPage separately
  /// unmounts media for route transitions; app backgrounding still retires it.
  final bool retainWhenCovered;

  @override
  State<CachedExerciseMedia> createState() => _CachedExerciseMediaState();
}

class _CachedExerciseMediaState extends State<CachedExerciseMedia>
    with WidgetsBindingObserver {
  DrillMediaController? _controller;
  DrillMediaPlaybackHandle? _legacyHandle;
  PoseHubMediaPreparationController? _preparation;
  Completer<Uri?>? _prepared;
  ValueListenable<PoseHubDownloadState>? _download;
  TrainingMediaRepository? _legacyRepository;
  VoidCallback? _releasePin;
  Uri? _source;
  Uri? _legacyPosterSource;
  bool _checkingLegacyPoster = false;
  String? _asset;
  Timer? _probeTimer;
  bool _legacy = false;
  bool _alive = true;
  bool _backgrounded = false;
  bool _visible = true;
  bool _initialized = false;
  bool _loading = false;
  bool _failed = false;
  bool _revealed = false;
  bool _probing = false;
  bool? _initialCacheHit;
  double? _previousPosition;
  double? _progress;
  int _epoch = 0;
  CachedMediaStatus? _reported;

  bool get _current => _alive && mounted;
  bool get _allowed => _current && widget.playing && !_backgrounded && _visible;
  bool get _hasSurface => _controller != null || _legacy;
  String get _id => widget.exercise.id;
  String get _slot => widget.slot ?? _id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _backgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        widget.retainWhenCovered ||
        (TickerMode.valuesOf(context).enabled &&
            (ModalRoute.isCurrentOf(context) ?? true));
    if (!_initialized || visible != _visible) {
      _initialized = true;
      _visible = visible;
      if (_allowed) {
        unawaited(_start());
      } else {
        unawaited(retire());
      }
    }
  }

  @override
  void didUpdateWidget(CachedExerciseMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackHandle != widget.playbackHandle) {
      oldWidget.playbackHandle?.unbind(this);
      _bindHandle();
    }
    final changed =
        oldWidget.exercise.id != _id ||
        oldWidget.exercise.media.revision != widget.exercise.media.revision ||
        oldWidget.mediaPreparer != widget.mediaPreparer;
    if (changed || oldWidget.playing != widget.playing) {
      if (changed) _initialCacheHit = null;
      if (_allowed) {
        unawaited(_start());
      } else {
        unawaited(retire());
      }
    } else if (oldWidget.paused != widget.paused) {
      _previousPosition = null;
      _syncPause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final backgrounded = state != AppLifecycleState.resumed;
    if (_backgrounded == backgrounded) return;
    _backgrounded = backgrounded;
    if (_allowed) {
      unawaited(_start());
    } else {
      unawaited(retire());
    }
  }

  void _bindHandle() => widget.playbackHandle?.bind(
    owner: this,
    mediaId: _id,
    controller: _controller,
  );

  void _report() {
    final status = (
      loading: _loading,
      failed: _failed,
      revealed: _revealed,
      progress: _progress,
    );
    if (status == _reported) return;
    _reported = status;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_current && epoch == _epoch && status == _reported) {
        widget.onStatus?.call(status);
      }
    });
  }

  void _rebuild() {
    if (!_current) return;
    setState(() {});
    _report();
  }

  Future<Uri?> _prepare(
    coach.PoseHubPackAction action,
    PoseHubMediaPreparer preparer,
  ) {
    final preparation = PoseHubMediaPreparationController();
    final result = Completer<Uri?>();
    _preparation = preparation;
    _prepared = result;
    void changed() {
      if (result.isCompleted) return;
      final state = preparation.state;
      if (state.status == PoseHubMediaPreparationStatus.ready) {
        result.complete(action.video.resolve(state.mediaBaseUri!));
      } else if (state.status == PoseHubMediaPreparationStatus.failed) {
        result.complete(null);
      }
    }

    preparation.addListener(changed);
    preparation.start(preparer, action);
    return result.future.whenComplete(
      () => preparation.removeListener(changed),
    );
  }

  Future<void> _start() async {
    if (!_current) return;
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final light = Theme.of(context).brightness == Brightness.light;
    final legacyRepository =
        services?.media ?? TrainingMediaScope.maybeOf(context);
    final nextEpoch = _epoch + 1;
    await retire();
    if (!_allowed || nextEpoch != _epoch) return;
    final epoch = _epoch;
    final exercise = widget.exercise;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    final repo = services?.poseHubMedia;
    _loading = true;
    _failed = false;
    _bindHandle();
    _rebuild();
    try {
      if (action != null) {
        if (!UgkPackedAlphaVideo.isSupported || repo == null) {
          await _fail(epoch);
          return;
        }
        final access = switch (repo) {
          final PoseHubVideoCacheAccess cache => cache,
          _ => null,
        };
        _releasePin = access?.retainVideo(exercise.id);
        _download = repo.watchFile(action.video)..addListener(_downloadChanged);
        final cached = await access?.cachedVideo(exercise.id);
        if (!_allowed || epoch != _epoch) return;
        _initialCacheHit ??= cached != null;
        final preparer = widget.mediaPreparer ?? services?.poseHubPreparer;
        final source =
            cached ??
            (preparer == null ? null : await _prepare(action, preparer));
        if (!_allowed || epoch != _epoch) return;
        if (source == null) {
          await _fail(epoch);
          return;
        }
        _source = source;
        _createController();
      } else if (exercise.media.hasPackedAlpha &&
          UgkPackedAlphaVideo.isSupported) {
        _initialCacheHit ??= true;
        _asset = exercise.media.packedAlphaVideo;
        _createController();
      } else {
        if (!exercise.media.videoAvailableFor(light: light)) {
          _loading = false;
          _rebuild();
          return;
        }
        _legacyRepository = legacyRepository;
        final available = await _legacyRepository?.availableVideo(
          exercise.id,
          theme: light ? 'light' : 'dark',
        );
        if (!_allowed || epoch != _epoch) return;
        _initialCacheHit ??= _legacyRepository == null || available != null;
        _legacyRepository?.addListener(_legacyProgressChanged);
        _legacyHandle = widget.playbackHandle ?? DrillMediaPlaybackHandle();
        _legacy = true;
      }
      _rebuild();
      _syncPause();
    } on Object {
      if (_current && epoch == _epoch) await _fail(epoch);
    }
  }

  void _createController() {
    final controller = DrillMediaController();
    _controller = controller;
    controller.addListener(_decoderChanged);
    _bindHandle();
    if (!widget.paused) controller.toggle();
  }

  void _downloadChanged() {
    if (!_current) return;
    _progress = _download?.value.progress;
    _rebuild();
  }

  void _legacyProgressChanged() {
    if (!_current) return;
    final state = _legacyRepository?.stateFor(_id);
    if (state == null) return;
    if (state.phase == TrainingMediaPhase.ready) _refreshLegacyPoster();
    if (const [
      TrainingMediaPhase.failed,
      TrainingMediaPhase.offline,
      TrainingMediaPhase.waitingForWifi,
    ].contains(state.phase)) {
      unawaited(_fail(_epoch));
      return;
    }
    _progress = state.totalBytes > 0
        ? (state.receivedBytes / state.totalBytes).clamp(0.0, 1.0)
        : null;
    _rebuild();
  }

  void _refreshLegacyPoster() {
    if (!widget.extractMissingPoster ||
        _checkingLegacyPoster ||
        _legacyPosterSource != null) {
      return;
    }
    final repository = _legacyRepository;
    if (repository == null) return;
    _checkingLegacyPoster = true;
    final epoch = _epoch;
    final theme = Theme.of(context).brightness == Brightness.light
        ? 'light'
        : 'dark';
    unawaited(() async {
      try {
        final resource = await repository.availableVideo(_id, theme: theme);
        if (!_current || epoch != _epoch) return;
        final path = resource?.cachePath;
        if (path != null) {
          _legacyPosterSource = Uri.file(path);
          _rebuild();
        }
      } on Object {
        // Poster recovery never changes the SDK's playback or training result.
      } finally {
        if (epoch == _epoch) _checkingLegacyPoster = false;
      }
    }());
  }

  void _decoderChanged() {
    if (_controller?.failed == true) {
      unawaited(_fail(_epoch));
    } else {
      _scheduleProbe();
    }
  }

  void _syncPause() {
    if (widget.paused || !_allowed) {
      _probeTimer?.cancel();
      _probeTimer = null;
      _controller?.pause();
    } else {
      final controller = _controller;
      if (controller != null && !controller.wantsPlay) controller.toggle();
      _scheduleProbe();
    }
  }

  void _scheduleProbe() {
    if (!_allowed ||
        widget.paused ||
        _revealed ||
        !_hasSurface ||
        _probing ||
        _probeTimer?.isActive == true) {
      return;
    }
    _probeTimer = Timer(const Duration(milliseconds: 80), _probe);
  }

  Future<void> _probe() async {
    if (!_allowed || widget.paused || _revealed || !_hasSurface) return;
    _probing = true;
    final epoch = _epoch;
    double? position;
    final controller = _controller;
    if (controller != null && controller.ready && controller.hasFrame) {
      position = await controller.readPosition();
    } else if (_legacy) {
      final snapshot = await _legacyHandle?.capture();
      if (snapshot?.ready == true) {
        position = snapshot?.videoSeconds;
        if (_current && epoch == _epoch) _refreshLegacyPoster();
      }
    }
    if (epoch != _epoch) return;
    _probing = false;
    if (!_allowed || widget.paused) return;
    if (position != null) {
      final previous = _previousPosition;
      final waitForWrap = widget.waitForLoopOnMiss && _initialCacheHit == false;
      if (waitForWrap
          ? previous != null && observedVideoWrap(previous, position)
          : position > 0) {
        _revealed = true;
        _loading = false;
        _rebuild();
        return;
      }
      _previousPosition = position;
    }
    _scheduleProbe();
  }

  Future<void> _fail(int epoch) async {
    if (!_current || epoch != _epoch || _failed) return;
    await retire(keepFailure: true);
  }

  Future<void> retire({bool repaint = true, bool keepFailure = false}) async {
    ++_epoch;
    _probeTimer?.cancel();
    _probeTimer = null;
    _probing = false;
    _previousPosition = null;
    _download?.removeListener(_downloadChanged);
    _download = null;
    _legacyRepository?.removeListener(_legacyProgressChanged);
    _legacyRepository = null;
    final hadSurface = _hasSurface;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_decoderChanged);
    controller?.pause();
    controller?.dispose();
    if (!identical(_legacyHandle, widget.playbackHandle)) {
      _legacyHandle?.dispose();
    }
    _legacyHandle = null;
    _legacy = false;
    _bindHandle();
    _source = null;
    _legacyPosterSource = null;
    _checkingLegacyPoster = false;
    _asset = null;
    final preparation = _preparation;
    _preparation = null;
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null && !prepared.isCompleted) prepared.complete(null);
    preparation?.cancel();
    preparation?.dispose();
    if (preparation != null) unawaited(preparation.cancellationComplete);
    _loading = false;
    _revealed = false;
    _failed = keepFailure;
    _progress = null;
    final release = _releasePin;
    _releasePin = null;
    if (repaint && _current) _rebuild();
    if (repaint && hadSurface && _current) {
      await WidgetsBinding.instance.endOfFrame;
    }
    release?.call();
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(retire(repaint: false));
    widget.playbackHandle?.unbind(this);
    super.dispose();
  }

  Widget _surface() {
    final controller = _controller;
    if (controller != null) {
      return _source != null
          ? UgkPackedAlphaVideo.source(
              key: ValueKey('cached-media-video-$_slot'),
              sourceUri: _source!,
              controller: controller,
            )
          : UgkPackedAlphaVideo(
              key: ValueKey('cached-media-video-$_slot'),
              asset: _asset!,
              controller: controller,
            );
    }
    final media = widget.exercise.media;
    final light = Theme.of(context).brightness == Brightness.light;
    return DrillMediaView(
      key: ValueKey('cached-media-video-$_slot'),
      media: DrillMedia(
        id: _id,
        videoAsset: media.video,
        posterAsset: media.playbackPosterFor(light: light),
        duration: media.loopSeconds,
        posterTime: media.posterSeconds,
        lightVideoAsset: media.lightVideo,
        lightPosterAsset: media.lightPlaybackPoster ?? media.lightPoster,
        theme: light ? 'light' : 'dark',
        videoAvailable: media.videoAvailableFor(light: light),
        bundledOnly: media.appTestOnly,
      ),
      playing: true,
      paused: widget.paused,
      mirrored: false,
      radius: 0,
      stage: Colors.transparent,
      playbackHandle: _legacyHandle,
    );
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.radius),
    child: ColoredBox(
      color:
          widget.stageColor ??
          (_controller == null ? SfColors.mediaStage : Colors.transparent),
      child: Transform.flip(
        flipX: widget.mirrored,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasSurface) _surface(),
              IgnorePointer(
                child: AnimatedOpacity(
                  key: ValueKey('cached-media-poster-$_slot'),
                  opacity: _revealed ? 0 : 1,
                  duration: _revealed
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: ColoredBox(
                    color: widget.stageColor ?? SfColors.mediaStage,
                    child: ExerciseFrameZero(
                      exercise: widget.exercise,
                      extractMissing: widget.extractMissingPoster,
                      verifiedSource: _source ?? _legacyPosterSource,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Serial media ownership copied from the validated App guide implementation.
class GuidePreviewCoordinator extends ChangeNotifier {
  String? _activeSlot;
  String? _requestedSlot;
  Future<void> Function()? _retire;
  Future<void> _tail = Future.value();
  int _intent = 0;
  bool _disposed = false;
  String? get activeSlot => _activeSlot;

  Future<void> stop() {
    if (_disposed) return Future.value();
    ++_intent;
    _requestedSlot = null;
    final result = _tail.then((_) => _retireActive());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool> _claim(String slot, Future<void> Function() retire) {
    if (_disposed) return Future.value(false);
    _requestedSlot = slot;
    final intent = ++_intent;
    final result = _tail.then((_) async {
      if (_disposed || intent != _intent) return false;
      await _retireActive();
      if (_disposed || intent != _intent) return false;
      _activeSlot = slot;
      _retire = retire;
      notifyListeners();
      return true;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _retireActive() async {
    final retire = _retire;
    final changed = _activeSlot != null;
    _activeSlot = null;
    _retire = null;
    if (changed && !_disposed) notifyListeners();
    await retire?.call();
  }

  Future<void> release(String slot) =>
      _activeSlot == slot || _requestedSlot == slot ? stop() : Future.value();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_intent;
    _requestedSlot = null;
    final retire = _retire;
    _retire = null;
    _activeSlot = null;
    if (retire != null) unawaited(retire());
    super.dispose();
  }
}

class GuideMedia extends StatefulWidget {
  const GuideMedia({
    super.key,
    required this.exercise,
    required this.slot,
    required this.coordinator,
    this.enabled = true,
  });
  final Exercise exercise;
  final String slot;
  final GuidePreviewCoordinator coordinator;
  final bool enabled;
  @override
  State<GuideMedia> createState() => _GuideMediaState();
}

class _GuideMediaState extends State<GuideMedia> with WidgetsBindingObserver {
  final _surface = GlobalKey<_CachedExerciseMediaState>();
  bool _alive = true;
  bool _mountedPlayback = false;
  bool _requestedPlay = false;
  bool _failed = false;
  int _intent = 0;
  Object _owner = Object();
  String? _controlPhase;
  Key _controlTransition = UniqueKey();
  CachedMediaStatus _status = (
    loading: false,
    failed: false,
    revealed: false,
    progress: null,
  );
  bool get _current => _alive && mounted && !widget.coordinator._disposed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled ||
        !(ModalRoute.isCurrentOf(context) ?? true)) {
      unawaited(widget.coordinator.release(widget.slot));
    }
  }

  @override
  void didUpdateWidget(GuideMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id ||
        (oldWidget.enabled && !widget.enabled)) {
      unawaited(widget.coordinator.release(oldWidget.slot));
      _failed = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.coordinator.release(widget.slot));
    }
  }

  Future<void> _retire() async {
    ++_intent;
    _mountedPlayback = false;
    _requestedPlay = false;
    if (_current) setState(() {});
    await _surface.currentState?.retire(repaint: _current);
  }

  Future<void> _toggle() async {
    if (!_current || !widget.enabled) return;
    if (_mountedPlayback && !_failed) {
      setState(() => _requestedPlay = !_requestedPlay);
      return;
    }
    final intent = ++_intent;
    final owner = _owner = Object();
    setState(() {
      _failed = false;
      _requestedPlay = true;
      _status = (loading: true, failed: false, revealed: false, progress: null);
    });
    final claimed = await widget.coordinator._claim(widget.slot, () async {
      if (identical(owner, _owner)) await _retire();
    });
    if (!_current || !claimed || intent != _intent) return;
    setState(() => _mountedPlayback = true);
  }

  void _changed(CachedMediaStatus status) {
    if (!_current) return;
    if (status.failed && !_failed) {
      _failed = true;
      _requestedPlay = false;
      unawaited(widget.coordinator.release(widget.slot));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '连上网络后可以播放视频',
            style: SfType.label.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    setState(() => _status = status);
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.coordinator.release(widget.slot));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final light = Theme.of(context).brightness == Brightness.light;
    final canPlay =
        services?.poseHubCatalog?.tryGet(widget.exercise.id) != null ||
        widget.exercise.media.videoAvailableFor(light: light);
    final loading = _status.loading && _requestedPlay;
    final controlPhase = loading
        ? 'loading'
        : _failed
        ? 'offline'
        : _requestedPlay
        ? 'pause'
        : 'play';
    if (_controlPhase != controlPhase) {
      _controlPhase = controlPhase;
      // A prior copy of this phase can still be fading out. Give each entry
      // its own lifetime while retaining stable keys on the actual controls.
      _controlTransition = UniqueKey();
    }
    final dark = !light;
    final stage = Theme.of(context).colorScheme.surfaceContainerHighest;
    final label = _failed
        ? '重试动作示范'
        : _requestedPlay
        ? '暂停动作示范'
        : '播放动作示范';
    return GestureDetector(
      key: ValueKey('guide-media-${widget.slot}'),
      behavior: HitTestBehavior.opaque,
      onTap: canPlay ? _toggle : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            key: ValueKey('guide-media-stage-${widget.slot}'),
            color: stage,
            child: Center(
              child: AspectRatio(
                key: ValueKey('guide-media-square-${widget.slot}'),
                aspectRatio: 1,
                child: CachedExerciseMedia(
                  key: _surface,
                  exercise: widget.exercise,
                  slot: widget.slot,
                  playing: _mountedPlayback,
                  paused: !_requestedPlay,
                  radius: 0,
                  stageColor: stage,
                  extractMissingPoster: true,
                  onStatus: _changed,
                ),
              ),
            ),
          ),
          if (canPlay)
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                label: label,
                button: true,
                child: GestureDetector(
                  key: ValueKey('guide-media-control-${widget.slot}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggle,
                  child: SizedBox.square(
                    key: ValueKey('article-video-toggle-${widget.slot}'),
                    dimension: 44,
                    child: Center(
                      child: Container(
                        key: ValueKey(
                          'guide-media-control-face-${widget.slot}',
                        ),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dark
                              ? Colors.black.withValues(alpha: .55)
                              : Colors.white.withValues(alpha: .92),
                          boxShadow: dark
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .12),
                                    offset: const Offset(0, 2),
                                    blurRadius: 8,
                                  ),
                                ],
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            child: KeyedSubtree(
                              key: _controlTransition,
                              child: loading
                                  ? SizedBox.square(
                                      key: ValueKey(
                                        'guide-media-loading-${widget.slot}',
                                      ),
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        value: _status.progress,
                                        strokeWidth: 2,
                                        color: SfColors.accent,
                                      ),
                                    )
                                  : Icon(
                                      _failed
                                          ? Icons.cloud_off_rounded
                                          : _requestedPlay
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      key: ValueKey(
                                        _failed
                                            ? 'guide-media-offline-${widget.slot}'
                                            : _requestedPlay
                                            ? 'pause'
                                            : 'play',
                                      ),
                                      size: 20,
                                      color: dark
                                          ? Colors.white
                                          : SfColors.accent,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('此动作暂无视频示范'),
              ),
            ),
        ],
      ),
    );
  }
}
