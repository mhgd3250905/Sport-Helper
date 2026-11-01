import 'plan.dart';

enum SavedPlanWriteMode { create, copy, update }

enum SavedPlanWriteStatus { saved, conflict, deleted, readOnly, failed }

class SavedPlanWriteResult {
  const SavedPlanWriteResult.saved(SavedPlan this.saved)
    : status = SavedPlanWriteStatus.saved,
      error = null;
  const SavedPlanWriteResult.failure(this.status, {this.error}) : saved = null;
  final SavedPlanWriteStatus status;
  final SavedPlan? saved;
  final Object? error;
}

/// A plan the user kept from the chat ("保存") to start again later.
class SavedPlan {
  const SavedPlan({
    required this.id,
    required this.name,
    required this.plan,
    required this.savedAt,
    this.lastUsedAt,
    this.sdkVersion,
  });

  final String id;
  final String name;
  final TrainingPlan plan;
  final DateTime savedAt;
  final DateTime? lastUsedAt;

  /// The SDK's plan version. Plans saved before version tracking have none.
  final int? sdkVersion;

  /// Most recent of saved / last started, for "上次那个" and sorting.
  DateTime get touchedAt => lastUsedAt != null && lastUsedAt!.isAfter(savedAt)
      ? lastUsedAt!
      : savedAt;

  SavedPlan copyWith({String? name, DateTime? lastUsedAt}) => SavedPlan(
    id: id,
    name: name ?? this.name,
    plan: plan,
    savedAt: savedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    sdkVersion: sdkVersion,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'plan': plan.toJson(),
    'savedAt': savedAt.toIso8601String(),
    'lastUsedAt': ?lastUsedAt?.toIso8601String(),
    'sdkVersion': ?sdkVersion,
  };

  factory SavedPlan.fromJson(Map<String, dynamic> j) => SavedPlan(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    plan: TrainingPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map)),
    savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime(2026),
    lastUsedAt: DateTime.tryParse(j['lastUsedAt'] as String? ?? ''),
    sdkVersion: j['sdkVersion'] is int ? j['sdkVersion'] as int : null,
  );
}
