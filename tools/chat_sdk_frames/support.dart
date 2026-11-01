import 'dart:convert';
import 'dart:io';

import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/packs/drill_pack.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_asset_bundle.dart';

/// The bundled drill packs, read straight from assets/packs (tests run from
/// the package root).
Future<PackSet> loadPacks() =>
    PackSet.load((path) async => File(path).readAsStringSync());

PackSet? _packs;

/// Synchronous variant for test bodies that build fixtures at the top level.
PackSet loadPacksSync() {
  if (_packs != null) return _packs!;
  final root = PackSet.defaultRoot;
  final index =
      jsonDecode(File('$root/index.json').readAsStringSync())
          as Map<String, dynamic>;
  final packs = [
    for (final e in index['packs'] as List)
      DrillPack.fromJson(
        jsonDecode(File('$root/${e['id']}/pack.json').readAsStringSync())
            as Map<String, dynamic>,
        folder: '$root/${e['id']}',
      ),
  ];
  return _packs = PackSet(packs.firstWhere((p) => p.isCommon), [
    for (final p in packs)
      if (!p.isCommon) p,
  ]);
}

/// Keep the full metadata fixture while resolving media through the release
/// manifest layout. The old pack media paths remain historical metadata only.
ExerciseLibrary loadLibrary() {
  final assets =
      (jsonDecode(
                File(
                  'assets/training_media/v0.3.0-app/assets-index.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['actions']
          as Map<String, dynamic>;
  return ExerciseLibrary([
    for (final pack in loadPacksSync().exercises)
      Exercise.fromPack(
        pack,
        mediaOverride: ExerciseMedia.fromPoseHub(
          pack,
          assets: Map<String, dynamic>.from(assets[pack.id] as Map),
        ),
      ),
  ]);
}

VoiceLibrary loadVoices() => VoiceLibrary.fromPacks(
  loadPacksSync(),
  bundle: VoiceAssetBundle.fromJson(
    jsonDecode(File(VoiceAssetBundle.manifestAsset).readAsStringSync())
        as Map<String, dynamic>,
  ),
);

TemplateCatalog loadCatalog() => TemplateCatalog.fromJson(
  jsonDecode(File('assets/library/templates.json').readAsStringSync())
      as Map<String, dynamic>,
);
