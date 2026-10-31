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
      'ugk_coach / ugk_trainer / ugk_coach_ui @ 99c14495685f160019e10340ea6f0de6418a65b9';
  static const performanceBase = 'ca246228922dd3a2371180657609cb733537e69a';
}
