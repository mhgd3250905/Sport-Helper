import 'dart:async';

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/services.dart';
import '../app/build_info.dart';
import '../app/training_media_config.dart';
import '../chat/safety_script.dart' show disclaimerText;
import '../diagnostics/runtime_log.dart';
import '../diagnostics/frame_recorder.dart';
import 'performance_settings.dart';
import 'action_issue_settings.dart';
import 'runtime_log_settings.dart';
import 'settings_widgets.dart';
import 'theme/settings_tokens.dart';
import 'training_media_settings.dart';

String get appVersion => AppBuildInfo.version;

const _privacyAi =
    '启用 AI 时，你输入的内容、近期对话、当前计划和训练条件会经 '
    'https://api.uuugk.win/v1 '
    '发送给 AI 服务，用于生成回复与训练计划。\n\n'
    'AI 记忆保存在本机；开启时，记住的训练条件会随请求发送给 AI 服务。'
    '可随时关闭或清除记忆。\n\n'
    'App 在本机随机生成并保存设备标识，随 AI 请求发送，用于服务器限流：'
    '每个设备每 10 分钟最多 30 次请求，限制由服务器执行。\n\n'
    '训练记录和已保存计划保存在本机。断网、请求超时或生成结果校验未通过时，'
    '使用本地模板生成训练计划。';
const _privacyLocal = '训练记录和已保存计划保存在本机。使用本地模板生成训练计划。';
const _mediaAttribution =
    '动作示范视频由 Pose-Hub 动作库预渲染。训练人物派生自 Blender Studio 的 Snow 角色：'
    'Snow Rig © Blender Foundation | studio.blender.org，'
    '许可 CC BY 4.0（https://creativecommons.org/licenses/by/4.0/），已修改：灰色人台头、服装材质、骨骼与动作、肌群高亮。'
    '头部参考来自 Blender Studio Human Base Meshes（CC0）。肌肉颜色仅为训练目标示意，不代表实测肌电。';
const _fontAttribution =
    '界面字体 Noto Sans SC（思源黑体）© 2014-2021 Adobe，SIL Open Font License 1.1；'
    'App 内为按常用字子集化的版本。界面设计语言与图标沿用 HipLab。';

Future<String> _materialLicenses() async {
  final media = await rootBundle.loadString(
    'assets/licenses/Drill-media-ATTRIBUTION.md',
  );
  final font = await rootBundle.loadString(
    'assets/licenses/NotoSansSC-OFL.txt',
  );
  return '$_mediaAttribution\n\n$_fontAttribution\n\n素材署名全文\n\n$media\n\n字体许可\n\n$font';
}

Future<String> _openSourceLicenses() async {
  final entries = await LicenseRegistry.licenses.toList();
  return entries
      .map(
        (entry) =>
            '${entry.packages.join('、')}\n\n${entry.paragraphs.map((p) => p.text).join('\n\n')}',
      )
      .join('\n\n────────\n\n');
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  AppServices? _services;
  Future<int>? _cacheBytes;
  bool _recordingLoaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppServices.of(context);
    if (!identical(_services, services)) {
      _services = services;
      _cacheBytes = trainingVideoCacheBytes(services);
      _recordingLoaded = false;
      unawaited(_loadRecordingPreference(services));
    }
  }

  Future<void> _loadRecordingPreference(AppServices services) async {
    await services.store.actionIssueStore.loadRecordingPreference();
    if (mounted && identical(_services, services)) {
      setState(() => _recordingLoaded = true);
    }
  }

  Future<void> _cache() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const TrainingMediaSettings()),
    );
    if (mounted) {
      setState(() => _cacheBytes = trainingVideoCacheBytes(_services!));
    }
  }

  void _document(String title, Future<String> text, {Widget? footer}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              SfSettingsDocumentPage(title: title, text: text, footer: footer),
        ),
      );

  void _tool(String title, Widget child) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => SfSettingsScaffold(
        title: title,
        children: [
          const SizedBox(height: 12),
          SfSettingsGroup(
            children: [
              Padding(padding: const EdgeInsets.all(20), child: child),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final services = _services!;
    final tokens = SfSettingsTokens.of(context);
    return ListenableBuilder(
      listenable: services.store,
      builder: (context, _) => SfSettingsScaffold(
        title: '设置',
        children: [
          const SfSettingsSection('外观'),
          SfSettingsGroup(
            children: [
              Column(
                children: [
                  _AppearanceSelector(
                    value: services.store.appearance,
                    onChanged: services.store.setAppearance,
                  ),
                  SfSettingsSwitchRow(
                    key: const ValueKey('starfield-switch'),
                    title: '星尘动效',
                    subtitle: '背景星尘缓慢漂移',
                    icon: Icons.auto_awesome_rounded,
                    tone: SfSettingsTone.violet,
                    value: services.store.starfield,
                    onChanged: services.store.setStarfield,
                  ),
                ],
              ),
            ],
          ),
          const SfSettingsSection('训练'),
          SfSettingsGroup(
            children: [
              SfSettingsSwitchRow(
                key: const ValueKey('voice-switch'),
                title: '教练语音',
                subtitle: '开始、计数、休息和下一个动作',
                icon: Icons.record_voice_over_rounded,
                tone: SfSettingsTone.mint,
                value: services.store.voice.voice,
                onChanged: (v) => services.store.setVoice(
                  services.store.voice.copyWith(voice: v),
                ),
              ),
              SfSettingsSwitchRow(
                key: const ValueKey('chime-switch'),
                title: '提示音',
                subtitle: '换动作和最后几秒',
                icon: Icons.music_note_rounded,
                tone: SfSettingsTone.coral,
                value: services.store.voice.chimes,
                onChanged: (v) => services.store.setVoice(
                  services.store.voice.copyWith(chimes: v),
                ),
              ),
              SfSettingsRow(
                key: const ValueKey('media-cache-open'),
                title: '动作视频缓存',
                subtitle: '已缓存的动作可离线训练',
                icon: Icons.file_download_outlined,
                tone: SfSettingsTone.blue,
                chevron: true,
                onTap: _cache,
                trailing: FutureBuilder<int>(
                  future: _cacheBytes,
                  builder: (context, snapshot) => Text(
                    snapshot.hasError
                        ? '—'
                        : snapshot.hasData
                        ? trainingCacheSize(snapshot.data!)
                        : '…',
                    style: tokens.detail.copyWith(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          if (services.aiConfig.enabled) ...[
            const SfSettingsSection('AI 教练'),
            const _AiMemorySettings(),
          ],
          const SfSettingsSection('关于'),
          _AppIdentity(),
          const SizedBox(height: 12),
          SfSettingsGroup(
            children: [
              SfSettingsRow(
                key: const ValueKey('settings-privacy'),
                title: services.aiConfig.enabled ? '隐私与 AI' : '隐私',
                icon: Icons.lock_outline_rounded,
                tone: SfSettingsTone.mint,
                chevron: true,
                onTap: () => _document(
                  services.aiConfig.enabled ? '隐私与 AI' : '隐私',
                  Future.value(
                    services.aiConfig.enabled ? _privacyAi : _privacyLocal,
                  ),
                ),
              ),
              SfSettingsRow(
                key: const ValueKey('settings-disclaimer'),
                title: '免责声明',
                icon: Icons.priority_high_rounded,
                tone: SfSettingsTone.amber,
                chevron: true,
                trailing: Text(
                  '重新确认',
                  style: tokens.detail.copyWith(fontSize: 14),
                ),
                onTap: () => _document(
                  '免责声明',
                  Future.value(disclaimerText),
                  footer: SfSettingsRow(
                    key: const ValueKey('safety-recheck'),
                    title: '重新做安全确认',
                    icon: Icons.verified_user_outlined,
                    tone: SfSettingsTone.amber,
                    chevron: true,
                    onTap: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      services.chat.startSafetyCheck();
                    },
                  ),
                ),
              ),
              SfSettingsRow(
                key: const ValueKey('settings-material-licenses'),
                title: '素材与字体许可',
                icon: Icons.copyright_rounded,
                tone: SfSettingsTone.blue,
                chevron: true,
                onTap: () => _document('素材与字体许可', _materialLicenses()),
              ),
              SfSettingsRow(
                key: const ValueKey('settings-open-source'),
                title: '开源软件许可',
                icon: Icons.data_object_rounded,
                tone: SfSettingsTone.gray,
                chevron: true,
                onTap: () => _document('开源软件许可', _openSourceLicenses()),
              ),
            ],
          ),
          if (TrainingMediaConfig.isInternal) ...[
            const SfSettingsSection('内测工具 · 正式版不显示'),
            SfSettingsGroup(
              key: const ValueKey('settings-internal-tools'),
              children: [
                ListenableBuilder(
                  listenable: services.store.actionIssueStore,
                  builder: (context, _) {
                    final store = services.store.actionIssueStore;
                    return SfSettingsRow(
                      key: const ValueKey('action-issues-open'),
                      title: '动作问题标记',
                      icon: Icons.flag_rounded,
                      onTap: store.available
                          ? () => _tool(
                              '动作问题标记',
                              ActionIssueSettings(store: store),
                            )
                          : null,
                      trailing: SfSettingsSwitch(
                        key: const ValueKey('action-issues-recording'),
                        value: _recordingLoaded && store.enabled,
                        onChanged: !store.available || !_recordingLoaded
                            ? null
                            : (value) async {
                                try {
                                  await store.setRecordingEnabled(value);
                                } on Object {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('标记开关保存失败，请重试'),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    );
                  },
                ),
                SfSettingsRow(
                  key: const ValueKey('performance-report-open'),
                  title: '导出性能报告',
                  icon: Icons.waves_rounded,
                  chevron: true,
                  onTap: FrameRecorder.buildEnabled
                      ? () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            settings: const RouteSettings(
                              name: 'performance_settings',
                            ),
                            builder: (_) => const PerformanceSettingsPage(),
                          ),
                        )
                      : null,
                ),
                SfSettingsRow(
                  key: const ValueKey('runtime-log-open'),
                  title: '运行日志',
                  icon: Icons.notes_rounded,
                  chevron: true,
                  onTap: RuntimeLog.instance.enabled
                      ? () => _tool('运行日志', const RuntimeLogSettings())
                      : null,
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
            child: Text(
              '动作示范由 Pose-Hub 预渲染 · 人物基于 Blender Studio Snow（CC BY 4.0）',
              textAlign: TextAlign.center,
              style: tokens.detail.copyWith(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIdentity extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    final parts = appVersion.split('+');
    final version = parts.length == 2
        ? '${parts.first} (${parts.last})'
        : appVersion;
    return SfSettingsGroup(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  SfSettingsTokens.appIconRadius,
                ),
                child: Image.asset(
                  'assets/brand/source/smartfit-icon-v4-crop.png',
                  width: SfSettingsTokens.appIconSize,
                  height: SfSettingsTokens.appIconSize,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '智能健身助手',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.title.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '版本 $version${TrainingMediaConfig.isInternal ? ' · 内测' : ''}',
                      style: tokens.detail.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceSelector extends StatelessWidget {
  const _AppearanceSelector({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = SfSettingsTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.track,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              for (final (id, label) in const [
                ('dark', '深空'),
                ('light', '浅色'),
                ('system', '跟随系统'),
              ])
                Expanded(
                  child: Semantics(
                    selected: value == id,
                    button: true,
                    child: Material(
                      color: value == id ? tokens.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      child: InkWell(
                        key: ValueKey('appearance-$id'),
                        borderRadius: BorderRadius.circular(11),
                        onTap: () => onChanged(id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Column(
                            children: [
                              Container(
                                width: 30,
                                height: 20,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: tokens.swatchBorder,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: ColoredBox(
                                        color: id == 'dark'
                                            ? tokens.swatchDark
                                            : tokens.swatchLight,
                                      ),
                                    ),
                                    Expanded(
                                      child: ColoredBox(
                                        color: id == 'light'
                                            ? tokens.swatchLight
                                            : tokens.swatchDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                label,
                                maxLines: 1,
                                style: tokens.detail.copyWith(
                                  fontSize: 14,
                                  color: value == id
                                      ? tokens.text
                                      : tokens.muted,
                                  fontWeight: value == id
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiMemorySettings extends StatefulWidget {
  const _AiMemorySettings();
  @override
  State<_AiMemorySettings> createState() => _AiMemorySettingsState();
}

class _AiMemorySettingsState extends State<_AiMemorySettings> {
  bool _busy = false;
  bool _clearing = false;
  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    return SfSettingsGroup(
      children: [
        SfSettingsSwitchRow(
          key: const ValueKey('ai-memory-switch'),
          title: 'AI 记忆',
          subtitle: '记住训练水平、器械和偏好',
          icon: Icons.adjust_rounded,
          tone: SfSettingsTone.amber,
          value: services.store.aiMemoryEnabled,
          onChanged: _busy ? null : (value) => _setEnabled(services, value),
        ),
        SfSettingsRow(
          key: const ValueKey('ai-memory-clear'),
          title: _clearing ? '正在清除…' : '清除记忆',
          icon: Icons.backspace_outlined,
          tone: SfSettingsTone.red,
          destructive: true,
          chevron: true,
          onTap: _busy ? null : () => _clear(services),
        ),
      ],
    );
  }

  Future<void> _setEnabled(AppServices services, bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await services.setAiMemoryEnabled(enabled);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记忆开关保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(AppServices services) async {
    if (_busy) return;
    final confirmed = await sfSettingsConfirm(
      context,
      title: '清除 AI 记忆？',
      message: '清除已记住的训练条件；聊天记录和已保存计划仍保留。',
      confirmLabel: '清除记忆',
      confirmKey: const ValueKey('ai-memory-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _clearing = true;
    });
    try {
      await services.clearAiMemory();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 记忆已清除')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('清除记忆失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _clearing = false;
        });
      }
    }
  }
}
