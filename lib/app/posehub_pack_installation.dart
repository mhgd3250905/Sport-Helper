import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class PoseHubPackConfig {
  static const enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_POSEHUB_PACK');
}

/// Installs the APK's local pack on Android's worker thread. The Dart isolate
/// never loads the archive into memory. Call this when opening the library or
/// starting practice, so the first home frame does not wait for installation.
class PoseHubPackInstallation extends ChangeNotifier {
  factory PoseHubPackInstallation() => _shared;

  PoseHubPackInstallation._(this._enabled, this._install);

  @visibleForTesting
  factory PoseHubPackInstallation.forTesting({
    required bool enabled,
    required Future<Uri> Function() install,
  }) => PoseHubPackInstallation._(enabled, install);

  static final _shared = PoseHubPackInstallation._(
    PoseHubPackConfig.enabled,
    _installOnAndroid,
  );
  static const channelName = 'smartfit/posehub_pack';
  static const _channel = MethodChannel(channelName);

  final bool _enabled;
  final Future<Uri> Function() _install;
  Future<Uri>? _pending;
  Uri? _mediaBaseUri;
  Object? _error;

  Uri? get mediaBaseUri => _mediaBaseUri;
  bool get busy => _pending != null;
  Object? get error => _error;

  /// All callers share the same attempt. A failed attempt can be retried.
  Future<Uri> ensureInstalled() {
    if (!_enabled) {
      return Future.error(StateError('The internal PoseHub pack is disabled.'));
    }
    if (_mediaBaseUri case final installed?) return Future.value(installed);
    if (_pending case final pending?) return pending;
    _error = null;
    // Future.sync also turns a synchronous platform/fake failure into a Future.
    final attempt = Future<Uri>.sync(_install).then(_validateBaseUri);
    _pending = attempt;
    attempt.then<void>(
      (uri) {
        _mediaBaseUri = uri;
        _pending = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace _) {
        _error = error;
        _pending = null;
        notifyListeners();
      },
    );
    notifyListeners();
    return attempt;
  }

  static Future<Uri> _installOnAndroid() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('Local PoseHub installation requires Android.');
    }
    final value = await _channel.invokeMethod<String>('ensureInstalled');
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null) {
      throw const FormatException('Invalid PoseHub installation result.');
    }
    return uri;
  }

  static Uri _validateBaseUri(Uri uri) {
    if (uri.scheme != 'file' ||
        uri.host.isNotEmpty ||
        !uri.path.startsWith('/') ||
        !uri.path.endsWith('/') ||
        uri.pathSegments.every((segment) => segment.isEmpty) ||
        uri.pathSegments.contains('..') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid PoseHub media base URI.');
    }
    return uri;
  }
}
