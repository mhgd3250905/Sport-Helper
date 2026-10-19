import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/services.dart';
import '../chat/safety_script.dart' show disclaimerText;
import 'theme.dart';

const appVersion = '0.1.0 (MVP)';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('关于与设置')),
      body: ListenableBuilder(
        listenable: s.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x8),
          children: [
            const SfSectionTitle('外观'),
            SfPanel(
              padding: const EdgeInsets.all(SfSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppearancePicker(
                    value: s.store.appearance,
                    onChanged: s.store.setAppearance,
                  ),
                  const SizedBox(height: SfSpace.x1),
                  _Switch(
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
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.x3, vertical: SfSpace.x1),
              child: Column(
                children: [
                  _Switch(
                    key: const ValueKey('voice-switch'),
                    title: '教练语音',
                    subtitle: '开始、计数、休息和下一个动作提示',
                    value: s.store.voice.voice,
                    onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(voice: v)),
                  ),
                  _Switch(
                    title: '提示音',
                    value: s.store.voice.chimes,
                    onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(chimes: v)),
                  ),
                ],
              ),
            ),
            const SfSectionTitle('免责声明'),
            SfPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(disclaimerText, style: SfType.body.copyWith(fontSize: 14.5, color: SfColors.muted)),
                  const SizedBox(height: SfSpace.x2),
                  TextButton(
                    key: const ValueKey('safety-recheck'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                    // Back to the chat, where the safety talk runs again.
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      s.chat.startSafetyCheck();
                    },
                    child: const Text('重新做安全确认'),
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
                    style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted),
                  ),
                  const SizedBox(height: SfSpace.x3),
                  Text(
                    '界面字体 Noto Sans SC（思源黑体）© 2014-2021 Adobe，SIL Open Font License 1.1；'
                    'App 内为按常用字子集化的版本。界面设计语言与图标沿用 HipLab。',
                    style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted),
                  ),
                  const SizedBox(height: SfSpace.x1),
                  Wrap(
                    spacing: SfSpace.x4,
                    children: [
                      _Link('素材署名全文', () => _showText(context, 'assets/licenses/Drill-media-ATTRIBUTION.md', '素材署名')),
                      _Link('字体许可', () => _showText(context, 'assets/licenses/NotoSansSC-OFL.txt', 'Noto Sans SC 许可')),
                      _Link('开源软件许可', () => showLicensePage(
                        context: context,
                        applicationName: '智能健身助手',
                        applicationVersion: appVersion,
                      )),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: SfSpace.x6),
            Center(
              child: Text(
                '版本 $appVersion · 训练计划由内置模板生成，不联网、不收集个人数据。',
                textAlign: TextAlign.center,
                style: SfType.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showText(BuildContext context, String asset, String title) async {
    final text = await rootBundle.loadString(asset);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(SfSpace.gutter),
          child: SelectableText(text, style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted)),
        ),
      ),
    ));
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
    onPressed: onTap,
    child: Text(label),
  );
}

class _Switch extends StatelessWidget {
  const _Switch({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: SfSpace.x1),
    title: Text(title, style: SfType.callout),
    subtitle: subtitle == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle!, style: SfType.label.copyWith(fontSize: 12.5)),
          ),
    value: value,
    onChanged: onChanged,
  );
}

/// 深空 / 浅色 / 跟随系统: a three-way segmented choice (tonal track,
/// the chosen segment one tone up; no raised thumb).
class _AppearancePicker extends StatelessWidget {
  const _AppearancePicker({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _items = [('dark', '深空'), ('light', '浅色'), ('system', '跟随系统')];

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: SfColors.isDark ? SfColors.background : SfColors.surfaceHigh,
      borderRadius: BorderRadius.circular(SfRadius.sm + 2),
    ),
    child: Row(
      children: [
        for (final (id, label) in _items)
          Expanded(
            child: SfPressable(
              key: ValueKey('appearance-$id'),
              semanticLabel: label,
              onTap: () => onChanged(id),
              child: AnimatedContainer(
                duration: SfMotion.medium,
                curve: SfMotion.standard,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == id ? (SfColors.isDark ? SfColors.surfaceHigh : SfColors.surface) : Colors.transparent,
                  borderRadius: BorderRadius.circular(SfRadius.sm - 1),
                  boxShadow: value == id && !SfColors.isDark
                      ? const [BoxShadow(color: Color(0x140D2A20), blurRadius: 4, offset: Offset(0, 1))]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: value == id ? FontWeight.w600 : FontWeight.w400,
                    color: value == id ? SfColors.text : SfColors.muted,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
