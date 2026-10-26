import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';
import '../app/posehub_media_preparer.dart';
import '../app/services.dart';
import 'theme.dart';
import 'theme/trainer_theme.dart';

/// Only the small local image materialization may precede catalog navigation.
/// Videos use the shared SDK preparation gate when practice is requested.
class PoseHubLibraryPage extends StatefulWidget {
  const PoseHubLibraryPage({
    super.key,
    required this.catalog,
    this.media,
    this.imagesReady,
  });

  final coach.PoseHubAppTestCatalog catalog;
  final PoseHubMediaRepository? media;
  final Future<void>? imagesReady;
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
    final imagesReady = widget.imagesReady ?? services?.poseHubImagesReady;
    final preparer = identical(services?.poseHubMedia, widget.media)
        ? services?.poseHubPreparer ?? _preparer
        : _preparer;
    return FutureBuilder<void>(
      future: imagesReady,
      builder: (context, snapshot) {
        if (imagesReady != null &&
            snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: const SfTopBar(title: '动作库'),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(SfSpace.x6),
                child: Text(
                  '正在准备本机动作图片',
                  key: const ValueKey('posehub-images-preparing'),
                  style: SfType.callout.copyWith(color: SfColors.muted),
                ),
              ),
            ),
          );
        }
        // Failed small images must not trap catalog navigation.
        return PoseHubActionBrowser(
          catalog: widget.catalog,
          mediaBaseUri:
              widget.media?.mediaBaseUri ??
              Uri(scheme: 'file', path: '/__posehub_cache_unavailable__/'),
          mediaPreparer: preparer,
          theme: SmartFitTrainerTheme.of(context),
        );
      },
    );
  }
}
