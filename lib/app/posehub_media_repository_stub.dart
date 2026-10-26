import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'posehub_media_repository_types.dart';

Future<PoseHubMediaFileStore> createPoseHubMediaStore({
  required String revision,
  required String? rootDirectory,
  required List<coach.PoseHubPackFile> files,
  required Uri? mediaBaseUrl,
  required List<String>? legacyDirectories,
  required bool allowInsecureLocalhost,
  required Duration timeout,
  required int maxRedirects,
}) => Future.error(
  const PoseHubMediaException(
    'unsupported',
    'Persistent media is unavailable on this platform.',
  ),
);
