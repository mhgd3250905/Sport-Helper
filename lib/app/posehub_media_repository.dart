import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'posehub_media_repository_stub.dart'
    if (dart.library.io) 'posehub_media_repository_io.dart'
    as platform;
import 'posehub_media_repository_types.dart';

export 'posehub_media_repository_types.dart'
    show
        PoseHubBundledFileLoader,
        PoseHubDownloadPhase,
        PoseHubDownloadState,
        PoseHubMediaException;

abstract interface class PoseHubMediaRepository {
  static Future<PoseHubMediaRepository> create({
    required coach.PoseHubAppTestCatalog catalog,
    required String catalogRevision,
    required List<Uri> mediaBaseUrls,
    String packVersion = 'r1-v3',
    String? rootDirectory,
    PoseHubBundledFileLoader? bundledFileLoader,
  }) => _create(
    catalog: catalog,
    catalogRevision: catalogRevision,
    mediaBaseUrls: mediaBaseUrls,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    bundledFileLoader: bundledFileLoader,
  );

  @visibleForTesting
  static Future<PoseHubMediaRepository> forTesting({
    required coach.PoseHubAppTestCatalog catalog,
    required String catalogRevision,
    required List<Uri> mediaBaseUrls,
    String packVersion = 'r1-v3',
    required String rootDirectory,
    PoseHubBundledFileLoader? bundledFileLoader,
    bool allowInsecureLocalhost = false,
    Duration timeout = const Duration(seconds: 15),
    Duration progressInterval = const Duration(milliseconds: 100),
    int maxConcurrent = 3,
    int maxRedirects = 5,
  }) => _create(
    catalog: catalog,
    catalogRevision: catalogRevision,
    mediaBaseUrls: mediaBaseUrls,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    bundledFileLoader: bundledFileLoader,
    allowInsecureLocalhost: allowInsecureLocalhost,
    timeout: timeout,
    progressInterval: progressInterval,
    maxConcurrent: maxConcurrent,
    maxRedirects: maxRedirects,
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
  bool allowInsecureLocalhost = false,
  Duration timeout = const Duration(seconds: 15),
  Duration progressInterval = const Duration(milliseconds: 100),
  int maxConcurrent = 3,
  int maxRedirects = 5,
}) async {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(catalogRevision) ||
      !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(packVersion) ||
      packVersion.length > 64 ||
      timeout <= Duration.zero ||
      progressInterval < Duration.zero ||
      maxConcurrent < 1 ||
      maxConcurrent > 3 ||
      maxRedirects < 0 ||
      maxRedirects > 8) {
    throw const FormatException('Invalid media repository configuration.');
  }
  final files = {
    for (final action in catalog.allActions)
      for (final file in action.files.values) file.path: file,
  };
  final bases = List<Uri>.unmodifiable(mediaBaseUrls);
  final store = await platform.createPoseHubMediaStore(
    revision: catalogRevision,
    packVersion: packVersion,
    rootDirectory: rootDirectory,
    files: files.values.toList(),
    mediaBaseUrls: bases,
    allowInsecureLocalhost: allowInsecureLocalhost,
    timeout: timeout,
    maxRedirects: maxRedirects,
  );
  return _Repository(
    catalog,
    files,
    store,
    bases,
    bundledFileLoader,
    timeout,
    progressInterval,
    maxConcurrent,
  );
}

class _Repository implements PoseHubMediaRepository {
  _Repository(
    this.catalog,
    this.files,
    this.store,
    this.bases,
    this.loadBundle,
    this.timeout,
    this.progressInterval,
    this.maxConcurrent,
  ) {
    for (final action in catalog.allActions) {
      for (final role in action.files.entries) {
        final file = role.value;
        (_actionsForFile[file.path] ??= {}).add(action.id);
        (_filesForHash[file.sha256] ??= []).add(file);
        if (role.key != 'video') _images.add(file.path);
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
  final _fileJobs = <String, Future<Uri>>{};
  final _contentJobs = <String, Future<Uri>>{};
  final _actionJobs = <String, Future<Uri>>{};
  final _fileStates = <String, ValueNotifier<PoseHubDownloadState>>{};
  final _actionStates = <String, ValueNotifier<PoseHubDownloadState>>{};
  final _actionsForFile = <String, Set<String>>{};
  final _filesForHash = <String, List<coach.PoseHubPackFile>>{};
  final _images = <String>{};
  final _lastProgress = <String, DateTime>{};
  final _queue = <Completer<void>>[];
  int _active = 0;
  bool _disposed = false;

  @override
  Uri get mediaBaseUri => store.mediaBaseUri;

  void _check() {
    if (_disposed) {
      throw const PoseHubMediaException(
        'disposed',
        'Media preparation stopped.',
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
  Future<Uri> ensureFile(coach.PoseHubPackFile file) {
    try {
      file = _known(file);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    if (_fileJobs[file.path] case final job?) return job;
    final job = Future<Uri>.microtask(() => _ensureFile(file));
    _fileJobs[file.path] = job;
    job.then<void>(
      (_) {
        _fileJobs.remove(file.path);
      },
      onError: (Object _, StackTrace _) {
        _fileJobs.remove(file.path);
      },
    );
    return job;
  }

  Future<Uri> _ensureFile(coach.PoseHubPackFile file) async {
    try {
      _set(file, PoseHubDownloadPhase.checking);
      final cached = await store.cached(file);
      _check();
      if (cached != null) {
        _set(file, PoseHubDownloadPhase.ready, received: file.bytes);
        return cached;
      }
      final content = await _content(file);
      _check();
      _set(file, PoseHubDownloadPhase.verifying, received: file.bytes);
      final uri = await store.materialize(file, content);
      _check();
      _set(file, PoseHubDownloadPhase.ready, received: file.bytes);
      return uri;
    } catch (error) {
      final safe = _safeError(error);
      _set(file, PoseHubDownloadPhase.failed, error: safe);
      throw safe;
    }
  }

  Future<Uri> _content(coach.PoseHubPackFile file) {
    if (_contentJobs[file.sha256] case final job?) return job;
    final job = Future<Uri>.microtask(() => _prepareContent(file));
    _contentJobs[file.sha256] = job;
    job.then<void>(
      (_) {
        _contentJobs.remove(file.sha256);
      },
      onError: (Object _, StackTrace _) {
        _contentJobs.remove(file.sha256);
      },
    );
    return job;
  }

  Future<void> _acquire() async {
    _check();
    if (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      _queue.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
  }

  void _release() {
    if (_queue.isEmpty) {
      _active--;
    } else {
      _queue.removeAt(0).complete();
    }
  }

  Future<Uri> _prepareContent(coach.PoseHubPackFile file) async {
    _contentState(file, PoseHubDownloadPhase.queued);
    await _acquire();
    try {
      _check();
      _contentState(file, PoseHubDownloadPhase.checking);
      final reusable = await store.reusable(file);
      _check();
      if (reusable != null) return reusable;
      void progress(int n) =>
          _contentState(file, PoseHubDownloadPhase.downloading, received: n);
      void verifying() => _contentState(
        file,
        PoseHubDownloadPhase.verifying,
        received: file.bytes,
      );
      if (_images.contains(file.path) && loadBundle != null) {
        final bytes = await loadBundle!(file).timeout(timeout);
        _check();
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
      for (final base in bases) {
        _check();
        _contentState(file, PoseHubDownloadPhase.downloading);
        try {
          return await store.download(
            file,
            base.resolve(file.path),
            progress,
            verifying,
          );
        } catch (error) {
          // A disposed consumer does not start a new mirror request. Each
          // failed transport has already closed and removed its own temp file.
          _check();
          failure = error;
        }
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    store.dispose();
    for (final queued in _queue) {
      queued.completeError(
        const PoseHubMediaException('disposed', 'Media preparation stopped.'),
      );
    }
    _queue.clear();
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
