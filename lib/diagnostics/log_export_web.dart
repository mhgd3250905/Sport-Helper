import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'log_export.dart';

Future<LogExportResult> saveRuntimeLog({
  required String filename,
  required String contents,
}) async {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    // Keep the URL alive while the browser starts reading the download.
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
  return LogExportResult.downloadStarted;
}
