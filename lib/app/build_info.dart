import 'package:package_info_plus/package_info_plus.dart';

/// Installed package identity. The native build number includes Android's
/// ABI offset; it must not be guessed from the pubspec build suffix.
abstract final class AppBuildInfo {
  static String _versionName = 'unknown';
  static String _buildNumber = 'unknown';

  static String get versionName => _versionName;
  static String get buildNumber => _buildNumber;
  static String get version =>
      _versionName == 'unknown' || _buildNumber == 'unknown'
      ? 'unknown'
      : '$_versionName+$_buildNumber';

  /// The optional loader keeps platform failures observable in local tests.
  /// Startup remains usable when package metadata cannot be read.
  static Future<void> initialize({Future<PackageInfo> Function()? load}) async {
    try {
      final info = await (load ?? PackageInfo.fromPlatform)();
      _versionName = _known(info.version);
      _buildNumber = _known(info.buildNumber);
    } on Object {
      _versionName = 'unknown';
      _buildNumber = 'unknown';
    }
  }

  static String _known(String value) =>
      value.trim().isEmpty ? 'unknown' : value.trim();

  static const sdkRef =
      'ugk_coach / ugk_trainer / ugk_coach_ui @ c97a79a5f03ba1f46f017b995f7f8d97fb3016a9';
  static const performanceBase = 'ccdf1b1729ee6365edb3669aaacae320c23bd49f';
}
