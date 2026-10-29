import 'dart:convert';

abstract final class PoseHubMediaConfig {
  static const enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_POSEHUB_PACK');

  /// Override the public file host without changing catalog identities/hashes.
  static String get mediaBaseUrls {
    const explicit = String.fromEnvironment('SMARTFIT_POSEHUB_MEDIA_BASE_URLS');
    if (explicit.trim().isNotEmpty) return explicit;
    const primary = String.fromEnvironment('SMARTFIT_MEDIA_PRIMARY_URL');
    const secondary = String.fromEnvironment('SMARTFIT_MEDIA_SECONDARY_URL');
    if (primary.trim().isEmpty) return '';
    return jsonEncode([
      primary.trim(),
      if (secondary.trim().isNotEmpty && secondary.trim() != primary.trim())
        secondary.trim(),
    ]);
  }
}
