import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../core/storage/local_state_storage.dart';

/// Bounded, opt-in diagnostics. Call sites pass metadata, never payloads.
/// Production releases cannot enable this with the debug logging define.
class RuntimeLog {
  RuntimeLog({
    required this.enabled,
    this.storage,
    this.maxEntries = 1500,
    this.maxBytes = 512 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const buildEnabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' ||
      (kDebugMode && bool.fromEnvironment('SMARTFIT_RUNTIME_LOGS'));
  static RuntimeLog instance = RuntimeLog(enabled: false);
  static const storageKey = 'smartfit.runtime-log.v1';
  final bool enabled;
  final int maxEntries;
  final int maxBytes;
  final LocalStateStorage? storage;
  final DateTime Function() _clock;
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
  Future<void>? _writing;
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
    'flavor',
    'platform',
    'state',
    'operationId',
  };
  static final _token = RegExp(r'^[A-Za-z0-9_.+\-]{1,96}$');
  static final _event = RegExp(r'^[a-z][a-z0-9_.]{0,63}$');

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
    unawaited(flush());
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

  Map<String, Object?> _snapshot() => {
    'schema': 1,
    'app': 'smartfit',
    'version': '0.1.0+15',
    'exportedAt': _clock().toUtc().toIso8601String(),
    'persistenceFailed': persistenceFailed,
    'retention': {'maxEntries': maxEntries, 'maxBytes': maxBytes, 'maxDays': 7},
    'events': List.of(_entries),
  };

  String exportJson() => jsonEncode(_snapshot());

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
          await storage!.write(storageKey, exportJson());
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
