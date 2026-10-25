import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_test_pack.dart';

/// Return the exact source bytes, or null when the declared file is not bundled.
/// The caller may explicitly read another verified source while packaging catches
/// up. This layer never guesses filesystem roots or falls back to an old pack.
typedef AppTestSemanticLoader =
    Future<List<int>?> Function(String relativePath);

enum AppTestSemanticStatus { missing, verified, rejected }

class AppTestSemanticSource {
  const AppTestSemanticSource({
    required this.path,
    required this.version,
    required this.bytes,
    required this.sha256,
  });

  final String path;
  final String version;
  final int bytes;
  final String sha256;

  static AppTestSemanticSource parse(Object? raw) {
    final map = _map(raw);
    final path = map['path'];
    final version = map['version'];
    final bytes = map['bytes'];
    final sha = map['sha256'];
    if (path is! String ||
        path.isEmpty ||
        path.contains('\\') ||
        path.contains('%') ||
        path.startsWith('/') ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..') ||
        Uri.parse(path).hasScheme ||
        Uri.parse(path).hasQuery ||
        Uri.parse(path).hasFragment ||
        version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        bytes is! int ||
        bytes <= 0 ||
        sha is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha)) {
      throw const FormatException('Invalid semantic catalog descriptor');
    }
    return AppTestSemanticSource(
      path: path,
      version: version,
      bytes: bytes,
      sha256: sha.toLowerCase(),
    );
  }
}

/// A usable definition is based on actual supplied fields, not an ID list,
/// historical pack, or review flag. Raw authored timing is retained losslessly.
class AppTestTrainingDefinition {
  AppTestTrainingDefinition._(this.drill, this.raw, this.source);

  final coach.Drill drill;
  final Map<String, Object?> raw;

  /// Present for legacy exact-ID joins. Inline delivery definitions are already
  /// covered by the bundled delivery catalog's integrity check.
  final AppTestSemanticSource? source;

  Map<String, Object?> get defaultDose =>
      raw['defaultDose']! as Map<String, Object?>;
  int? get holdSeconds => defaultDose['holdSeconds'] as int?;
  Map<String, Object?>? get rhythm => raw['rhythm'] as Map<String, Object?>?;
}

class AppTestCatalogEntry {
  AppTestCatalogEntry._({
    required this.id,
    required this.nameZh,
    required this.equipment,
    required this.revision,
    required this.media,
    required this.mediaFiles,
    required this.declaredAvailableForApp,
    required this.training,
    required this.trainingProblems,
    required this.raw,
  });

  final String id;
  final String nameZh;

  /// Raw IDs, including currently unfamiliar equipment. Empty means bodyweight.
  final List<String> equipment;
  final String? revision;

  /// Media already validated/bundled by AppTestPack; absence never hides a row.
  final AppTestAction? media;
  final Map<String, Object?> mediaFiles;
  final bool declaredAvailableForApp;
  final AppTestTrainingDefinition? training;
  final List<String> trainingProblems;
  final Map<String, Object?> raw;

  bool get trainingEligible => training != null;
  bool get mediaPlayable => media != null;
}

class AppTestCatalog {
  AppTestCatalog._(
    this._semanticJson, {
    required this.id,
    required this.entries,
    required this.semanticStatus,
    required this.semanticProblem,
    required this.semanticSource,
  });

  final String id;
  final Map<String, AppTestCatalogEntry> entries;
  final AppTestSemanticStatus semanticStatus;
  final String? semanticProblem;
  final AppTestSemanticSource? semanticSource;
  final Map<String, Object?>? _semanticJson;

  Iterable<String> get trainingEligibleIds => entries.values
      .where((entry) => entry.trainingEligible)
      .map((entry) => entry.id);

  /// Builds only new-plan definitions. This never changes saved plan JSON.
  /// Original raw rhythm/defaultDose fields remain available to the trainer's
  /// existing rhythmsFromCatalog helper.
  coach.Catalog? toCoachCatalog() {
    final source = _semanticJson;
    if (source == null && !entries.values.any((e) => e.trainingEligible)) {
      return null;
    }
    return coach.Catalog.fromJson({
      'format': coach.catalogFormat,
      'formatVersion': coach.supportedCatalogFormatVersion,
      'version': semanticSource?.version ?? '0.0.0',
      ...?source,
      'drills': [
        for (final entry in entries.values)
          if (entry.training case final training?) training.raw,
      ],
    });
  }

  static Future<AppTestCatalog> load({
    required String deliveryCatalogJson,
    String? manifestJson,
    AppTestSemanticLoader? readSemanticCatalog,
    Map<String, AppTestAction> bundledMedia = const {},
  }) async {
    final delivery = _map(jsonDecode(deliveryCatalogJson));
    if (delivery['format'] != 'pose-hub-app-test-catalog@1' ||
        !_text(delivery['id']) ||
        delivery['actions'] is! List) {
      throw const FormatException('Invalid app-test catalog');
    }
    final manifest = manifestJson == null
        ? const {}
        : _map(jsonDecode(manifestJson));
    final descriptor =
        delivery['semanticCatalog'] ?? manifest['semanticCatalog'];
    AppTestSemanticSource? source;
    Map<String, Object?>? semantic;
    var status = AppTestSemanticStatus.missing;
    String? problem = 'semantic_catalog_missing';
    if (descriptor != null) {
      try {
        source = AppTestSemanticSource.parse(descriptor);
        final bytes = await readSemanticCatalog?.call(source.path);
        if (bytes != null) {
          if (bytes.length != source.bytes ||
              coach.sha256Hex(bytes) != source.sha256) {
            throw const FormatException('semantic_catalog_integrity');
          }
          final decoded = _map(jsonDecode(utf8.decode(bytes)));
          if (decoded['format'] != coach.catalogFormat ||
              decoded['formatVersion'] != coach.supportedCatalogFormatVersion ||
              decoded['version'] != source.version ||
              decoded['drills'] is! List) {
            throw const FormatException('semantic_catalog_format_or_version');
          }
          semantic = _freezeMap(decoded);
          status = AppTestSemanticStatus.verified;
          problem = null;
        }
      } on FormatException {
        status = AppTestSemanticStatus.rejected;
        problem = 'semantic_catalog_rejected';
      } on Object {
        problem = 'semantic_catalog_unavailable';
      }
    }

    final definitions = <String, Map<String, Object?>>{};
    if (semantic != null) {
      for (final value in semantic['drills']! as List) {
        final row = _map(value);
        final id = row['id'];
        if (!_text(id) || definitions.containsKey(id)) {
          // Ambiguous source identity cannot select an arbitrary prescription.
          status = AppTestSemanticStatus.rejected;
          problem = 'semantic_catalog_duplicate_or_invalid_id';
          definitions.clear();
          semantic = null;
          break;
        }
        definitions[id! as String] = row;
      }
    }
    final entries = <String, AppTestCatalogEntry>{};
    for (final value in delivery['actions']! as List) {
      final row = _map(value);
      final id = row['id'];
      if (!_text(id) || !_text(row['nameZh']) || !_strings(row['equipment'])) {
        throw const FormatException(
          'Invalid app-test catalog identity/equipment',
        );
      }
      final actionId = id! as String;
      if (entries.containsKey(actionId)) {
        throw const FormatException('Duplicate app-test catalog action id');
      }
      // Current exports carry authored training fields directly on each row.
      // Once present, those fields are authoritative, even when incomplete;
      // never silently restore an old dose from the separate legacy catalog.
      final inline = _trainingFields.any(row.containsKey);
      final definition = inline
          ? <String, Object?>{
              for (final field in _trainingFields)
                if (row.containsKey(field)) field: row[field],
              'rhythm': ?_map(row['rhythm'])['execution'],
            }
          : definitions[actionId];
      final joined = <String, Object?>{
        'id': actionId,
        'name': {'zh': row['nameZh']},
        'equipment': row['equipment'],
        if (row['muscleGroups'] != null) 'muscleGroups': row['muscleGroups'],
        ...?definition,
      };
      final problems = definition == null
          ? ['semantic_definition_missing']
          : _trainingProblems(joined, semantic ?? const {});
      AppTestTrainingDefinition? training;
      if (problems.isEmpty) {
        final parsed = coach.Drill.tryParse(joined, problems);
        if (parsed != null) {
          training = AppTestTrainingDefinition._(
            parsed,
            _freezeMap(joined),
            inline ? null : source,
          );
        }
      }
      final name = _map(joined['name'])['zh'];
      final equipment = joined['equipment'];
      final media = bundledMedia[actionId];
      if (media != null &&
          (media.id != actionId || media.revision != row['revision'])) {
        throw const FormatException(
          'Bundled test media identity/revision mismatch',
        );
      }
      entries[actionId] = AppTestCatalogEntry._(
        id: actionId,
        nameZh: _text(name) ? name! as String : row['nameZh']! as String,
        equipment: List.unmodifiable(
          List<String>.from(
            _strings(equipment)
                ? equipment! as List
                : row['equipment']! as List,
          ),
        ),
        revision: row['revision'] as String?,
        media: media,
        mediaFiles: _freezeMap(_map(row['files'])),
        declaredAvailableForApp: row['availableForApp'] == true,
        training: training,
        trainingProblems: List.unmodifiable(problems),
        raw: _freezeMap(row),
      );
    }
    if (bundledMedia.keys.any((id) => !entries.containsKey(id))) {
      throw const FormatException('Bundled test media absent from catalog');
    }
    return AppTestCatalog._(
      semantic,
      id: delivery['id']! as String,
      entries: Map.unmodifiable(entries),
      semanticStatus: status,
      semanticProblem: problem,
      semanticSource: source,
    );
  }
}

const _trainingFields = [
  'category',
  'purpose',
  'muscles',
  'position',
  'unilateral',
  'level',
  'scenes',
  'defaultDose',
  'doseRange',
  'cues',
  'primaryCue',
  'cautions',
  'contraindications',
  'alternative',
];

List<String> _trainingProblems(
  Map<String, Object?> row,
  Map<String, Object?> catalog,
) {
  final problems = <String>[];
  if (!_text(_map(row['name'])['zh'])) problems.add('name.zh');
  if (!const [
    'strength',
    'core',
    'cardio',
    'mobility',
    'stretch',
  ].contains(row['category'])) {
    problems.add('category');
  }
  if (!const [1, 2, 3].contains(row['level']) || row['level'] is! int) {
    problems.add('level');
  }
  final position = row['position'];
  final positions = _map(_map(catalog['taxonomy'])['positions']);
  if (!_text(position) ||
      (positions.isNotEmpty && !positions.containsKey(position))) {
    problems.add('position');
  }
  if (row['unilateral'] is! bool) problems.add('unilateral');
  if (!_strings(row['equipment'])) problems.add('equipment');
  final scenes = row['scenes'];
  if (!_strings(scenes, nonempty: true) ||
      (scenes! as List).any(
        (scene) => !const ['home', 'office', 'gym'].contains(scene),
      )) {
    problems.add('scenes');
  }
  if (!_strings(_map(row['cues'])['zh'], nonempty: true)) {
    problems.add('cues.zh');
  }
  final dose = _map(row['defaultDose']);
  if (!const ['reps', 'time'].contains(dose['mode'])) {
    problems.add('defaultDose.mode');
  }
  if (!_integer(dose['sets'], 1, 6)) problems.add('defaultDose.sets');
  if (!_integer(dose['restSeconds'], 0, 180)) {
    problems.add('defaultDose.restSeconds');
  }
  if (dose['mode'] == 'reps' && !_integer(dose['reps'], 1, 30)) {
    problems.add('defaultDose.reps');
  }
  if (dose['mode'] == 'time' &&
      !_integer(dose['seconds'] ?? dose['workSeconds'], 10, 120)) {
    problems.add('defaultDose.seconds');
  }
  if (dose.containsKey('holdSeconds') &&
      (dose['mode'] != 'reps' || !_integer(dose['holdSeconds'], 1, 120))) {
    problems.add('defaultDose.holdSeconds');
  }
  for (final field in [
    'muscles',
    'muscleGroups',
    'cautions',
    'contraindications',
  ]) {
    if (row.containsKey(field) && !_strings(row[field])) problems.add(field);
  }
  if (row.containsKey('doseRange')) {
    final ranges = row['doseRange'];
    if (ranges is! Map ||
        ranges.values.any(
          (value) =>
              value is! List ||
              value.length != 2 ||
              value.any((v) => v is! int || v < 0) ||
              (value[0] as int) > (value[1] as int),
        )) {
      problems.add('doseRange');
    }
  }
  if (row.containsKey('rhythm')) {
    final rhythm = _map(row['rhythm']);
    final phases = rhythm['phases'];
    final staticHold = rhythm['kind'] == 'hold' && phases == null;
    if (!_text(rhythm['kind']) ||
        (!staticHold &&
            (phases is! List ||
                phases.isEmpty ||
                phases.any(
                  (phase) =>
                      !_text(_map(phase)['id']) ||
                      _map(phase)['seconds'] is! num ||
                      !(_map(phase)['seconds']! as num).isFinite ||
                      (_map(phase)['seconds']! as num) < 0,
                )))) {
      problems.add('rhythm');
    }
  }
  return problems;
}

bool _text(Object? value) => value is String && value.trim().isNotEmpty;
bool _integer(Object? value, int low, int high) =>
    value is int && value >= low && value <= high;
bool _strings(Object? value, {bool nonempty = false}) =>
    value is List && (!nonempty || value.isNotEmpty) && value.every(_text);
Map<String, Object?> _map(Object? value) => value is Map
    ? {for (final entry in value.entries) entry.key.toString(): entry.value}
    : {};
Map<String, Object?> _freezeMap(Map<String, Object?> map) => Map.unmodifiable({
  for (final entry in map.entries) entry.key: _freeze(entry.value),
});
Object? _freeze(Object? value) => value is Map
    ? _freezeMap(_map(value))
    : value is List
    ? List<Object?>.unmodifiable(value.map(_freeze))
    : value;
