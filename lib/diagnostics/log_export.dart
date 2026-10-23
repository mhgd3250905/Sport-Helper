import 'log_export_native.dart'
    if (dart.library.js_interop) 'log_export_web.dart'
    as platform;

/// A saved result is returned only after the platform finishes writing the file.
/// Web browsers manage their own downloads and report [LogExportResult.downloadStarted].
enum LogExportResult { saved, cancelled, downloadStarted }

abstract interface class RuntimeLogExporter {
  Future<LogExportResult> save({
    required String filename,
    required String contents,
  });
}

class PlatformRuntimeLogExporter implements RuntimeLogExporter {
  const PlatformRuntimeLogExporter();

  @override
  Future<LogExportResult> save({
    required String filename,
    required String contents,
  }) => platform.saveRuntimeLog(filename: filename, contents: contents);
}

String runtimeLogFilename(DateTime now) {
  final stamp = now.toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9TZ]'),
    '',
  );
  return 'SmartFit-runtime-$stamp.json';
}
