import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/plan_generator.dart';
import '../domain/template.dart';
import '../voice/session_script.dart';
import '../voice/voice_library.dart';
import '../voice/voice_queue.dart';

/// Everything pages need, created once at start-up.
class AppServices {
  AppServices({
    required this.library,
    required this.catalog,
    required this.store,
    required this.voiceLibrary,
    required this.voiceOutput,
  }) : generator = TemplatePlanGenerator(lib: library, catalog: catalog);

  final ExerciseLibrary library;
  final TemplateCatalog catalog;
  final AppStore store;
  final VoiceLibrary voiceLibrary;
  final VoiceOutput voiceOutput;

  /// MVP: fixed templates only. An AI generator plugs in behind the same
  /// interface later (see AiPlanGenerator).
  final PlanGenerator generator;

  VoiceQueue voiceQueue() {
    voiceOutput.volume = store.voice.volume;
    return VoiceQueue(output: voiceOutput, lib: voiceLibrary, settings: store.voice);
  }

  SessionScript script() => SessionScript(lib: voiceLibrary, exercises: library);

  static Future<(ExerciseLibrary, TemplateCatalog)> loadContent() async {
    final lib = ExerciseLibrary.fromJson(
      jsonDecode(await rootBundle.loadString('assets/library/exercises.json'))
          as Map<String, dynamic>,
    );
    final cat = TemplateCatalog.fromJson(
      jsonDecode(await rootBundle.loadString('assets/library/templates.json'))
          as Map<String, dynamic>,
    );
    return (lib, cat);
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
