import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import '../app/posehub_media_preparer.dart';
import '../app/services.dart';
import 'open_training.dart';
import 'theme/trainer_theme.dart';
import 'training_visible_poster_preload.dart';

/// SDK-owned catalog, standing images and direct single-action training.
class PoseHubLibraryPage extends StatefulWidget {
  const PoseHubLibraryPage({super.key, required this.catalog, this.media});

  final coach.PoseHubAppTestCatalog catalog;
  final PoseHubMediaRepository? media;
  @override
  State<PoseHubLibraryPage> createState() => _PoseHubLibraryPageState();
}

class _PoseHubLibraryPageState extends State<PoseHubLibraryPage> {
  SmartFitPoseHubMediaPreparer? _preparer;
  TrainingLibraryConfig? _config;
  coach.PoseHubAppTestCatalog? _configCatalog;
  String? _configLanguage;

  /// Library strings follow the app locale (SDK v0.6.0). The scope keeps every
  /// browsable action, so the list is the one SF showed without a config.
  TrainingLibraryConfig _libraryConfig(String languageTag) {
    if (_config case final config?
        when identical(_configCatalog, widget.catalog) &&
            _configLanguage == languageTag) {
      return config;
    }
    _configCatalog = widget.catalog;
    _configLanguage = languageTag;
    return _config = TrainingLibraryConfig(
      scopeManifest: coach.CoachActionScopeManifest.fromCatalogBytes(
        appId: 'smartfit',
        catalogBytes: utf8.encode(jsonEncode(widget.catalog.raw)),
        allowedActionIds: widget.catalog.semanticCompleteActions.map(
          (action) => action.id,
        ),
      ),
      strings: TrainingLibraryStrings.forLanguage(languageTag),
    );
  }

  @override
  void initState() {
    super.initState();
    _preparer = SmartFitPoseHubMediaPreparer(widget.media);
  }

  @override
  void didUpdateWidget(PoseHubLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.media, widget.media)) {
      _preparer = SmartFitPoseHubMediaPreparer(widget.media);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = context
        .dependOnInheritedWidgetOfExactType<AppScope>()
        ?.services;
    final preparer = identical(services?.poseHubMedia, widget.media)
        ? services?.poseHubPreparer ?? _preparer
        : _preparer;
    final voice = services?.trainerVoice();
    final theme = SmartFitTrainerTheme.of(context);
    return TrainingVisiblePosterPreload(
      child: PoseHubActionBrowser(
        catalog: widget.catalog,
        libraryConfig: _libraryConfig(
          Localizations.localeOf(context).toLanguageTag(),
        ),
        mediaBaseUri:
            widget.media?.mediaBaseUri ??
            Uri(scheme: 'file', path: '/__posehub_cache_unavailable__/'),
        mediaPreparer: preparer,
        voice: voice,
        theme: theme,
        onCompleted: services?.recordTrainingCompletion,
        onOpenAction: (action) => unawaited(
          openTraining(
            context,
            practice: PoseHubSinglePracticePage(
              action: action,
              mediaBaseUri:
                  widget.media?.mediaBaseUri ??
                  Uri(scheme: 'file', path: '/__posehub_cache_unavailable__/'),
              mediaPreparer: preparer,
              voice: voice,
              theme: theme,
              startMode: TrainerStartMode.preview,
              onCompleted: services?.recordTrainingCompletion,
            ),
            sourceEntry: 'action_library',
          ),
        ),
        onOpenPractice: (page) => unawaited(
          openTraining(context, practice: page, sourceEntry: 'action_library'),
        ),
      ),
    );
  }
}
