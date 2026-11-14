import 'dart:convert';

abstract final class PoseHubMediaConfig {
  static const enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_POSEHUB_PACK');

  /// Override the public file host without changing catalog identities/hashes.
  ///
  /// `SMARTFIT_POSEHUB_MEDIA_BASE_URLS` is a JSON list of templates with one
  /// `{pack}` each. The shared release mirror `SMARTFIT_MEDIA_PRIMARY_URL`
  /// (and secondary) is reused only when it ends in `/pack/<version>/`; that
  /// segment becomes `{pack}` so the pack follows the catalogue in use.
  static String get mediaBaseUrls {
    const explicit = String.fromEnvironment('SMARTFIT_POSEHUB_MEDIA_BASE_URLS');
    if (explicit.trim().isNotEmpty) return explicit;
    return fromMirrors(
      const String.fromEnvironment('SMARTFIT_MEDIA_PRIMARY_URL'),
      const String.fromEnvironment('SMARTFIT_MEDIA_SECONDARY_URL'),
    );
  }

  static final _packDir = RegExp(r'/pack/[a-z0-9]+(?:-[a-z0-9]+)*/$');

  static String fromMirrors(String primary, String secondary) {
    final templates = <String>[];
    for (final raw in [primary.trim(), secondary.trim()]) {
      if (!_packDir.hasMatch(raw)) continue;
      final template = raw.replaceFirst(_packDir, '/pack/{pack}/');
      if (!templates.contains(template)) templates.add(template);
    }
    return templates.isEmpty ? '' : jsonEncode(templates);
  }
}
