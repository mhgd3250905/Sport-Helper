/// Exercise library + training plan data model (schema v1).
///
/// The same [TrainingPlan] JSON is produced by the template generator (MVP)
/// and, later, by an AI generator; both go through `PlanValidator`.
library;

enum DoseMode {
  reps('reps', '次'),
  time('time', '秒');

  const DoseMode(this.id, this.unit);
  final String id;
  final String unit;
  static DoseMode byId(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => reps);
}

class Dose {
  const Dose({
    required this.mode,
    required this.sets,
    this.reps,
    this.seconds,
    required this.restSec,
  });
  final DoseMode mode;
  final int sets;
  final int? reps;
  final int? seconds;
  final int restSec;

  factory Dose.fromJson(Map<String, dynamic> j) => Dose(
    mode: DoseMode.byId(j['mode'] as String?),
    sets: (j['sets'] as num?)?.toInt() ?? 1,
    reps: (j['reps'] as num?)?.toInt(),
    seconds: (j['seconds'] as num?)?.toInt(),
    restSec: (j['restSec'] as num?)?.toInt() ?? 30,
  );
}

const equipmentZh = {
  'mat': '垫子',
  'chair': '椅子',
  'wall': '墙',
  'band': '弹力带',
  'dumbbell': '哑铃',
  'towel': '毛巾',
};

const categoryZh = {
  'strength': '力量',
  'core': '核心',
  'cardio': '有氧',
  'mobility': '灵活',
  'stretch': '拉伸',
};

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    this.nameEn = '',
    required this.category,
    required this.position,
    required this.equipment,
    required this.scenes,
    required this.level,
    required this.unilateral,
    required this.muscles,
    required this.musclesZh,
    required this.regions,
    required this.dose,
    this.repSec = 4,
    this.loopSec = 8,
    required this.cues,
    this.caution,
    required this.video,
    required this.poster,
  });

  final String id;
  final String name;
  final String nameEn;
  final String category;
  final String position;
  final List<String> equipment;
  final List<String> scenes;
  final int level;
  final bool unilateral;
  final List<String> muscles;
  final List<String> musclesZh;
  final List<String> regions;
  final Dose dose;
  final double repSec;
  final double loopSec;
  final List<String> cues;
  final String? caution;
  final String video;
  final String poster;

  /// Clip id used by the WebView player (file stem of [video]).
  String get mediaId => video.split('/').last.replaceAll('.mp4', '');

  /// Equipment beyond the floor/mat the user needs (mat is always assumed
  /// optional at home).
  List<String> get gear => equipment.where((e) => e != 'mat').toList();

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final media = Map<String, dynamic>.from(j['media'] as Map);
    List<String> strs(Object? o) =>
        (o as List? ?? const []).map((e) => e.toString()).toList();
    return Exercise(
      id: j['id'] as String,
      name: j['name'] as String,
      nameEn: j['nameEn'] as String? ?? '',
      category: j['category'] as String,
      position: j['position'] as String? ?? '',
      equipment: strs(j['equipment']),
      scenes: strs(j['scenes']),
      level: (j['level'] as num?)?.toInt() ?? 1,
      unilateral: j['unilateral'] == true,
      muscles: strs(j['muscles']),
      musclesZh: strs(j['musclesZh']),
      regions: strs(j['regions']),
      dose: Dose.fromJson(Map<String, dynamic>.from(j['dose'] as Map)),
      repSec: (j['repSec'] as num?)?.toDouble() ?? 4,
      loopSec: (j['loopSec'] as num?)?.toDouble() ?? 8,
      cues: strs(j['cues']),
      caution: j['caution'] as String?,
      video: media['video'] as String,
      poster: media['poster'] as String,
    );
  }
}

// ---------------------------------------------------------------- templates

class TemplateItem {
  const TemplateItem({
    required this.id,
    this.sets,
    this.reps,
    this.seconds,
    this.restSec,
  });
  final String id;
  final int? sets;
  final int? reps;
  final int? seconds;
  final int? restSec;
  factory TemplateItem.fromJson(Map<String, dynamic> j) => TemplateItem(
    id: j['id'] as String,
    sets: (j['sets'] as num?)?.toInt(),
    reps: (j['reps'] as num?)?.toInt(),
    seconds: (j['seconds'] as num?)?.toInt(),
    restSec: (j['restSec'] as num?)?.toInt(),
  );
}

class TemplateBlock {
  const TemplateBlock({
    required this.name,
    required this.type,
    required this.rounds,
    required this.restBetweenRoundsSec,
    required this.items,
  });
  final String name;
  final String type;
  final int rounds;
  final int restBetweenRoundsSec;
  final List<TemplateItem> items;
  factory TemplateBlock.fromJson(Map<String, dynamic> j) => TemplateBlock(
    name: j['name'] as String,
    type: j['type'] as String? ?? 'main',
    rounds: (j['rounds'] as num?)?.toInt() ?? 1,
    restBetweenRoundsSec: (j['restBetweenRoundsSec'] as num?)?.toInt() ?? 0,
    items: [
      for (final i in j['items'] as List)
        TemplateItem.fromJson(Map<String, dynamic>.from(i as Map)),
    ],
  );
}

class PlanTemplate {
  const PlanTemplate({
    required this.id,
    required this.name,
    required this.goal,
    required this.scene,
    required this.equipment,
    required this.requires,
    required this.focus,
    required this.summary,
    required this.keywords,
    required this.blocks,
  });
  final String id;
  final String name;
  final String goal;
  final String scene;
  final List<String> equipment;

  /// Equipment without which the template makes no sense (no substitution).
  final List<String> requires;
  final List<String> focus;
  final String summary;
  final List<String> keywords;
  final List<TemplateBlock> blocks;

  factory PlanTemplate.fromJson(Map<String, dynamic> j) {
    List<String> strs(Object? o) =>
        (o as List? ?? const []).map((e) => e.toString()).toList();
    return PlanTemplate(
      id: j['id'] as String,
      name: j['name'] as String,
      goal: j['goal'] as String,
      scene: j['scene'] as String,
      equipment: strs(j['equipment']),
      requires: strs(j['requires']),
      focus: strs(j['focus']),
      summary: j['summary'] as String? ?? '',
      keywords: strs(j['keywords']),
      blocks: [
        for (final b in j['blocks'] as List)
          TemplateBlock.fromJson(Map<String, dynamic>.from(b as Map)),
      ],
    );
  }
}

// --------------------------------------------------------------------- plan

class PlanItem {
  const PlanItem({
    required this.exerciseId,
    required this.mode,
    required this.sets,
    this.reps,
    this.workSec,
    required this.perSide,
    required this.restSec,
    this.replacedFrom,
  });
  final String exerciseId;
  final DoseMode mode;
  final int sets;
  final int? reps;
  final int? workSec;
  final bool perSide;
  final int restSec;

  /// The template's original exercise when this one was substituted
  /// (missing equipment / level).
  final String? replacedFrom;

  PlanItem copyWith({
    String? exerciseId,
    int? sets,
    int? reps,
    int? workSec,
    int? restSec,
    String? replacedFrom,
  }) => PlanItem(
    exerciseId: exerciseId ?? this.exerciseId,
    mode: mode,
    sets: sets ?? this.sets,
    reps: reps ?? this.reps,
    workSec: workSec ?? this.workSec,
    perSide: perSide,
    restSec: restSec ?? this.restSec,
    replacedFrom: replacedFrom ?? this.replacedFrom,
  );

  /// "3 组 × 12 次" / "2 组 × 每侧 30 秒".
  String get doseLabel {
    final side = perSide ? '每侧 ' : '';
    final amt = mode == DoseMode.reps ? '$reps 次' : '$workSec 秒';
    return sets > 1 ? '$sets 组 × $side$amt' : '$side$amt';
  }

  Map<String, Object?> toJson() => {
    'exerciseId': exerciseId,
    'mode': mode.id,
    'sets': sets,
    if (reps != null) 'reps': reps,
    if (workSec != null) 'workSec': workSec,
    'perSide': perSide,
    'restSec': restSec,
    if (replacedFrom != null) 'replacedFrom': replacedFrom,
  };

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    exerciseId: j['exerciseId'] as String,
    mode: DoseMode.byId(j['mode'] as String?),
    sets: (j['sets'] as num).toInt(),
    reps: (j['reps'] as num?)?.toInt(),
    workSec: (j['workSec'] as num?)?.toInt(),
    perSide: j['perSide'] == true,
    restSec: (j['restSec'] as num).toInt(),
    replacedFrom: j['replacedFrom'] as String?,
  );
}

class PlanBlock {
  const PlanBlock({
    required this.name,
    required this.type,
    required this.rounds,
    required this.restBetweenRoundsSec,
    required this.items,
  });
  final String name;
  final String type;
  final int rounds;
  final int restBetweenRoundsSec;
  final List<PlanItem> items;

  bool get isCircuit => type == 'circuit' && rounds > 1;

  String get typeZh => switch (type) {
    'warmup' => '热身',
    'cooldown' => '放松',
    'circuit' => '循环',
    _ => '主训练',
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type,
    'rounds': rounds,
    'restBetweenRoundsSec': restBetweenRoundsSec,
    'items': [for (final i in items) i.toJson()],
  };

  factory PlanBlock.fromJson(Map<String, dynamic> j) => PlanBlock(
    name: j['name'] as String,
    type: j['type'] as String,
    rounds: (j['rounds'] as num).toInt(),
    restBetweenRoundsSec: (j['restBetweenRoundsSec'] as num?)?.toInt() ?? 0,
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
    required this.estimatedMinutes,
    required this.safetyNotes,
    required this.blocks,
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
  final int estimatedMinutes;
  final List<String> safetyNotes;
  final List<PlanBlock> blocks;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'source': source,
    if (templateId != null) 'templateId': templateId,
    'title': title,
    'summary': summary,
    'goal': goal,
    'scene': scene,
    'equipment': equipment,
    'level': level,
    'estimatedMinutes': estimatedMinutes,
    'safetyNotes': safetyNotes,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  factory TrainingPlan.fromJson(Map<String, dynamic> j) => TrainingPlan(
    schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 1,
    id: j['id'] as String,
    source: j['source'] as String,
    templateId: j['templateId'] as String?,
    title: j['title'] as String,
    summary: j['summary'] as String? ?? '',
    goal: j['goal'] as String,
    scene: j['scene'] as String,
    equipment: (j['equipment'] as List).map((e) => e.toString()).toList(),
    level: (j['level'] as num).toInt(),
    estimatedMinutes: (j['estimatedMinutes'] as num).toInt(),
    safetyNotes: (j['safetyNotes'] as List? ?? const [])
        .map((e) => e.toString())
        .toList(),
    blocks: [
      for (final b in j['blocks'] as List)
        PlanBlock.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );
}

// ----------------------------------------------------------------- request

enum Goal {
  relax('relax', '放松拉伸'),
  mobility('mobility', '灵活柔韧'),
  strength('strength', '力量塑形'),
  core('core', '核心'),
  activate('activate', '激活提神'),
  warmup('warmup', '运动前热身');

  const Goal(this.id, this.zh);
  final String id;
  final String zh;
  static Goal? byId(String? id) =>
      values.where((g) => g.id == id).firstOrNull;
}

enum Scene {
  home('home', '居家'),
  office('office', '办公室');

  const Scene(this.id, this.zh);
  final String id;
  final String zh;
  static Scene byId(String? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => home);
}

enum Focus {
  any('any', '全身'),
  upper('upper', '上肢肩背'),
  lower('lower', '下肢臀腿'),
  core('core', '核心腰腹');

  const Focus(this.id, this.zh);
  final String id;
  final String zh;
}

/// What the user asked for: from the chips, a typed description, or both.
class ScenarioRequest {
  const ScenarioRequest({
    this.description = '',
    this.goal,
    this.scene = Scene.home,
    this.equipment = const {},
    this.minutes = 15,
    this.level = 1,
    this.focus = Focus.any,
  });
  final String description;
  final Goal? goal;
  final Scene scene;

  /// Available gear beyond the floor: chair / wall / band / dumbbell / mat.
  final Set<String> equipment;
  final int minutes;

  /// 1 入门 · 2 基础 · 3 进阶
  final int level;
  final Focus focus;

  ScenarioRequest copyWith({
    String? description,
    Goal? goal,
    bool clearGoal = false,
    Scene? scene,
    Set<String>? equipment,
    int? minutes,
    int? level,
    Focus? focus,
  }) => ScenarioRequest(
    description: description ?? this.description,
    goal: clearGoal ? null : goal ?? this.goal,
    scene: scene ?? this.scene,
    equipment: equipment ?? this.equipment,
    minutes: minutes ?? this.minutes,
    level: level ?? this.level,
    focus: focus ?? this.focus,
  );
}

const levelZh = {1: '入门', 2: '基础', 3: '进阶'};
