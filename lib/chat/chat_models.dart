/// Chat home data: messages, the engine's conversation state and replies.
/// Pure Dart (no Flutter) so the engine can be tested and swapped (rules
/// today, a language model later) behind [ChatEngine].
library;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import '../domain/scenario.dart';

enum ChatRole { user, assistant }

/// A tappable answer inside an assistant bubble. Tapping sends [value] as
/// the user's message (shown as [label]); values starting with `@` are
/// commands handled by the app (`@drawer`, `@library`, `@saved:<id>`…).
class ChatOption {
  const ChatOption(this.label, [String? value]) : value = value ?? label;
  final String label;
  final String value;

  bool get isCommand => value.startsWith('@');

  Map<String, Object?> toJson() => {'label': label, 'value': value};
  factory ChatOption.fromJson(Map<String, dynamic> j) =>
      ChatOption(j['label'] as String? ?? '', j['value'] as String?);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.at,
    this.text = '',
    this.options = const [],
    this.chosen,
    this.plan,
    this.request,
  });

  final String id;
  final ChatRole role;
  final DateTime at;
  final String text;
  final List<ChatOption> options;

  /// Index of the option the user picked (options lock once answered).
  final int? chosen;

  /// A plan card (assistant only) and the request it was made for.
  final TrainingPlan? plan;
  final ScenarioRequest? request;

  bool get isUser => role == ChatRole.user;
  bool get isPlan => plan != null;

  ChatMessage copyWith({int? chosen}) => ChatMessage(
    id: id,
    role: role,
    at: at,
    text: text,
    options: options,
    chosen: chosen ?? this.chosen,
    plan: plan,
    request: request,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'at': at.toIso8601String(),
    if (text.isNotEmpty) 'text': text,
    if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
    'chosen': ?chosen,
    'plan': ?plan?.toJson(),
    'request': ?(request == null ? null : requestToJson(request!)),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    role: j['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
    text: j['text'] as String? ?? '',
    options: [
      for (final o in j['options'] as List? ?? const [])
        ChatOption.fromJson(Map<String, dynamic>.from(o as Map)),
    ],
    chosen: (j['chosen'] as num?)?.toInt(),
    plan: j['plan'] is Map
        ? TrainingPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map))
        : null,
    request: j['request'] is Map
        ? requestFromJson(Map<String, dynamic>.from(j['request'] as Map))
        : null,
  );
}

Map<String, Object?> requestToJson(ScenarioRequest r) => {
  'description': r.description,
  'goal': ?r.goal,
  'scene': r.scene,
  'equipment': [for (final e in r.equipment) e.name],
  'minutes': r.minutes,
  'level': r.level,
  'avoid': [...r.avoid],
  'templateId': ?r.templateId,
};

ScenarioRequest requestFromJson(Map<String, dynamic> j) => ScenarioRequest(
  description: j['description'] as String? ?? '',
  goal: j['goal'] as String?,
  scene: j['scene'] as String? ?? 'home',
  equipment: {
    for (final e in j['equipment'] as List? ?? const []) Equipment.byName(e as String),
  },
  minutes: (j['minutes'] as num?)?.toInt() ?? 10,
  level: (j['level'] as num?)?.toInt() ?? 1,
  avoid: {for (final a in j['avoid'] as List? ?? const []) a as String},
  templateId: j['templateId'] as String?,
);

/// The request rebuilt from a plan (saved plans and old cards).
ScenarioRequest requestForPlan(TrainingPlan p) => ScenarioRequest(
  goal: p.goal,
  scene: p.scene,
  equipment: {
    for (final e in p.equipment) Equipment.byName(e),
  }..removeWhere((e) => e == Equipment.none),
  minutes: p.targetMinutes,
  level: p.level,
  templateId: p.templateId,
);

/// What the user has told us so far for one plan request. Null = not said.
class Slots {
  const Slots({
    this.goal,
    this.scene,
    this.minutes,
    this.equipment,
    this.level,
    this.avoid = const {},
    this.focus = const {},
    this.description = '',
  });

  final String? goal;
  final String? scene;
  final int? minutes;

  /// Extra gear: {} = "徒手" said explicitly, null = not mentioned.
  final Set<Equipment>? equipment;
  final int? level;
  final Set<String> avoid;

  /// Body parts the user wants to train (肩颈, 核心, 臀腿…).
  final Set<String> focus;
  final String description;

  bool get isEmpty =>
      goal == null &&
      scene == null &&
      minutes == null &&
      equipment == null &&
      level == null &&
      avoid.isEmpty &&
      focus.isEmpty;

  /// [o] is newer: its said values win, sets add up.
  Slots merge(Slots o) => Slots(
    goal: o.goal ?? goal,
    scene: o.scene ?? scene,
    minutes: o.minutes ?? minutes,
    equipment: o.equipment == null
        ? equipment
        : (o.equipment!.isEmpty ? <Equipment>{} : {...?equipment, ...o.equipment!}),
    level: o.level ?? level,
    avoid: {...avoid, ...o.avoid},
    focus: {...focus, ...o.focus},
    description: [description, o.description].where((d) => d.isNotEmpty).join('，'),
  );

  Slots copyWith({String? goal, int? minutes, Set<Equipment>? equipment}) => Slots(
    goal: goal ?? this.goal,
    scene: scene,
    minutes: minutes ?? this.minutes,
    equipment: equipment ?? this.equipment,
    level: level,
    avoid: avoid,
    focus: focus,
    description: description,
  );

  ScenarioRequest toRequest({String? fallbackGoal}) => ScenarioRequest(
    description: description,
    goal: goal ?? fallbackGoal,
    scene: scene ?? 'home',
    equipment: equipment ?? const {},
    minutes: minutes ?? switch (goal) {
      'warmup' => 6,
      'cooldown' => 8,
      _ => 10,
    },
    level: level ?? 1,
    avoid: avoid,
  );

  @override
  String toString() =>
      'Slots(goal: $goal, scene: $scene, min: $minutes, eq: ${equipment?.map((e) => e.name)}, '
      'L$level, avoid: $avoid, focus: $focus)';
}

/// The engine's memory of the conversation, owned by the controller and
/// handed back with every reply.
class ChatState {
  const ChatState({
    this.pending,
    this.asked = const [],
    this.plan,
    this.request,
    this.safetyBlocked = false,
    this.saved = const [],
    this.lastPlan,
  });

  /// A plan request still waiting for an answer to a follow-up question.
  final Slots? pending;

  /// Slots already asked about for [pending] ('goal', 'minutes', 'equipment').
  final List<String> asked;

  /// The plan on the latest card and its request: what edits apply to.
  final TrainingPlan? plan;
  final ScenarioRequest? request;

  /// Any "是" in the safety check: no generated plans.
  final bool safetyBlocked;

  /// The user's saved plans (newest first) and the last plan they started.
  final List<SavedPlan> saved;
  final TrainingPlan? lastPlan;

  ChatState copyWith({
    Slots? pending,
    bool clearPending = false,
    List<String>? asked,
    TrainingPlan? plan,
    ScenarioRequest? request,
    bool? safetyBlocked,
    List<SavedPlan>? saved,
    TrainingPlan? lastPlan,
  }) => ChatState(
    pending: clearPending ? null : (pending ?? this.pending),
    asked: clearPending ? const [] : (asked ?? this.asked),
    plan: plan ?? this.plan,
    request: request ?? this.request,
    safetyBlocked: safetyBlocked ?? this.safetyBlocked,
    saved: saved ?? this.saved,
    lastPlan: lastPlan ?? this.lastPlan,
  );
}

/// One assistant bubble the engine wants to show (ids and times are added
/// by the controller).
class BotMessage {
  const BotMessage(this.text, {this.options = const [], this.plan, this.request});
  final String text;
  final List<ChatOption> options;
  final TrainingPlan? plan;
  final ScenarioRequest? request;
}

class ChatReply {
  const ChatReply({
    required this.messages,
    required this.state,
    this.suggestions = const [],
    this.action,
  });

  final List<BotMessage> messages;
  final ChatState state;

  /// Quick replies for the chips above the input (empty = app defaults).
  final List<String> suggestions;

  /// A command for the app to run after showing the reply (`@library`…).
  final String? action;
}

/// Turns what the user typed into assistant replies. [RuleChatEngine] is
/// the offline implementation; a model-backed engine (with the same plan
/// validation) plugs in here later.
abstract interface class ChatEngine {
  String get id;
  Future<ChatReply> reply(String text, ChatState state);
}
