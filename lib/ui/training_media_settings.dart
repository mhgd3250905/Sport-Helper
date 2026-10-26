import 'package:flutter/material.dart';

import '../app/posehub_media_repository.dart';
import '../app/services.dart';
import 'settings_widgets.dart';
import 'theme/settings_tokens.dart';

Future<int> trainingVideoCacheBytes(AppServices services) {
  final repository = services.poseHubMedia;
  if (repository is PoseHubVideoCache) {
    return (repository as PoseHubVideoCache).videoCacheBytes();
  }
  return services.media?.cacheBytes() ?? Future.value(0);
}

Future<void> clearTrainingVideoCache(AppServices services) async {
  final repository = services.poseHubMedia;
  if (repository is PoseHubVideoCache) {
    await (repository as PoseHubVideoCache).clearVideoCache();
  } else {
    await services.media?.clearCache();
  }
}

String trainingCacheSize(int bytes) =>
    '${(bytes / 1000000).toStringAsFixed(1)} MB';

/// Video-only cache management. Catalog images and personal data are retained.
class TrainingMediaSettings extends StatefulWidget {
  const TrainingMediaSettings({super.key});
  @override
  State<TrainingMediaSettings> createState() => _TrainingMediaSettingsState();
}

class _TrainingMediaSettingsState extends State<TrainingMediaSettings> {
  AppServices? _services;
  int? _bytes;
  bool _working = false;
  bool _readError = false;
  String? _message;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    if (!identical(_services, services)) {
      _services = services;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final bytes = await trainingVideoCacheBytes(_services!);
      if (mounted && generation == _generation) {
        setState(() {
          _bytes = bytes;
          _readError = false;
        });
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _readError = true);
      }
    }
  }

  Future<void> _clear() async {
    if (_working) return;
    final confirmed = await sfSettingsConfirm(
      context,
      title: '清除动作视频缓存？',
      message: '动作图片、已保存计划、训练记录和 AI 记忆都会保留。之后播放未缓存动作时会重新下载视频。',
      confirmLabel: '清除缓存',
      confirmKey: const ValueKey('media-clear-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await clearTrainingVideoCache(_services!);
      if (mounted) setState(() => _message = '动作视频缓存已清除');
    } on Object {
      if (mounted) setState(() => _message = '缓存暂时无法清理，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _working = false);
        await _refresh();
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    final repository = _services!.poseHubMedia;
    final canClear =
        repository is PoseHubVideoCache || _services!.media != null;
    return SfSettingsScaffold(
      title: '动作视频缓存',
      children: [
        const SizedBox(height: 12),
        SfSettingsGroup(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已用缓存', style: tokens.detail),
                  const SizedBox(height: 8),
                  Text(
                    _readError
                        ? '暂时无法读取'
                        : _bytes == null
                        ? '正在读取…'
                        : trainingCacheSize(_bytes!),
                    key: const ValueKey('media-cache-size'),
                    style: tokens.title.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '已缓存的动作可离线训练。这里只清除动作视频，动作图片和个人训练数据会保留。',
                    style: tokens.body,
                  ),
                ],
              ),
            ),
            SfSettingsRow(
              key: const ValueKey('media-clear-cache'),
              title: _working ? '正在清除…' : '清除视频缓存',
              icon: Icons.delete_outline_rounded,
              tone: SfSettingsTone.red,
              destructive: true,
              onTap: canClear && !_working ? _clear : null,
            ),
          ],
        ),
        if (_readError)
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextButton(
              onPressed: _refresh,
              child: Text('重新读取', style: tokens.title),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Semantics(
              liveRegion: true,
              child: Text(_message!, style: tokens.body),
            ),
          ),
      ],
    );
  }
}
