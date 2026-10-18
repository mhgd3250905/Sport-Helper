/// TrainingPlan v1 — the one schema both the template generator and a future
/// AI generator produce (docs/plan-schema.md). Plain JSON, ids only.
library;

import 'exercise.dart';

enum BlockType {
  warmup('热身'),
  main('主训练'),
  circuit('循环'),
  cooldown('放松');

  const BlockType(this.zh);
  final String zh;
  static BlockType byName(String s) =>
      values.firstWhere((v) => v.name == s, orElse: () => main);
}

/// Seconds between two sides of a unilateral set.
const switchSideSeconds = 5;

/// Seconds between two different exercises (next-move preview + 3-2-1).
const transitionSeconds = 15;

class PlanItem {
  const PlanItem({
    required this.exerciseId,
    required this.mode,
    required this.sets,
    this.reps,
    this.workSeconds,
    required this.perSide,
    required this.restSeconds,
    this.note,
    this.replacedFrom,
  });

  final String exerciseId;
  final DoseMode mode;
  final int sets;
  final int? reps;
  final int? workSeconds;
  final bool perSide;

  /// Rest after each set of this item (inside the item).
  final int restSeconds;
  final String? note;

  /// Original exercise when the generator swapped it (level, gear, cautions).
  final String? replacedFrom;

  /// Seconds of work for one side of one set.
  double workFor(Exercise e) => mode == DoseMode.reps
      ? (reps ?? 10) * (e.repSeconds ?? 3.0)
      : (workSeconds ?? 30).toDouble();

  String doseText() {
    final per = perSide ? '每侧 ' : '';
    final amount = mode == DoseMode.reps ? '$per${reps ?? 10} 次' : '$per${workSeconds ?? 30} 秒';
    return sets > 1 ? '$sets 组 × $amount' : amount;
  }

  PlanItem copyWith({
    String? exerciseId,
    int? sets,
    int? reps,
    int? workSeconds,
    bool? perSide,
    int? restSeconds,
    DoseMode? mode,
    String? replacedFrom,
  }) => PlanItem(
    exerciseId: exerciseId ?? this.exerciseId,
    mode: mode ?? this.mode,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    workSeconds: workSeconds ?? this.workSeconds,
    perSide: perSide ?? this.perSide,
    restSeconds: restSeconds ?? this.restSeconds,
    note: note,
    replacedFrom: replacedFrom ?? this.replacedFrom,
  );

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'mode': mode.name,
    'sets': sets,
    'reps': ?reps,
    'workSeconds': ?workSeconds,
    'perSide': perSide,
    'restSeconds': restSeconds,
    'note': ?note,
    'replacedFrom': ?replacedFrom,
  };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    exerciseId: j['exerciseId'] as String,
    mode: j['mode'] == 'reps' ? DoseMode.reps : DoseMode.time,
    sets: (j['sets'] as num?)?.toInt() ?? 1,
    reps: (j['reps'] as num?)?.toInt(),
    workSeconds: (j['workSeconds'] as num?)?.toInt(),
    perSide: j['perSide'] == true,
    restSeconds: (j['restSeconds'] as num?)?.toInt() ?? 20,
    note: j['note'] as String?,
    replacedFrom: j['replacedFrom'] as String?,
  );
}

class PlanBlock {
  const PlanBlock({
    required this.id,
    required this.name,
    required this.type,
    required this.rounds,
    required this.restBetweenRoundsSeconds,
    required this.items,
  });

  final String id;
  final String name;
  final BlockType type;

  /// Circuit blocks repeat their items [rounds] times, one set each.
  final int rounds;
  final int restBetweenRoundsSeconds;
  final List<PlanItem> items;

  PlanBlock copyWith({int? rounds, List<PlanItem>? items}) => PlanBlock(
    id: id,
    name: name,
    type: type,
    rounds: rounds ?? this.rounds,
    restBetweenRoundsSeconds: restBetweenRoundsSeconds,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'rounds': rounds,
    'restBetweenRoundsSeconds': restBetweenRoundsSeconds,
    'items': [for (final i in items) i.toJson()],
  };

  factory PlanBlock.fromJson(Map<String, dynamic> j) => PlanBlock(
    id: j['id'] as String,
    name: j['name'] as String,
    type: BlockType.byName(j['type'] as String),
    rounds: (j['rounds'] as num?)?.toInt() ?? 1,
    restBetweenRoundsSeconds:
        (j['restBetweenRoundsSeconds'] as num?)?.toInt() ?? 0,
    items: [
      for (final i in j['items'] as List)
        PlanItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
  );
}

class TrainingPlan {
  const TrainingPlan({
    this.schemaVersion = 1,
    required this.id,
    required this.source,
    this.templateId,
    required this.title,
    required this.summary,
    required this.goal,
    required this.scene,
    required this.equipment,
    required this.level,
    required this.targetMinutes,
    required this.blocks,
    this.notes = const [],
    this.safetyNotes = const [],
  });

  final int schemaVersion;
  final String id;

  /// 'template' | 'ai'
  final String source;
  final String? templateId;
  final String title;
  final String summary;
  final String goal;
  final String scene;
  final List<String> equipment;
  final int level;
  final int targetMinutes;
  final List<PlanBlock> blocks;

  /// What the generator changed for this user ("换成了…", "按 15 分钟加了一轮").
  final List<String> notes;
  final List<String> safetyNotes;

  Iterable<PlanItem> get items => blocks.expand((b) => b.items);
  Set<String> get exerciseIds => {for (final i in items) i.exerciseId};

  TrainingPlan copyWith({List<PlanBlock>? blocks, List<String>? notes}) =>
      TrainingPlan(
        schemaVersion: schemaVersion,
        id: id,
        source: source,
        templateId: templateId,
        title: title,
        summary: summary,
        goal: goal,
        scene: scene,
        equipment: equipment,
        level: level,
        targetMinutes: targetMinutes,
        blocks: blocks ?? this.blocks,
        notes: notes ?? this.notes,
        safetyNotes: safetyNotes,
      );

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'source': source,
    'templateId': ?templateId,
    'title': title,
    'summary': summary,
    'goal': goal,
    'scene': scene,
    'equipment': equipment,
    'level': level,
    'targetMinutes': targetMinutes,
    'blocks': [for (final b in blocks) b.toJson()],
    'notes': notes,
    'safetyNotes': safetyNotes,
  };

  factory TrainingPlan.fromJson(Map<String, dynamic> j) => TrainingPlan(
    schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    id: j['id'] as String,
    source: j['source'] as String? ?? 'template',
    templateId: j['templateId'] as String?,
    title: j['title'] as String,
    summary: j['summary'] as String? ?? '',
    goal: j['goal'] as String? ?? 'mixed',
    scene: j['scene'] as String? ?? 'home',
    equipment: List<String>.from(j['equipment'] as List? ?? const []),
    level: (j['level'] as num?)?.toInt() ?? 1,
    targetMinutes: (j['targetMinutes'] as num?)?.toInt() ?? 10,
    blocks: [
      for (final b in j['blocks'] as List)
        PlanBlock.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
    notes: List<String>.from(j['notes'] as List? ?? const []),
    safetyNotes: List<String>.from(j['safetyNotes'] as List? ?? const []),
  );
}
