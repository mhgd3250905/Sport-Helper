import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/local_state_storage.dart';
import '../domain/plan.dart';
import '../voice/voice_queue.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.at,
    required this.minutes,
    required this.completed,
    required this.total,
  });
  final String title;
  final DateTime at;
  final int minutes;
  final int completed;
  final int total;

  Map<String, Object?> toJson() => {
    'title': title,
    'at': at.toIso8601String(),
    'minutes': minutes,
    'completed': completed,
    'total': total,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    title: j['title'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    completed: (j['completed'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
  );
}

/// On-device state, one JSON value under `smartfit.state.v1`.
class AppStore extends ChangeNotifier {
  AppStore(this._storage);

  static const key = 'smartfit.state.v1';
  final LocalStateStorage _storage;

  bool safetyAccepted = false;

  /// A safety question was answered "是": browse only, no generated plans.
  bool safetyBlocked = false;
  VoiceSettings voice = const VoiceSettings();
  TrainingPlan? lastPlan;
  final List<HistoryEntry> history = [];

  Future<void> load() async {
    try {
      final raw = await _storage.read(key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      safetyAccepted = j['safetyAccepted'] == true;
      safetyBlocked = j['safetyBlocked'] == true;
      if (j['voice'] is Map) {
        voice = VoiceSettings.fromJson(Map<String, dynamic>.from(j['voice'] as Map));
      }
      if (j['lastPlan'] is Map) {
        lastPlan = TrainingPlan.fromJson(
          Map<String, dynamic>.from(j['lastPlan'] as Map),
        );
      }
      history
        ..clear()
        ..addAll([
          for (final h in j['history'] as List? ?? const [])
            HistoryEntry.fromJson(Map<String, dynamic>.from(h as Map)),
        ]);
    } on Object {
      // Corrupt or old state: start fresh rather than crash.
    }
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      await _storage.write(
        key,
        jsonEncode({
          'safetyAccepted': safetyAccepted,
          'safetyBlocked': safetyBlocked,
          'voice': voice.toJson(),
          'lastPlan': lastPlan?.toJson(),
          'history': [for (final h in history.take(30)) h.toJson()],
        }),
      );
    } on Object {
      // Storage unavailable (tests): keep the in-memory state.
    }
  }

  Future<void> acceptSafety({required bool blocked}) {
    safetyAccepted = true;
    safetyBlocked = blocked;
    return _save();
  }

  Future<void> setVoice(VoiceSettings v) {
    voice = v;
    return _save();
  }

  Future<void> rememberPlan(TrainingPlan p) {
    lastPlan = p;
    return _save();
  }

  Future<void> addHistory(HistoryEntry e) {
    history.insert(0, e);
    return _save();
  }
}
