import 'package:flutter/services.dart';

import 'log_export.dart';

const _channel = MethodChannel('smartfit/runtime_log_export');

Future<LogExportResult> saveRuntimeLog({
  required String filename,
  required String contents,
}) async {
  final saved = await _channel.invokeMethod<bool>('save', {
    'filename': filename,
    'contents': contents,
  });
  if (saved == null) {
    throw PlatformException(code: 'invalid_export_result');
  }
  return saved ? LogExportResult.saved : LogExportResult.cancelled;
}
