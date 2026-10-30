import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show SessionResult, TrainingFeeling;

import '../app/user_memory_store.dart';
import '../core/storage/local_state_storage.dart';
import '../diagnostics/runtime_log.dart';
import '../diagnostics/action_issue.dart';
import '../diagnostics/action_issue_store.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import '../voice/voice_queue.dart';

/// Receives only a detached JSON tree, never the Store or its listeners.
typedef AppStateEncoder =
    Future<String> Function(Map<String, Object?> snapshot);

const _smallStateEncodingLimit = 16 * 1024;

String _encodeJsonSnapshot(Map<String, Object?> snapshot) =>
    jsonEncode(snapshot);

/// A conservative UTF-8 JSON bound, stopping as soon as the small-state
/// allowance is exhausted. Six bytes cover every escaped UTF-16 code unit.
/// This never encodes a large string just to decide where to encode it.
int _jsonSizeBound(Object? value, int limit) {
  if (value is String) return value.length * 6 + 2;
  if (value is num) return 32;
  if (value is bool || value == null) return 5;
  var bytes = 2;
  if (value is List) {
    for (final item in value) {
      bytes += 1 + _jsonSizeBound(item, limit - bytes);
      if (bytes >= limit) return bytes;
    }
  } else if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      bytes += 2 + _jsonSizeBound(entry.key, limit - bytes);
      if (bytes >= limit) return bytes;
      bytes += _jsonSizeBound(entry.value, limit - bytes);
      if (bytes >= limit) return bytes;
    }
  }
  return bytes;
}

Future<String> _encodeAppState(Map<String, Object?> snapshot) async {
  final bound = _jsonSizeBound(snapshot, _smallStateEncodingLimit);
  final worker = bound >= _smallStateEncodingLimit;
  final kind = worker ? 'compute' : 'inline_small';
  final watch = Stopwatch()..start();
  RuntimeLog.instance.record(
    'state.serialization.started',
    fields: {'kind': kind, if (!worker) 'bytes': bound},
  );
  try {
    return worker
        ? await compute(
            _encodeJsonSnapshot,
            snapshot,
            debugLabel: 'smartfit_state_json',
          )
        : _encodeJsonSnapshot(snapshot);
  } finally {
    RuntimeLog.instance.record(
      'state.serialization.completed',
      // Wall time includes worker startup/scheduling; it is not UI CPU time.
      fields: {'kind': kind, 'elapsedMs': watch.elapsedMicroseconds / 1000},
    );
  }
}

Object? _freezeJson(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freezeJson(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw JsonUnsupportedObjectError(value);
}

Map<String, Object?> _freezeState(Map<String, Object?> state) =>
    _freezeJson(state)! as Map<String, Object?>;

class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.at,
    required this.minutes,
    required this.completed,
    required this.total,
    this.sessionId,
    this.feeling,
  });
  final String title;
  final DateTime at;
  final int minutes;
  final int completed;
  final int total;

  /// Null for records saved before ugk_trainer was introduced.
  final String? sessionId;

  /// Optional completion-page feedback; old records have no selection.
  final TrainingFeeling? feeling;

  Map<String, Object?> toJson() => {
    'title': title,
    'at': at.toIso8601String(),
    'minutes': minutes,
    'completed': completed,
    'total': total,
    if (sessionId != null) 'sessionId': sessionId,
    if (feeling != null) 'feeling': feeling!.name,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    title: j['title'] as String? ?? '',
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
    minutes: (j['minutes'] as num?)?.toInt() ?? 0,
    completed: (j['completed'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    sessionId: j['sessionId'] as String?,
    feeling: TrainingFeeling.values
        .where((feeling) => feeling.name == j['feeling'])
        .firstOrNull,
  );
}

/// On-device state, one JSON value under `smartfit.state.v1`.
class AppStore extends ChangeNotifier {
  AppStore(
    this._storage, {
    this.actionIssueEnabled = actionIssueBuildEnabled,
    AppStateEncoder? stateEncoder,
  }) : _stateEncoder = stateEncoder ?? _encodeAppState;

  static const key = 'smartfit.state.v1';
  static const _retiredVisualKey = 'glassQuality';
  final LocalStateStorage _storage;
  final AppStateEncoder _stateEncoder;
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

  /// Opaque SDK snapshot; the App never edits or derives session facts.
  String? coachSessionJson;
  final List<Map<String, dynamic>> coachDisplayMessages = [];

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
          await _enqueueWrite(() async {
            final encoded = await _stateEncoder(_freezeState(j));
            await _storage.write(key, encoded);
          });
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
      final snapshot = j['coachSessionJson'];
      coachSessionJson = snapshot == null
          ? null
          : snapshot is String
          ? snapshot
          : jsonEncode(snapshot);
      coachDisplayMessages
        ..clear()
        ..addAll([
          for (final row in j['coachDisplay'] as List? ?? const [])
            if (row is Map) Map<String, dynamic>.from(row),
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

  Map<String, Object?> _snapshotState({
    Iterable<HistoryEntry>? updatedHistory,
    Iterable<SessionResult>? updatedSessions,
  }) => _freezeState({
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
    'coachSessionJson': ?coachSessionJson,
    if (coachSessionJson != null) 'coachDisplay': coachDisplayMessages,
    'chat': chatLog.length > chatLogLimit
        ? chatLog.sublist(chatLog.length - chatLogLimit)
        : chatLog,
  });

  Future<void> _writeState({
    Iterable<HistoryEntry>? updatedHistory,
    Iterable<SessionResult>? updatedSessions,
  }) async {
    // Capture at the head of the write queue. A settings/chat edit made while
    // encoding is pending belongs to its later queued write, not this one.
    final snapshot = _snapshotState(
      updatedHistory: updatedHistory,
      updatedSessions: updatedSessions,
    );
    final encoded = await _stateEncoder(snapshot);
    await _storage.write(key, encoded);
  }

  Future<void> _save({bool notify = true}) async {
    if (notify) notifyListeners();
    try {
      await _enqueueWrite(() => _writeState());
    } on Object {
      // Storage unavailable (tests): keep the in-memory state.
    }
  }

  /// TrainerPlayer's onFinished callback. Commit only after durable storage
  /// succeeds; failures reach ResultSaver so its completion page can retry.
  Future<void> saveSession(SessionResult result) => _enqueueWrite(() async {
    final previousFeeling = _sessions[result.sessionId]?.feeling;
    // A delayed automatic-save retry must not erase completion-page feedback.
    final receipt = result.feeling == null && previousFeeling != null
        ? result.withFeeling(previousFeeling)
        : result;
    final entry = HistoryEntry(
      sessionId: receipt.sessionId,
      title: receipt.planTitle,
      at: receipt.endedAt,
      minutes: receipt.minutes,
      completed: receipt.completedExercises,
      total: receipt.totalExercises,
      feeling: receipt.feeling,
    );
    final nextHistory = [
      entry,
      ...history.where((h) => h.sessionId != result.sessionId),
    ];
    final nextSessions = {..._sessions, receipt.sessionId: receipt};
    await _writeState(
      updatedHistory: nextHistory,
      updatedSessions: nextSessions.values,
    );
    _sessions[receipt.sessionId] = receipt;
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
    return _enqueueWrite(() => _writeState());
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

  /// Finds this exact content and SDK version, rather than an older card with
  /// the same plan id. [savedFor] remains available for identity-only lookups.
  SavedPlan? savedForSnapshot(
    TrainingPlan p, {
    int? sdkVersion,
    String? savedId,
  }) => savedPlans
      .where(
        (saved) =>
            (savedId == null || saved.id == savedId) &&
            saved.sdkVersion == sdkVersion &&
            _samePlanSnapshot(saved.plan, p),
      )
      .firstOrNull;

  /// Keeps the latest snapshot for this plan id without changing the saved
  /// record's name or history. [forceNew] keeps the original and creates a
  /// separate record named from [name], the existing name, or the plan title,
  /// followed by " 新版". Duplicate names receive a numeric suffix.
  Future<SavedPlan> savePlan(
    TrainingPlan p, {
    String? name,
    DateTime? now,
    int? sdkVersion,
    bool forceNew = false,
  }) async {
    final existing = savedFor(p);
    if (!forceNew && existing != null) {
      return (await updateSavedPlan(existing.id, p, sdkVersion: sdkVersion))!;
    }
    final originalName = (name ?? (forceNew ? existing?.name : null) ?? p.title)
        .trim();
    final displayName = originalName.isEmpty ? '我的计划' : originalName;
    final base = forceNew ? '$displayName 新版' : displayName;
    var n = base;
    for (var i = 2; savedPlans.any((s) => s.name == n); i++) {
      n = '$base $i';
    }
    final at = now ?? DateTime.now();
    final baseId = 'saved-${at.microsecondsSinceEpoch}';
    var id = baseId;
    for (var i = 2; savedPlans.any((saved) => saved.id == id); i++) {
      id = '$baseId-$i';
    }
    final saved = SavedPlan(
      id: id,
      name: n,
      plan: p,
      savedAt: at,
      sdkVersion: sdkVersion,
    );
    savedPlans.insert(0, saved);
    await _save();
    return saved;
  }

  /// Replaces only this saved record's plan snapshot and SDK version. A deleted
  /// record returns null so callers can offer an ordinary save instead.
  Future<SavedPlan?> updateSavedPlan(
    String savedId,
    TrainingPlan p, {
    int? sdkVersion,
  }) async {
    final index = savedPlans.indexWhere((saved) => saved.id == savedId);
    if (index < 0) return null;
    final previous = savedPlans[index];
    if (previous.sdkVersion == sdkVersion &&
        _samePlanSnapshot(previous.plan, p)) {
      return previous;
    }
    final updated = SavedPlan(
      id: previous.id,
      name: previous.name,
      plan: p,
      savedAt: previous.savedAt,
      lastUsedAt: previous.lastUsedAt,
      sdkVersion: sdkVersion,
    );
    savedPlans[index] = updated;
    await _save();
    return updated;
  }

  static bool _samePlanSnapshot(TrainingPlan first, TrainingPlan second) =>
      jsonEncode(_snapshotForComparison(first)) ==
      jsonEncode(_snapshotForComparison(second));

  static Map<String, Object?> _snapshotForComparison(TrainingPlan plan) => {
    ...plan.toJson(),
    // These describe sets; block, action, segment and dose ordering is retained.
    'equipment': plan.equipment.toSet().toList()..sort(),
    if (plan.avoid.isNotEmpty) 'avoid': plan.avoid.toList()..sort(),
  };

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
    return setConversation(log, sessionJson: null);
  }

  /// One storage write pairs display messages with their exact SDK snapshot.
  Future<void> setConversation(
    List<Map<String, dynamic>> log, {
    required String? sessionJson,
    List<Map<String, dynamic>> sdkMessages = const [],
    bool notify = true,
  }) {
    coachSessionJson = sessionJson;
    coachDisplayMessages
      ..clear()
      ..addAll(sdkMessages);
    chatLog
      ..clear()
      ..addAll(
        log.length > chatLogLimit
            ? log.sublist(log.length - chatLogLimit)
            : log,
      );
    return _save(notify: notify);
  }
}
