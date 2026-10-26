import 'dart:convert';
import 'dart:io';

import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';
import 'support.dart';

class SettingsCacheRepository extends PoseHubUiRepository
    implements PoseHubVideoCache {
  SettingsCacheRepository({this.bytes = 86000000})
    : super(mediaBaseUri: Uri.parse('file:///settings-ui-contract/'));
  int bytes;
  int clears = 0;
  bool failClear = false;
  @override
  Future<int> videoCacheBytes() async => bytes;
  @override
  Future<void> clearVideoCache() async {
    clears++;
    if (failClear) throw StateError('UI-only cache failure');
    bytes = 0;
  }
}

AppServices settingsServices({
  bool ai = true,
  SettingsCacheRepository? cache,
  AppStore? store,
}) {
  final packs = loadPacksSync();
  return AppServices(
    library: loadLibrary(),
    catalog: loadCatalog(),
    store: store ?? AppStore(PoseHubUiStorage(), actionIssueEnabled: true),
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    poseHubMedia: cache,
    coachCatalog: ai
        ? const coach.DrillPackAdapter().build(
            version: 'settings-ui-contract',
            packs: {for (final pack in packs.exercises) pack.id: pack.json},
          )
        : null,
    coachProfile: ai
        ? coach.CoachProfile.fromJson(
            jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
          )
        : null,
    aiConfig: ai
        ? const AiCoachConfig(token: 'settings-ui-fixture-only')
        : const AiCoachConfig(),
    deviceId: ai ? '7a318be8-d0b7-4c83-8b7a-2a5aaecf9f66' : null,
    chatReplyDelay: Duration.zero,
  );
}
