import 'dart:typed_data';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart'
    show CatalogMediaTiming, CatalogMediaTimingCallback;

import '../diagnostics/runtime_log.dart';

/// Optional diagnostics capability; marking an entry never starts media work.
abstract interface class PoseHubMediaTimingAnchor {
  void markTrainingEntry();
}

/// Opt-in training path. Ordinary file/action callers retain their FIFO order.
abstract interface class PoseHubTrainingVideoPreparation {
  Future<Uri> ensureVideo(String actionId, {bool priority = false});
}

/// Entry-aware callers opt in without changing older repository fakes.
abstract interface class PoseHubMediaEntryPreparation {
  void markMediaEntry(String entry);
  Future<Uri> ensureVideoForEntry(
    String actionId, {
    required String entry,
    bool priority = false,
  });
}

final _hostTimingFields = Expando<Map<String, Object?>>();

/// Adds only Host task/entry identity to the unchanged SDK terminal record.
Map<String, Object?> poseHubMediaTimingFields(CatalogMediaTiming timing) => {
  ...timing.toFields(),
  ...?_hostTimingFields[timing],
};

String _safeMediaEntry(String entry) =>
    RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(entry) ? entry : 'unknown';

/// Request milestones only: no URI, path, headers or exception text is logged.
class PoseHubMediaTiming {
  PoseHubMediaTiming(coach.PoseHubAppTestCatalog catalog, {this.onTiming})
    : _log = RuntimeLog.instance {
    if (!_enabled) return;
    for (final action in catalog.allActions) {
      for (final entry in action.files.entries) {
        _owners.putIfAbsent(
          entry.value.path,
          () => (actionId: action.id, kind: entry.key),
        );
      }
    }
  }

  final RuntimeLog _log;
  final CatalogMediaTimingCallback? onTiming;
  bool get _enabled => _log.enabled || onTiming != null;
  final _clock = Stopwatch()..start();
  final _owners = <String, ({String actionId, String kind})>{};
  final _tasks = <String, _MediaTimingTask>{};
  final _entryAnchors = <String, ({String id, int at})>{};
  String _currentEntry = 'background';

  void markTrainingEntry() => markMediaEntry('training');

  void markMediaEntry(String entry) {
    if (!_enabled) return;
    _currentEntry = _safeMediaEntry(entry);
    _entryAnchors[_currentEntry] = (
      id: _log.newOperation('media-entry'),
      at: _clock.elapsedMilliseconds,
    );
    repository('entry');
  }

  void repository(String phase, {String? result, String? errorCode}) {
    if (!_enabled) return;
    final anchor = _entryAnchors[_currentEntry];
    _record({
      'actionId': 'repository',
      'kind': 'repository',
      'bytes': 0,
      'phase': phase,
      'elapsedMs': _clock.elapsedMilliseconds,
      'entry': _currentEntry,
      'entryId': ?anchor?.id,
      if (anchor != null)
        'sinceEntryMs': _clock.elapsedMilliseconds - anchor.at,
      'result': ?result,
      'errorCode': ?errorCode,
    }, anchor?.id);
  }

  void begin(coach.PoseHubPackFile file, {String entry = 'background'}) {
    if (!_enabled) return;
    final sourceEntry = _safeMediaEntry(entry);
    _tasks[file.path] = _MediaTimingTask(
      _log.newOperation('media'),
      _clock.elapsedMilliseconds,
      sourceEntry,
      _entryAnchors[sourceEntry],
    );
    event(file, 'issued');
  }

  void event(
    coach.PoseHubPackFile file,
    String phase, {
    int? receivedBytes,
    int? queueDepth,
    int? activeSlots,
    int? baseIndex,
    int? retry,
    int? httpStatus,
    String? source,
    String? result,
    String? errorCode,
    String? consumerEntry,
  }) {
    final task = _tasks[file.path];
    final owner = _owners[file.path];
    if (task == null || owner == null) return;
    final entry = consumerEntry == null
        ? task.entry
        : _safeMediaEntry(consumerEntry);
    final anchor = consumerEntry == null ? task.anchor : _entryAnchors[entry];
    task.baseIndex = baseIndex ?? task.baseIndex;
    task.retry = retry ?? task.retry;
    final now = DateTime.now().toUtc();
    switch (phase) {
      case 'enqueued':
        task.enqueuedAt = now;
      case 'slot_acquired':
        task.acquiredAt = now;
      case 'attempt':
        task.requestStartedAt = null;
        task.firstByteAt = null;
        task.downloadCompletedAt = null;
        task.verifiedAt = null;
      case 'http_request':
        task.requestStartedAt = now;
      case 'first_byte':
        task.firstByteAt = now;
      case 'body_complete':
        task.downloadCompletedAt = now;
      case 'verify_end':
        task.verifiedAt = now;
    }
    if (source == 'network' ||
        (source == 'bundle' && task.source != 'network')) {
      task.source = source;
    }
    _record({
      'taskId': task.id,
      'entry': entry,
      'entryId': ?anchor?.id,
      'actionId': owner.actionId,
      'kind': owner.kind,
      'bytes': file.bytes,
      'receivedBytes': ?receivedBytes,
      'phase': phase,
      'elapsedMs': _clock.elapsedMilliseconds - task.startedAt,
      if (anchor != null)
        'sinceEntryMs': _clock.elapsedMilliseconds - anchor.at,
      'queueDepth': ?queueDepth,
      'activeSlots': ?activeSlots,
      'baseIndex': task.baseIndex == null ? null : task.baseIndex! + 1,
      'retry': ?task.retry,
      'httpStatus': ?httpStatus,
      'source': ?source,
      'result': ?result,
      'errorCode': ?errorCode,
    }, task.id);
  }

  void end(coach.PoseHubPackFile file, {required String result, String? code}) {
    event(file, 'complete', result: result, errorCode: code);
    final task = _tasks.remove(file.path);
    final owner = _owners[file.path];
    if (task == null || owner == null || onTiming == null) return;
    try {
      final record = CatalogMediaTiming(
        actionId: owner.actionId,
        kind: owner.kind,
        bytes: file.bytes,
        enqueuedAt: task.enqueuedAt,
        acquiredAt: task.acquiredAt,
        requestStartedAt: task.requestStartedAt,
        firstByteAt: task.firstByteAt,
        downloadCompletedAt: task.downloadCompletedAt,
        verifiedAt: task.verifiedAt,
        completedAt: DateTime.now().toUtc(),
        baseIndex: task.baseIndex == null ? null : task.baseIndex! + 1,
        retries: task.retry ?? 0,
        result: result == 'failed' ? 'failed' : 'ready',
        source: result == 'cache' ? 'cache' : task.source ?? 'cache',
        code: code,
      );
      _hostTimingFields[record] = Map.unmodifiable({
        'taskId': task.id,
        'entry': task.entry,
        'entryId': ?task.anchor?.id,
        if (task.anchor case final anchor?)
          'sinceEntryMs': _clock.elapsedMilliseconds - anchor.at,
      });
      onTiming?.call(record);
    } catch (_) {
      // The optional SDK-typed observer cannot fail the media request.
    }
  }

  void _record(Map<String, Object?> fields, String? operation) {
    try {
      _log.record('media.timing', fields: fields, operation: operation);
    } catch (_) {
      // A diagnostic failure cannot change a media result or queue ownership.
    }
  }
}

class _MediaTimingTask {
  _MediaTimingTask(this.id, this.startedAt, this.entry, this.anchor)
    : enqueuedAt = DateTime.now().toUtc();
  final String id;
  final int startedAt;
  final String entry;
  final ({String id, int at})? anchor;
  int? baseIndex;
  int? retry;
  DateTime enqueuedAt;
  DateTime? acquiredAt,
      requestStartedAt,
      firstByteAt,
      downloadCompletedAt,
      verifiedAt;
  String? source;
}

enum PoseHubDownloadPhase {
  idle,
  queued,
  checking,
  downloading,
  verifying,
  ready,
  failed,
}

class PoseHubDownloadState {
  const PoseHubDownloadState({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final PoseHubDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final Object? error;
  int get bytes => receivedBytes;
  int get total => totalBytes;
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Receives the original path and expected SHA. Videos never use this loader.
typedef PoseHubBundledFileLoader =
    Future<Uint8List?> Function(coach.PoseHubPackFile file);

/// Messages deliberately contain no request URI, redirect signature or headers.
class PoseHubMediaException implements Exception {
  const PoseHubMediaException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Optional settings capability for the App's shared published-video budget.
/// Images, partial downloads, unknown files and playing videos are preserved.
abstract interface class PoseHubVideoCache {
  /// Shared published-video budget, including preserved unknown legacy SHA
  /// objects conservatively. Image paths and unfinished downloads are excluded.
  Future<int> videoCacheBytes();
  Future<void> clearVideoCache();
}

const poseHubVideoCacheLimitBytes = 300000000;

/// Trusted legacy descriptor. The old SDK stores this video at version/SHA.
class PoseHubLegacyVideoFile {
  const PoseHubLegacyVideoFile({
    required this.version,
    required this.bytes,
    required this.sha256,
  });

  final String version;
  final int bytes;
  final String sha256;
}

/// Optional playback capability; older repository fakes need not implement it.
abstract interface class PoseHubVideoCacheAccess {
  /// Validates a published video and records its use, without downloading.
  Future<Uri?> cachedVideo(String actionId);

  /// Protects a video before asynchronous preparation/playback begins. Release
  /// after the decoder is disposed; repeated release calls have no effect.
  void Function() retainVideo(String actionId);
}

/// Internal platform boundary, so the public service also compiles for Web.
abstract interface class PoseHubMediaFileStore {
  Uri get mediaBaseUri;
  Future<Uri?> cached(coach.PoseHubPackFile file);
  Future<Uri?> reusable(coach.PoseHubPackFile file);
  void Function() retainVideo(coach.PoseHubPackFile file);
  Future<Uri> bundled(
    coach.PoseHubPackFile file,
    Uint8List bytes,
    void Function(int) onProgress,
    void Function() onVerifying,
  );
  Future<Uri> download(
    coach.PoseHubPackFile file,
    Uri url,
    void Function(int) onProgress,
    void Function() onVerifying,
  );
  Future<Uri> materialize(coach.PoseHubPackFile file, Uri source);
  void cancelVideoDownloads();
  Future<int> videoCacheBytes();
  Future<void> clearVideoCache();
  void dispose();
}
