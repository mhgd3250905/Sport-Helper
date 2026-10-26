import 'dart:typed_data';

import 'package:ugk_coach/ugk_coach.dart' as coach;

enum PoseHubDownloadPhase {
  idle,
  queued,
  checking,
  downloading,
  verifying,
  ready,
  failed,
}

class PoseHubDownloadState {
  const PoseHubDownloadState({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final PoseHubDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final Object? error;
  int get bytes => receivedBytes;
  int get total => totalBytes;
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;
}

/// Receives the original path and expected SHA. Videos never use this loader.
typedef PoseHubBundledFileLoader =
    Future<Uint8List?> Function(coach.PoseHubPackFile file);

/// Messages deliberately contain no request URI, redirect signature or headers.
class PoseHubMediaException implements Exception {
  const PoseHubMediaException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Internal platform boundary, so the public service also compiles for Web.
abstract interface class PoseHubMediaFileStore {
  Uri get mediaBaseUri;
  Future<Uri?> cached(coach.PoseHubPackFile file);
  Future<Uri?> reusable(coach.PoseHubPackFile file);
  Future<Uri> bundled(
    coach.PoseHubPackFile file,
    Uint8List bytes,
    void Function(int) onProgress,
    void Function() onVerifying,
  );
  Future<Uri> download(
    coach.PoseHubPackFile file,
    Uri url,
    void Function(int) onProgress,
    void Function() onVerifying,
  );
  Future<Uri> materialize(coach.PoseHubPackFile file, Uri source);
  void dispose();
}
