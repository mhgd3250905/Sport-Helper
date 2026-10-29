import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/guide_poster_cache.dart';
import '../app/services.dart';
import '../domain/exercise.dart';
import 'chat/coach_ui_adapter.dart';
import 'guide_cached_poster.dart';
import 'theme/tokens.dart';

/// One guide preview is retained, including when the user pauses it.
class GuidePreviewCoordinator extends ChangeNotifier {
  String? _activeSlot;
  String? _requestedSlot;
  Future<void> Function()? _retire;
  Future<void> _tail = Future<void>.value();
  int _intent = 0;
  bool _disposed = false;

  String? get activeSlot => _activeSlot;

  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool> _claim(String slot, Future<void> Function() retire) {
    if (_disposed) return Future.value(false);
    _requestedSlot = slot;
    final intent = ++_intent;
    return _ordered(() async {
      if (_disposed || intent != _intent) return false;
      await _retireActive();
      if (_disposed || intent != _intent) return false;
      _activeSlot = slot;
      _retire = retire;
      notifyListeners();
      return true;
    });
  }

  Future<void> _retireActive() async {
    final retire = _retire;
    final changed = _activeSlot != null;
    _retire = null;
    _activeSlot = null;
    if (changed && !_disposed) notifyListeners();
    await retire?.call();
  }

  Future<void> stop() {
    if (_disposed) return Future.value();
    ++_intent;
    _requestedSlot = null;
    return _ordered(_retireActive);
  }

  Future<void> release(String slot) {
    if (_disposed || (_activeSlot != slot && _requestedSlot != slot)) {
      return Future.value();
    }
    return stop();
  }

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

class _GuideSource {
  const _GuideSource({
    required this.source,
    required this.packed,
    required this.revision,
    this.asset,
  });
  final Uri source;
  final String? asset;
  final bool packed;
  final String revision;
}

/// Static images do not construct a media controller or prepare a pack. A tap
/// alone claims playback; an exceptional missing image may extract frame zero.
class GuideMedia extends StatefulWidget {
  const GuideMedia({
    super.key,
    required this.exercise,
    required this.slot,
    required this.coordinator,
  });
  final Exercise exercise;
  final String slot;
  final GuidePreviewCoordinator coordinator;

  @override
  State<GuideMedia> createState() => _GuideMediaState();
}

class _GuideMediaState extends State<GuideMedia> with WidgetsBindingObserver {
  DrillMediaController? _controller;
  DrillMediaPlaybackHandle? _legacyHandle;
  PoseHubMediaPreparationController? _preparation;
  Completer<_GuideSource?>? _preparationResult;
  Future<_GuideSource?>? _sourceFuture;
  _GuideSource? _source;
  Future<String?>? _posterFuture;
  Timer? _probeTimer;
  final _readiness = Stopwatch();
  Object _owner = Object();
  int _generation = 0;
  int _sourceEpoch = 0;
  bool _alive = true;
  bool _requestedPlay = false;
  bool _loading = false;
  bool _revealed = false;
  bool _legacy = false;
  bool _probing = false;
  bool _failed = false;
  Brightness? _brightness;

  bool get _current => _alive && mounted && !widget.coordinator._disposed;
  bool get _hasSurface => _controller != null || _legacy;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('slot', widget.slot))
      ..add(StringProperty('activeSlot', widget.coordinator.activeSlot))
      ..add(DiagnosticsProperty<bool>('loading', _loading))
      ..add(DiagnosticsProperty<bool>('failed', _failed))
      ..add(DiagnosticsProperty<bool>('surface', _hasSurface))
      ..add(
        EnumProperty<PoseHubMediaPreparationStatus>(
          'preparation',
          _preparation?.state.status,
        ),
      );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness != null && _brightness != brightness) {
      unawaited(widget.coordinator.release(widget.slot));
      unawaited(_retire());
      _source = null;
      _sourceFuture = null;
      _posterFuture = null;
    }
    _brightness = brightness;
  }

  @override
  void didUpdateWidget(GuideMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exercise.id != widget.exercise.id ||
        oldWidget.exercise.media != widget.exercise.media ||
        oldWidget.slot != widget.slot ||
        oldWidget.coordinator != widget.coordinator) {
      unawaited(oldWidget.coordinator.release(oldWidget.slot));
      unawaited(_retire());
      _owner = Object();
      _source = null;
      _sourceFuture = null;
      _posterFuture = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(widget.coordinator.release(widget.slot));
    }
  }

  Future<_GuideSource?> _resolveSource() {
    if (_source != null) return Future.value(_source);
    return _sourceFuture ??= _prepareSource();
  }

  Future<_GuideSource?> _prepareSource() async {
    final exercise = widget.exercise;
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final action = services?.poseHubCatalog?.tryGet(exercise.id);
    final generation = _sourceEpoch;
    if (action != null) {
      final preparer = services?.poseHubPreparer;
      if (preparer == null) return null;
      final preparation = PoseHubMediaPreparationController();
      final result = Completer<_GuideSource?>();
      _preparation = preparation;
      _preparationResult = result;
      void changed() {
        if (result.isCompleted) return;
        final state = preparation.state;
        if (state.status == PoseHubMediaPreparationStatus.ready) {
          result.complete(
            _GuideSource(
              source: action.video.resolve(state.mediaBaseUri!),
              packed: true,
              revision: action.video.sha256,
            ),
          );
        } else if (state.status == PoseHubMediaPreparationStatus.failed) {
          result.complete(null);
        }
      }

      preparation.addListener(changed);
      preparation.start(preparer, action);
      final source = await result.future;
      preparation.removeListener(changed);
      // Keep the verified gate until this preview retires. Ready certifies the
      // files; stream-close acknowledgement is not a decoder-readiness barrier.
      if (identical(_preparation, preparation)) {
        _preparationResult = null;
      }
      if (!_current || generation != _sourceEpoch) return null;
      _source = source;
      if (source == null) _sourceFuture = null;
      return source;
    }
    final media = exercise.media;
    final light = _brightness == Brightness.light;
    final packed = media.packedAlphaVideo?.isNotEmpty == true;
    final asset = packed
        ? media.packedAlphaVideo!
        : light
        ? media.lightVideo ?? ''
        : media.video;
    if (asset.isEmpty || !media.videoAvailableFor(light: light)) return null;
    return _source = _GuideSource(
      source: Uri(scheme: 'asset', host: '', path: '/$asset'),
      asset: asset,
      packed: packed,
      revision: media.revision ?? media.source,
    );
  }

  Future<String?> _extractPoster() async {
    final source = await _resolveSource();
    if (!_current || source == null) return null;
    return GuidePosterCache.shared.frameZero(
      source: source.source,
      revision: source.revision,
      packedAlpha: source.packed,
    );
  }

  Future<void> _start() async {
    if (!_current) return;
    final generation = ++_generation;
    final owner = _owner;
    setState(() {
      _loading = true;
      _failed = false;
      _requestedPlay = true;
    });
    final claimed = await widget.coordinator._claim(widget.slot, () async {
      if (identical(owner, _owner)) await _retire();
    });
    if (!_current || generation != _generation) return;
    if (!claimed || widget.coordinator.activeSlot != widget.slot) {
      await _retire();
      return;
    }
    final source = await _resolveSource();
    if (!_current || generation != _generation) return;
    if (source == null) {
      _failed = true;
      await widget.coordinator.release(widget.slot);
      return;
    }
    if (source.packed) {
      final controller = DrillMediaController();
      _controller = controller;
      controller.addListener(_changed);
      controller.toggle();
    } else {
      _legacyHandle = DrillMediaPlaybackHandle();
      _legacy = true;
    }
    _readiness
      ..reset()
      ..start();
    setState(() {});
    _scheduleProbe();
  }

  void _toggle() {
    if (!_current) return;
    if (_loading && !_hasSurface) {
      unawaited(_retire());
      unawaited(widget.coordinator.release(widget.slot));
      return;
    }
    if (!_hasSurface) {
      unawaited(_start());
      return;
    }
    setState(() => _requestedPlay = !_requestedPlay);
    if (_requestedPlay) {
      _readiness.start();
      final controller = _controller;
      if (controller != null && !controller.wantsPlay) controller.toggle();
      _scheduleProbe();
    } else {
      _readiness.stop();
      _probeTimer?.cancel();
      _controller?.pause();
    }
  }

  void _changed() {
    if (!_current) return;
    if (_controller?.failed == true) {
      _failed = true;
      unawaited(widget.coordinator.release(widget.slot));
      return;
    }
    _scheduleProbe();
  }

  void _scheduleProbe() {
    if (!_current || !_requestedPlay || _revealed || !_hasSurface) return;
    if (_probeTimer?.isActive == true || _probing) return;
    _probeTimer = Timer(const Duration(milliseconds: 80), _probe);
  }

  Future<void> _probe() async {
    if (!_current || !_requestedPlay || _revealed || !_hasSurface) return;
    if (_readiness.elapsed > const Duration(seconds: 12)) {
      _failed = true;
      unawaited(widget.coordinator.release(widget.slot));
      return;
    }
    _probing = true;
    final generation = _generation;
    double? position;
    final controller = _controller;
    if (controller != null && controller.ready && controller.hasFrame) {
      position = await controller.readPosition();
    } else if (_legacy) {
      final snapshot = await _legacyHandle?.capture();
      if (snapshot?.ready == true) position = snapshot?.videoSeconds;
    }
    _probing = false;
    if (!_current || generation != _generation) return;
    if (position != null && position > 0) {
      _readiness.stop();
      setState(() {
        _revealed = true;
        _loading = false;
      });
    } else {
      _scheduleProbe();
    }
  }

  Future<void> _retire() async {
    ++_generation;
    ++_sourceEpoch;
    _probeTimer?.cancel();
    _probeTimer = null;
    _readiness.stop();
    final hadSurface = _hasSurface;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_changed);
    controller?.pause();
    controller?.dispose();
    _legacyHandle?.dispose();
    _legacyHandle = null;
    _legacy = false;
    _requestedPlay = false;
    _loading = false;
    _revealed = false;
    _sourceFuture = null;
    final preparation = _preparation;
    _preparation = null;
    preparation?.cancel();
    preparation?.dispose();
    final result = _preparationResult;
    _preparationResult = null;
    if (result != null && !result.isCompleted) result.complete(null);
    if (_current) setState(() {});
    if (preparation != null) {
      // cancel/dispose synchronously invalidates this consumer. Neither a
      // pending host download nor its close acknowledgement owns playback.
      unawaited(preparation.cancellationComplete);
    }
    if (hadSurface && _current) {
      // Unmount the SDK surface before a new claim constructs its decoder.
      // The public primitive dispatches native dispose during this frame.
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  List<String> _posterCandidates() {
    final exercise = widget.exercise;
    final services = context
        .getInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final standing = services?.poseHubCatalog?.tryGet(exercise.id) != null
        ? 'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${exercise.id}.webp'
        : toCoachRecommendationExercise(exercise).stillCutout;
    return {
      if (standing?.isNotEmpty == true) standing!,
      exercise.media.playbackPosterFor(light: _brightness == Brightness.light),
    }.where((asset) => asset.isNotEmpty).toList();
  }

  Widget _poster(List<String> candidates, int index, int cacheWidth) {
    if (index < candidates.length) {
      return Image.asset(
        candidates[index],
        cacheWidth: cacheWidth,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => _poster(candidates, index + 1, cacheWidth),
      );
    }
    return FutureBuilder<String?>(
      future: _posterFuture ??= _extractPoster(),
      builder: (context, snapshot) => snapshot.data == null
          ? const SizedBox.expand()
          : guideCachedPoster(
              snapshot.data!,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
    );
  }

  Widget _video(BoxConstraints constraints) {
    final controller = _controller;
    if (controller != null) {
      final source = _source!;
      return FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.square(
          dimension: constraints.maxWidth,
          child: source.asset == null
              ? UgkPackedAlphaVideo.source(
                  key: ValueKey('guide-media-video-${widget.slot}'),
                  sourceUri: source.source,
                  controller: controller,
                )
              : UgkPackedAlphaVideo(
                  key: ValueKey('guide-media-video-${widget.slot}'),
                  asset: source.asset!,
                  controller: controller,
                ),
        ),
      );
    }
    final media = widget.exercise.media;
    return DrillMediaView(
      key: ValueKey('guide-media-video-${widget.slot}'),
      media: DrillMedia(
        id: widget.exercise.id,
        videoAsset: media.video,
        posterAsset: media.playbackPosterFor(light: false),
        duration: media.loopSeconds,
        posterTime: media.posterSeconds,
        lightVideoAsset: media.lightVideo,
        lightPosterAsset: media.lightPlaybackPoster ?? media.lightPoster,
        videoAvailable: media.videoAvailableFor(
          light: _brightness == Brightness.light,
        ),
        theme: _brightness == Brightness.light ? 'light' : 'dark',
        bundledOnly: media.appTestOnly,
      ),
      playing: true,
      paused: !_requestedPlay,
      radius: 0,
      stage: Colors.transparent,
      playbackHandle: _legacyHandle,
    );
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_retire());
    unawaited(widget.coordinator.release(widget.slot));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final services = context
          .getInheritedWidgetOfExactType<AppScope>()
          ?.services;
      final media = widget.exercise.media;
      final canPlay =
          services?.poseHubCatalog?.tryGet(widget.exercise.id) != null ||
          (media.videoAvailableFor(light: !dark) &&
              (media.packedAlphaVideo?.isNotEmpty == true ||
                  (dark ? media.video : media.lightVideo ?? '').isNotEmpty));
      final cacheWidth =
          (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context))
              .round()
              .clamp(1, 0x7fffffff);
      final loading = _loading && _requestedPlay;
      final label = _failed
          ? '重试动作示范'
          : _requestedPlay
          ? '暂停动作示范'
          : '播放动作示范';
      return Semantics(
        button: canPlay,
        label: canPlay ? label : '此动作暂无视频示范',
        child: GestureDetector(
          key: ValueKey('guide-media-${widget.slot}'),
          behavior: HitTestBehavior.opaque,
          onTap: canPlay ? _toggle : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_hasSurface) _video(constraints),
              IgnorePointer(
                child: AnimatedOpacity(
                  key: ValueKey('guide-media-poster-${widget.slot}'),
                  opacity: _revealed ? 0 : 1,
                  duration: _revealed
                      ? const Duration(milliseconds: 200)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  child: _poster(_posterCandidates(), 0, cacheWidth),
                ),
              ),
              if (canPlay)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Semantics(
                    button: true,
                    label: label,
                    child: GestureDetector(
                      key: ValueKey('guide-media-control-${widget.slot}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: SizedBox.square(
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
                                        color: Colors.black.withValues(
                                          alpha: .12,
                                        ),
                                        offset: const Offset(0, 2),
                                        blurRadius: 8,
                                      ),
                                    ],
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 150),
                                child: loading
                                    ? SizedBox.square(
                                        key: ValueKey(
                                          'guide-media-loading-${widget.slot}',
                                        ),
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: dark
                                              ? Colors.white
                                              : SfColors.accent,
                                        ),
                                      )
                                    : Icon(
                                        _requestedPlay
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        key: ValueKey(
                                          _requestedPlay ? 'pause' : 'play',
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
        ),
      );
    },
  );
}
