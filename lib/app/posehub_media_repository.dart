import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show CatalogMediaTimingCallback;

import 'posehub_media_repository_stub.dart'
    if (dart.library.io) 'posehub_media_repository_io.dart'
    as platform;
import 'posehub_media_repository_types.dart';

export 'posehub_media_repository_types.dart'
    show
        PoseHubBundledFileLoader,
        PoseHubDownloadPhase,
        PoseHubDownloadState,
        PoseHubMediaException,
        PoseHubMediaTimingAnchor,
        PoseHubMediaEntryPreparation,
        poseHubMediaTimingFields,
        PoseHubTrainingVideoPreparation,
        PoseHubLegacyVideoFile,
        PoseHubVideoCache,
        PoseHubVideoCacheAccess,
        poseHubVideoCacheLimitBytes;

abstract interface class PoseHubMediaRepository {
  static Future<PoseHubMediaRepository> create({
    required coach.PoseHubAppTestCatalog catalog,
    required String catalogRevision,
    required List<Uri> mediaBaseUrls,
    String packVersion = 'r1-v3',
    String? rootDirectory,
    PoseHubBundledFileLoader? bundledFileLoader,
    CatalogMediaTimingCallback? onTiming,
  }) => _create(
    catalog: catalog,
    catalogRevision: catalogRevision,
    mediaBaseUrls: mediaBaseUrls,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    bundledFileLoader: bundledFileLoader,
    onTiming: onTiming,
  );

  @visibleForTesting
  static Future<PoseHubMediaRepository> forTesting({
    required coach.PoseHubAppTestCatalog catalog,
    required String catalogRevision,
    required List<Uri> mediaBaseUrls,
    String packVersion = 'r1-v3',
    required String rootDirectory,
    PoseHubBundledFileLoader? bundledFileLoader,
    CatalogMediaTimingCallback? onTiming,
    bool allowInsecureLocalhost = false,
    Duration timeout = const Duration(seconds: 15),
    Duration progressInterval = const Duration(milliseconds: 100),
    int maxConcurrent = 2,
    int maxRedirects = 5,
    int maxVideoCacheBytes = poseHubVideoCacheLimitBytes,
    // Explicit AppCache parent for fixtures; no device directories are queried.
    String? legacyCacheDirectory,
    List<PoseHubLegacyVideoFile> legacyVideos = const [],
  }) => _create(
    catalog: catalog,
    catalogRevision: catalogRevision,
    mediaBaseUrls: mediaBaseUrls,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    bundledFileLoader: bundledFileLoader,
    onTiming: onTiming,
    allowInsecureLocalhost: allowInsecureLocalhost,
    timeout: timeout,
    progressInterval: progressInterval,
    maxConcurrent: maxConcurrent,
    maxRedirects: maxRedirects,
    maxVideoCacheBytes: maxVideoCacheBytes,
    legacyCacheDirectory: legacyCacheDirectory,
    legacyVideos: legacyVideos,
  );

  /// Created immediately; it does not promise that all catalogue files exist.
  Uri get mediaBaseUri;
  Future<Uri> ensureFile(coach.PoseHubPackFile file);
  Future<Uri> ensureAction(String actionId);
  ValueListenable<PoseHubDownloadState> watchFile(coach.PoseHubPackFile file);
  ValueListenable<PoseHubDownloadState> watchAction(String actionId);
  void dispose();
}

Future<PoseHubMediaRepository> _create({
  required coach.PoseHubAppTestCatalog catalog,
  required String catalogRevision,
  required List<Uri> mediaBaseUrls,
  required String packVersion,
  String? rootDirectory,
  PoseHubBundledFileLoader? bundledFileLoader,
  CatalogMediaTimingCallback? onTiming,
  bool allowInsecureLocalhost = false,
  Duration timeout = const Duration(seconds: 15),
  Duration progressInterval = const Duration(milliseconds: 100),
  int maxConcurrent = 2,
  int maxRedirects = 5,
  int maxVideoCacheBytes = poseHubVideoCacheLimitBytes,
  String? legacyCacheDirectory,
  List<PoseHubLegacyVideoFile> legacyVideos = const [],
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(catalogRevision) ||
      !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(packVersion) ||
      packVersion.length > 64 ||
      timeout <= Duration.zero ||
      progressInterval < Duration.zero ||
      maxConcurrent < 1 ||
      maxConcurrent > 3 ||
      maxVideoCacheBytes < 1 ||
      maxVideoCacheBytes > poseHubVideoCacheLimitBytes ||
      maxRedirects < 0 ||
      maxRedirects > 8) {
    throw const FormatException('Invalid media repository configuration.');
  }
  final files = {
    for (final action in catalog.allActions)
      for (final file in action.files.values) file.path: file,
  };
  final bases = List<Uri>.unmodifiable(mediaBaseUrls);
  final timing = PoseHubMediaTiming(catalog, onTiming: onTiming);
  timing.repository('create_start');
  final store = await platform.createPoseHubMediaStore(
    revision: catalogRevision,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    files: files.values.toList(),
    videos: {
      for (final action in catalog.allActions) action.video.path: action.video,
    }.values.toList(),
    mediaBaseUrls: bases,
    allowInsecureLocalhost: allowInsecureLocalhost,
    timeout: timeout,
    maxRedirects: maxRedirects,
    maxVideoCacheBytes: maxVideoCacheBytes,
    legacyCacheDirectory: legacyCacheDirectory,
    legacyVideos: legacyVideos,
    timing: timing,
  );
  timing.repository('create_complete', result: 'ok');
  return _Repository(
    catalog,
    files,
    store,
    bases,
    bundledFileLoader,
    timeout,
    progressInterval,
    maxConcurrent,
    timing,
  );
}

class _Repository
    implements
        PoseHubMediaRepository,
        PoseHubVideoCache,
        PoseHubVideoCacheAccess,
        PoseHubMediaTimingAnchor,
        PoseHubTrainingVideoPreparation,
        PoseHubMediaEntryPreparation {
  _Repository(
    this.catalog,
    this.files,
    this.store,
    this.bases,
    this.loadBundle,
    this.timeout,
    this.progressInterval,
    this.maxConcurrent,
    this.timing,
  ) {
    for (final action in catalog.allActions) {
      for (final role in action.files.entries) {
        final file = role.value;
        (_actionsForFile[file.path] ??= {}).add(action.id);
        (_filesForHash[file.sha256] ??= []).add(file);
        if (role.key != 'video') _images.add(file.path);
        if (role.key == 'video') _videos.add(file.path);
      }
    }
  }

  final coach.PoseHubAppTestCatalog catalog;
  final Map<String, coach.PoseHubPackFile> files;
  final PoseHubMediaFileStore store;
  final List<Uri> bases;
  final PoseHubBundledFileLoader? loadBundle;
  final Duration timeout, progressInterval;
  final int maxConcurrent;
  final PoseHubMediaTiming timing;
  final _fileJobs = <String, Future<Uri>>{};
  final _contentJobs = <String, Future<Uri>>{};
  final _actionJobs = <String, Future<Uri>>{};
  final _afterClearFiles = <String, Future<Uri>>{};
  final _afterClearActions = <String, Future<Uri>>{};
  final _fileStates = <String, ValueNotifier<PoseHubDownloadState>>{};
  final _actionStates = <String, ValueNotifier<PoseHubDownloadState>>{};
  final _actionsForFile = <String, Set<String>>{};
  final _filesForHash = <String, List<coach.PoseHubPackFile>>{};
  final _images = <String>{};
  final _videos = <String>{};
  final _lastProgress = <String, DateTime>{};
  final _queue =
      <({Completer<void> ready, int? generation, String contentKey})>[];
  final _priorityContent = <String>{};
  final _afterClearPriority = <String>{};
  int _active = 0;
  int _generation = 0;
  Future<void>? _clearing;
  bool _disposed = false;

  @override
  Uri get mediaBaseUri => store.mediaBaseUri;

  @override
  void markTrainingEntry() => timing.markTrainingEntry();

  @override
  void markMediaEntry(String entry) => timing.markMediaEntry(entry);

  void _check([int? generation]) {
    if (_disposed) {
      throw const PoseHubMediaException(
        'disposed',
        'Media preparation stopped.',
      );
    }
    if (generation != null && generation != _generation) {
      throw const PoseHubMediaException(
        'cache_cleared',
        'Video preparation stopped while its cache was cleared.',
      );
    }
  }

  coach.PoseHubPackFile _known(coach.PoseHubPackFile file) {
    _check();
    final known = files[file.path];
    if (known == null ||
        known.bytes != file.bytes ||
        known.sha256 != file.sha256) {
      throw const FormatException('File does not match the selected catalog.');
    }
    return known;
  }

  coach.PoseHubPackAction _action(String id) {
    _check();
    final action = catalog.tryGet(id);
    if (action == null) throw ArgumentError('Unknown PoseHub action.');
    return action;
  }

  @override
  ValueListenable<PoseHubDownloadState> watchFile(coach.PoseHubPackFile file) {
    file = _known(file);
    return _fileStates.putIfAbsent(
      file.path,
      () => ValueNotifier(
        PoseHubDownloadState(
          phase: PoseHubDownloadPhase.idle,
          totalBytes: file.bytes,
        ),
      ),
    );
  }

  @override
  ValueListenable<PoseHubDownloadState> watchAction(String actionId) {
    final action = _action(actionId);
    return _actionStates.putIfAbsent(
      actionId,
      () => ValueNotifier(_aggregate(action)),
    );
  }

  PoseHubDownloadState _aggregate(coach.PoseHubPackAction action) {
    final states = [
      for (final file in action.files.values)
        _fileStates[file.path]?.value ??
            PoseHubDownloadState(
              phase: PoseHubDownloadPhase.idle,
              totalBytes: file.bytes,
            ),
    ];
    final failed = states.where((s) => s.phase == PoseHubDownloadPhase.failed);
    var phase = PoseHubDownloadPhase.idle;
    if (failed.isNotEmpty) {
      phase = PoseHubDownloadPhase.failed;
    } else if (states.every((s) => s.phase == PoseHubDownloadPhase.ready)) {
      phase = PoseHubDownloadPhase.ready;
    } else {
      for (final candidate in const [
        PoseHubDownloadPhase.downloading,
        PoseHubDownloadPhase.verifying,
        PoseHubDownloadPhase.checking,
        PoseHubDownloadPhase.queued,
      ]) {
        if (states.any((s) => s.phase == candidate)) {
          phase = candidate;
          break;
        }
      }
    }
    return PoseHubDownloadState(
      phase: phase,
      receivedBytes: states.fold(0, (n, s) => n + s.receivedBytes),
      totalBytes: states.fold(0, (n, s) => n + s.totalBytes),
      error: failed.isEmpty ? null : failed.first.error,
    );
  }

  void _set(
    coach.PoseHubPackFile file,
    PoseHubDownloadPhase phase, {
    int received = 0,
    Object? error,
  }) {
    if (_disposed) return;
    final notifier = watchFile(file) as ValueNotifier<PoseHubDownloadState>;
    final now = DateTime.now();
    if (phase == PoseHubDownloadPhase.downloading &&
        notifier.value.phase == phase &&
        received >= notifier.value.receivedBytes &&
        received < file.bytes) {
      final previous = _lastProgress[file.path];
      if (previous != null && now.difference(previous) < progressInterval) {
        return;
      }
    }
    _lastProgress[file.path] = now;
    notifier.value = PoseHubDownloadState(
      phase: phase,
      receivedBytes: received.clamp(0, file.bytes),
      totalBytes: file.bytes,
      error: error,
    );
    for (final id in _actionsForFile[file.path] ?? const <String>{}) {
      _actionStates[id]?.value = _aggregate(catalog.tryGet(id)!);
    }
  }

  void _contentState(
    coach.PoseHubPackFile file,
    PoseHubDownloadPhase phase, {
    int received = 0,
  }) {
    for (final alias in _filesForHash[file.sha256]!) {
      if (_fileJobs.containsKey(alias.path)) {
        _set(alias, phase, received: received);
      }
    }
  }

  @override
  Future<Uri> ensureFile(coach.PoseHubPackFile file) => _requestFile(file);

  @override
  Future<Uri> ensureVideo(String actionId, {bool priority = false}) {
    try {
      return _requestFile(
        _action(actionId).video,
        priority: priority,
        entry: 'training',
      );
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  @override
  Future<Uri> ensureVideoForEntry(
    String actionId, {
    required String entry,
    bool priority = false,
  }) {
    try {
      return _requestFile(
        _action(actionId).video,
        priority: priority,
        entry: entry,
      );
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void _promote(coach.PoseHubPackFile file) {
    _priorityContent.add(file.sha256);
    final index = _queue.indexWhere((entry) => entry.contentKey == file.sha256);
    if (index > 0) {
      final entry = _queue.removeAt(index);
      _queue.insert(0, entry);
      timing.event(
        file,
        'promoted',
        queueDepth: _queue.length,
        activeSlots: _active,
      );
    }
  }

  Future<Uri> _requestFile(
    coach.PoseHubPackFile file, {
    bool priority = false,
    String entry = 'background',
  }) {
    try {
      file = _known(file);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    if (_clearing case final barrier?) {
      if (priority) _afterClearPriority.add(file.path);
      return _afterClear(_afterClearFiles, file.path, barrier, () {
        final requestedPriority = _afterClearPriority.remove(file.path);
        return _requestFile(
          file,
          priority: priority || requestedPriority,
          entry: entry,
        );
      });
    }
    if (priority) _promote(file);
    if (_fileJobs[file.path] case final job?) {
      timing.event(file, 'joined', consumerEntry: entry);
      return job;
    }
    timing.begin(file, entry: entry);
    final generation = _images.contains(file.path) ? null : _generation;
    final job = Future<Uri>.microtask(() => _ensureFile(file, generation));
    _fileJobs[file.path] = job;
    job.then<void>(
      (_) {
        _fileJobs.remove(file.path);
        if (!_contentJobs.containsKey(file.sha256)) {
          _priorityContent.remove(file.sha256);
        }
      },
      onError: (Object _, StackTrace _) {
        _fileJobs.remove(file.path);
        if (!_contentJobs.containsKey(file.sha256)) {
          _priorityContent.remove(file.sha256);
        }
      },
    );
    return job;
  }

  Future<Uri> _ensureFile(coach.PoseHubPackFile file, int? generation) async {
    // Content aliases may be the source of materialize(), so keep them alive
    // until this request has finished copying and publishing its own path.
    final releases = [
      for (final alias in _filesForHash[file.sha256]!)
        if (_videos.contains(alias.path)) store.retainVideo(alias),
    ];
    try {
      _check(generation);
      _set(file, PoseHubDownloadPhase.checking);
      timing.event(file, 'cache_lookup');
      final cached = await store.cached(file);
      _check(generation);
      if (cached != null) {
        _set(file, PoseHubDownloadPhase.ready, received: file.bytes);
        timing.end(file, result: 'cache');
        return cached;
      }
      final content = await _content(file, generation);
      _check(generation);
      _set(file, PoseHubDownloadPhase.verifying, received: file.bytes);
      timing.event(file, 'materialize_start', source: 'publish');
      final uri = await store.materialize(file, content);
      _check(generation);
      _set(file, PoseHubDownloadPhase.ready, received: file.bytes);
      timing.end(file, result: 'ok');
      return uri;
    } catch (error) {
      final safe = _safeError(error);
      _set(file, PoseHubDownloadPhase.failed, error: safe);
      timing.end(file, result: 'failed', code: safe.code);
      throw safe;
    } finally {
      for (final release in releases) {
        release();
      }
    }
  }

  Future<Uri> _content(coach.PoseHubPackFile file, int? generation) {
    if (_contentJobs[file.sha256] case final job?) {
      timing.event(file, 'content_joined', source: 'cache');
      return job;
    }
    final job = Future<Uri>.microtask(() => _prepareContent(file, generation));
    _contentJobs[file.sha256] = job;
    job.then<void>(
      (_) {
        _contentJobs.remove(file.sha256);
        _priorityContent.remove(file.sha256);
      },
      onError: (Object _, StackTrace _) {
        _contentJobs.remove(file.sha256);
        _priorityContent.remove(file.sha256);
      },
    );
    return job;
  }

  Future<void> _acquire(coach.PoseHubPackFile file, int? generation) async {
    _check(generation);
    if (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      final entry = (
        ready: waiter,
        generation: generation,
        contentKey: file.sha256,
      );
      if (_priorityContent.contains(file.sha256)) {
        _queue.insert(0, entry);
      } else {
        _queue.add(entry);
      }
      await waiter.future;
    } else {
      _active++;
    }
  }

  void _release() {
    if (_queue.isEmpty) {
      _active--;
    } else {
      _queue.removeAt(0).ready.complete();
    }
  }

  Future<Uri> _prepareContent(
    coach.PoseHubPackFile file,
    int? generation,
  ) async {
    _contentState(file, PoseHubDownloadPhase.queued);
    timing.event(
      file,
      'enqueued',
      queueDepth: _queue.length,
      activeSlots: _active,
    );
    await _acquire(file, generation);
    timing.event(
      file,
      'slot_acquired',
      queueDepth: _queue.length,
      activeSlots: _active,
    );
    try {
      _check(generation);
      _contentState(file, PoseHubDownloadPhase.checking);
      final reusable = await store.reusable(file);
      _check(generation);
      if (reusable != null) {
        timing.event(file, 'reusable', source: 'cache');
        return reusable;
      }
      void progress(int n) =>
          _contentState(file, PoseHubDownloadPhase.downloading, received: n);
      void verifying() => _contentState(
        file,
        PoseHubDownloadPhase.verifying,
        received: file.bytes,
      );
      if (_images.contains(file.path) && loadBundle != null) {
        timing.event(file, 'bundle_lookup', source: 'bundle');
        final bytes = await loadBundle!(file).timeout(timeout);
        _check(generation);
        if (bytes != null) {
          return await store.bundled(file, bytes, progress, verifying);
        }
      }
      if (bases.isEmpty) {
        throw const PoseHubMediaException(
          'not_configured',
          'Media download is not configured yet.',
        );
      }
      Object? failure;
      var baseIndex = 0;
      for (final base in bases) {
        _check(generation);
        _contentState(file, PoseHubDownloadPhase.downloading);
        timing.event(
          file,
          'attempt',
          baseIndex: baseIndex,
          retry: baseIndex,
          source: 'network',
        );
        try {
          return await store.download(
            file,
            base.resolve(file.path),
            progress,
            verifying,
          );
        } catch (error) {
          timing.event(
            file,
            'attempt_failed',
            result: 'failed',
            errorCode: _safeError(error).code,
          );
          // A disposed consumer does not start a new mirror request. Each
          // failed transport has already closed and removed its own temp file.
          _check(generation);
          if (error is PoseHubMediaException && error.code == 'cache_full') {
            rethrow;
          }
          failure = error;
        }
        baseIndex++;
      }
      throw _safeError(failure!);
    } finally {
      _release();
    }
  }

  @override
  Future<Uri> ensureAction(String actionId) {
    coach.PoseHubPackAction action;
    try {
      action = _action(actionId);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    if (_clearing case final barrier?) {
      return _afterClear(
        _afterClearActions,
        actionId,
        barrier,
        () => ensureAction(actionId),
      );
    }
    if (_actionJobs[actionId] case final job?) return job;
    final job = Future.wait(
      action.files.values.map(ensureFile),
      eagerError: true,
    ).then((_) => mediaBaseUri);
    _actionJobs[actionId] = job;
    job.then<void>(
      (_) {
        _actionJobs.remove(actionId);
      },
      onError: (Object _, StackTrace _) {
        _actionJobs.remove(actionId);
      },
    );
    return job;
  }

  Future<Uri> _afterClear(
    Map<String, Future<Uri>> waiting,
    String key,
    Future<void> barrier,
    Future<Uri> Function() start,
  ) {
    if (waiting[key] case final existing?) return existing;
    late Future<Uri> next;
    void forget() {
      if (identical(waiting[key], next)) waiting.remove(key);
    }

    next = barrier.then((_) {
      forget();
      return start();
    });
    waiting[key] = next;
    next.then<void>(
      (_) => forget(),
      onError: (Object _, StackTrace _) => forget(),
    );
    return next;
  }

  @override
  Future<Uri?> cachedVideo(String actionId) async {
    final video = _action(actionId).video;
    await _clearing;
    _check();
    final uri = await store.cached(video);
    _check();
    _set(
      video,
      uri == null ? PoseHubDownloadPhase.idle : PoseHubDownloadPhase.ready,
      received: uri == null ? 0 : video.bytes,
    );
    return uri;
  }

  @override
  void Function() retainVideo(String actionId) =>
      store.retainVideo(_action(actionId).video);

  @override
  Future<int> videoCacheBytes() async {
    _check();
    await _clearing;
    _check();
    return store.videoCacheBytes();
  }

  @override
  Future<void> clearVideoCache() {
    try {
      _check();
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    if (_clearing case final existing?) return existing;
    final job = Future<void>.microtask(_clearVideos);
    _clearing = job;
    job.then<void>(
      (_) {
        _clearing = null;
      },
      onError: (Object _, StackTrace _) {
        _clearing = null;
      },
    );
    return job;
  }

  Future<void> _clearVideos() async {
    // SDK TrainingMediaRepository uses the same retire/cancel/await ordering.
    // Here the retirement and filesystem deletion are scoped to videos only.
    _generation++;
    final old = [
      for (final entry in _fileJobs.entries)
        if (!_images.contains(entry.key)) entry.value,
    ];
    final queuedVideos = _queue
        .where((entry) => entry.generation != null)
        .toList();
    _queue.removeWhere((entry) => entry.generation != null);
    for (final queued in queuedVideos) {
      queued.ready.completeError(
        const PoseHubMediaException(
          'cache_cleared',
          'Video preparation stopped while its cache was cleared.',
        ),
      );
    }
    store.cancelVideoDownloads();
    await Future.wait(
      old.map(
        (job) => job.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
    _check();
    await store.clearVideoCache();
    _check();
    for (final action in catalog.allActions) {
      if (_fileStates.containsKey(action.video.path)) {
        _set(action.video, PoseHubDownloadPhase.idle);
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    store.dispose();
    for (final queued in _queue) {
      queued.ready.completeError(
        const PoseHubMediaException('disposed', 'Media preparation stopped.'),
      );
    }
    _queue.clear();
    _priorityContent.clear();
    _afterClearPriority.clear();
    for (final state in [..._fileStates.values, ..._actionStates.values]) {
      state.dispose();
    }
  }
}

PoseHubMediaException _safeError(Object error) {
  if (error is PoseHubMediaException) return error;
  if (error is TimeoutException) {
    return const PoseHubMediaException('timeout', 'Media request timed out.');
  }
  return const PoseHubMediaException(
    'unavailable',
    'Media is unavailable. Please retry.',
  );
}
