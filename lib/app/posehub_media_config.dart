abstract final class PoseHubMediaConfig {
  static const enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_POSEHUB_PACK');

  /// Override the public file host without changing catalog identities/hashes.
  static const mediaBaseUrls = String.fromEnvironment(
    'SMARTFIT_POSEHUB_MEDIA_BASE_URLS',
  );
}
