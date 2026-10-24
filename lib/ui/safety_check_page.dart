import 'package:flutter/material.dart';

import '../app/services.dart';
import '../chat/safety_script.dart';
import 'theme.dart';

/// The local safety gate has no dependency on a conversation or AI service.
Future<bool> showSafetyCheck(
  BuildContext context, {
  bool restart = false,
}) async {
  final store = AppServices.of(context).store;
  if (restart) await store.beginSafetyCheck();
  if (!context.mounted) return false;
  return await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'safety_check'),
          builder: (_) => const SafetyCheckPage(),
        ),
      ) ??
      false;
}

Future<bool> ensureTrainingSafety(BuildContext context) async {
  if (AppServices.of(context).store.trainingAllowed) return true;
  return showSafetyCheck(context);
}

class SafetyCheckPage extends StatefulWidget {
  const SafetyCheckPage({super.key});

  @override
  State<SafetyCheckPage> createState() => _SafetyCheckPageState();
}

class _SafetyCheckPageState extends State<SafetyCheckPage> {
  int _question = -1;
  bool _saving = false;
  bool _blocked = false;

  Future<void> _answer(bool risk) async {
    final store = AppServices.of(context).store;
    if (risk || _question == safetyQuestions.length - 1) {
      setState(() => _saving = true);
      await store.acceptSafety(blocked: risk);
      if (!mounted) return;
      if (risk) {
        setState(() {
          _blocked = true;
          _saving = false;
        });
      } else {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() => _question++);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const SfTopBar(title: '安全确认'),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SfSpace.x4),
        children: [
          SfPanel(
            child: Text(
              _blocked
                  ? '根据本次回答，暂不开放训练。请先咨询医生或专业人员；你仍可浏览动作示范。情况变化后可在设置重新确认。'
                  : _question < 0
                  ? disclaimerText
                  : safetyQuestionText(_question),
              style: SfType.body,
            ),
          ),
          const SizedBox(height: SfSpace.x6),
          if (_blocked)
            SfPrimaryButton(
              label: '返回浏览',
              onPressed: () => Navigator.of(context).pop(false),
            )
          else if (_question < 0)
            SfPrimaryButton(
              key: const ValueKey('basic-safety-understood'),
              label: '我已了解',
              onPressed: () => setState(() => _question = 0),
            )
          else ...[
            SfPrimaryButton(
              key: const ValueKey('basic-safety-no'),
              label: '否',
              onPressed: _saving ? null : () => _answer(false),
            ),
            const SizedBox(height: SfSpace.x3),
            SfSecondaryButton(
              key: const ValueKey('basic-safety-yes'),
              label: '是',
              onPressed: _saving ? null : () => _answer(true),
            ),
          ],
        ],
      ),
    ),
  );
}
