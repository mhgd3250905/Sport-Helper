import 'dart:convert';

import 'package:flutter/services.dart';

import 'action_issue_store.dart';

class ActionIssueSavedFile {
  const ActionIssueSavedFile({required this.uri, required this.displayName});
  final Uri uri;
  final String displayName;

  static const directory = 'Download/SmartFit';
}

abstract interface class ActionIssueExporter {
  Future<ActionIssueSavedFile> saveToDownloads({
    required String filename,
    required String contents,
  });
}

/// Native protocol for InternalMainActivity:
/// channel smartfit/action_issue_export, method saveToDownloads;
/// args {filename, contents (UTF-8 JSON), mimeType: application/json}.
/// Write directly to MediaStore.Downloads in Download/SmartFit, without any
/// chooser or share intent. Return {uri, displayName} only after writing and
/// publishing succeeds; failures must return a PlatformException.
class AndroidActionIssueExporter implements ActionIssueExporter {
  const AndroidActionIssueExporter();

  static const channelName = 'smartfit/action_issue_export';
  static const channel = MethodChannel(channelName);

  @override
  Future<ActionIssueSavedFile> saveToDownloads({
    required String filename,
    required String contents,
  }) async {
    final saved = await channel.invokeMapMethod<String, Object?>(
      'saveToDownloads',
      {
        'filename': filename,
        'contents': contents,
        'mimeType': 'application/json',
      },
    );
    final uri = Uri.tryParse(saved?['uri'] as String? ?? '');
    final displayName = saved?['displayName'] as String?;
    if (uri == null ||
        uri.scheme != 'content' ||
        displayName == null ||
        displayName.isEmpty) {
      throw PlatformException(code: 'invalid_action_issue_export_result');
    }
    return ActionIssueSavedFile(uri: uri, displayName: displayName);
  }
}

class ActionIssueExportService {
  ActionIssueExportService({
    required this.store,
    this.exporter = const AndroidActionIssueExporter(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalActionIssueStore store;
  final ActionIssueExporter exporter;
  final DateTime Function() _clock;
  Future<ActionIssueSavedFile>? _saving;

  /// Concurrent taps share one pending save; no data is removed by export.
  Future<ActionIssueSavedFile> saveToDownloads() {
    if (_saving case final pending?) return pending;
    final result = _save();
    _saving = result;
    result.then<void>(
      (_) => _saving = null,
      onError: (Object _, StackTrace _) => _saving = null,
    );
    return result;
  }

  Future<ActionIssueSavedFile> _save() async {
    final records = await store.snapshot();
    final now = _clock().toUtc();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[^0-9TZ]'), '');
    return exporter.saveToDownloads(
      filename: 'SmartFit-action-issues-$stamp.json',
      contents: const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'exportedAt': now.toIso8601String(),
        'issues': [for (final record in records) record.toJson()],
      }),
    );
  }
}
