import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/services.dart';
import '../chat/safety_script.dart' show disclaimerText;
import 'theme.dart';
import 'training_media_settings.dart';

const appVersion = '0.1.0+11 (MVP)';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return Scaffold(
      appBar: const SfTopBar(title: '设置'),
      body: ListenableBuilder(
        listenable: s.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            SfSpace.x4,
            0,
            SfSpace.x4,
            SfSpace.x8,
          ),
          children: [
            const SfSectionTitle('外观'),
            SfPanel(
              padding: const EdgeInsets.all(SfSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SfSegmented<String>(
                    keyPrefix: 'appearance-',
                    items: const [
                      ('dark', '深空'),
                      ('light', '浅色'),
                      ('system', '跟随系统'),
                    ],
                    value: s.store.appearance,
                    onChanged: s.store.setAppearance,
                  ),
                  const SizedBox(height: SfSpace.x2),
                  SfSwitchRow(
                    key: const ValueKey('starfield-switch'),
                    title: '星尘动效',
                    subtitle: '背景的星尘缓慢漂移；关掉后静止。系统开启「减少动画」时自动静止',
                    value: s.store.starfield,
                    onChanged: s.store.setStarfield,
                  ),
                ],
              ),
            ),
            const SfSectionTitle('语音播报'),
            SfPanel(
              padding: const EdgeInsets.symmetric(
                horizontal: SfSpace.x3,
                vertical: SfSpace.x1,
              ),
              child: Column(
                children: [
                  SfSwitchRow(
                    key: const ValueKey('voice-switch'),
                    title: '教练语音',
                    subtitle: '开始、计数、休息和下一个动作提示',
                    value: s.store.voice.voice,
                    onChanged: (v) =>
                        s.store.setVoice(s.store.voice.copyWith(voice: v)),
                  ),
                  SfSwitchRow(
                    title: '提示音',
                    subtitle: '开始、换动作和最后几秒的提示音',
                    value: s.store.voice.chimes,
                    onChanged: (v) =>
                        s.store.setVoice(s.store.voice.copyWith(chimes: v)),
                  ),
                ],
              ),
            ),
            if (s.media != null) ...[
              const SfSectionTitle('动作素材'),
              const SfPanel(child: TrainingMediaSettings()),
            ],
            const SfSectionTitle('AI 记忆'),
            const SfPanel(child: _AiMemorySettings()),
            const SfSectionTitle('隐私与 AI'),
            SfPanel(
              child: Text(
                '启用 AI 时，你输入的内容、近期对话、当前计划和训练条件会经 '
                'https://api.uuugk.win/v1 '
                '发送给 AI 服务，用于生成回复与训练计划。\n\n'
                'AI 记忆保存在本机；开启时，记住的训练条件会随请求发送给 AI 服务。'
                '可随时关闭或清除记忆。\n\n'
                'App 在本机随机生成并保存设备标识，随 AI 请求发送，用于服务器限流：'
                '每个设备每 10 分钟最多 30 次请求，限制由服务器执行。\n\n'
                '训练记录和已保存计划保存在本机。断网、请求超时或生成结果校验未通过时，'
                '使用本地模板生成训练计划。',
                style: SfType.body.copyWith(
                  fontSize: 14.5,
                  color: SfColors.muted,
                ),
              ),
            ),
            const SfSectionTitle('免责声明'),
            SfPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    disclaimerText,
                    style: SfType.body.copyWith(
                      fontSize: 14.5,
                      color: SfColors.muted,
                    ),
                  ),
                  const SizedBox(height: SfSpace.x2),
                  SfTextAction(
                    key: const ValueKey('safety-recheck'),
                    icon: SfGlyph.shield,
                    color: SfColors.accentText,
                    label: '重新做安全确认',
                    // Back to the chat, where the safety talk runs again.
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      s.chat.startSafetyCheck();
                    },
                  ),
                ],
              ),
            ),
            const SfSectionTitle('素材与许可'),
            SfPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '动作示范视频由 Pose-Hub 动作库预渲染。训练人物派生自 Blender Studio 的 Snow 角色：'
                    'Snow Rig © Blender Foundation | studio.blender.org，'
                    '许可 CC BY 4.0（https://creativecommons.org/licenses/by/4.0/），已修改：灰色人台头、服装材质、骨骼与动作、肌群高亮。'
                    '头部参考来自 Blender Studio Human Base Meshes（CC0）。肌肉颜色仅为训练目标示意，不代表实测肌电。',
                    style: SfType.body.copyWith(
                      fontSize: 14,
                      color: SfColors.muted,
                    ),
                  ),
                  const SizedBox(height: SfSpace.x3),
                  Text(
                    '界面字体 Noto Sans SC（思源黑体）© 2014-2021 Adobe，SIL Open Font License 1.1；'
                    'App 内为按常用字子集化的版本。界面设计语言与图标沿用 HipLab。',
                    style: SfType.body.copyWith(
                      fontSize: 14,
                      color: SfColors.muted,
                    ),
                  ),
                  const SizedBox(height: SfSpace.x2),
                  SfListRow(
                    title: '素材署名全文',
                    onTap: () => _showText(
                      context,
                      'assets/licenses/Drill-media-ATTRIBUTION.md',
                      '素材署名',
                    ),
                  ),
                  SfListRow(
                    title: '字体许可',
                    onTap: () => _showText(
                      context,
                      'assets/licenses/NotoSansSC-OFL.txt',
                      'Noto Sans SC 许可',
                    ),
                  ),
                  SfListRow(
                    title: '开源软件许可',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: '智能健身助手',
                      applicationVersion: appVersion,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: SfSpace.x6),
            Center(
              child: Text(
                '版本 $appVersion',
                textAlign: TextAlign.center,
                style: SfType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showText(
    BuildContext context,
    String asset,
    String title,
  ) async {
    final text = await rootBundle.loadString(asset);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: SfTopBar(title: title),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(SfSpace.gutter),
            child: SelectableText(
              text,
              style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted),
            ),
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
    final s = AppServices.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          ignoring: _busy,
          child: SfSwitchRow(
            key: const ValueKey('ai-memory-switch'),
            title: 'AI 记忆',
            subtitle:
                '记住训练水平、器械和偏好，供之后的对话参考。关闭后不再读取或新增记忆；'
                '当前对话仍保留，点「新对话」可清空旧上下文',
            value: s.store.aiMemoryEnabled,
            onChanged: (enabled) => _setEnabled(s, enabled),
          ),
        ),
        SfTextAction(
          key: const ValueKey('ai-memory-clear'),
          label: _clearing ? '正在清除…' : '清除记忆',
          onPressed: _busy ? null : () => _clear(s),
        ),
        Text(
          '清除已记住的训练条件；聊天记录和已保存计划仍保留。',
          style: SfType.label.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }

  Future<void> _setEnabled(AppServices s, bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await s.setAiMemoryEnabled(enabled);
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

  Future<void> _clear(AppServices s) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _clearing = true;
    });
    try {
      await s.clearAiMemory();
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
