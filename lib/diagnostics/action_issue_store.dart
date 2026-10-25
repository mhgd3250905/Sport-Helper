import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/local_state_storage.dart';
import 'action_issue.dart';

/// One separate value in the same local storage boundary as AppStore.
/// A record becomes visible only after the durable write succeeds.
class LocalActionIssueStore extends ChangeNotifier {
  LocalActionIssueStore(this.storage, {this.enabled = actionIssueBuildEnabled});

  static const storageKey = 'smartfit.action-issues.v1';
  final LocalStateStorage storage;
  final bool enabled;
  final List<ActionIssue> _records = [];
  Future<void> _tail = Future.value();
  bool _loaded = false;
  int _sequence = 0;

  List<ActionIssue> get records => List.unmodifiable(_records);
  int get count => _records.length;

  Future<void> load() => enabled ? _enqueue(_load) : Future.value();

  Future<void> _load() async {
    if (_loaded) return;
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
      _requireEnabled();
      await _load();
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
    _requireEnabled();
    await _load();
    return records;
  });

  void _requireEnabled() {
    if (!enabled) throw StateError('Action issue review is internal-only');
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
