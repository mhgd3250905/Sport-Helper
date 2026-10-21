import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../core/storage/local_state_storage.dart';

/// The Agent's training memories, kept separately from chat and app settings.
/// Only the SDK's memory entries are written; request credentials never enter
/// this storage boundary. I/O failures propagate to the caller.
class LocalUserMemoryStore implements coach.UserMemoryStore {
  LocalUserMemoryStore(this._storage);

  static const key = 'smartfit.ai-memory.v1';
  final LocalStateStorage _storage;

  @override
  Future<List<coach.MemoryEntry>> load() async {
    final raw = await _storage.read(key);
    if (raw == null) return [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      // Unreadable old/corrupt memory cannot become model context.
      return [];
    }
    if (decoded is! List) return [];
    return decoded
        .map(coach.MemoryEntry.tryParse)
        .whereType<coach.MemoryEntry>()
        .toList();
  }

  @override
  Future<void> save(List<coach.MemoryEntry> entries) => _storage.write(
    key,
    jsonEncode([for (final entry in entries) entry.toJson()]),
  );
}
