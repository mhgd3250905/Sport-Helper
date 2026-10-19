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
          padding: const EdgeInsets.all(16),
          children: [
            const Text('语音播报', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SwitchListTile(
              key: const ValueKey('voice-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('教练语音'),
              subtitle: const Text('开始、计数、休息和下一个动作提示'),
              value: s.store.voice.voice,
              onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(voice: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('提示音'),
              value: s.store.voice.chimes,
              onChanged: (v) => s.store.setVoice(s.store.voice.copyWith(chimes: v)),
            ),
            const Divider(height: 32),
            const Text('外观', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            SwitchListTile(
              key: const ValueKey('starfield-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('星尘动效'),
              subtitle: const Text('主界面背景的星尘缓慢漂移；关掉后为静态星空。系统开启「减少动画」时自动静止'),
              value: s.store.starfield,
              onChanged: s.store.setStarfield,
            ),
            const Divider(height: 32),
            const Text('免责声明', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(disclaimerText, style: TextStyle(height: 1.6, color: SfColors.muted)),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('safety-recheck'),
              // Back to the chat, where the safety talk runs again.
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                s.chat.startSafetyCheck();
              },
              child: const Text('重新做安全确认'),
            ),
            const Divider(height: 32),
            const Text('素材与许可', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              '动作示范视频由 Pose-Hub 动作库预渲染。训练人物派生自 Blender Studio 的 Snow 角色：'
              'Snow Rig © Blender Foundation | studio.blender.org，'
              '许可 CC BY 4.0（https://creativecommons.org/licenses/by/4.0/），已修改：灰色人台头、服装材质、骨骼与动作、肌群高亮。'
              '头部参考来自 Blender Studio Human Base Meshes（CC0）。肌肉颜色仅为训练目标示意，不代表实测肌电。',
              style: TextStyle(height: 1.6, color: SfColors.muted),
            ),
            TextButton(
              onPressed: () => _showText(context, 'assets/licenses/Drill-media-ATTRIBUTION.md', '素材署名'),
              child: const Text('查看素材署名全文'),
            ),
            TextButton(
              onPressed: () => showLicensePage(context: context, applicationName: '智能健身助手', applicationVersion: appVersion),
              child: const Text('开源软件许可'),
            ),
            const Divider(height: 32),
            Text('版本 $appVersion · 训练计划由内置模板生成，不联网、不收集个人数据。',
                style: const TextStyle(color: SfColors.muted, fontSize: 13)),
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
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(text)),
      ),
    ));
  }
}
