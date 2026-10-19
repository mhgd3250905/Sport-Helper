/// Keyword / slot parsing for the rule-based chat: what the user wants
/// (goal, scene, gear, minutes, level, body parts) and what they want done
/// to the current plan (shorter, harder, swap the 3rd move…).
library;

import '../domain/exercise.dart';
import '../domain/scenario.dart';
import '../domain/template.dart';
import 'chat_models.dart';

enum EditKind { shorter, longer, easier, harder, replace, minutes, another }

class PlanEdit {
  const PlanEdit(this.kind, {this.index, this.name, this.minutes});
  final EditKind kind;

  /// 1-based position for [EditKind.replace] (null = ask which one).
  final int? index;

  /// Exercise name the user mentioned instead of a position.
  final String? name;
  final int? minutes;

  @override
  String toString() => 'PlanEdit($kind, #$index, $name, $minutes)';
}

class SlotParser {
  const SlotParser();

  static const _matcher = DescriptionMatcher();

  /// Body-part words → the goal they suggest when nothing else does.
  static const focusGoals = <String, String>{
    '肩颈': 'relax',
    '颈椎': 'relax',
    '脖子': 'relax',
    '后背': 'strength',
    '背': 'strength',
    '腰': 'relax',
    '核心': 'core',
    '腹': 'core',
    '马甲线': 'core',
    '臀': 'strength',
    '腿': 'strength',
    '手臂': 'strength',
    '胳膊': 'strength',
    '胸': 'strength',
    '肩': 'strength',
    '髋': 'mobility',
    '胯': 'mobility',
    '全身': 'fullbody',
  };

  static const _extraGoals = <String, String>{
    '减肥': 'fullbody',
    '瘦': 'fullbody',
    '出汗': 'fullbody',
    '有氧': 'fullbody',
    '活动一下': 'fullbody',
  };

  static const _trainWords = [
    '练', '训练', '运动', '健身', '锻炼', '动一动', '动动', '活动', '计划',
    '拉伸', '放松', '热身', '燃脂', '减脂', '减肥', '塑形', '开胯', '一套',
  ];

  /// Words that say "nothing / bare hands" when we asked about gear.
  static const _noGear = ['徒手', '没有器械', '无器械', '不用器械', '没器械', '空手', '什么都没有'];

  /// [asked] is the slot we just asked about, so short answers ("10",
  /// "没有", "都有") fill it.
  Slots parse(String text, {String? asked}) {
    final t = text.trim();
    if (t.isEmpty) return const Slots();

    String? scene;
    if (_any(t, ['办公室', '工位', '上班', '公司', '办公', '午休', '单位'])) {
      scene = 'office';
    } else if (_any(t, ['在家', '家里', '居家', '卧室', '客厅', '床上', '宿舍', '酒店'])) {
      scene = 'home';
    }

    var minutes = parseMinutes(t);
    if (minutes == null && asked == 'minutes') {
      final n = int.tryParse(RegExp(r'^\s*(\d{1,3})\s*$').firstMatch(t)?.group(1) ?? '') ??
          _cnNumber(t.replaceAll(RegExp(r'[吧啊呀的个\s]'), ''));
      if (n != null && n > 0) minutes = n.clamp(5, 45);
    }

    Set<Equipment>? eq;
    final band = _any(t, ['弹力带', '拉力带', '阻力带']);
    final db = _any(t, ['哑铃']);
    if (_any(t, _noGear)) {
      eq = {};
    } else if (band || db) {
      eq = {if (band) Equipment.band, if (db) Equipment.dumbbell};
    } else if (asked == 'equipment') {
      if (_any(t, ['都有', '两个都', '都行'])) {
        eq = {Equipment.band, Equipment.dumbbell};
      } else if (_any(t, ['没有', '没', '不用', '无', '就行'])) {
        eq = {};
      }
    }

    int? level;
    if (_any(t, ['新手', '入门', '小白', '零基础', '很久没', '第一次'])) {
      level = 1;
    } else if (_any(t, ['进阶', '高强度', '有基础', '老手', '挑战'])) {
      level = 3;
    } else if (_any(t, ['偶尔练', '基础'])) {
      level = 2;
    }

    final avoid = _matcher.apply(t, const ScenarioRequest()).avoid;

    final focus = <String>{};
    for (final f in focusGoals.keys) {
      if (t.contains(f) && !avoid.any(f.contains)) focus.add(f);
    }
    // "肩颈" already covers "肩"; "腰" alone is a body part to protect more
    // often than a goal, so only count it when nothing hurts there.
    if (focus.contains('肩颈')) focus.remove('肩');

    // Gear alone ("有哑铃") is an answer about equipment, not a goal.
    final tg = t.replaceAll(RegExp('哑铃|弹力带|拉力带|阻力带'), '');
    String? goal;
    for (final g in goalLabels.entries) {
      if (tg.contains(g.value)) goal = g.key;
    }
    goal ??= _matcher.detectGoal(tg);
    if (goal == null) {
      for (final e in _extraGoals.entries) {
        if (tg.contains(e.key)) goal = e.value;
      }
    }
    if (goal == null && focus.isNotEmpty) goal = focusGoals[focus.first];

    return Slots(
      goal: goal,
      scene: scene,
      minutes: minutes,
      equipment: eq,
      level: level,
      avoid: avoid,
      focus: focus,
      description: t,
    );
  }

  /// "10 分钟", "十五分钟", "半小时", "一刻钟", "1 小时" (clamped 5–45).
  int? parseMinutes(String t) {
    final m = RegExp(r'(\d{1,3})\s*(分钟|min|分)').firstMatch(t);
    if (m != null) return int.parse(m.group(1)!).clamp(5, 45);
    final cn = RegExp(r'([一二两三四五六七八九十]{1,3})\s*分钟').firstMatch(t);
    if (cn != null) return _cnNumber(cn.group(1)!)?.clamp(5, 45);
    if (t.contains('半小时') || t.contains('半个小时')) return 30;
    if (t.contains('一刻钟')) return 15;
    if (RegExp(r'(1|一|一个)\s*(个)?小时').hasMatch(t)) return 45;
    return null;
  }

  bool wantsTraining(String t) => _any(t, _trainWords);

  /// What the user wants changed on the current plan, if anything.
  PlanEdit? parseEdit(String text, List<String> planNames) {
    final t = text.trim();
    final idx = RegExp(r'第\s*(\d{1,2}|[一二两三四五六七八九十]{1,3})\s*个').firstMatch(t);
    final swapWord = _any(t, ['换', '替', '不想做', '不要', '不做', '去掉', '删掉', '做不了', '不会做']);
    if (idx != null && swapWord) {
      final g = idx.group(1)!;
      return PlanEdit(EditKind.replace, index: int.tryParse(g) ?? _cnNumber(g));
    }
    if (swapWord) {
      for (final n in planNames) {
        if (n.length >= 2 && t.contains(n)) return PlanEdit(EditKind.replace, name: n);
      }
    }
    if (_any(t, ['换一套', '换套', '换个计划', '换一个计划', '换一个方案', '重新排', '再来一套', '换个别的', '不喜欢这套'])) {
      return const PlanEdit(EditKind.another);
    }
    if (_any(t, ['换一个', '换个动作', '换动作', '替换一个'])) {
      return const PlanEdit(EditKind.replace);
    }
    if (_any(t, ['太简单', '太轻松', '太容易'])) return const PlanEdit(EditKind.harder);
    if (_any(t, ['太难', '太累', '难了', '吃力', '做不动'])) return const PlanEdit(EditKind.easier);
    if (_any(t, ['难一点', '难点', '再难', '加难', '更难', '强度大', '强度高', '加强度', '提高难度', '高强度一点'])) {
      return const PlanEdit(EditKind.harder);
    }
    if (_any(t, ['简单', '轻松一点', '轻松点', '容易', '降低难度', '轻一点', '强度低', '低强度'])) {
      return const PlanEdit(EditKind.easier);
    }
    if (_any(t, ['短一点', '短点', '再短', '少一点', '少点', '时间短', '没那么多时间', '快一点', '缩短', '精简'])) {
      return const PlanEdit(EditKind.shorter);
    }
    if (_any(t, ['长一点', '长点', '再长', '多一点', '多练', '久一点', '加长', '延长', '再加点', '加点'])) {
      return const PlanEdit(EditKind.longer);
    }
    final m = parseMinutes(t);
    if (m != null && _any(t, ['改', '换成', '变成', '调', '只有', '就', '缩到', '加到', '控制在'])) {
      return PlanEdit(EditKind.minutes, minutes: m);
    }
    return null;
  }

  /// 一 … 九十九 (两 = 2).
  static int? _cnNumber(String s) {
    const d = {'一': 1, '二': 2, '两': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9};
    if (s.isEmpty) return null;
    if (s == '十') return 10;
    final i = s.indexOf('十');
    if (i < 0) return s.length == 1 ? d[s] : null;
    final tens = i == 0 ? 1 : d[s.substring(0, i)];
    final rest = s.substring(i + 1);
    final ones = rest.isEmpty ? 0 : d[rest];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }

  static bool _any(String t, List<String> words) => words.any(t.contains);
}
