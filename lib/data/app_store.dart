import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/storage/local_state_storage.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
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

  /// All training entry points require a completed, clear safety check.
  bool get trainingAllowed => safetyAccepted && !safetyBlocked;
  VoiceSettings voice = const VoiceSettings();
  TrainingPlan? lastPlan;
  final List<HistoryEntry> history = [];

  /// Plans kept from the chat, newest first.
  final List<SavedPlan> savedPlans = [];

  /// The chat home's recent conversation (ChatMessage JSON, oldest first).
  final List<Map<String, dynamic>> chatLog = [];

  /// Drifting star dust behind the chat (off = static sky).
  bool starfield = true;

  /// 外观: 'dark' (深空, default), 'light' (白色无边空间) or 'system'.
  String appearance = 'dark';
  static const appearances = ['dark', 'light', 'system'];

  /// How many chat messages are kept on the device.
  static const chatLogLimit = 60;

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
      starfield = j['starfield'] != false;
      if (appearances.contains(j['appearance'])) appearance = j['appearance'] as String;
      savedPlans
        ..clear()
        ..addAll([
          for (final p in j['savedPlans'] as List? ?? const [])
            SavedPlan.fromJson(Map<String, dynamic>.from(p as Map)),
        ]);
      chatLog
        ..clear()
        ..addAll([
          for (final m in j['chat'] as List? ?? const [])
            Map<String, dynamic>.from(m as Map),
        ]);
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
          'starfield': starfield,
          'appearance': appearance,
          'savedPlans': [for (final p in savedPlans) p.toJson()],
          'chat': chatLog.length > chatLogLimit
              ? chatLog.sublist(chatLog.length - chatLogLimit)
              : chatLog,
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

  /// A re-check invalidates the previous answers immediately. Persist the
  /// pending state so restarting halfway through cannot reopen training.
  Future<void> beginSafetyCheck() {
    if (!safetyAccepted) return Future.value();
    safetyAccepted = false;
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

  Future<void> setStarfield(bool on) {
    starfield = on;
    return _save();
  }

  Future<void> setAppearance(String a) {
    if (!appearances.contains(a)) return Future.value();
    appearance = a;
    return _save();
  }

  SavedPlan? savedFor(TrainingPlan p) =>
      savedPlans.where((s) => s.plan.id == p.id).firstOrNull;

  /// Keeps [p] (once per plan id). The name defaults to the plan title,
  /// numbered when that name is taken ("核心训练 2").
  Future<SavedPlan> savePlan(TrainingPlan p, {String? name, DateTime? now}) async {
    final existing = savedFor(p);
    if (existing != null) return existing;
    final base = (name ?? p.title).trim().isEmpty ? '我的计划' : (name ?? p.title).trim();
    var n = base;
    for (var i = 2; savedPlans.any((s) => s.name == n); i++) {
      n = '$base $i';
    }
    final at = now ?? DateTime.now();
    final saved = SavedPlan(id: 'saved-${at.microsecondsSinceEpoch}', name: n, plan: p, savedAt: at);
    savedPlans.insert(0, saved);
    await _save();
    return saved;
  }

  Future<void> renamePlan(String id, String name) {
    final i = savedPlans.indexWhere((s) => s.id == id);
    if (i < 0 || name.trim().isEmpty) return Future.value();
    savedPlans[i] = savedPlans[i].copyWith(name: name.trim());
    return _save();
  }

  Future<void> deletePlan(String id) {
    savedPlans.removeWhere((s) => s.id == id);
    return _save();
  }

  /// A saved plan was started: it becomes the "上次那个" candidate.
  Future<void> touchPlan(String id, {DateTime? now}) {
    final i = savedPlans.indexWhere((s) => s.id == id);
    if (i < 0) return Future.value();
    savedPlans[i] = savedPlans[i].copyWith(lastUsedAt: now ?? DateTime.now());
    return _save();
  }

  Future<void> setChatLog(List<Map<String, dynamic>> log) {
    chatLog
      ..clear()
      ..addAll(log.length > chatLogLimit ? log.sublist(log.length - chatLogLimit) : log);
    return _save();
  }
}
