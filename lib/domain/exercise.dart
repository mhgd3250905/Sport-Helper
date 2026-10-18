/// One move in the exercise library (assets/library/exercises.json, built by
/// tools/library/build_library.py). Ids are the 3D-Pose-Hub drill ids.
library;

enum DoseMode { reps, time }

enum ExerciseCategory {
  strength('力量'),
  core('核心'),
  cardio('有氧'),
  mobility('灵活'),
  stretch('拉伸');

  const ExerciseCategory(this.zh);
  final String zh;
  static ExerciseCategory byName(String s) =>
      values.firstWhere((v) => v.name == s, orElse: () => mobility);
}

/// Equipment the user can tick. `mat`, `wall` and `block` (a book works) are
/// assumed at home; `chair` and `wall` are assumed at the office.
enum Equipment {
  none('徒手'),
  mat('瑜伽垫'),
  chair('椅子'),
  wall('墙'),
  band('弹力带'),
  dumbbell('哑铃'),
  block('瑜伽砖'),
  slider('滑垫');

  const Equipment(this.zh);
  final String zh;
  static Equipment byName(String s) =>
      values.firstWhere((v) => v.name == s, orElse: () => none);
}

/// Floor positions need a mat and are left out at the office.
const floorPositions = {'supine', 'prone', 'quadruped', 'kneeling', 'side_lying'};

class Dose {
  const Dose({
    required this.mode,
    required this.sets,
    this.reps,
    this.seconds,
    required this.restSeconds,
  });
  final DoseMode mode;
  final int sets;
  final int? reps;
  final int? seconds;
  final int restSeconds;

  factory Dose.fromJson(Map<String, dynamic> j) => Dose(
    mode: j['mode'] == 'reps' ? DoseMode.reps : DoseMode.time,
    sets: (j['sets'] as num).toInt(),
    reps: (j['reps'] as num?)?.toInt(),
    seconds: (j['seconds'] as num?)?.toInt(),
    restSeconds: (j['restSeconds'] as num?)?.toInt() ?? 20,
  );
}

class ExerciseMedia {
  const ExerciseMedia({
    required this.video,
    required this.poster,
    required this.loopSeconds,
    required this.posterSeconds,
    required this.source,
  });
  final String video;
  final String poster;
  final double loopSeconds;
  final double posterSeconds;
  final String source;

  /// The WebView player id: file name without extension (`sf-h-squat`).
  String get playerId => video.split('/').last.replaceAll('.mp4', '');

  factory ExerciseMedia.fromJson(Map<String, dynamic> j) => ExerciseMedia(
    video: j['video'] as String,
    poster: j['poster'] as String,
    loopSeconds: (j['loopSeconds'] as num).toDouble(),
    posterSeconds: (j['posterSeconds'] as num?)?.toDouble() ?? 0,
    source: j['source'] as String? ?? '',
  );
}

class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscles,
    required this.unilateral,
    required this.category,
    required this.equipment,
    required this.position,
    required this.level,
    required this.scenes,
    required this.dose,
    required this.repSeconds,
    required this.cue,
    required this.cautions,
    required this.alternative,
    required this.media,
  });

  final String id;
  final String name;
  final List<String> muscles;
  final bool unilateral;
  final ExerciseCategory category;
  final List<Equipment> equipment;
  final String position;

  /// 1 入门 · 2 基础 · 3 进阶.
  final int level;
  final List<String> scenes;
  final Dose dose;

  /// Seconds per repetition in the clip (reps mode only).
  final double? repSeconds;
  final String cue;

  /// Body parts to be careful with: 膝 腰 肩 手腕 颈 髋 大腿内侧.
  final List<String> cautions;
  final String? alternative;
  final ExerciseMedia media;

  bool get isFloor => floorPositions.contains(position);

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
    id: j['id'] as String,
    name: j['name'] as String,
    muscles: List<String>.from(j['muscles'] as List),
    unilateral: j['unilateral'] == true,
    category: ExerciseCategory.byName(j['category'] as String),
    equipment: [
      for (final e in j['equipment'] as List) Equipment.byName(e as String),
    ],
    position: j['position'] as String,
    level: (j['level'] as num).toInt(),
    scenes: List<String>.from(j['scenes'] as List),
    dose: Dose.fromJson(Map<String, dynamic>.from(j['dose'] as Map)),
    repSeconds: (j['repSeconds'] as num?)?.toDouble(),
    cue: j['cue'] as String,
    cautions: List<String>.from(j['cautions'] as List),
    alternative: j['alternative'] as String?,
    media: ExerciseMedia.fromJson(Map<String, dynamic>.from(j['media'] as Map)),
  );
}

class ExerciseLibrary {
  ExerciseLibrary(List<Exercise> list) : _byId = {for (final e in list) e.id: e};

  final Map<String, Exercise> _byId;

  Iterable<Exercise> get all => _byId.values;
  int get length => _byId.length;
  bool contains(String id) => _byId.containsKey(id);
  Exercise? tryGet(String id) => _byId[id];
  Exercise operator [](String id) =>
      _byId[id] ?? (throw ArgumentError('Unknown exercise id: $id'));

  factory ExerciseLibrary.fromJson(Map<String, dynamic> j) => ExerciseLibrary([
    for (final e in j['exercises'] as List)
      Exercise.fromJson(Map<String, dynamic>.from(e as Map)),
  ]);
}
