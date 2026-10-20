import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../chat/chat_controller.dart';
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
    this.chatReplyDelay = const Duration(milliseconds: 450),
  }) : templates = TemplatePlanGenerator(lib: library, catalog: catalog);

  final ExerciseLibrary library;
  final TemplateCatalog catalog;
  final AppStore store;
  final VoiceSource voiceLibrary;
  final VoiceOutput voiceOutput;

  /// MVP: fixed templates only. An AI generator plugs in behind the same
  /// interface later (see AiPlanGenerator).
  final TemplatePlanGenerator templates;
  PlanGenerator get generator => templates;

  TrainerVoice trainerVoice() => TrainerVoice(
    source: voiceLibrary,
    output: voiceOutput,
    settings: store.voice.toTrainerSettings(),
  );

  /// The output belongs to the App, so page navigation never destroys it.
  Future<void> dispose() async {
    final output = voiceOutput;
    if (output is JustAudioVoiceOutput) {
      await output.dispose();
    } else {
      await output.end();
    }
  }

  /// What answers in the chat home.
  /// Rules + templates today; a model-backed [ChatEngine] later, with the
  /// same plan validation.
  late final ChatEngine chatEngine = RuleChatEngine(
    lib: library,
    templates: templates,
  );

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
  static Future<(ExerciseLibrary, TemplateCatalog, DrillPackVoiceSource)>
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
