import 'package:flutter/material.dart';

import '../app/services.dart';
import 'theme.dart';

const disclaimerText =
    '智能健身助手提供的是通用健身与拉伸建议，不是医疗诊断或康复处方。'
    '训练中如出现疼痛、麻木、头晕、胸闷或呼吸困难，请立即停止并及时就医。'
    '有慢性病、伤病或正在康复期，请先咨询医生。动作示范中的肌肉高亮仅为教学示意。';

const safetyQuestions = [
  '孕期或产后 6 个月内',
  '近期做过手术，或医生让你限制运动',
  '最近摔伤、扭伤，或关节、腰背正在疼痛肿胀',
  '有心脏病、未控制的高血压，或运动时出现过胸痛、晕厥',
];

/// First launch: disclaimer + four yes/no questions. Any "是" → browse
/// only (the library and previews stay open; plans are not generated).
class SafetyPage extends StatefulWidget {
  const SafetyPage({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  State<SafetyPage> createState() => _SafetyPageState();
}

class _SafetyPageState extends State<SafetyPage> {
  final _answers = List<bool?>.filled(safetyQuestions.length, null);
  bool _agree = false;

  bool get _complete => _agree && _answers.every((a) => a != null);

  @override
  Widget build(BuildContext context) {
    final store = AppServices.of(context).store;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            const Text('开始之前', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('花 10 秒确认一下安全情况。', style: TextStyle(color: SfColors.muted, fontSize: 15)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SfColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(disclaimerText, style: TextStyle(height: 1.6, fontSize: 14)),
            ),
            const SizedBox(height: 20),
            const Text('以下情况是否符合你？', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            for (var i = 0; i < safetyQuestions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: SfColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(safetyQuestions[i], style: const TextStyle(fontSize: 15, height: 1.4))),
                      const SizedBox(width: 8),
                      _yn('否', _answers[i] == false, () => setState(() => _answers[i] = false)),
                      const SizedBox(width: 6),
                      _yn('是', _answers[i] == true, () => setState(() => _answers[i] = true)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('我已阅读并理解以上说明', style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('safety-continue'),
              onPressed: _complete
                  ? () async {
                      final blocked = _answers.any((a) => a == true);
                      await store.acceptSafety(blocked: blocked);
                      widget.onDone();
                    }
                  : null,
              child: const Text('继续'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _yn(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onTap(),
  );
}
