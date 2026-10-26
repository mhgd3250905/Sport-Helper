import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import '../app/posehub_media_preparer.dart';
import '../app/services.dart';
import 'theme/trainer_theme.dart';

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
    return PoseHubActionBrowser(
      catalog: widget.catalog,
      mediaBaseUri:
          widget.media?.mediaBaseUri ??
          Uri(scheme: 'file', path: '/__posehub_cache_unavailable__/'),
      mediaPreparer: preparer,
      voice: services?.trainerVoice(),
      theme: SmartFitTrainerTheme.of(context),
    );
  }
}
