/// Drill packs (docs/drill-pack-spec.md, format 1): one folder per move with
/// its metadata, cover frame, demo clip and voice lines, plus the shared
/// `_common` pack (counts, units, calls, chimes). This file only reads the
/// format; it knows nothing about SmartFit's plans or sessions, so it can be
/// copied into another app together with the packs.
library;

import 'dart:convert';

/// Loads a text asset by path (rootBundle.loadString in the app, File in tests).
typedef PackTextLoader = Future<String> Function(String path);

const drillPackFormat = 'drill-pack';
const drillPackIndexFormat = 'drill-pack-index';
const drillPackFormatVersion = 1;
const commonPackId = '_common';

class DrillPackFormatException implements Exception {
  DrillPackFormatException(this.message);
  final String message;
  @override
  String toString() => 'DrillPackFormatException: $message';
}

/// One voice line: a clip per language at `voice/<lang>/<id>.m4a`.
class PackVoiceLine {
  const PackVoiceLine({
    required this.id,
    required this.role,
    required this.text,
    required this.ms,
  });

  final String id;

  /// name intro cue side_switch rest finish (exercise) · phrase unit count (common).
  final String role;
  final Map<String, String> text;

  /// Decoded clip length per language, in milliseconds.
  final Map<String, int> ms;

  factory PackVoiceLine.fromJson(Map<String, dynamic> j) => PackVoiceLine(
    id: j['id'] as String,
    role: j['role'] as String,
    text: Map<String, String>.from(j['text'] as Map),
    ms: {
      for (final e in Map<String, dynamic>.from(j['ms'] as Map? ?? const {}).entries)
        e.key: (e.value as num).toInt(),
    },
  );
}

class PackMedia {
  const PackMedia({
    required this.cover,
    required this.coverSeconds,
    required this.video,
    required this.loopSeconds,
    this.repSeconds,
    this.showsSide,
    this.width,
    this.height,
  });

  /// Paths relative to the pack folder.
  final String cover;
  final double coverSeconds;
  final String video;
  final double loopSeconds;
  final double? repSeconds;
  final String? showsSide;
  final int? width;
  final int? height;

  factory PackMedia.fromJson(Map<String, dynamic> j) => PackMedia(
    cover: j['cover'] as String,
    coverSeconds: (j['coverSeconds'] as num?)?.toDouble() ?? 0,
    video: j['video'] as String,
    loopSeconds: (j['loopSeconds'] as num).toDouble(),
    repSeconds: (j['repSeconds'] as num?)?.toDouble(),
    showsSide: j['showsSide'] as String?,
    width: (j['width'] as num?)?.toInt(),
    height: (j['height'] as num?)?.toInt(),
  );
}

class DrillPack {
  DrillPack({
    required this.id,
    required this.kind,
    required this.version,
    required this.folder,
    required this.json,
    required this.name,
    required this.languages,
    required this.lines,
    required this.chimes,
    this.media,
  });

  final String id;

  /// `exercise` or `common`.
  final String kind;
  final String version;

  /// Asset folder of the pack, e.g. `assets/packs/h-squat` (no trailing slash).
  final String folder;

  /// The whole pack.json, for fields an app interprets itself (dose, cues…).
  final Map<String, dynamic> json;
  final Map<String, String> name;
  final List<String> languages;
  final List<PackVoiceLine> lines;

  /// Chime name → path relative to the folder (common pack only).
  final Map<String, String> chimes;
  final PackMedia? media;

  bool get isCommon => kind == 'common';

  PackVoiceLine? line(String id) {
    for (final l in lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  Iterable<PackVoiceLine> linesWithRole(String role) =>
      lines.where((l) => l.role == role);

  String asset(String relative) => '$folder/$relative';
  String voiceAsset(String lineId, String lang) =>
      '$folder/voice/$lang/$lineId.m4a';

  factory DrillPack.fromJson(Map<String, dynamic> j, {required String folder}) {
    if (j['format'] != drillPackFormat) {
      throw DrillPackFormatException('$folder: not a drill pack');
    }
    if (j['formatVersion'] != drillPackFormatVersion) {
      throw DrillPackFormatException(
        '$folder: formatVersion ${j['formatVersion']} unsupported',
      );
    }
    final voice = Map<String, dynamic>.from(j['voice'] as Map? ?? const {});
    return DrillPack(
      id: j['id'] as String,
      kind: j['kind'] as String,
      version: j['version'] as String,
      folder: folder,
      json: j,
      name: Map<String, String>.from(j['name'] as Map),
      languages: List<String>.from(voice['languages'] as List? ?? const []),
      lines: [
        for (final l in voice['lines'] as List? ?? const [])
          PackVoiceLine.fromJson(Map<String, dynamic>.from(l as Map)),
      ],
      chimes: {
        for (final e in Map<String, dynamic>.from(j['chimes'] as Map? ?? const {}).entries)
          e.key: (e.value as Map)['file'] as String,
      },
      media: j['media'] == null
          ? null
          : PackMedia.fromJson(Map<String, dynamic>.from(j['media'] as Map)),
    );
  }
}

/// Every pack listed in `<root>/index.json`, common pack separate.
class PackSet {
  PackSet(this.common, this.exercises);

  final DrillPack common;
  final List<DrillPack> exercises;

  static const defaultRoot = 'assets/packs';

  static Future<PackSet> load(
    PackTextLoader read, {
    String root = defaultRoot,
  }) async {
    final index = jsonDecode(await read('$root/index.json')) as Map<String, dynamic>;
    if (index['format'] != drillPackIndexFormat ||
        index['formatVersion'] != drillPackFormatVersion) {
      throw DrillPackFormatException('$root/index.json: unsupported index');
    }
    final commonId = index['common'] as String? ?? commonPackId;
    final ids = [
      for (final e in index['packs'] as List) (e as Map)['id'] as String,
    ];
    final packs = await Future.wait([
      for (final id in ids)
        read('$root/$id/pack.json').then(
          (s) => DrillPack.fromJson(
            jsonDecode(s) as Map<String, dynamic>,
            folder: '$root/$id',
          ),
        ),
    ]);
    final common = packs.where((p) => p.id == commonId).firstOrNull;
    if (common == null) {
      throw DrillPackFormatException('$root: common pack $commonId missing');
    }
    return PackSet(common, [
      for (final p in packs)
        if (p.kind == 'exercise') p,
    ]);
  }
}
