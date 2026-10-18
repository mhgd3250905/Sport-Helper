/// What the user asked for: picked on the scenario page and/or parsed from a
/// one-line description.
library;

import 'exercise.dart';

class ScenarioRequest {
  const ScenarioRequest({
    this.description = '',
    this.goal,
    this.scene = 'home',
    this.equipment = const {},
    this.minutes = 10,
    this.level = 1,
    this.avoid = const {},
    this.templateId,
  });

  final String description;

  /// null = let the description / matcher decide.
  final String? goal;

  /// 'home' | 'office'
  final String scene;

  /// Extra equipment the user has (band, dumbbell). Mat / chair / wall /
  /// block are assumed per scene (see [availableEquipment]).
  final Set<Equipment> equipment;
  final int minutes;

  /// 1 入门 2 基础 3 进阶
  final int level;

  /// Body parts to protect: 膝 腰 肩 手腕.
  final Set<String> avoid;

  /// Start from this template directly (the template list on Home).
  final String? templateId;

  Set<Equipment> get availableEquipment => {
    Equipment.none,
    Equipment.chair,
    Equipment.wall,
    if (scene == 'home') ...{Equipment.mat, Equipment.block},
    ...equipment,
  };

  ScenarioRequest copyWith({
    String? description,
    String? goal,
    bool clearGoal = false,
    String? scene,
    Set<Equipment>? equipment,
    int? minutes,
    int? level,
    Set<String>? avoid,
    String? templateId,
  }) => ScenarioRequest(
    description: description ?? this.description,
    goal: clearGoal ? null : (goal ?? this.goal),
    scene: scene ?? this.scene,
    equipment: equipment ?? this.equipment,
    minutes: minutes ?? this.minutes,
    level: level ?? this.level,
    avoid: avoid ?? this.avoid,
    templateId: templateId ?? this.templateId,
  );

  @override
  String toString() =>
      'ScenarioRequest(goal: $goal, scene: $scene, eq: ${equipment.map((e) => e.name)}, '
      '$minutes min, L$level, avoid: $avoid, "$description")';
}

/// Rule-based "描述 → 场景" placeholder for the future AI generator: pulls
/// scene, minutes, equipment, level, goal and body parts to avoid out of a
/// Chinese sentence. Explicit picks on the page win over what it finds.
class DescriptionMatcher {
  const DescriptionMatcher();

  static const _goalWords = <String, List<String>>{
    'relax': ['放松', '睡前', '失眠', '助眠', '舒缓', '肩颈', '颈椎', '僵硬'],
    'mobility': ['开胯', '髋', '胯', '柔韧', '一字马', '劈叉', '灵活', '晨起', '早上', '起床'],
    'strength': ['力量', '增肌', '塑形', '臀', '腿', '哑铃', '弹力带', '体态', '圆肩', '驼背'],
    'core': ['核心', '腹', '马甲线', '腰腹', '平板', '小肚子'],
    'fullbody': ['全身', '激活', '提神', '犯困', '减脂', '燃脂'],
    'warmup': ['热身', '运动前', '跑步前', '打球前'],
    'cooldown': ['运动后', '跑步后', '拉伸', '酸痛', '冷身'],
  };

  ScenarioRequest apply(String text, ScenarioRequest base) {
    final t = text.trim();
    if (t.isEmpty) return base;
    var r = base.copyWith(description: t);

    if (_any(t, ['办公室', '工位', '上班', '公司', '办公', '午休'])) {
      r = r.copyWith(scene: 'office');
    } else if (_any(t, ['在家', '家里', '居家', '卧室', '客厅', '床'])) {
      r = r.copyWith(scene: 'home');
    }

    final m = RegExp(r'(\d{1,2})\s*(分钟|min|分)').firstMatch(t);
    if (m != null) {
      r = r.copyWith(minutes: int.parse(m.group(1)!).clamp(5, 45));
    } else if (_any(t, ['半小时'])) {
      r = r.copyWith(minutes: 30);
    } else if (_any(t, ['一刻钟'])) {
      r = r.copyWith(minutes: 15);
    }

    final eq = {...r.equipment};
    if (_any(t, ['哑铃'])) eq.add(Equipment.dumbbell);
    if (_any(t, ['弹力带', '拉力带', '阻力带'])) eq.add(Equipment.band);
    if (_any(t, ['徒手', '没有器械', '无器械', '不用器械'])) {
      eq
        ..remove(Equipment.dumbbell)
        ..remove(Equipment.band);
    }
    r = r.copyWith(equipment: eq);

    if (_any(t, ['新手', '入门', '小白', '零基础', '很久没', '第一次'])) {
      r = r.copyWith(level: 1);
    } else if (_any(t, ['进阶', '高强度', '有基础', '老手', '挑战'])) {
      r = r.copyWith(level: 3);
    } else if (_any(t, ['基础', '偶尔练'])) {
      r = r.copyWith(level: 2);
    }

    final avoid = {...r.avoid};
    for (final part in ['膝', '腰', '肩', '手腕']) {
      if (RegExp('$part[^，。,\\s]{0,3}(疼|痛|伤|不好|不舒服|受伤)').hasMatch(t) ||
          RegExp('(保护|护)$part').hasMatch(t)) {
        avoid.add(part);
      }
    }
    r = r.copyWith(avoid: avoid);

    if (base.goal == null) {
      final g = detectGoal(t);
      if (g != null) r = r.copyWith(goal: g);
    }
    return r;
  }

  /// The goal whose words appear most (first listed wins ties).
  String? detectGoal(String t) {
    String? best;
    var bestHits = 0;
    for (final e in _goalWords.entries) {
      final hits = e.value.where(t.contains).length;
      if (hits > bestHits) {
        best = e.key;
        bestHits = hits;
      }
    }
    return best;
  }

  static bool _any(String t, List<String> words) => words.any(t.contains);
}
