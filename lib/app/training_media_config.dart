import 'package:ugk_trainer/ugk_trainer.dart' show TrainingMediaPreviewPolicy;

/// Public distribution endpoints, supplied by the build environment.
/// Each URL points at v0.3.0-app/; its sibling v0.3.0/ holds the videos.
abstract final class TrainingMediaConfig {
  static const assetRoot = 'assets/training_media/v0.3.0-app';
  static const manifestAsset = '$assetRoot/app-manifest.json';
  static const videoRoot = 'assets/training_media/v0.3.0/realistic/dark';

  static const includePending =
      TrainingMediaPreviewPolicy.enabled &&
      bool.fromEnvironment('SMARTFIT_INCLUDE_PENDING_MEDIA');
  static const isInternal =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal';

  static List<Uri> get baseUrls => [
    for (final value in const [
      String.fromEnvironment('SMARTFIT_MEDIA_PRIMARY_URL'),
      String.fromEnvironment('SMARTFIT_MEDIA_SECONDARY_URL'),
    ])
      if (value.trim().isNotEmpty) _base(value.trim()),
  ];

  static Uri _base(String value) {
    final uri = Uri.parse(value.endsWith('/') ? value : '$value/');
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' &&
            !(TrainingMediaPreviewPolicy.enabled && uri.scheme == 'http'))) {
      throw const FormatException('Invalid training media endpoint');
    }
    return uri;
  }
}
