import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/local_state_storage.dart';
import 'action_issue.dart';

/// One separate value in the same local storage boundary as AppStore.
/// A record becomes visible only after the durable write succeeds.
class LocalActionIssueStore extends ChangeNotifier {
  LocalActionIssueStore(this.storage, {bool enabled = actionIssueBuildEnabled})
    : available = enabled;

  static const storageKey = 'smartfit.action-issues.v1';
  static const recordingKey = 'smartfit.action-issues.recording.v1';
  final LocalStateStorage storage;
  final bool available;
  bool _recordingEnabled = true;
  bool _preferenceLoaded = false;
  bool _preferenceInvalid = false;
  bool get enabled => available && _recordingEnabled;
  final List<ActionIssue> _records = [];
  Future<void> _tail = Future.value();
  bool _loaded = false;
  int _sequence = 0;

  List<ActionIssue> get records => List.unmodifiable(_records);
  int get count => _records.length;

  Future<void> load() => available ? _enqueue(_load) : Future.value();

  Future<void> loadRecordingPreference() =>
      available ? _enqueue(_loadRecordingPreference) : Future.value();

  Future<void> _loadRecordingPreference() async {
    if (_preferenceLoaded) return;
    Object? value;
    try {
      final raw = await storage.read(recordingKey);
      value = raw == null ? true : jsonDecode(raw);
    } on Object {
      value = null;
    }
    _preferenceInvalid = value is! bool;
    _recordingEnabled = value is bool ? value : false;
    _preferenceLoaded = true;
    notifyListeners();
  }

  Future<void> setRecordingEnabled(bool enabled) => _enqueue(() async {
    _requireAvailable();
    await _loadRecordingPreference();
    if (_recordingEnabled == enabled && !_preferenceInvalid) return;
    await storage.write(recordingKey, jsonEncode(enabled));
    _recordingEnabled = enabled;
    _preferenceInvalid = false;
    notifyListeners();
  });

  Future<void> _load() async {
    if (_loaded) return;
    await _loadRecordingPreference();
    final raw = await storage.read(storageKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['schemaVersion'] != 1) {
        throw const FormatException('Unsupported action issue schema');
      }
      final restored = [
        for (final entry in decoded['issues'] as List)
          ActionIssue.fromJson(Map<String, dynamic>.from(entry as Map)),
      ];
      // Parse completely before replacing state. Unreadable data is preserved
      // in storage and cannot silently be overwritten by the next append.
      _records
        ..clear()
        ..addAll(restored);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<ActionIssue> add(
    ActionIssueContext capture, {
    Iterable<ActionIssueTag> tags = const [],
    String note = '',
  }) {
    final selected = List<ActionIssueTag>.of(tags);
    return _enqueue(() async {
      _requireAvailable();
      await _load();
      _requireEnabled();
      String id;
      do {
        id =
            'issue-${capture.capturedAt.microsecondsSinceEpoch}-${++_sequence}';
      } while (_records.any((record) => record.id == id));
      final record = ActionIssue(
        id: id,
        capture: capture,
        tags: selected,
        note: note,
      );
      final next = [..._records, record];
      await storage.write(storageKey, _encode(next));
      _records.add(record);
      notifyListeners();
      return record;
    });
  }

  /// Queued behind pending writes, for a consistent export snapshot.
  Future<List<ActionIssue>> snapshot() => _enqueue(() async {
    _requireAvailable();
    await _load();
    return records;
  });

  void _requireEnabled() {
    if (!enabled) throw StateError('Action issue review is internal-only');
  }

  void _requireAvailable() {
    if (!available) throw StateError('Action issue review is internal-only');
  }

  String _encode(List<ActionIssue> records) => jsonEncode({
    'schemaVersion': 1,
    'issues': [for (final record in records) record.toJson()],
  });

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
