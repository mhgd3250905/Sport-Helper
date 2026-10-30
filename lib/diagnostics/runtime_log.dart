import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../app/training_transition_activity.dart';
import '../core/storage/local_state_storage.dart';
import '../app/build_info.dart';
import 'developer_log_sanitizer.dart';
import 'runtime_log_storage.dart' show runtimeLogStorageKey;
import 'session_snapshot_archive.dart';

/// A sendable, storage-free request. The sanitizer contains only Dart values;
/// its credentials are used for redaction and never added to the JSON envelope.
String encodeRuntimeLogSnapshot(Map<String, Object?> request) {
  final snapshot = request['snapshot']! as Map<String, Object?>;
  final sanitizer = request['sanitizer']! as DeveloperLogSanitizer;
  return jsonEncode({
    ...snapshot,
    'events': sanitizer.sanitize(snapshot['events']),
  });
}

Future<String> _encodeRuntimeLogInBackground(Map<String, Object?> request) =>
    compute(
      encodeRuntimeLogSnapshot,
      request,
      debugLabel: 'runtime-log.encode',
    );

/// Bounded developer diagnostics; detailed chat/tool data uses an explicit API.
/// Production releases cannot enable this with the debug logging define.
class RuntimeLog {
  RuntimeLog({
    required this.enabled,
    this.storage,
    this.maxEntries = 1500,
    this.maxBytes = 512 * 1024,
    Iterable<String> secrets = const [],
    SessionSnapshotArchive? snapshotArchive,
    DateTime Function()? clock,
    Future<String> Function(Map<String, Object?>)? encode,
  }) : _clock = clock ?? DateTime.now,
       _sanitizer = DeveloperLogSanitizer(secrets),
       _encode = encode ?? _encodeRuntimeLogInBackground,
       _snapshotArchive = snapshotArchive ?? createSessionSnapshotArchive();

  static const buildEnabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' ||
      (kDebugMode && bool.fromEnvironment('SMARTFIT_RUNTIME_LOGS'));
  static RuntimeLog instance = RuntimeLog(enabled: false);
  static const storageKey = runtimeLogStorageKey;
  final bool enabled;
  final int maxEntries;
  final int maxBytes;
  final LocalStateStorage? storage;
  final DateTime Function() _clock;
  final DeveloperLogSanitizer _sanitizer;
  final Future<String> Function(Map<String, Object?>) _encode;
  final SessionSnapshotArchive _snapshotArchive;
  final _uptime = Stopwatch()..start();
  final List<Map<String, Object?>> _entries = [];
  late final _session = _clock().toUtc().microsecondsSinceEpoch.toRadixString(
    36,
  );
  int _sequence = 0;
  int _operationSequence = 0;
  int _bytes = 0;
  int _revision = 0;
  int _savedRevision = 0;
  int _redactionEpoch = 0;
  Future<void>? _writing;
  bool _automaticFlushQueued = false;
  bool persistenceFailed = false;
  bool _writeFailureRecorded = false;

  int get entryCount => _entries.length;
  int get usedBytes => _bytes;

  // No unrestricted strings, nested payloads, messages, headers, URLs or stacks.
  static const _fields = {
    'reason',
    'status',
    'phase',
    'source',
    'model',
    'kind',
    'code',
    'errorType',
    'actionId',
    'step',
    'attempt',
    'elapsedMs',
    'count',
    'bytes',
    'totalBytes',
    'completed',
    'total',
    'durationMs',
    'positionMs',
    'itemIndex',
    'inputChars',
    'hasPlan',
    'hasActions',
    'enabled',
    'available',
    'offline',
    'wifiOnly',
    'success',
    'paused',
    'remainingSeconds',
    'voice',
    'chimes',
    'cacheVersion',
    'verified',
    'route',
    'promptTokens',
    'completionTokens',
    'reasoningTokens',
    'steps',
    'submissions',
    'reads',
    'httpStatus',
    'hasKey',
    'hasDeviceIdentity',
    'catalogCount',
    'version',
    'versionName',
    'buildNumber',
    'flavor',
    'platform',
    'state',
    'operationId',
    'feeling',
  };
  static const _feelingValues = {
    'easy',
    'justRight',
    'tired',
    'uncomfortable',
    'unselected',
  };
  static final _token = RegExp(r'^[A-Za-z0-9_.+\-]{1,96}$');
  static final _event = RegExp(r'^[a-z][a-z0-9_.]{0,63}$');
  static const _developerEvents = {
    'chat.user',
    'ai.tool.requested',
    'ai.tool.result',
    'ai.agent.event',
    'chat.session.archived',
  };

  static String errorType(Object error) {
    final name = error.runtimeType.toString();
    return _token.hasMatch(name) ? name : 'Error';
  }

  /// Preserve a machine error code and a fixed classification, never the
  /// native message/details (which can contain paths or preference contents).
  static Map<String, Object?> errorFields(Object error) {
    final fields = <String, Object?>{'errorType': errorType(error)};
    if (error is PlatformException) {
      fields['code'] = _safeToken(error.code) ?? 'platform_error';
      final message = error.message ?? '';
      if (message.contains('NoSuchMethodError')) {
        fields['reason'] = 'jni_method_lookup_failed';
      } else if (message.contains('ClassNotFoundException') ||
          message.contains('NoClassDefFoundError')) {
        fields['reason'] = 'jni_class_lookup_failed';
      }
    }
    return fields;
  }

  Map<String, Object?> _safeFields(Map fields) => {
    for (final entry in fields.entries)
      if (_fields.contains(entry.key) &&
          (entry.key != 'feeling' || _feelingValues.contains(entry.value)) &&
          (entry.value is bool ||
              entry.value is int ||
              (entry.value is double && (entry.value as double).isFinite) ||
              (entry.value is String && _token.hasMatch(entry.value))))
        entry.key as String: entry.value,
  };

  Future<void> initialize() async {
    if (!enabled) return;
    try {
      final raw = await storage?.read(storageKey);
      if (raw != null && raw.length <= maxBytes * 2) {
        final saved = jsonDecode(raw);
        if (saved is Map && saved['schema'] == 1 && saved['events'] is List) {
          for (final event in saved['events'] as List) {
            if (event is! Map || !_event.hasMatch('${event['event']}')) {
              continue;
            }
            final at = DateTime.tryParse('${event['at']}');
            if (at == null ||
                _clock().toUtc().difference(at) > const Duration(days: 7)) {
              continue;
            }
            _append({
              'at': at.toUtc().toIso8601String(),
              'session': _safeToken(event['session']) ?? 'previous',
              'seq': event['seq'] is int ? event['seq'] : 0,
              'sinceStartMs': event['sinceStartMs'] is int
                  ? event['sinceStartMs']
                  : 0,
              'event': event['event'],
              'operation': ?_safeToken(event['operation']),
              'fields': _safeFields(
                event['fields'] is Map ? event['fields'] : {},
              ),
              if (_developerEvents.contains(event['event']) &&
                  event['data'] is Map)
                'data': _sanitizer.sanitize(event['data']),
            });
          }
        }
      }
    } on Object catch (error) {
      persistenceFailed = true;
      record('diagnostics.storage_read_failed', fields: errorFields(error));
    }
  }

  static String? _safeToken(Object? value) =>
      value is String && _token.hasMatch(value) ? value : null;

  String newOperation(String kind) =>
      '${_safeToken(kind) ?? 'op'}-$_session-${++_operationSequence}';

  /// Synchronous and never waits on disk/network or changes the caller's result.
  void record(
    String event, {
    Map<String, Object?> fields = const {},
    String? operation,
  }) {
    if (!enabled || !_event.hasMatch(event)) return;
    _append({
      'at': _clock().toUtc().toIso8601String(),
      'session': _session,
      'seq': ++_sequence,
      'sinceStartMs': _uptime.elapsedMilliseconds,
      'event': event,
      'operation': ?_safeToken(operation),
      'fields': _safeFields(fields),
    });
    _revision++;
    _scheduleFlush();
  }

  /// This is never shown in the conversation UI and is disabled with the log.
  void recordDeveloper(
    String event, {
    Map<String, Object?> data = const {},
    Map<String, Object?> fields = const {},
    String? operation,
  }) {
    if (!enabled || !_developerEvents.contains(event)) return;
    _append({
      'at': _clock().toUtc().toIso8601String(),
      'session': _session,
      'seq': ++_sequence,
      'sinceStartMs': _uptime.elapsedMilliseconds,
      'event': event,
      'operation': ?_safeToken(operation),
      'fields': _safeFields(fields),
      'data': _sanitizer.sanitize(data),
    });
    _revision++;
    _scheduleFlush();
  }

  /// Credentials are only used for redaction, never included in output.
  void protectSecret(String secret) {
    if (secret.isEmpty) return;
    _sanitizer.protect(secret);
    _redactionEpoch++;
    if (enabled) {
      _revision++;
      _scheduleFlush();
    }
  }

  Future<void> archiveSession(Map<String, Object?> snapshot) async {
    if (!enabled) return;
    try {
      final filename = await _snapshotArchive.save(
        jsonEncode(_sanitizer.sanitize(snapshot)),
      );
      recordDeveloper(
        'chat.session.archived',
        fields: const {'status': 'ok'},
        data: {'filename': filename},
      );
    } on Object catch (error) {
      record('chat.session_archive_failed', fields: errorFields(error));
    }
  }

  void _append(Map<String, Object?> event) {
    final bytes = utf8.encode(jsonEncode(event)).length;
    _entries.add(event);
    _bytes += bytes;
    // Leave room for the export envelope and JSON separators.
    while (_entries.isNotEmpty &&
        (_entries.length > maxEntries ||
            _bytes + _entries.length + 2048 > maxBytes ||
            _clock().toUtc().difference(
                  DateTime.parse(_entries.first['at'] as String),
                ) >
                const Duration(days: 7))) {
      _bytes -= utf8.encode(jsonEncode(_entries.removeAt(0))).length;
    }
  }

  Map<String, Object?> _encodingRequest() => {
    'sanitizer': _sanitizer,
    'snapshot': <String, Object?>{
      'schema': 1,
      'app': 'smartfit',
      'version': AppBuildInfo.version,
      'versionName': AppBuildInfo.versionName,
      'buildNumber': AppBuildInfo.buildNumber,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'persistenceFailed': persistenceFailed,
      'retention': {
        'maxEntries': maxEntries,
        'maxBytes': maxBytes,
        'maxDays': 7,
      },
      // Entry maps are private and immutable after append. Copy the list only;
      // full redaction and JSON encoding belong to the worker isolate.
      'events': List<Map<String, Object?>>.of(_entries),
    },
  };

  String exportJson() => encodeRuntimeLogSnapshot(_encodingRequest());

  void _scheduleFlush() {
    if (!enabled ||
        storage == null ||
        _writing != null ||
        _automaticFlushQueued) {
      return;
    }
    _automaticFlushQueued = true;
    scheduleMicrotask(() async {
      try {
        // Do not occupy _writing while waiting: explicit flush/export can
        // still request a background write during an active transition.
        do {
          await TrainingTransitionActivity.instance.waitUntilIdle();
        } while (TrainingTransitionActivity.instance.active);
        await flush();
      } finally {
        _automaticFlushQueued = false;
        // A caller may append in a completion callback after _writing clears
        // but before this continuation resumes. Do not strand that revision.
        if (_savedRevision != _revision && !persistenceFailed) {
          _scheduleFlush();
        }
      }
    });
  }

  /// Coalesces bursts and serializes writes so older snapshots never win.
  /// Failed writes retain the in-memory log and can be retried at export/pause.
  Future<void> flush() {
    if (!enabled || storage == null) return Future.value();
    if (_writing case final writing?) return writing;
    final done = Completer<void>();
    _writing = done.future;
    () async {
      try {
        while (_savedRevision != _revision) {
          final revision = _revision;
          final redactionEpoch = _redactionEpoch;
          final encoded = await _encode(_encodingRequest());
          // A newly registered credential may have appeared in an old event.
          // Never publish the worker's now-obsolete redaction result.
          if (redactionEpoch != _redactionEpoch) continue;
          await storage!.write(storageKey, encoded);
          _savedRevision = revision;
          persistenceFailed = false;
          _writeFailureRecorded = false;
        }
      } on Object catch (error) {
        persistenceFailed = true;
        if (!_writeFailureRecorded) {
          _writeFailureRecorded = true;
          record(
            'diagnostics.storage_write_failed',
            fields: errorFields(error),
          );
        }
      } finally {
        _writing = null;
        done.complete();
      }
    }();
    return done.future;
  }
}
