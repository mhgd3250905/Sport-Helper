/// One move in the exercise library. Each move comes from its drill pack
/// (`assets/packs/<id>/pack.json`, docs/drill-pack-spec.md). Ids are the
/// 3D-Pose-Hub drill ids.
library;

import '../packs/drill_pack.dart';

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
const floorPositions = {
  'supine',
  'prone',
  'quadruped',
  'kneeling',
  'side_lying',
};

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
    required this.id,
    required this.video,
    required this.poster,
    required this.loopSeconds,
    required this.posterSeconds,
    required this.source,
    this.videoAvailable = true,
    this.lightVideo,
    this.lightPoster,
    this.lightVideoAvailable,
  });

  /// Pack id; the WebView player plays `/packs/<id>/demo.mp4`.
  final String id;

  /// Asset paths (`assets/packs/<id>/demo.mp4`, `…/cover.jpg`).
  final String video;
  final String poster;
  final double loopSeconds;
  final double posterSeconds;
  final String source;
  final bool videoAvailable;

  /// Light-stage render of the same clip / cover, when the pack has one.
  final String? lightVideo;
  final String? lightPoster;
  final bool? lightVideoAvailable;

  bool get hasLight => lightPoster != null;

  bool videoAvailableFor({required bool light}) =>
      light ? (lightVideoAvailable ?? lightVideo != null) : videoAvailable;

  String get playerId => id;

  factory ExerciseMedia.fromPoseHub(
    DrillPack p, {
    String version = '0.3.0',
    required Map<String, dynamic> assets,
  }) {
    String? asset(String theme, String role) {
      final entry = (assets[theme] as Map?)?[role];
      if (entry == null) return null;
      final path = (entry as Map)['asset'] as String?;
      if (path == null ||
          !path.startsWith('assets/training_media/') ||
          path.contains('..') ||
          path.contains('\\')) {
        throw FormatException('Invalid bundled media asset for ${p.id}');
      }
      return path;
    }

    final darkPoster = asset('dark', 'poster');
    final lightPoster = asset('light', 'poster');
    if (darkPoster == null || lightPoster == null) {
      throw FormatException('Both theme stills are required for ${p.id}');
    }
    final darkVideo = asset('dark', 'video');
    final lightVideo = asset('light', 'video');
    return ExerciseMedia(
      id: p.id,
      video: darkVideo ?? '',
      poster: darkPoster,
      loopSeconds: p.media?.loopSeconds ?? 8,
      posterSeconds: 0,
      source: 'Pose-Hub $version',
      videoAvailable: darkVideo != null,
      lightVideo: lightVideo,
      lightPoster: lightPoster,
      lightVideoAvailable: lightVideo != null,
    );
  }

  factory ExerciseMedia.fromPack(DrillPack p) {
    final m = p.media!;
    return ExerciseMedia(
      id: p.id,
      video: p.asset(m.video),
      poster: p.asset(m.cover),
      loopSeconds: m.loopSeconds,
      posterSeconds: m.coverSeconds,
      source: (p.json['credits'] as Map?)?['mediaSource'] as String? ?? '',
      lightVideo: m.lightVideo == null ? null : p.asset(m.lightVideo!),
      lightPoster: m.lightCover == null ? null : p.asset(m.lightCover!),
    );
  }
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
    required this.cues,
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

  /// Key points in the order they are spoken (1–3).
  final List<String> cues;

  /// All key points as one line, for display.
  String get cue => cues.join('；');

  /// Body parts to be careful with: 膝 腰 肩 手腕 颈 髋 大腿内侧.
  final List<String> cautions;
  final String? alternative;
  final ExerciseMedia media;

  bool get isFloor => floorPositions.contains(position);

  factory Exercise.fromPack(DrillPack p, {ExerciseMedia? mediaOverride}) {
    final j = p.json;
    final dose = Map<String, dynamic>.from(j['defaultDose'] as Map);
    return Exercise(
      id: p.id,
      name: p.name['zh'] ?? p.id,
      muscles: List<String>.from(j['muscles'] as List),
      unilateral: j['unilateral'] == true,
      category: ExerciseCategory.byName(j['category'] as String),
      equipment: [
        for (final e in j['equipment'] as List) Equipment.byName(e as String),
      ],
      position: j['position'] as String,
      level: (j['level'] as num).toInt(),
      scenes: List<String>.from(j['scenes'] as List),
      dose: Dose.fromJson(dose),
      repSeconds: dose['mode'] == 'reps' ? p.media?.repSeconds : null,
      cues: List<String>.from((j['cues'] as Map)['zh'] as List),
      cautions: List<String>.from(j['cautions'] as List),
      alternative: j['alternative'] as String?,
      media: mediaOverride ?? ExerciseMedia.fromPack(p),
    );
  }
}

class ExerciseLibrary {
  ExerciseLibrary(List<Exercise> list)
    : _byId = {for (final e in list) e.id: e};

  final Map<String, Exercise> _byId;

  Iterable<Exercise> get all => _byId.values;
  int get length => _byId.length;
  bool contains(String id) => _byId.containsKey(id);
  Exercise? tryGet(String id) => _byId[id];
  Exercise operator [](String id) =>
      _byId[id] ?? (throw ArgumentError('Unknown exercise id: $id'));

  factory ExerciseLibrary.fromPacks(PackSet packs) =>
      ExerciseLibrary([for (final p in packs.exercises) Exercise.fromPack(p)]);
}
