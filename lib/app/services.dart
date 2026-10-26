import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../chat/chat_controller.dart';
import '../chat/ai_chat_engine.dart';
import '../chat/ai_coach_config.dart';
import '../chat/chat_models.dart';
import '../chat/rule_chat_engine.dart';
import '../data/app_store.dart';
import '../diagnostics/runtime_log.dart';
import '../diagnostics/training_media_log.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_generator.dart';
import '../domain/template.dart';
import '../packs/drill_pack.dart';
import '../voice/voice_asset_bundle.dart';
import '../voice/voice_library.dart';
import 'training_media_config.dart';
import 'app_test_pack.dart';
import 'app_test_catalog.dart';
import 'posehub_media_repository.dart';

/// Everything pages need, created once at start-up.
class AppServices {
  AppServices({
    required this.library,
    required this.catalog,
    required this.store,
    required this.voiceLibrary,
    required this.voiceOutput,
    this.coachCatalog,
    this.coachProfile,
    this.aiConfig = const AiCoachConfig.fromEnvironment(),
    this.deviceId,
    this.memoryStore,
    this.chatReplyDelay = const Duration(milliseconds: 450),
    this.media,
    this.testCatalog,
    this.poseHubCatalog,
    this.poseHubMedia,
  }) : templates = TemplatePlanGenerator(
         lib: library,
         catalog: catalog,
         preferredExerciseIds: () => media?.isOffline == true
             ? media!.readyActionIds
             : const <String>{},
         onGenerated: (plan) {
           RuntimeLog.instance.record(
             'plan.generated',
             fields: {'source': 'template', 'count': plan.items.length},
           );
           if (media != null) {
             unawaited(
               media.prefetchActions(plan.exerciseIds).catchError((
                 Object error,
               ) {
                 RuntimeLog.instance.record(
                   'media.prefetch_error',
                   fields: {'errorType': RuntimeLog.errorType(error)},
                 );
               }),
             );
           }
         },
       ) {
    if (media != null) {
      _mediaLog = TrainingMediaLog(media!)..start();
    }
  }

  final ExerciseLibrary library;
  final AppTestCatalog? testCatalog;
  final coach.PoseHubAppTestCatalog? poseHubCatalog;
  final PoseHubMediaRepository? poseHubMedia;
  final TemplateCatalog catalog;
  final AppStore store;
  final VoiceSource voiceLibrary;
  final VoiceOutput voiceOutput;
  final TrainingMediaRepository? media;
  TrainingMediaLog? _mediaLog;
  String? _prefetchedPlan;

  void _prefetchChatPlan() => prefetchPlan(chat.currentPlan);

  /// Start downloads without delaying navigation, the clock or voice output.
  void prefetchPlan(TrainingPlan? plan) {
    final repository = media;
    if (repository == null || plan == null) return;
    final ids = plan.exerciseIds;
    final signature = '${plan.id}/${ids.join(',')}';
    if (_prefetchedPlan == signature) return;
    _prefetchedPlan = signature;
    final log = RuntimeLog.instance;
    final operation = log.newOperation('prefetch');
    log.record(
      'media.prefetch_start',
      operation: operation,
      fields: {'count': ids.length, 'offline': repository.isOffline},
    );
    final timer = Stopwatch()..start();
    unawaited(
      repository
          .prefetchActions(ids)
          .then((_) {
            log.record(
              'media.prefetch_end',
              operation: operation,
              fields: {
                'count': ids.length,
                'elapsedMs': timer.elapsedMilliseconds,
              },
            );
          })
          .catchError((Object error) {
            log.record(
              'media.prefetch_error',
              operation: operation,
              fields: {
                'errorType': RuntimeLog.errorType(error),
                'elapsedMs': timer.elapsedMilliseconds,
              },
            );
          }),
    );
  }

  final coach.Catalog? coachCatalog;
  final coach.CoachProfile? coachProfile;
  final AiCoachConfig aiConfig;
  final String? deviceId;
  final coach.UserMemoryStore? memoryStore;
  coach.UserMemoryStore get userMemoryStore =>
      memoryStore ?? store.aiMemoryStore;

  Future<void> setAiMemoryEnabled(bool enabled) async {
    final engine = chatEngine;
    if (engine is AiChatEngine) engine.enableUserMemory = enabled;
    await store.setAiMemoryEnabled(enabled);
    RuntimeLog.instance.record(
      'settings.ai_memory',
      fields: {'enabled': enabled},
    );
  }

  Future<void> clearAiMemory() async {
    final engine = chatEngine;
    if (engine is AiChatEngine) {
      await engine.clearMemory();
    } else {
      await userMemoryStore.save([]);
      if ((await userMemoryStore.load()).isNotEmpty) {
        throw StateError('AI memory could not be cleared from local storage');
      }
    }
    RuntimeLog.instance.record('settings.ai_memory_cleared');
  }

  /// Manual forms stay deterministic; AI enters through the chat engine.
  final TemplatePlanGenerator templates;
  PlanGenerator get generator => templates;

  TrainerVoice trainerVoice() => TrainerVoice(
    source: voiceLibrary,
    output: voiceOutput,
    settings: store.voice.toTrainerSettings(),
  );

  /// The output belongs to the App, so page navigation never destroys it.
  Future<void> dispose() async {
    chat.dispose();
    _mediaLog?.dispose();
    media?.dispose();
    if (chatEngine case final ManagedChatEngine managed) managed.dispose();
    final output = voiceOutput;
    if (output is JustAudioVoiceOutput) {
      await output.dispose();
    } else {
      await output.end();
    }
  }

  /// No token means the original offline engine; a token never goes to storage.
  late final ChatEngine chatEngine = _createChatEngine();

  ChatEngine _createChatEngine() {
    final local = RuleChatEngine(lib: library, templates: templates);
    final catalog = coachCatalog;
    final profile = coachProfile;
    final id = deviceId;
    RuntimeLog.instance.record(
      'chat.engine',
      fields: {
        'hasKey': aiConfig.enabled,
        'hasDeviceIdentity': id != null,
        'available': catalog != null && profile != null,
        'catalogCount': catalog?.length ?? 0,
        'route':
            !aiConfig.enabled ||
                catalog == null ||
                profile == null ||
                id == null
            ? 'local'
            : 'sdk',
        'reason': !aiConfig.enabled
            ? 'missing_key'
            : id == null
            ? 'identity_unavailable'
            : catalog == null
            ? 'catalog_unavailable'
            : profile == null
            ? 'profile_unavailable'
            : 'configured',
      },
    );
    if (!aiConfig.enabled || catalog == null || profile == null || id == null) {
      return local;
    }
    return AiChatEngine(
      local: local,
      catalog: catalog,
      profile: profile,
      client: aiConfig.createClient(deviceId: id),
      memoryStore: userMemoryStore,
      enableUserMemory: store.aiMemoryEnabled,
    );
  }

  /// The "typing" pause before a reply (zero in tests and screenshots).
  final Duration chatReplyDelay;

  /// The home conversation lives as long as the app (pages come and go).
  late final ChatController chat = _createChat();

  ChatController _createChat() {
    final controller = ChatController(
      engine: chatEngine,
      store: store,
      replyDelay: chatReplyDelay,
      prepareReply: media == null
          ? null
          : () async {
              await media!.canDownload();
            },
    );
    if (media != null) controller.addListener(_prefetchChatPlan);
    return controller;
  }

  /// The exercise library and the voice lines both come from the drill
  /// packs (assets/packs/, docs/drill-pack-spec.md); templates stay
  /// app-specific (assets/library/templates.json).
  static Future<(ExerciseLibrary, TemplateCatalog, VoiceLibrary, coach.Catalog)>
  loadContent({TrainingMediaRepository? media, AppTestPack? testPack}) async {
    final packs = await PackSet.load(rootBundle.loadString);
    final manifest =
        jsonDecode(
              await rootBundle.loadString(TrainingMediaConfig.manifestAsset),
            )
            as Map<String, dynamic>;
    final allowed = media != null
        ? media.visibleActions.map((a) => a.id).toSet()
        : {
            for (final action in manifest['actions'] as List)
              if ((action as Map)['releaseEligible'] == true ||
                  TrainingMediaConfig.includePending)
                action['id'] as String,
          };
    final bundledAssets =
        (jsonDecode(await rootBundle.loadString(TrainingMediaConfig.assetIndex))
                as Map<String, dynamic>)['actions']
            as Map<String, dynamic>;
    final visiblePacks = [
      for (final p in packs.exercises)
        if (allowed.contains(p.id)) p,
    ];
    final cat = TemplateCatalog.fromJson(
      jsonDecode(await rootBundle.loadString('assets/library/templates.json'))
          as Map<String, dynamic>,
    );
    return (
      ExerciseLibrary([
        for (final p in visiblePacks)
          Exercise.fromPack(
            p,
            mediaOverride: _testMedia(
              testPack,
              p.id,
              ExerciseMedia.fromPoseHub(
                p,
                version: manifest['version'] as String,
                assets: Map<String, dynamic>.from(bundledAssets[p.id] as Map),
              ),
            ),
          ),
      ]),
      cat,
      VoiceLibrary.fromPacks(
        packs,
        bundle: await VoiceAssetBundle.load(rootBundle.loadString),
      ),
      const coach.DrillPackAdapter().build(
        version: 'smartfit-pose-hub-${manifest['version']}',
        packs: {for (final p in visiblePacks) p.id: p.json},
      ),
    );
  }

  static ExerciseMedia _testMedia(
    AppTestPack? pack,
    String id,
    ExerciseMedia fallback,
  ) => pack?.actions[id]?.applyTo(fallback) ?? fallback;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;
  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
