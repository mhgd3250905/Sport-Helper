import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../chat/ai_coach_config.dart';
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
import 'coach_chat.dart';
import 'training_media_config.dart';
import 'app_test_pack.dart';
import 'app_test_catalog.dart';
import 'posehub_media_repository.dart';
import 'posehub_media_preparer.dart';

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
    this.agentMode = CoachChatAgentMode.legacy,
    this.appAiTags = const {},
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
  final CoachChatAgentMode agentMode;
  final Map<String, Map<String, Object?>> appAiTags;
  final AppTestCatalog? testCatalog;
  final coach.PoseHubAppTestCatalog? poseHubCatalog;
  final PoseHubMediaRepository? poseHubMedia;
  late final SmartFitPoseHubMediaPreparer? poseHubPreparer =
      poseHubCatalog == null
      ? null
      : SmartFitPoseHubMediaPreparer(poseHubMedia);
  final TemplateCatalog catalog;
  final AppStore store;
  final VoiceSource voiceLibrary;
  final VoiceOutput voiceOutput;
  final TrainingMediaRepository? media;
  TrainingMediaLog? _mediaLog;
  String? _prefetchedPlan;
  int _prefetchEpoch = 0;

  void _prefetchChatPlan() {
    final plan = chat.currentPlan;
    prefetchPlan(plan == null ? null : TrainingPlan.fromJson(plan.toJson()));
  }

  /// Start downloads without delaying navigation, the clock or voice output.
  void prefetchPlan(TrainingPlan? plan) {
    if (plan == null || (media == null && poseHubMedia == null)) return;
    final ids = plan.exerciseIds;
    final signature = '${plan.id}/${ids.join(',')}';
    if (_prefetchedPlan == signature) return;
    _prefetchedPlan = signature;
    final epoch = ++_prefetchEpoch;
    final log = RuntimeLog.instance;
    final operation = log.newOperation('prefetch');
    log.record(
      'media.prefetch_start',
      operation: operation,
      fields: {
        'count': ids.length,
        if (media != null) 'offline': media!.isOffline,
      },
    );
    final timer = Stopwatch()..start();
    unawaited(
      (poseHubMedia != null
              ? _prefetchPoseHub(ids, epoch)
              : media!.prefetchActions(ids))
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
          })
          .whenComplete(() {
            if (_prefetchedPlan == signature) _prefetchedPlan = null;
          }),
    );
  }

  Future<void> _prefetchPoseHub(Iterable<String> ids, int epoch) async {
    final repository = poseHubMedia!;
    final ordered = ids
        .where((id) => poseHubCatalog?.tryGet(id) != null)
        .toSet()
        .toList(growable: false);
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (epoch == _prefetchEpoch && next < ordered.length) {
        final id = ordered[next++];
        try {
          await repository.ensureAction(id);
        } on Object {
          failed = true;
        }
      }
    }

    // Start the first action before the second worker; never hold navigation,
    // training clocks or voice while these two ordered workers prepare files.
    await Future.wait([worker(), worker()]);
    if (failed) {
      throw const PoseHubMediaException(
        'prefetch_failed',
        'Some training videos could not be cached.',
      );
    }
  }

  final coach.Catalog? coachCatalog;
  final coach.CoachProfile? coachProfile;
  final AiCoachConfig aiConfig;
  final String? deviceId;
  final coach.UserMemoryStore? memoryStore;
  coach.UserMemoryStore get userMemoryStore =>
      memoryStore ?? store.aiMemoryStore;

  /// The optional completion-page receipt updates the already saved workout.
  /// This local feedback never becomes a coach turn, memory or recommendation.
  /// Throwing preserves the SDK completion page's retry of the same receipt.
  Future<void> recordTrainingCompletion(SessionResult result) async {
    final fields = <String, Object?>{
      'feeling': result.feeling?.name ?? 'unselected',
      'completed': result.completedExercises,
      'total': result.totalExercises,
    };
    try {
      await store.saveSession(result);
      RuntimeLog.instance.record(
        'training.completion.feedback',
        fields: {...fields, 'success': true},
      );
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'training.completion.feedback',
        fields: {
          ...fields,
          'success': false,
          'errorType': RuntimeLog.errorType(error),
        },
      );
      rethrow;
    }
  }

  Future<void> setAiMemoryEnabled(bool enabled) async {
    final controller = _chat;
    if (controller != null) {
      await controller.start();
      controller.agent.enableUserMemory = enabled;
    }
    await store.setAiMemoryEnabled(enabled);
    await _chat?.flushPersistence();
    RuntimeLog.instance.record(
      'settings.ai_memory',
      fields: {'enabled': enabled},
    );
  }

  Future<void> clearAiMemory() async {
    final controller = _chat;
    if (controller != null) {
      await controller.start();
      await controller.agent.clearMemory();
    } else {
      await userMemoryStore.save([]);
    }
    if ((await userMemoryStore.load()).isNotEmpty) {
      throw StateError('AI memory could not be cleared from local storage');
    }
    await _chat?.flushPersistence();
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
    final controller = _chat;
    if (controller != null) {
      await controller.close();
      controller.dispose();
    }
    _mediaLog?.dispose();
    media?.dispose();
    final output = voiceOutput;
    if (output is JustAudioVoiceOutput) {
      await output.dispose();
    } else {
      await output.end();
    }
  }

  /// The original reply pause; tests may opt into a zero duration.
  final Duration chatReplyDelay;

  /// One SDK controller owns conversation, history, tools and training returns.
  CoachChatController? _chat;
  CoachChatController get chat => _chat ??= _createChat();

  CoachChatController _createChat() {
    final controller = createSmartfitChat(this);
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
