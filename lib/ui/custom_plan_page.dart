import 'package:flutter/material.dart';

import '../app/services.dart';
import '../data/app_store.dart';
import '../domain/exercise.dart';
import '../domain/scenario.dart';
import '../domain/template.dart';
import 'plan_page.dart';
import 'theme.dart';

const examplePrompts = [
  '在办公室午休 10 分钟，肩颈很僵',
  '家里有哑铃，想练 25 分钟全身力量',
  '睡前放松一下，腰有点酸',
  '新手，想练核心马甲线，15 分钟',
  '跑步前热身',
  '膝盖不太好，想练练臀腿',
];

/// The original form (目标 / 场景 / 器械 / 时长 / 水平 / 保护部位 + templates),
/// kept as the 「自定义计划」 entry in the chat drawer.
class CustomPlanPage extends StatefulWidget {
  const CustomPlanPage({super.key});
  @override
  State<CustomPlanPage> createState() => _CustomPlanPageState();
}

class _CustomPlanPageState extends State<CustomPlanPage> {
  final _text = TextEditingController();
  var _req = const ScenarioRequest(minutes: 10);
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _generate({String? templateId}) async {
    final s = AppServices.of(context);
    if (!s.store.trainingAllowed) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.store.safetyAccepted ? '暂不生成训练计划' : '先完成安全确认'),
          content: Text(s.store.safetyAccepted
              ? '你在安全确认里选了需要注意的情况。建议先咨询医生；你仍可以在「动作库」里浏览动作示范。'
                  '如情况已变化，可在「设置」里重新做安全确认。'
              : '请返回首页对话，完成上方的安全确认后再生成计划。'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了'))],
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final tpl = templateId == null ? null : s.catalog.byId(templateId);
    final req = ScenarioRequest(
      description: tpl == null ? _text.text : '',
      goal: tpl == null ? _req.goal : null,
      scene: tpl == null || tpl.scenes.contains(_req.scene) ? _req.scene : tpl.scenes.first,
      equipment: {..._req.equipment, if (tpl != null) ...tpl.equipment.map(Equipment.byName)},
      minutes: tpl?.minutes ?? _req.minutes,
      level: _req.level,
      avoid: _req.avoid,
      templateId: templateId,
    );
    final r = await s.generator.generate(req);
    if (!mounted) return;
    setState(() => _busy = false);
    final plan = r.plan;
    if (plan == null) {
      showSfToast(context, '没能生成计划：${r.issues.take(2).join('；')}', icon: SfGlyph.info, bottom: 24);
      return;
    }
    await s.store.rememberPlan(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlanPage(
        plan: plan,
        request: const DescriptionMatcher().apply(req.description, req),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    Widget chips(List<Widget> children) => Wrap(spacing: SfSpace.x2, runSpacing: SfSpace.x2, children: children);
    return Scaffold(
      appBar: const SfTopBar(title: '自定义计划', caption: '自己选条件，或从常规模板开始'),
      body: ListenableBuilder(
        listenable: s.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(SfSpace.x4, SfSpace.x2, SfSpace.x4, SfSpace.x8),
          children: [
            if (!s.store.trainingAllowed) _blockedBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(SfSpace.x1, 0, SfSpace.x1, SfSpace.x2),
              child: Text('描述你今天想怎么练', style: SfType.headline),
            ),
            TextField(
              key: const ValueKey('prompt'),
              controller: _text,
              minLines: 2,
              maxLines: 4,
              style: SfType.body,
              decoration: const InputDecoration(
                hintText: '例如：在家 15 分钟，没有器械，想练核心，腰不太好',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SfSpace.x1, SfSpace.x2, SfSpace.x1, SfSpace.x3),
              child: Text('描述里提到的场景、时长、器械、水平和不适部位会自动识别，并优先于下方选项。', style: SfType.caption.copyWith(color: SfColors.muted)),
            ),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: examplePrompts.length,
                separatorBuilder: (_, _) => const SizedBox(width: SfSpace.x2),
                itemBuilder: (_, i) {
                  final p = examplePrompts[i];
                  return SfChoiceChip(
                    label: p,
                    selected: _text.text == p,
                    dense: true,
                    onTap: () => setState(() {
                      _text.text = p;
                      // Keep goal picks explicit; infer from the current text at generation.
                      _req = const DescriptionMatcher().apply(p, _req).copyWith(clearGoal: _req.goal == null);
                    }),
                  );
                },
              ),
            ),
            const SfSectionTitle('目标（不选则按描述自动判断）'),
            chips([
              for (final g in goalLabels.entries)
                SfChoiceChip(
                  label: g.value,
                  selected: _req.goal == g.key,
                  onTap: () => setState(
                    () => _req = _req.goal == g.key ? _req.copyWith(clearGoal: true) : _req.copyWith(goal: g.key),
                  ),
                ),
            ]),
            const SfSectionTitle('场景'),
            chips([
              for (final sc in const [('home', '居家'), ('office', '办公室')])
                SfChoiceChip(
                  label: sc.$2,
                  selected: _req.scene == sc.$1,
                  onTap: () => setState(() => _req = _req.copyWith(scene: sc.$1)),
                ),
            ]),
            const SfSectionTitle('手边的器械（徒手、椅子、墙默认都有）'),
            chips([
              for (final q in const [Equipment.band, Equipment.dumbbell])
                SfChoiceChip(
                  label: q.zh,
                  selected: _req.equipment.contains(q),
                  onTap: () => setState(() {
                    final eq = {..._req.equipment};
                    eq.contains(q) ? eq.remove(q) : eq.add(q);
                    _req = _req.copyWith(equipment: eq);
                  }),
                ),
            ]),
            const SfSectionTitle('时长'),
            chips([
              for (final m in const [5, 10, 15, 20, 30])
                SfChoiceChip(
                  label: '$m 分钟',
                  selected: _req.minutes == m,
                  onTap: () => setState(() => _req = _req.copyWith(minutes: m)),
                ),
            ]),
            const SfSectionTitle('水平'),
            chips([
              for (final l in const [1, 2, 3])
                SfChoiceChip(
                  label: levelZh(l),
                  selected: _req.level == l,
                  onTap: () => setState(() => _req = _req.copyWith(level: l)),
                ),
            ]),
            const SfSectionTitle('需要保护的部位'),
            chips([
              for (final part in const ['膝', '腰', '肩', '手腕'])
                SfChoiceChip(
                  label: part,
                  selected: _req.avoid.contains(part),
                  onTap: () => setState(() {
                    final a = {..._req.avoid};
                    a.contains(part) ? a.remove(part) : a.add(part);
                    _req = _req.copyWith(avoid: a);
                  }),
                ),
            ]),
            const SizedBox(height: SfSpace.x6),
            SfPrimaryButton(
              key: const ValueKey('generate'),
              icon: SfGlyph.sparkle,
              label: _busy ? '生成中…' : '生成训练计划',
              onPressed: _busy ? null : () => _generate(),
            ),
            const SfSectionTitle('常规模板'),
            for (final t in s.catalog.templates)
              Padding(
                padding: const EdgeInsets.only(bottom: SfSpace.x2),
                child: _templateCard(t),
              ),
            if (s.store.history.isNotEmpty) ...[
              const SfSectionTitle('最近训练'),
              SfPanel(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.x3, vertical: SfSpace.x1),
                child: Column(
                  children: [
                    for (final h in s.store.history.take(5)) _historyRow(h),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyRow(HistoryEntry h) {
    final done = h.completed >= h.total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SfSpace.x2),
      child: Row(
        children: [
          SfIcon(done ? SfGlyph.checkCircle : SfGlyph.clock, size: 20, color: done ? SfColors.accentText : SfColors.muted),
          const SizedBox(width: SfSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: SfType.callout),
                Text(
                  '${h.at.month}月${h.at.day}日 · ${h.minutes} 分钟 · 完成 ${h.completed}/${h.total} 个动作',
                  style: SfType.label.copyWith(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockedBanner() => Padding(
    padding: const EdgeInsets.only(bottom: SfSpace.x4),
    child: SfPanel(
      padding: const EdgeInsets.all(SfSpace.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SfIcon(SfGlyph.shield, size: 20, color: SfColors.caution),
          const SizedBox(width: SfSpace.x3),
          Expanded(
            child: Text(
              AppServices.of(context).store.safetyAccepted
                  ? '根据你的安全确认，当前只开放动作浏览。建议先咨询医生后再开始训练。'
                  : '请先返回首页对话完成安全确认，再生成训练计划。',
              style: SfType.body.copyWith(fontSize: 15),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _templateCard(PlanTemplate t) {
    final s = AppServices.of(context);
    final first = t.blocks.expand((b) => b.items).map((i) => s.library.tryGet(i.exerciseId)).whereType<Exercise>().firstOrNull;
    return SfPressable(
      key: ValueKey('template-${t.id}'),
      semanticLabel: t.name,
      onTap: _busy ? null : () => _generate(templateId: t.id),
      scale: .985,
      child: SfPanel(
        padding: const EdgeInsets.all(SfSpace.x2),
        radius: SfRadius.lg,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(SfRadius.lg - SfSpace.x2),
              child: SizedBox.square(
                dimension: 64,
                child: ColoredBox(
                  color: SfColors.mediaStage,
                  child: first == null
                      ? null
                      : Image.asset(sfPoster(first), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ),
            ),
            const SizedBox(width: SfSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name, style: SfType.callout.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(t.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: SfType.label.copyWith(fontSize: 12.5)),
                ],
              ),
            ),
            const SizedBox(width: SfSpace.x2),
            Padding(
              padding: const EdgeInsets.only(right: SfSpace.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${t.minutes}′', style: SfType.callout.copyWith(fontWeight: FontWeight.w700, fontFeatures: SfType.tabular)),
                  Text(t.scenes.contains('office') ? (t.scenes.length > 1 ? '通用' : '办公室') : '居家', style: SfType.caption.copyWith(color: SfColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
