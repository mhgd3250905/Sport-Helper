/// The offline chat: keyword / slot parsing + template plans + validation.
/// Short, spoken Chinese; asks at most two follow-ups per plan; edits the
/// current plan (shorter / longer / easier / harder / swap the Nth move);
/// steers small talk back to training instead of pretending to chat.
library;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_generator.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import '../domain/session.dart';
import 'chat_models.dart';
import 'slot_parser.dart';

const defaultSuggestions = ['办公室 10 分钟肩颈放松', '在家 20 分钟练核心', '睡前拉伸 10 分钟', '跑步前热身'];
const planSuggestions = ['再短一点', '难一点', '换掉第 2 个', '换一套'];

class RuleChatEngine implements ChatEngine {
  RuleChatEngine({
    required this.lib,
    required this.templates,
    PlanGenerator? generator,
    this.parser = const SlotParser(),
  }) : generator = generator ?? templates;

  final ExerciseLibrary lib;

  /// Template helpers for edits (refit, replacements, ranking).
  final TemplatePlanGenerator templates;

  /// Makes new plans (the template generator today; an AI one later).
  final PlanGenerator generator;
  final SlotParser parser;

  @override
  String get id => 'rules';

  static const _maxQuestions = 2;

  @override
  Future<ChatReply> reply(String input, ChatState s) async {
    final t = input.trim();
    if (t.isEmpty) return ChatReply(messages: const [], state: s);

    if (t.startsWith('@saved:')) return _showSaved(t.substring(7), s);

    if (_any(t, ['晕厥', '头晕', '眼前发黑', '呼吸困难', '喘不上气', '心慌', '心悸']) ||
        RegExp('胸[口部]?.{0,3}(闷|痛|疼|压)').hasMatch(t)) {
      return ChatReply(
        messages: const [
          BotMessage('这些症状不适合继续练。先停下来休息；如果没有缓解或反复出现，请尽快就医。'),
        ],
        state: s.copyWith(clearPending: true),
        suggestions: const ['我缓过来了，来点轻松的拉伸'],
      );
    }

    if (_any(t, ['上次那个', '上次的', '上一次', '老样子', '再来一次', '再来一遍', '跟上次一样', '上回那个'])) {
      return _recallLast(s);
    }
    if (_any(t, ['我的计划', '保存的', '存的计划', '收藏', '已保存', '我存的'])) {
      return _listSaved(s);
    }
    if (_any(t, ['动作库', '有哪些动作', '所有动作', '看看动作'])) {
      return ChatReply(
        messages: const [BotMessage('打开动作库，点动作就能看示范。')],
        state: s,
        action: '@library',
      );
    }

    final slots = parser.parse(t, asked: s.pending == null ? null : s.asked.lastOrNull);

    final plan = s.plan;
    if (plan != null) {
      final edit = parser.parseEdit(t, _names(plan));
      final newGoal = slots.goal != null && slots.goal != plan.goal;
      final timeOnly = edit != null &&
          const {EditKind.shorter, EditKind.longer, EditKind.minutes}.contains(edit.kind);
      if (edit != null && !(timeOnly && newGoal)) {
        if (s.safetyBlocked) return _blocked(s);
        return _edit(edit, plan, s.request ?? requestForPlan(plan), s);
      }
    }

    // "有哑铃" / "在办公室" / "膝盖疼" right after a card: rebuild that plan
    // with the new condition instead of starting a fresh request.
    final req0 = s.request;
    if (plan != null &&
        req0 != null &&
        s.pending == null &&
        slots.goal == null &&
        slots.focus.isEmpty &&
        slots.minutes == null &&
        (slots.equipment != null || slots.scene != null || slots.level != null || slots.avoid.isNotEmpty)) {
      final base = Slots(
        goal: req0.goal ?? plan.goal,
        scene: req0.scene,
        minutes: req0.minutes,
        equipment: req0.equipment,
        level: req0.level,
        avoid: req0.avoid,
        description: req0.description,
      );
      return _plan(base.merge(slots), s.copyWith(clearPending: true), redo: true);
    }

    if (_isGreeting(t)) {
      return ChatReply(
        messages: const [BotMessage('你好！说说想练什么、在哪儿、有多少时间，我给你排一套。')],
        state: s,
        suggestions: _suggestions(s),
      );
    }
    if (_any(t, ['谢谢', '多谢', '感谢', 'thx', 'thanks'])) {
      return ChatReply(
        messages: const [BotMessage('不客气。练完记得喝点水。')],
        state: s,
        suggestions: _suggestions(s),
      );
    }
    if (_any(t, ['你能做什么', '你会什么', '怎么用', '能干嘛', '能干什么', '帮助', '你是谁'])) {
      return ChatReply(
        messages: const [
          BotMessage(
            '我是你的训练助手：告诉我目标、场景和时间，我排一套带示范和语音的计划。\n'
            '排好后可以说「再短一点」「难一点」「换掉第 2 个」，满意就点「保存」，下次说「上次那个」就能调出来。',
          ),
        ],
        state: s,
        suggestions: _suggestions(s),
      );
    }

    final pending = s.pending;
    // A different goal while a question is open is a new request.
    final fresh = pending != null && slots.goal != null && pending.goal != null && slots.goal != pending.goal;
    if (pending != null && !slots.isEmpty && !fresh) {
      return _plan(pending.merge(slots), s);
    }
    if (!slots.isEmpty || parser.wantsTraining(t)) {
      return _plan(slots, s.copyWith(clearPending: true));
    }
    if (pending != null) {
      final q = _question(s.asked.last, pending);
      return ChatReply(
        messages: [BotMessage('没太听明白。${q.text}', options: q.options)],
        state: s,
      );
    }
    return ChatReply(
      messages: const [BotMessage('这个我帮不上忙，我只负责帮你安排训练。今天想怎么练？')],
      state: s,
      suggestions: _suggestions(s),
    );
  }

  // ---------------------------------------------------------------- plans

  Future<ChatReply> _plan(Slots slots, ChatState s, {bool redo = false}) async {
    if (s.safetyBlocked) return _blocked(s);

    final missing = redo ? null : _missing(slots);
    if (missing != null && s.asked.length < _maxQuestions && !s.asked.contains(missing)) {
      final q = _question(missing, slots);
      return ChatReply(
        messages: [BotMessage(q.text, options: q.options)],
        state: s.copyWith(pending: slots, asked: [...s.asked, missing]),
      );
    }

    final gearDefaulted = slots.equipment == null && _gearMatters(slots);
    final req = slots.toRequest(fallbackGoal: slots.scene == 'office' ? 'relax' : 'fullbody');
    // Pick the template here, from the merged slots, so earlier wording
    // ("办公室…" then "在家") can't override what the user said last.
    final pick = templates.rank(req).first.$1;
    final r = await generator.generate(req.copyWith(description: '', templateId: pick.id));
    final plan = r.plan;
    if (plan == null) {
      return ChatReply(
        messages: [
          BotMessage('这次没排出来：${r.issues.take(1).join()}。换个说法或者放宽一点条件试试？'),
        ],
        state: s.copyWith(clearPending: true),
        suggestions: _suggestions(s),
      );
    }
    final lines = <String>[
      redo
          ? '按新条件重新排了：「${plan.title}」，${minutesZhShort(_seconds(plan))}，${_count(plan)} 个动作。'
          : '好，给你排了一套「${plan.title}」，${minutesZhShort(_seconds(plan))}，${_count(plan)} 个动作。',
    ];
    final swaps = plan.notes.where((n) => n.contains('换成') || n.contains('去掉')).length;
    if (slots.avoid.isNotEmpty) {
      lines.add('已避开会加重${slots.avoid.join('、')}负担的动作；如果是持续疼痛或肿胀，先别练，找医生看看。');
    } else if (swaps > 0) {
      lines.add('按你的条件换掉了 $swaps 个动作。');
    }
    if (gearDefaulted) lines.add('先按徒手排的，有哑铃或弹力带跟我说一声。');
    return ChatReply(
      messages: [
        BotMessage(lines.join('\n')),
        BotMessage('', plan: plan, request: req),
      ],
      state: s.copyWith(clearPending: true, plan: plan, request: req),
      suggestions: planSuggestions,
    );
  }

  /// The next thing worth asking, or null when we can plan.
  String? _missing(Slots s) {
    if (s.goal == null && s.focus.isEmpty) return 'goal';
    // Warm-ups and cool-downs have a natural length: no need to ask.
    if (s.minutes == null && !const {'warmup', 'cooldown'}.contains(s.goal)) return 'minutes';
    if (s.equipment == null && _gearMatters(s)) return 'equipment';
    return null;
  }

  bool _gearMatters(Slots s) =>
      s.scene != 'office' && const {'strength', 'fullbody', 'core'}.contains(s.goal);

  BotMessage _question(String slot, Slots s) => switch (slot) {
    'goal' => const BotMessage(
      '想练哪方面？',
      options: [ChatOption('放松拉伸'), ChatOption('力量塑形'), ChatOption('核心腰腹'), ChatOption('全身激活')],
    ),
    'minutes' => const BotMessage(
      '大概有几分钟？',
      options: [ChatOption('5 分钟'), ChatOption('10 分钟'), ChatOption('20 分钟'), ChatOption('30 分钟')],
    ),
    _ => const BotMessage(
      '手边有哑铃或弹力带吗？',
      options: [ChatOption('徒手就行'), ChatOption('有弹力带'), ChatOption('有哑铃'), ChatOption('都有')],
    ),
  };

  // ---------------------------------------------------------------- edits

  Future<ChatReply> _edit(PlanEdit e, TrainingPlan plan, ScenarioRequest req, ChatState s) async {
    final now = _minutes(plan);
    switch (e.kind) {
      case EditKind.shorter:
        final target = (now - (now * 0.3).round().clamp(3, 10)).clamp(5, 45);
        return _retime(plan, req, s, target, shorter: true);
      case EditKind.longer:
        final target = (now + (now * 0.3).round().clamp(5, 10)).clamp(5, 45);
        return _retime(plan, req, s, target, shorter: false);
      case EditKind.minutes:
        if ((e.minutes! - now).abs() <= 1) {
          return ChatReply(
            messages: [BotMessage('现在就是${minutesZhShort(_seconds(plan))}，不用改。')],
            state: s,
            suggestions: planSuggestions,
          );
        }
        return _retime(plan, req, s, e.minutes!, shorter: e.minutes! < now);
      case EditKind.easier:
      case EditKind.harder:
        return _relevel(plan, req, s, e.kind == EditKind.harder ? 1 : -1);
      case EditKind.replace:
        return _replace(plan, req, s, e);
      case EditKind.another:
        return _another(plan, req, s);
    }
  }

  ChatReply _retime(TrainingPlan plan, ScenarioRequest req, ChatState s, int target, {required bool shorter}) {
    final before = _seconds(plan);
    var next = templates.refit(plan, target);
    final after = _seconds(next);
    final changed = shorter ? after < before - 30 : after > before + 30;
    if (!changed) {
      return ChatReply(
        messages: [
          BotMessage(
            shorter
                ? '这已经是这套最精简的版本了（${minutesZhShort(before)}），再短就练不到位了。要不换一套更短的？'
                : '这套已经加到头了（${minutesZhShort(before)}）。想练更久的话，我换一套更长的？',
            options: const [ChatOption('换一套')],
          ),
        ],
        state: s,
        suggestions: planSuggestions,
      );
    }
    next = _renew(next);
    final r = req.copyWith(minutes: target);
    return _planReply(
      '${shorter ? '缩' : '加'}到${minutesZhShort(after)}了。',
      next,
      r,
      s,
    );
  }

  Future<ChatReply> _relevel(TrainingPlan plan, ScenarioRequest req, ChatState s, int delta) async {
    final level = req.level + delta;
    if (level < 1 || level > 3) {
      return ChatReply(
        messages: [
          BotMessage(
            delta < 0
                ? '已经是入门强度了。累的话可以说「再短一点」，或者组间多歇一会儿。'
                : '已经是进阶强度了，再往上就超出这套计划的范围了。可以说「长一点」多练几组。',
          ),
        ],
        state: s,
        suggestions: planSuggestions,
      );
    }
    final r = req.copyWith(level: level, minutes: _minutes(plan), templateId: plan.templateId);
    // The template is fixed: don't let the old wording re-pick minutes.
    final g = await generator.generate(r.copyWith(description: ''));
    final next = g.plan;
    if (next == null) {
      return ChatReply(
        messages: [BotMessage('这套暂时调不了难度：${g.issues.take(1).join()}。')],
        state: s,
        suggestions: planSuggestions,
      );
    }
    return _planReply(
      delta < 0
          ? '降了一档，现在是「${_levelZh(level)}」强度，次数和时长都少了一点。'
          : '加了一档，现在是「${_levelZh(level)}」强度，次数和时长都多了一点。',
      next,
      r,
      s,
    );
  }

  ChatReply _replace(TrainingPlan plan, ScenarioRequest req, ChatState s, PlanEdit e) {
    final items = plan.items.toList();
    var index = e.index;
    if (index == null && e.name != null) {
      final i = items.indexWhere((it) => lib.tryGet(it.exerciseId)?.name == e.name);
      if (i >= 0) index = i + 1;
    }
    if (index == null) {
      return ChatReply(
        messages: [
          BotMessage(
            '换哪一个？',
            options: [
              for (var i = 0; i < items.length && i < 4; i++)
                ChatOption('第 ${i + 1} 个 ${lib.tryGet(items[i].exerciseId)?.name ?? ''}', '换掉第 ${i + 1} 个'),
            ],
          ),
        ],
        state: s,
      );
    }
    if (index < 1 || index > items.length) {
      return ChatReply(
        messages: [BotMessage('这套一共 ${items.length} 个动作，你说的是第几个？')],
        state: s,
        suggestions: planSuggestions,
      );
    }
    final old = items[index - 1];
    final from = lib.tryGet(old.exerciseId);
    if (from == null) return ChatReply(messages: const [], state: s);
    final used = {for (final it in items) it.exerciseId};
    final alt = templates.replacementFor(from, req, used);
    if (alt == null) {
      return ChatReply(
        messages: [BotMessage('第 $index 个「${from.name}」暂时没有合适的替换动作。要不换一套？', options: const [ChatOption('换一套')])],
        state: s,
        suggestions: planSuggestions,
      );
    }
    final d = alt.dose;
    final swapped = PlanItem(
      exerciseId: alt.id,
      mode: d.mode,
      sets: old.sets,
      reps: d.mode == DoseMode.reps ? (old.mode == DoseMode.reps ? old.reps : d.reps) : null,
      workSeconds: d.mode == DoseMode.time ? (old.mode == DoseMode.time ? old.workSeconds : d.seconds) : null,
      perSide: alt.unilateral,
      restSeconds: old.restSeconds,
      replacedFrom: from.id,
    );
    var k = 0;
    final blocks = [
      for (final b in plan.blocks)
        b.copyWith(items: [
          for (final it in b.items) (++k == index) ? swapped : it,
        ]),
    ];
    final next = _renew(plan.copyWith(blocks: blocks, notes: [...plan.notes, '「${from.name}」换成「${alt.name}」（对话里替换）']));
    final issues = PlanValidator(lib).validate(next, req);
    if (issues.isNotEmpty) {
      return ChatReply(
        messages: [BotMessage('这个换不了：${issues.first}。')],
        state: s,
        suggestions: planSuggestions,
      );
    }
    return _planReply('把第 $index 个「${from.name}」换成了「${alt.name}」。', next, req, s);
  }

  Future<ChatReply> _another(TrainingPlan plan, ScenarioRequest req, ChatState s) async {
    final ranked = templates.rank(req.copyWith(description: req.description));
    final pick = ranked.map((e) => e.$1).where((t) => t.id != plan.templateId).firstOrNull;
    if (pick == null) return ChatReply(messages: const [BotMessage('暂时没有别的合适计划了。')], state: s);
    final r = ScenarioRequest(
      description: req.description,
      goal: req.goal,
      scene: pick.scenes.contains(req.scene) ? req.scene : pick.scenes.first,
      equipment: req.equipment,
      minutes: req.minutes,
      level: req.level,
      avoid: req.avoid,
      templateId: pick.id,
    );
    final g = await generator.generate(r.copyWith(description: ''));
    final next = g.plan;
    if (next == null) {
      return ChatReply(messages: [BotMessage('换一套没成功：${g.issues.take(1).join()}。')], state: s);
    }
    return _planReply('换一套试试：「${next.title}」，${minutesZhShort(_seconds(next))}。', next, r, s);
  }

  ChatReply _planReply(String text, TrainingPlan plan, ScenarioRequest req, ChatState s) => ChatReply(
    messages: [BotMessage(text), BotMessage('', plan: plan, request: req)],
    state: s.copyWith(clearPending: true, plan: plan, request: req),
    suggestions: planSuggestions,
  );

  /// An edited plan is a new version: new id, so saving it keeps both.
  TrainingPlan _renew(TrainingPlan p) => TrainingPlan(
    schemaVersion: p.schemaVersion,
    id: '${p.id.split('~').first}~${DateTime.now().microsecondsSinceEpoch}',
    source: p.source,
    templateId: p.templateId,
    title: p.title,
    summary: p.summary,
    goal: p.goal,
    scene: p.scene,
    equipment: p.equipment,
    level: p.level,
    targetMinutes: p.targetMinutes,
    blocks: p.blocks,
    avoid: p.avoid,
    notes: p.notes,
    safetyNotes: p.safetyNotes,
  );

  // ---------------------------------------------------------------- saved

  ChatReply _recallLast(ChatState s) {
    final latestSaved = s.saved.isEmpty
        ? null
        : (s.saved.toList()..sort((a, b) => b.touchedAt.compareTo(a.touchedAt))).first;
    final plan = s.lastPlan ?? latestSaved?.plan;
    if (plan == null) {
      return ChatReply(
        messages: const [BotMessage('还没有练过的计划。先说说今天想怎么练？')],
        state: s,
        suggestions: defaultSuggestions,
      );
    }
    if (s.safetyBlocked) return _blocked(s);
    final req = requestForPlan(plan);
    return _planReply('这是你上次的「${plan.title}」，直接开始就行。', plan, req, s);
  }

  ChatReply _listSaved(ChatState s) {
    if (s.saved.isEmpty) {
      return ChatReply(
        messages: const [BotMessage('还没有保存的计划。练得顺手的计划，点卡片上的「保存」就能存下来。')],
        state: s,
        suggestions: _suggestions(s),
      );
    }
    final list = s.saved.toList()..sort((a, b) => b.touchedAt.compareTo(a.touchedAt));
    return ChatReply(
      messages: [
        BotMessage(
          '你保存了 ${list.length} 套计划，点一个调出来：',
          options: [
            for (final p in list.take(4)) ChatOption(p.name, '@saved:${p.id}'),
            if (list.length > 4) const ChatOption('全部计划', '@drawer'),
          ],
        ),
      ],
      state: s,
    );
  }

  ChatReply _showSaved(String id, ChatState s) {
    final saved = s.saved.where((p) => p.id == id).firstOrNull;
    if (saved == null) {
      return ChatReply(messages: const [BotMessage('这套计划已经删掉了。')], state: s);
    }
    if (s.safetyBlocked) return _blocked(s);
    return _planReply('「${saved.name}」来了。', saved.plan, requestForPlan(saved.plan), s);
  }

  ChatReply _blocked(ChatState s) => ChatReply(
    messages: const [
      BotMessage(
        '根据你的安全确认，我先不生成训练计划，建议先咨询医生。你仍可以浏览动作库里的示范；'
        '情况变化后，可以在「关于与设置」里重新确认。',
        options: [ChatOption('浏览动作库', '@library'), ChatOption('重新确认', '@safety')],
      ),
    ],
    state: s.copyWith(clearPending: true),
  );

  // ---------------------------------------------------------------- utils

  List<String> _suggestions(ChatState s) => [
    if (s.lastPlan != null || s.saved.isNotEmpty) '上次那个',
    ...defaultSuggestions,
  ].take(4).toList();

  List<String> _names(TrainingPlan p) => [
    for (final i in p.items) ?lib.tryGet(i.exerciseId)?.name,
  ];

  double _seconds(TrainingPlan p) => SessionBuilder(lib).planSeconds(p);
  int _minutes(TrainingPlan p) => (_seconds(p) / 60).round().clamp(1, 90);
  int _count(TrainingPlan p) => p.items.length;

  static String _levelZh(int l) => switch (l) {
    1 => '入门',
    2 => '基础',
    _ => '进阶',
  };

  static bool _isGreeting(String t) =>
      t.length <= 6 && _any(t.toLowerCase(), ['你好', '您好', '在吗', 'hi', 'hello', '嗨', '哈喽', '早上好', '晚上好']);

  static bool _any(String t, List<String> words) => words.any(t.contains);
}

/// "约 12 分钟" (never "0 分钟").
String minutesZhShort(double seconds) {
  final m = (seconds / 60).round();
  return m < 1 ? '不到 1 分钟' : '约 $m 分钟';
}
