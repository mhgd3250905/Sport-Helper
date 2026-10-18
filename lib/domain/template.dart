import 'plan.dart';

/// A fixed training template (assets/library/templates.json).
class PlanTemplate {
  const PlanTemplate({
    required this.id,
    required this.name,
    required this.summary,
    required this.goal,
    required this.scenes,
    required this.equipment,
    required this.minutes,
    required this.minLevel,
    required this.maxLevel,
    required this.keywords,
    required this.blocks,
  });

  final String id;
  final String name;
  final String summary;

  /// relax | mobility | strength | core | fullbody | warmup | cooldown
  final String goal;
  final List<String> scenes;

  /// Equipment the template needs beyond what every home has.
  final List<String> equipment;
  final int minutes;
  final int minLevel;
  final int maxLevel;
  final List<String> keywords;
  final List<PlanBlock> blocks;

  factory PlanTemplate.fromJson(Map<String, dynamic> j) {
    final level = List<int>.from(
      (j['level'] as List? ?? const [1, 3]).map((e) => (e as num).toInt()),
    );
    return PlanTemplate(
      id: j['id'] as String,
      name: j['name'] as String,
      summary: j['summary'] as String? ?? '',
      goal: j['goal'] as String,
      scenes: List<String>.from(j['scenes'] as List),
      equipment: List<String>.from(j['equipment'] as List? ?? const []),
      minutes: (j['minutes'] as num).toInt(),
      minLevel: level.first,
      maxLevel: level.last,
      keywords: List<String>.from(j['keywords'] as List? ?? const []),
      blocks: [
        for (final b in j['blocks'] as List)
          PlanBlock.fromJson(Map<String, dynamic>.from(b as Map)),
      ],
    );
  }
}

class TemplateCatalog {
  TemplateCatalog(this.templates);
  final List<PlanTemplate> templates;

  PlanTemplate? byId(String id) =>
      templates.where((t) => t.id == id).firstOrNull;

  factory TemplateCatalog.fromJson(Map<String, dynamic> j) => TemplateCatalog([
    for (final t in j['templates'] as List)
      PlanTemplate.fromJson(Map<String, dynamic>.from(t as Map)),
  ]);
}

/// Goals shown on the scenario page, in order.
const goalLabels = {
  'relax': '放松拉伸',
  'mobility': '灵活开胯',
  'strength': '力量塑形',
  'core': '核心腰腹',
  'fullbody': '全身激活',
  'warmup': '运动前热身',
  'cooldown': '运动后拉伸',
};
