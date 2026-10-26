import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show SessionResult;

import '../app/user_memory_store.dart';
import '../core/storage/local_state_storage.dart';
import '../diagnostics/runtime_log.dart';
import '../diagnostics/action_issue.dart';
import '../diagnostics/action_issue_store.dart';
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
    this.sessionId,
  });
  final String title;
  final DateTime at;
  final int minutes;
  final int completed;
  final int total;

  /// Null for records saved before ugk_trainer was introduced.
  final String? sessionId;

  Map<String, Object?> toJson() => {
    'title': title,
    'at': at.toIso8601String(),
    'minutes': minutes,
    'completed': completed,
    'total': total,
    if (sessionId != null) 'sessionId': sessionId,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    title: j['title'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    completed: (j['completed'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    sessionId: j['sessionId'] as String?,
  );
}

/// On-device state, one JSON value under `smartfit.state.v1`.
class AppStore extends ChangeNotifier {
  AppStore(this._storage, {this.actionIssueEnabled = actionIssueBuildEnabled});

  static const key = 'smartfit.state.v1';
  static const _retiredVisualKey = 'glassQuality';
  final LocalStateStorage _storage;
  final bool actionIssueEnabled;

  late final actionIssueStore = LocalActionIssueStore(
    _storage,
    enabled: actionIssueEnabled,
  );

  /// Memories have their own key and survive disabling the capability.
  late final LocalUserMemoryStore aiMemoryStore = LocalUserMemoryStore(
    _storage,
  );

  bool aiMemoryEnabled = true;
  bool mediaWifiOnly = true;

  bool safetyAccepted = false;

  /// A safety question was answered "是": browse only, no generated plans.
  bool safetyBlocked = false;

  /// All training entry points require a completed, clear safety check.
  bool get trainingAllowed => safetyAccepted && !safetyBlocked;
  VoiceSettings voice = const VoiceSettings();
  TrainingPlan? lastPlan;
  final List<HistoryEntry> history = [];
  final Map<String, SessionResult> _sessions = {};

  /// Complete trainer results, keyed internally by the session's stable id.
  List<SessionResult> get sessionResults => List.unmodifiable(_sessions.values);

  // All writes share one queue so a settings save cannot overwrite a newer
  // training result. A failed write must not poison subsequent retries.
  Future<void> _writes = Future.value();

  /// Plans kept from the chat, newest first.
  final List<SavedPlan> savedPlans = [];

  /// The chat home's recent conversation (ChatMessage JSON, oldest first).
  final List<Map<String, dynamic>> chatLog = [];

  /// Drifting star dust behind the chat (off = static sky).
  bool starfield = true;

  /// 外观: 'dark' (深空), 'light' (白色无边空间) or 'system' (default since the
  /// light-stage media landed, §6.3; a stored choice is kept).
  String appearance = const String.fromEnvironment(
    'SF_APPEARANCE',
    defaultValue: 'system',
  );
  static const appearances = ['dark', 'light', 'system'];

  /// How many chat messages are kept on the device.
  static const chatLogLimit = 60;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key);
      if (raw == null) {
        RuntimeLog.instance.record(
          'state.loaded',
          fields: {'available': false},
        );
        return;
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j.containsKey(_retiredVisualKey)) {
        j.remove(_retiredVisualKey);
        try {
          // Persist the original map so unrelated keys and long histories survive.
          await _enqueueWrite(() => _storage.write(key, jsonEncode(j)));
        } on Object catch (error) {
          RuntimeLog.instance.record(
            'state.retired_preference_cleanup_deferred',
            fields: RuntimeLog.errorFields(error),
          );
        }
      }
      safetyAccepted = j['safetyAccepted'] == true;
      safetyBlocked = j['safetyBlocked'] == true;
      if (j['voice'] is Map) {
        voice = VoiceSettings.fromJson(
          Map<String, dynamic>.from(j['voice'] as Map),
        );
      }
      if (j['lastPlan'] is Map) {
        lastPlan = TrainingPlan.fromJson(
          Map<String, dynamic>.from(j['lastPlan'] as Map),
        );
      }
      starfield = j['starfield'] != false;
      aiMemoryEnabled = j['aiMemoryEnabled'] != false;
      mediaWifiOnly = j['mediaWifiOnly'] != false;
      if (appearances.contains(j['appearance'])) {
        appearance = j['appearance'] as String;
      }
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
      _sessions.clear();
      for (final result in j['sessions'] as List? ?? const []) {
        final session = SessionResult.fromJson(
          Map<String, dynamic>.from(result as Map),
        );
        _sessions[session.sessionId] = session;
      }
      RuntimeLog.instance.record('state.loaded', fields: {'available': true});
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'state.load_failed',
        fields: RuntimeLog.errorFields(error),
      );
      // Corrupt or old state: start fresh rather than crash.
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final pending = _writes.then((_) => write());
    _writes = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  String _encodeState({
    Iterable<HistoryEntry>? updatedHistory,
    Iterable<SessionResult>? updatedSessions,
  }) => jsonEncode({
    'safetyAccepted': safetyAccepted,
    'safetyBlocked': safetyBlocked,
    'voice': voice.toJson(),
    'lastPlan': lastPlan?.toJson(),
    'history': [
      for (final h in (updatedHistory ?? history).take(30)) h.toJson(),
    ],
    'sessions': [
      for (final r in updatedSessions ?? _sessions.values) r.toJson(),
    ],
    'starfield': starfield,
    'aiMemoryEnabled': aiMemoryEnabled,
    'mediaWifiOnly': mediaWifiOnly,
    'appearance': appearance,
    'savedPlans': [for (final p in savedPlans) p.toJson()],
    'chat': chatLog.length > chatLogLimit
        ? chatLog.sublist(chatLog.length - chatLogLimit)
        : chatLog,
  });

  Future<void> _save({bool notify = true}) async {
    if (notify) notifyListeners();
    try {
      await _enqueueWrite(() => _storage.write(key, _encodeState()));
    } on Object {
      // Storage unavailable (tests): keep the in-memory state.
    }
  }

  /// TrainerPlayer's onFinished callback. Commit only after durable storage
  /// succeeds; failures reach ResultSaver so its completion page can retry.
  Future<void> saveSession(SessionResult result) => _enqueueWrite(() async {
    final entry = HistoryEntry(
      sessionId: result.sessionId,
      title: result.planTitle,
      at: result.endedAt,
      minutes: result.minutes,
      completed: result.completedExercises,
      total: result.totalExercises,
    );
    final nextHistory = [
      entry,
      ...history.where((h) => h.sessionId != result.sessionId),
    ];
    final nextSessions = {..._sessions, result.sessionId: result};
    await _storage.write(
      key,
      _encodeState(
        updatedHistory: nextHistory,
        updatedSessions: nextSessions.values,
      ),
    );
    _sessions[result.sessionId] = result;
    // Other App methods may have updated memory while storage was pending.
    // Preserve those edits; their queued saves will persist the merged state.
    history.removeWhere((h) => h.sessionId == result.sessionId);
    history.insert(0, entry);
    notifyListeners();
  });

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

  /// Change this immediately for the running agent; persist failures reach the
  /// settings UI so it can explain that the preference needs another save.
  Future<void> setAiMemoryEnabled(bool enabled) {
    aiMemoryEnabled = enabled;
    notifyListeners();
    return _enqueueWrite(() => _storage.write(key, _encodeState()));
  }

  Future<void> setAppearance(String a) {
    if (!appearances.contains(a)) return Future.value();
    appearance = a;
    return _save();
  }

  Future<void> setMediaWifiOnly(bool value) {
    mediaWifiOnly = value;
    return _save();
  }

  SavedPlan? savedFor(TrainingPlan p) =>
      savedPlans.where((s) => s.plan.id == p.id).firstOrNull;

  /// Keeps [p] (once per plan id). The name defaults to the plan title,
  /// numbered when that name is taken ("核心训练 2").
  Future<SavedPlan> savePlan(
    TrainingPlan p, {
    String? name,
    DateTime? now,
  }) async {
    final existing = savedFor(p);
    if (existing != null) return existing;
    final base = (name ?? p.title).trim().isEmpty
        ? '我的计划'
        : (name ?? p.title).trim();
    var n = base;
    for (var i = 2; savedPlans.any((s) => s.name == n); i++) {
      n = '$base $i';
    }
    final at = now ?? DateTime.now();
    final saved = SavedPlan(
      id: 'saved-${at.microsecondsSinceEpoch}',
      name: n,
      plan: p,
      savedAt: at,
    );
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
      ..addAll(
        log.length > chatLogLimit
            ? log.sublist(log.length - chatLogLimit)
            : log,
      );
    return _save();
  }
}
