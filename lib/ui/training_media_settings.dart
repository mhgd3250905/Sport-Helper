import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/services.dart';
import '../app/training_media_config.dart';
import '../diagnostics/runtime_log.dart';
import '../diagnostics/training_media_log.dart';
import 'theme.dart';

class TrainingMediaSettings extends StatefulWidget {
  const TrainingMediaSettings({super.key});
  @override
  State<TrainingMediaSettings> createState() => _TrainingMediaSettingsState();
}

class _TrainingMediaSettingsState extends State<TrainingMediaSettings> {
  int _usedBytes = 0;
  bool _working = false;
  int _operation = 0;
  String? _message;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final bytes = await AppServices.of(context).media!.cacheBytes();
    if (_usedBytes != bytes) {
      RuntimeLog.instance.record('media.cache.usage', fields: {'bytes': bytes});
    }
    if (mounted) setState(() => _usedBytes = bytes);
  }

  Future<void> _download(TrainingMediaRepository repository) async {
    final operation = ++_operation;
    final log = RuntimeLog.instance;
    final logOperation = log.newOperation('package');
    final watch = Stopwatch()..start();
    log.record(
      'media.package.requested',
      operation: logOperation,
      fields: {
        'kind': 'realistic-dark',
        'wifiOnly': repository.wifiOnly,
        'offline': repository.isOffline,
      },
    );
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await repository.downloadPackage();
      log.record(
        'media.package.completed',
        operation: logOperation,
        fields: {
          'kind': 'realistic-dark',
          'verified': true,
          'elapsedMs': watch.elapsedMilliseconds,
        },
      );
      if (mounted && operation == _operation) {
        setState(() => _message = '完整动作素材已下载并校验');
      }
    } on Object catch (error) {
      final state = repository.stateFor('realistic-dark');
      log.record(
        'media.package.failed',
        operation: logOperation,
        fields: {
          'phase': state.phase.name,
          'reason': TrainingMediaLog.failureReason(state.error),
          'errorType': RuntimeLog.errorType(error),
          'elapsedMs': watch.elapsedMilliseconds,
        },
      );
      if (mounted && operation == _operation) {
        setState(
          () => _message = switch (state.phase) {
            TrainingMediaPhase.waitingForWifi => '等待 Wi-Fi；已内置的动作仍可使用',
            TrainingMediaPhase.offline => '当前离线；已有动作仍可使用，计时和语音不受影响',
            _ => '下载未完成或校验未通过；已保留可用素材，可以重试',
          },
        );
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _working = false);
        await _refresh();
      }
    }
  }

  Future<void> _clear(TrainingMediaRepository repository) async {
    final operation = ++_operation;
    final log = RuntimeLog.instance;
    final logOperation = log.newOperation('cache');
    log.record(
      'media.cache.clear_requested',
      operation: logOperation,
      fields: {'bytes': _usedBytes},
    );
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await repository.clearCache();
      log.record(
        'media.cache.cleared',
        operation: logOperation,
        fields: {'success': true},
      );
      if (mounted && operation == _operation) {
        setState(() => _message = '缓存已清理，内置动作、计划和训练记录保留');
      }
    } on Object catch (error) {
      log.record(
        'media.cache.clear_failed',
        operation: logOperation,
        fields: {'errorType': RuntimeLog.errorType(error)},
      );
      if (mounted && operation == _operation) {
        setState(() => _message = '缓存暂时无法清理，请稍后重试');
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _working = false);
        await _refresh();
      }
    }
  }

  static String _size(int bytes) =>
      '${(bytes / 1000000).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final repository = services.media!;
    return ListenableBuilder(
      listenable: repository,
      builder: (context, _) {
        final state = repository.stateFor('realistic-dark');
        final downloading =
            state.phase == TrainingMediaPhase.queued ||
            state.phase == TrainingMediaPhase.downloading;
        final message = switch (state.phase) {
          TrainingMediaPhase.waitingForWifi => '等待 Wi-Fi；已内置的动作仍可使用',
          TrainingMediaPhase.offline => '当前离线；已有动作仍可使用，计时和语音不受影响',
          TrainingMediaPhase.failed => '下载未完成或校验未通过；已保留可用素材，可以重试',
          TrainingMediaPhase.ready => '完整动作素材已下载并校验',
          TrainingMediaPhase.queued || TrainingMediaPhase.downloading => null,
          _ => _message,
        };
        final total =
            repository.manifest.packages['realistic-dark']!.totalBytes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('完整动作素材 · ${_size(total)}', style: SfType.callout),
            const SizedBox(height: SfSpace.x1),
            Text('已内置 32 个动作。其余示范按计划下载；下载期间仍可计时和语音跟练。', style: SfType.caption),
            SfSwitchRow(
              key: const ValueKey('media-wifi-only'),
              title: '仅在 Wi-Fi 下载',
              subtitle: '关闭后可能使用移动流量',
              value: repository.wifiOnly,
              onChanged: (value) async {
                repository.wifiOnly = value;
                RuntimeLog.instance.record(
                  'media.wifi_only.changed',
                  fields: {'wifiOnly': value},
                );
                await services.store.setMediaWifiOnly(value);
              },
            ),
            if (state.phase == TrainingMediaPhase.downloading) ...[
              LinearProgressIndicator(
                value: state.totalBytes == 0
                    ? null
                    : (state.receivedBytes / state.totalBytes).clamp(0.0, 1.0),
              ),
              Text(
                '${_size(state.receivedBytes)} / ${_size(state.totalBytes)}',
                style: SfType.caption,
              ),
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, style: SfType.caption),
              ),
            SfTextAction(
              key: const ValueKey('media-download-default'),
              icon: SfGlyph.play,
              label: _working || downloading ? '处理中…' : '下载完整动作素材',
              onPressed:
                  _working || downloading || repository.visibleActions.isEmpty
                  ? null
                  : () => _download(repository),
            ),
            if (repository.visibleActions.isEmpty)
              Text('当前没有已审核的可下载动作', style: SfType.caption),
            Text('已用缓存 ${_size(_usedBytes)}', style: SfType.caption),
            SfTextAction(
              key: const ValueKey('media-clear-cache'),
              icon: SfGlyph.bookmark,
              label: '清理缓存',
              onPressed: () => _clear(repository),
            ),
            if (repository.allowPending)
              Text(
                TrainingMediaConfig.isInternal
                    ? '内测预览：包含待审核动作'
                    : '开发预览：包含待审核动作',
                style: SfType.caption,
              ),
          ],
        );
      },
    );
  }
}
