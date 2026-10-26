import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/build_info.dart';
import 'frame_recorder.dart';

abstract interface class PerformanceReportPlatform {
  Future<Map<String, Object?>> deviceInfo();

  /// Completes when the system chooser opens; this does not confirm delivery.
  Future<void> share({required String filename, required String contents});
}

class AndroidPerformanceReportPlatform implements PerformanceReportPlatform {
  const AndroidPerformanceReportPlatform();
  static const _channel = MethodChannel('smartfit/performance');

  @override
  Future<Map<String, Object?>> deviceInfo() async {
    final info = await _channel.invokeMapMethod<String, Object?>('deviceInfo');
    if (info == null) throw StateError('Device information unavailable');
    return info;
  }

  @override
  Future<void> share({
    required String filename,
    required String contents,
  }) async {
    final opened = await _channel.invokeMethod<bool>('share', {
      'filename': filename,
      'contents': contents,
    });
    if (opened != true) throw StateError('Share sheet did not open');
  }
}

/// All JSON encoding is deferred until export and runs outside the UI isolate.
class PerformanceReportService extends ChangeNotifier {
  static const maximumExportBytes = 64 * 1024 * 1024;
  PerformanceReportService({
    FrameRecorder? recorder,
    this.platform = const AndroidPerformanceReportPlatform(),
    this.maxExportBytes = maximumExportBytes,
  }) : recorder = recorder ?? FrameRecorder.instance;

  static final instance = PerformanceReportService();
  final FrameRecorder recorder;
  final PerformanceReportPlatform platform;
  final int maxExportBytes;
  Future<void>? _initializing;
  bool _metadataReady = false;
  String renderer = 'unverified';
  String rendererBackend = 'unverified';
  bool rendererVerified = false;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!recorder.enabled) return;
    recorder.setMetadata({
      'appVersion': AppBuildInfo.version,
      'appBuild': AppBuildInfo.version.split('+').last,
      'appBaseCommit': AppBuildInfo.performanceBase,
      'sdkRef': AppBuildInfo.sdkRef,
      'appSource': const String.fromEnvironment(
        'SMARTFIT_BUILD_SOURCE',
        defaultValue: 'working_tree',
      ),
      'measurementKind': 'solid_frame_raw_v1',
      'material': 'solid',
      'sourceFingerprint': const String.fromEnvironment(
        'SMARTFIT_SOURCE_FINGERPRINT',
        defaultValue: 'unavailable',
      ),
      'flavor': 'internal',
      'buildMode': kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug'),
      'platform': defaultTargetPlatform.name,
      // Requested renderer is not proof of the engine actually selected.
      'renderer': 'unverified',
      'metadataStatus': 'unavailable',
    });
    await refreshDeviceInfo();
  }

  /// Retry on export if the first native query failed. No fabricated device.
  Future<void> refreshDeviceInfo() async {
    if (!recorder.enabled) return;
    try {
      final info = await platform.deviceInfo().timeout(
        const Duration(seconds: 3),
      );
      final reportedRenderer = '${info['renderer']}'.toLowerCase();
      rendererVerified =
          info['rendererVerified'] == true &&
          (reportedRenderer == 'impeller' || reportedRenderer == 'skia');
      renderer = rendererVerified ? reportedRenderer : 'unverified';
      rendererBackend = rendererVerified
          ? '${info['rendererBackend'] ?? 'unverified'}'
          : 'unverified';
      recorder.setMetadata({
        'deviceModel': info['model'],
        'deviceManufacturer': info['manufacturer'],
        'systemVersion': info['osVersion'],
        'deviceApiLevel': info['apiLevel'],
        'appVersion': info['appVersion'],
        'appBuildNumber': info['appBuildNumber'],
        'isEmulator': info['isEmulator'],
        'metadataStatus': 'available',
        'renderer': renderer,
        'rendererBackend': rendererBackend,
        'rendererSource': info['rendererSource'] ?? 'unavailable',
        'rendererVerified': rendererVerified,
      });
      final hz = info['refreshRateHz'];
      if (hz is num && hz.isFinite && hz >= 10 && hz <= 1000) {
        recorder.setRefreshRateHz(hz.toDouble());
        recorder.setMetadata({'refreshRateSource': 'android_display'});
      }
      _metadataReady = true;
      notifyListeners();
    } on Object {
      _metadataReady = false;
      recorder.setMetadata({'metadataStatus': 'unavailable'});
    }
  }

  Future<void> share() async {
    if (!recorder.enabled) {
      throw StateError('Internal diagnostics are disabled');
    }
    await initialize();
    if (!_metadataReady) await refreshDeviceInfo();
    final report = recorder.snapshot();
    if ((report['recordedFrameCount'] as int) == 0) {
      throw const NoPerformanceFrames();
    }
    final encoded = await compute(_encodeReport, report);
    if (encoded.byteLength > maxExportBytes) {
      throw PerformanceReportTooLarge(encoded.byteLength, maxExportBytes);
    }
    await platform.share(
      filename: performanceReportFilename(DateTime.now()),
      contents: encoded.contents,
    );
  }
}

class NoPerformanceFrames implements Exception {
  const NoPerformanceFrames();
}

class PerformanceReportTooLarge implements Exception {
  const PerformanceReportTooLarge(this.actualBytes, this.maximumBytes);
  final int actualBytes, maximumBytes;
}

({String contents, int byteLength}) _encodeReport(Map<String, Object?> report) {
  final contents = jsonEncode(report);
  return (contents: contents, byteLength: utf8.encode(contents).length);
}

String performanceReportFilename(DateTime time) =>
    'SmartFit-performance-${time.toUtc().toIso8601String().replaceAll(RegExp(r'[-:.]'), '')}.json';
