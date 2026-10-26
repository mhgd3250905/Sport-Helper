import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartfit/app/posehub_pack_installation.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

class PoseHubUiStorage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

AppServices poseHubUiServices({
  required coach.PoseHubAppTestCatalog catalog,
  required PoseHubPackInstallation installation,
  ExerciseLibrary? library,
}) => AppServices(
  library: library ?? ExerciseLibrary([]),
  catalog: TemplateCatalog([]),
  store: AppStore(PoseHubUiStorage())..starfield = false,
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
  poseHubCatalog: catalog,
  poseHubMedia: installation,
);

Widget poseHubUiApp({
  required SfPalette palette,
  required Widget home,
  AppServices? services,
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    theme: buildTheme(palette),
    builder: (_, child) => SfPaletteScope(child: child!),
    home: home,
  );
  return services == null ? app : AppScope(services: services, child: app);
}

Exercise poseHubUiExercise(coach.PoseHubPackAction action) => Exercise(
  id: action.id,
  name: action.nameZh,
  muscles: const [],
  unilateral: false,
  category: ExerciseCategory.core,
  equipment: const [],
  position: 'supine',
  level: 1,
  scenes: const ['home'],
  dose: const Dose(mode: DoseMode.time, sets: 1, seconds: 30, restSeconds: 0),
  repSeconds: null,
  cues: const [],
  cautions: const [],
  alternative: null,
  media: ExerciseMedia(
    id: action.id,
    video: 'assets/old-video-must-not-load.mp4',
    poster: 'assets/old-poster-must-not-load.webp',
    loopSeconds: 8,
    posterSeconds: 0,
    source: 'test-only old resolver seam',
    revision: action.raw['revision'] as String?,
  ),
);

/// Fake native transport only: the actual SDK widgets, URI resolver and
/// controller still run. No composed-video or device-performance claim.
class PoseHubUiVideoPlatform extends PackedAlphaPlatform
    implements PackedAlphaUriPlatform {
  final uris = <Uri>[];
  final commands = <(int, String, Object?)>[];
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);

  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('PoseHub media must resolve an external file URI');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    uris.add(uri);
    return (playerId: uris.length, textureId: uris.length + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    commands.add((id, type, value));
    return null;
  }

  void ready(int id) => _events.add({'playerId': id, 'type': 'ready'});
  Future<void> close() => _events.close();
}
