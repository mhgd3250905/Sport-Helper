import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../domain/scenario.dart';
import '../domain/template.dart';
import 'about_page.dart';
import 'library_page.dart';
import 'plan_page.dart';
import 'safety_check_page.dart';
import 'theme.dart';

/// Release home: local actions, fixed routines and saved workout history.
/// No conversation is initialized when AI has not been explicitly configured.
class BasicHomePage extends StatefulWidget {
  const BasicHomePage({super.key});

  @override
  State<BasicHomePage> createState() => _BasicHomePageState();
}

class _BasicHomePageState extends State<BasicHomePage> {
  bool _opening = false;

  Future<void> _routine(PlanTemplate template) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      if (!await ensureTrainingSafety(context) || !mounted) return;
      final s = AppServices.of(context);
      final result = await s.generator.generate(
        ScenarioRequest(
          templateId: template.id,
          scene: template.scenes.first,
          equipment: template.equipment.map(Equipment.byName).toSet(),
          minutes: template.minutes,
          level: template.minLevel,
        ),
      );
      if (!mounted) return;
      final plan = result.plan;
      if (plan == null) {
        showSfToast(context, '这套套路暂时无法开始，请选择其他动作或套路。');
        return;
      }
      await s.store.rememberPlan(plan);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'plan'),
          builder: (_) => PlanPage(plan: plan),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return Scaffold(
      appBar: SfTopBar(
        title: 'SmartFit',
        caption: '选动作或套路，按自己的节奏跟练',
        trailing: SfCircleButton(
          key: const ValueKey('basic-settings'),
          icon: SfGlyph.sliders,
          tooltip: '设置',
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'settings'),
              builder: (_) => const AboutPage(),
            ),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: s.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(
            SfSpace.x4,
            SfSpace.x2,
            SfSpace.x4,
            SfSpace.x8,
          ),
          children: [
            if (!s.store.trainingAllowed) ...[
              SfPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.store.safetyAccepted ? '当前仅开放动作浏览' : '开始前，先确认训练安全',
                      style: SfType.callout,
                    ),
                    const SizedBox(height: SfSpace.x2),
                    Text(
                      s.store.safetyAccepted
                          ? '请先咨询医生或专业人员；情况变化后可重新确认。'
                          : '动作示范用于一般健身，请根据自己的身体情况选择。',
                      style: SfType.label,
                    ),
                    const SizedBox(height: SfSpace.x3),
                    SfTextAction(
                      key: const ValueKey('basic-safety-open'),
                      label: '安全确认',
                      icon: SfGlyph.shield,
                      onPressed: () => showSafetyCheck(context, restart: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SfSpace.x4),
            ],
            SfPrimaryButton(
              key: const ValueKey('basic-library'),
              label: '选择动作',
              icon: SfGlyph.grid,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  settings: const RouteSettings(name: 'library'),
                  builder: (_) => const LibraryPage(),
                ),
              ),
            ),
            const SfSectionTitle('训练套路'),
            for (final template in s.catalog.templates)
              Padding(
                padding: const EdgeInsets.only(bottom: SfSpace.x3),
                child: SfPanel(
                  child: SfListRow(
                    key: ValueKey('basic-routine-${template.id}'),
                    title: template.name,
                    detail: '${template.minutes} 分钟 · ${template.summary}',
                    onTap: () => _routine(template),
                  ),
                ),
              ),
            if (s.store.lastPlan case final plan?
                when plan.items.every(
                  (item) => s.library.contains(item.exerciseId),
                )) ...[
              const SfSectionTitle('上次的计划'),
              SfPanel(
                child: SfListRow(
                  title: plan.title,
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      settings: const RouteSettings(name: 'plan'),
                      builder: (_) => PlanPage(plan: plan),
                    ),
                  ),
                ),
              ),
            ],
            if (s.store.history.isNotEmpty) ...[
              const SfSectionTitle('最近训练'),
              SfPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in s.store.history.take(5))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: SfSpace.x2,
                        ),
                        child: Text(
                          '${entry.title}\n'
                          '${entry.at.month}月${entry.at.day}日 · '
                          '完成 ${entry.completed}/${entry.total} 个动作',
                          style: SfType.callout,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
