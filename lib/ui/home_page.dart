import 'package:flutter/material.dart';

import '../app/services.dart';
import '../domain/exercise.dart';
import '../domain/scenario.dart';
import '../domain/template.dart';
import 'about_page.dart';
import 'library_page.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
    if (s.store.safetyBlocked) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('暂不生成训练计划'),
          content: const Text(
            '你在安全确认里选了需要注意的情况。建议先咨询医生；你仍可以在「动作库」里浏览动作示范。'
            '如情况已变化，可在「关于」里重新做安全确认。',
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没能生成计划：${r.issues.take(2).join('；')}')),
      );
      return;
    }
    await s.store.rememberPlan(plan);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlanPage(plan: plan)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能健身助手', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: '动作库',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LibraryPage()),
            ),
          ),
          IconButton(
            tooltip: '关于与设置',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: s.store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (s.store.safetyBlocked) _blockedBanner(),
            const Text('描述你今天想怎么练', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('prompt'),
              controller: _text,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '例如：在家 15 分钟，没有器械，想练核心，腰不太好',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in examplePrompts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p, style: const TextStyle(fontSize: 13)),
                        onPressed: () => setState(() {
                          _text.text = p;
                          _req = const DescriptionMatcher().apply(p, _req.copyWith(clearGoal: true));
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _section('目标（不选则按描述自动判断）'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in goalLabels.entries)
                  ChoiceChip(
                    label: Text(g.value),
                    selected: _req.goal == g.key,
                    onSelected: (v) => setState(
                      () => _req = v ? _req.copyWith(goal: g.key) : _req.copyWith(clearGoal: true),
                    ),
                  ),
              ],
            ),
            _section('场景'),
            Wrap(spacing: 8, children: [
              for (final sc in const [('home', '居家'), ('office', '办公室')])
                ChoiceChip(
                  label: Text(sc.$2),
                  selected: _req.scene == sc.$1,
                  onSelected: (_) => setState(() => _req = _req.copyWith(scene: sc.$1)),
                ),
            ]),
            _section('手边的器械（徒手、椅子、墙默认都有）'),
            Wrap(spacing: 8, children: [
              for (final q in const [Equipment.band, Equipment.dumbbell])
                FilterChip(
                  label: Text(q.zh),
                  selected: _req.equipment.contains(q),
                  onSelected: (v) => setState(() {
                    final eq = {..._req.equipment};
                    v ? eq.add(q) : eq.remove(q);
                    _req = _req.copyWith(equipment: eq);
                  }),
                ),
            ]),
            _section('时长'),
            Wrap(spacing: 8, children: [
              for (final m in const [5, 10, 15, 20, 30])
                ChoiceChip(
                  label: Text('$m 分钟'),
                  selected: _req.minutes == m,
                  onSelected: (_) => setState(() => _req = _req.copyWith(minutes: m)),
                ),
            ]),
            _section('水平'),
            Wrap(spacing: 8, children: [
              for (final l in const [1, 2, 3])
                ChoiceChip(
                  label: Text(levelZh(l)),
                  selected: _req.level == l,
                  onSelected: (_) => setState(() => _req = _req.copyWith(level: l)),
                ),
            ]),
            _section('需要保护的部位'),
            Wrap(spacing: 8, children: [
              for (final part in const ['膝', '腰', '肩', '手腕'])
                FilterChip(
                  label: Text(part),
                  selected: _req.avoid.contains(part),
                  onSelected: (v) => setState(() {
                    final a = {..._req.avoid};
                    v ? a.add(part) : a.remove(part);
                    _req = _req.copyWith(avoid: a);
                  }),
                ),
            ]),
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const ValueKey('generate'),
              onPressed: _busy ? null : () => _generate(),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(_busy ? '生成中…' : '生成训练计划'),
            ),
            const SizedBox(height: 28),
            const Text('常规模板', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final t in s.catalog.templates)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _templateCard(t),
              ),
            if (s.store.history.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('最近训练', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final h in s.store.history.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    h.completed >= h.total ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                    color: h.completed >= h.total ? SfColors.ok : SfColors.warn,
                  ),
                  title: Text(h.title),
                  subtitle: Text(
                    '${h.at.month}月${h.at.day}日 · ${h.minutes} 分钟 · 完成 ${h.completed}/${h.total} 个动作',
                    style: const TextStyle(color: SfColors.muted),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _blockedBanner() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0x33FFC857),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Text(
      '根据你的安全确认，当前只开放动作浏览。建议先咨询医生后再开始训练。',
      style: TextStyle(height: 1.5),
    ),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(title, style: const TextStyle(color: SfColors.muted, fontSize: 14)),
  );

  Widget _templateCard(PlanTemplate t) {
    final s = AppServices.of(context);
    final first = t.blocks.expand((b) => b.items).map((i) => s.library.tryGet(i.exerciseId)).whereType<Exercise>().firstOrNull;
    return Card(
      child: InkWell(
        key: ValueKey('template-${t.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _generate(templateId: t.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: first == null
                      ? const ColoredBox(color: SfColors.surface2)
                      : Image.asset(first.media.poster, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const ColoredBox(color: SfColors.surface2)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(t.summary, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: SfColors.muted, fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text('${t.minutes}′', style: const TextStyle(color: SfColors.accent, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(t.scenes.contains('office') ? (t.scenes.length > 1 ? '通用' : '办公室') : '居家',
                      style: const TextStyle(color: SfColors.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
