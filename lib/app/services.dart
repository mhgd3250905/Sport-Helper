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
import '../domain/exercise.dart';
import '../domain/plan_generator.dart';
import '../domain/template.dart';
import '../packs/drill_pack.dart';

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
  }) : templates = TemplatePlanGenerator(lib: library, catalog: catalog);

  final ExerciseLibrary library;
  final TemplateCatalog catalog;
  final AppStore store;
  final VoiceSource voiceLibrary;
  final VoiceOutput voiceOutput;
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
  late final ChatController chat = ChatController(
    engine: chatEngine,
    store: store,
    replyDelay: chatReplyDelay,
  );

  /// The exercise library and the voice lines both come from the drill
  /// packs (assets/packs/, docs/drill-pack-spec.md); templates stay
  /// app-specific (assets/library/templates.json).
  static Future<
    (ExerciseLibrary, TemplateCatalog, DrillPackVoiceSource, coach.Catalog)
  >
  loadContent() async {
    final packs = await PackSet.load(rootBundle.loadString);
    final cat = TemplateCatalog.fromJson(
      jsonDecode(await rootBundle.loadString('assets/library/templates.json'))
          as Map<String, dynamic>,
    );
    return (
      ExerciseLibrary.fromPacks(packs),
      cat,
      DrillPackVoiceSource.fromPacks(
        common: packs.common.json,
        packs: {for (final p in packs.exercises) p.id: p.json},
      ),
      const coach.DrillPackAdapter().build(
        version: 'smartfit-bundled-1.1.0',
        packs: {for (final p in packs.exercises) p.id: p.json},
      ),
    );
  }

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;
  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
