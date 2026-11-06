import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart'
    show
        PoseHubActionLibrary,
        PoseHubCatalogChannel,
        PoseHubCatalogStore,
        PoseHubCatalogUpdateConfig,
        PoseHubCatalogUpdateEvent,
        PoseHubCatalogUpdateOutcome,
        PoseHubCatalogUpdater,
        createPoseHubCatalogFileStore,
        poseHubPackVersionOf;

/// Action-library hot update (SDK `PoseHubCatalogUpdater`).
///
/// Checks the channel pointer once per launch and again on resume once a day
/// has passed. A verified new catalogue is stored and takes effect on the next
/// launch; [PoseHubActionLibrary.load] always opens the verified cache first,
/// then the bundled r2-v1 baseline.
///
/// The channel is fixed at build time: `--dart-define=POSEHUB_CATALOG_CHANNEL=
/// dev|beta|stable`, defaulting to `stable`.
class PoseHubCatalogUpdates with WidgetsBindingObserver {
  PoseHubCatalogUpdates._(this.updater);

  static const channelName = String.fromEnvironment(
    'POSEHUB_CATALOG_CHANNEL',
    defaultValue: 'stable',
  );

  static PoseHubCatalogChannel get channel => PoseHubCatalogChannel.values
      .firstWhere((c) => c.name == channelName,
          orElse: () => PoseHubCatalogChannel.stable);

  static PoseHubCatalogUpdateConfig get buildConfig =>
      PoseHubCatalogUpdateConfig(channel: channel);

  final PoseHubCatalogUpdater updater;

  /// The verified cache opened by [start]; null when updates are disabled.
  static PoseHubCatalogStore? activeStore;

  /// Opens the verified cache for [PoseHubActionLibrary.load] and starts the
  /// launch check in the background. Returns null on web or when the support
  /// directory is unavailable (bundled baseline only).
  static Future<PoseHubCatalogUpdates?> start({
    void Function(PoseHubCatalogUpdateEvent event)? onEvent,
    void Function(PoseHubCatalogUpdateOutcome outcome)? onOutcome,
    PoseHubCatalogStore? store,
    Future<coach.PoseHubAppTestCatalog> Function()? loadLocal,
  }) async {
    if (kIsWeb && store == null) return null;
    try {
      final resolved =
          store ??
          createPoseHubCatalogFileStore(
            '${(await getApplicationSupportDirectory()).path}/posehub-catalog',
          );
      PoseHubActionLibrary.useVerifiedCache(resolved);
      activeStore = resolved;
      final updates = PoseHubCatalogUpdates._(
        PoseHubCatalogUpdater(
          config: buildConfig,
          store: resolved,
          loadLocal: loadLocal,
          onEvent: onEvent,
        ),
      );
      updates._onOutcome = onOutcome;
      WidgetsBinding.instance.addObserver(updates);
      updates._check();
      return updates;
    } on Object catch (error) {
      debugPrint('PoseHub catalogue updates disabled: $error');
      return null;
    }
  }

  void Function(PoseHubCatalogUpdateOutcome outcome)? _onOutcome;

  void _check() {
    unawaited(
      updater.maybeCheck().then((outcome) => _onOutcome?.call(outcome)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);
}

/// A 64-hex revision for the catalogue in use: the SDK's audited SHA for the
/// bundled baseline, else a content digest of the verified cached catalogue.
String poseHubCatalogRevisionOf(coach.PoseHubAppTestCatalog catalog) {
  if (poseHubPackVersionOf(catalog) == PoseHubActionLibrary.packVersion) {
    return PoseHubActionLibrary.catalogSha256;
  }
  return coach.sha256Hex(utf8.encode(jsonEncode(catalog.raw)));
}
