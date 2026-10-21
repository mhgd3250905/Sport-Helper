import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../app/services.dart';
import '../chat/safety_script.dart' show disclaimerText;
import 'theme.dart';

const appVersion = '0.1.0+6 (MVP)';

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
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, 0, SfSpace.x4, SfSpace.x8),
          children: [
            const SfSectionTitle('外观'),
            SfPanel(
              padding: const EdgeInsets.all(SfSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SfSegmented<String>(
                    keyPrefix: 'appearance-',
                    items: const [('dark', '深空'), ('light', '浅色'), ('system', '跟随系统')],
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
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.x3, vertical: SfSpace.x1),
              child: Column(
                children: [
                  SfSwitchRow(
                    key: const ValueKey('voice-switch'),
                    title: '教练语音',
                    subtitle: '开始、计数、休息和下一个动作提示',
                    value: s.store.voice.voice,
                    onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(voice: v)),
                  ),
                  SfSwitchRow(
                    title: '提示音',
                    subtitle: '开始、换动作和最后几秒的提示音',
                    value: s.store.voice.chimes,
                    onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(chimes: v)),
                  ),
                ],
              ),
            ),
            const SfSectionTitle('隐私与 AI'),
            SfPanel(
              child: Text(
                '启用 AI 时，你输入的内容、近期对话、当前计划和训练条件会经 '
                'https://api.uuugk.win/v1 '
                '发送给 AI 服务，用于生成回复与训练计划。\n\n'
                'App 在本机随机生成并保存设备标识，随 AI 请求发送，用于服务器限流：'
                '每个设备每 10 分钟最多 30 次请求，限制由服务器执行。\n\n'
                '训练记录和已保存计划保存在本机。断网、请求超时或生成结果校验未通过时，'
                '使用本地模板生成训练计划。',
                style: SfType.body.copyWith(fontSize: 14.5, color: SfColors.muted),
              ),
            ),
            const SfSectionTitle('免责声明'),
            SfPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(disclaimerText, style: SfType.body.copyWith(fontSize: 14.5, color: SfColors.muted)),
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
                    style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted),
                  ),
                  const SizedBox(height: SfSpace.x3),
                  Text(
                    '界面字体 Noto Sans SC（思源黑体）© 2014-2021 Adobe，SIL Open Font License 1.1；'
                    'App 内为按常用字子集化的版本。界面设计语言与图标沿用 HipLab。',
                    style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted),
                  ),
                  const SizedBox(height: SfSpace.x2),
                  SfListRow(title: '素材署名全文', onTap: () => _showText(context, 'assets/licenses/Drill-media-ATTRIBUTION.md', '素材署名')),
                  SfListRow(title: '字体许可', onTap: () => _showText(context, 'assets/licenses/NotoSansSC-OFL.txt', 'Noto Sans SC 许可')),
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

  Future<void> _showText(BuildContext context, String asset, String title) async {
    final text = await rootBundle.loadString(asset);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: SfTopBar(title: title),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(SfSpace.gutter),
          child: SelectableText(text, style: SfType.body.copyWith(fontSize: 14, color: SfColors.muted)),
        ),
      ),
    ));
  }
}
