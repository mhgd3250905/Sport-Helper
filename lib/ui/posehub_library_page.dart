import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import 'theme/trainer_theme.dart';

/// Catalog navigation never waits for a video or a whole-library installation.
/// SDK resource-provider wiring follows the formal v3 patch.
class PoseHubLibraryPage extends StatelessWidget {
  const PoseHubLibraryPage({super.key, required this.catalog, this.media});

  final coach.PoseHubAppTestCatalog catalog;
  final PoseHubMediaRepository? media;

  @override
  Widget build(BuildContext context) => PoseHubActionBrowser(
    catalog: catalog,
    mediaBaseUri:
        media?.mediaBaseUri ??
        Uri(scheme: 'file', path: '/__posehub_cache_unavailable__/'),
    theme: SmartFitTrainerTheme.of(context),
  );
}
