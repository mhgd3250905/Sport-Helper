import 'dart:async';

import 'package:ugk_trainer/ugk_trainer.dart';

import 'runtime_log.dart';

/// Observes the shared repository without affecting downloads or validation.
/// Byte updates are sampled, while all policy/phase changes are retained.
class TrainingMediaLog {
  TrainingMediaLog(this.repository, {RuntimeLog? log})
    : _log = log ?? RuntimeLog.instance;

  final TrainingMediaRepository repository;
  final RuntimeLog _log;
  final _phases = <String, TrainingMediaPhase>{};
  Timer? _progress;
  bool _started = false;
  bool? _offline;
  bool? _wifiOnly;
  int? _cacheRevision;
  late final String _operation;

  void start() {
    if (_started || !_log.enabled) return;
    _started = true;
    _operation = _log.newOperation('media');
    repository.addListener(_changed);
    _changed();
    _progress = Timer.periodic(const Duration(seconds: 30), (_) => _sample());
  }

  void _record(String event, Map<String, Object?> fields) =>
      _log.record(event, fields: fields, operation: _operation);

  void _changed() {
    if (!_started) return;
    if (_offline != repository.isOffline || _wifiOnly != repository.wifiOnly) {
      _offline = repository.isOffline;
      _wifiOnly = repository.wifiOnly;
      _record('media.network_policy', {
        'offline': _offline,
        'wifiOnly': _wifiOnly,
      });
    }
    if (_cacheRevision != repository.cacheRevision) {
      if (_cacheRevision != null) {
        _record('media.cache.invalidated', {'kind': 'cache_revision'});
      }
      _cacheRevision = repository.cacheRevision;
      _phases.clear();
    }
    for (final id in [
      ...repository.manifest.actions.map((action) => action.id),
      ...repository.manifest.packages.keys,
    ]) {
      final state = repository.stateFor(id);
      final before = _phases[id];
      if (before == state.phase) continue;
      _phases[id] = state.phase;
      if (state.phase == TrainingMediaPhase.idle) continue;
      final downloaded =
          before == TrainingMediaPhase.downloading ||
          before == TrainingMediaPhase.queued;
      _record('media.resource.state', {
        'actionId': id,
        'kind': repository.manifest.packages.containsKey(id)
            ? 'package'
            : 'video',
        'phase': state.phase.name,
        'bytes': state.receivedBytes,
        'totalBytes': state.totalBytes,
        if (state.phase == TrainingMediaPhase.ready) ...{
          if (downloaded) 'verified': true,
          'source': downloaded
              ? 'download'
              : repository.manifest.packages['builtin']?.actionIds.contains(
                      id,
                    ) ==
                    true
              ? 'builtin'
              : 'available',
        },
        if (state.error != null) 'reason': failureReason(state.error),
      });
    }
  }

  void _sample() {
    var downloading = 0;
    var bytes = 0;
    var total = 0;
    for (final id in _phases.keys) {
      final state = repository.stateFor(id);
      if (state.phase != TrainingMediaPhase.downloading &&
          state.phase != TrainingMediaPhase.queued) {
        continue;
      }
      downloading++;
      bytes += state.receivedBytes;
      total += state.totalBytes;
    }
    if (downloading > 0) {
      _record('media.download.progress', {
        'count': downloading,
        'bytes': bytes,
        'totalBytes': total,
      });
    }
  }

  /// Repository errors can include URLs and paths. Only fixed classifications
  /// leave this boundary; the original message is never recorded.
  static String failureReason(String? error) {
    if (error == null) return 'unknown';
    if (error.contains('SHA-256')) return 'checksum_failed';
    if (error.contains('TimeoutException')) return 'timeout';
    if (error.contains('No network connection')) return 'offline';
    if (error.contains('Waiting for Wi-Fi')) return 'wifi_required';
    if (error.contains('Download cancelled')) return 'cancelled';
    if (error.contains('size/status mismatch')) return 'http_status_or_size';
    if (error.contains('declared size')) return 'size_mismatch';
    if (error.contains('index mismatch')) return 'manifest_invalid';
    return 'download_or_validation_failed';
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _progress?.cancel();
    repository.removeListener(_changed);
  }
}
