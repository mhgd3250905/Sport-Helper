import 'dart:async';

import 'package:flutter/material.dart';

import '../app/posehub_media_repository.dart';
import 'theme.dart';

/// Only this small status area listens to transfer progress, not the page.
class PoseHubDownloadStatus extends StatelessWidget {
  const PoseHubDownloadStatus({
    super.key,
    required this.repo,
    required this.actionId,
    this.onRetry,
  });

  final PoseHubMediaRepository repo;
  final String actionId;

  /// A preview retries its cover; playback retries the complete current action.
  final VoidCallback? onRetry;

  void _retry() {
    if (onRetry case final retry?) {
      retry();
      return;
    }
    unawaited(
      repo
          .ensureAction(actionId)
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.light
        ? SfPalette.light
        : SfPalette.dark;
    return ValueListenableBuilder<PoseHubDownloadState>(
      valueListenable: repo.watchAction(actionId),
      builder: (context, state, _) {
        final failed = state.phase == PoseHubDownloadPhase.failed;
        final ready = state.phase == PoseHubDownloadPhase.ready;
        final progress = state.progress?.clamp(0.0, 1.0);
        final message = switch (state.phase) {
          PoseHubDownloadPhase.idle => '正在准备动作素材',
          PoseHubDownloadPhase.queued => '等待下载动作素材',
          PoseHubDownloadPhase.checking => '正在检查本机素材',
          PoseHubDownloadPhase.downloading => '正在下载动作素材',
          PoseHubDownloadPhase.verifying => '正在校验动作素材',
          PoseHubDownloadPhase.ready => '动作素材已准备好',
          PoseHubDownloadPhase.failed => '动作素材暂时无法下载',
        };
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              key: ValueKey(
                failed ? 'posehub-download-error' : 'posehub-download-status',
              ),
              style: SfType.caption.copyWith(color: palette.muted),
              textAlign: TextAlign.center,
            ),
            if (!failed && !ready) ...[
              const SizedBox(height: SfSpace.x3),
              if (progress == null)
                SizedBox(
                  key: const ValueKey('posehub-download-waiting-track'),
                  height: SfSpace.x1,
                  width: double.infinity,
                  child: ColoredBox(color: palette.surfaceHigh),
                )
              else
                LinearProgressIndicator(
                  key: const ValueKey('posehub-download-progress'),
                  value: progress,
                  color: palette.accent,
                  backgroundColor: palette.surfaceHigh,
                  minHeight: SfSpace.x1,
                  semanticsLabel: '动作素材下载进度',
                  semanticsValue: '${(progress * 100).round()}%',
                ),
              if (state.totalBytes > 0) ...[
                const SizedBox(height: SfSpace.x2),
                Text(
                  '${_bytes(state.receivedBytes)} / ${_bytes(state.totalBytes)}',
                  key: const ValueKey('posehub-download-bytes'),
                  style: SfType.caption.copyWith(color: palette.muted),
                ),
              ],
            ],
            if (failed)
              TextButton(
                key: const ValueKey('posehub-download-retry'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.accentText,
                ),
                onPressed: _retry,
                child: const Text('重试'),
              ),
          ],
        );
      },
    );
  }
}

String _bytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
