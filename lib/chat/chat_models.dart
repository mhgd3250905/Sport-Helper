/// Chat home data: messages, the engine's conversation state and replies.
/// Pure Dart (no Flutter) so the engine can be tested and swapped (rules
/// today, a language model later) behind [ChatEngine].
library;

import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import '../domain/scenario.dart';

enum ChatRole { user, assistant }

/// One finished (or ended) workout, as the chat sees it: what 「上次练了
/// 什么」「这周练了多少」 answer from.
class WorkoutLog {
  const WorkoutLog({
    required this.title,
    required this.at,
    required this.minutes,
    required this.completed,
    required this.total,
  });
  final String title;
  final DateTime at;
  final int minutes;
  final int completed;
  final int total;
  bool get finished => total > 0 && completed >= total;
}

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
    this.question,
    this.questionAnswered = false,
    this.answeredChoices = const [],
    this.plan,
    this.validatedPlan,
    this.actions,
    this.request,
    this.greeting = false,
    this.aiVisible = false,
  });

  final String id;
  final ChatRole role;
  final DateTime at;
  final String text;
  final List<ChatOption> options;

  /// Index of the option the user picked (options lock once answered).
  final int? chosen;

  /// A gate-admitted SDK clarification. It never uses App command options.
  final coach.AskUserQuestion? question;
  final bool questionAnswered;
  final List<String> answeredChoices;

  /// A plan card (assistant only) and the request it was made for.
  final TrainingPlan? plan;
  final coach.ValidatedPlan? validatedPlan;
  final coach.ValidatedActions? actions;
  final ScenarioRequest? request;

  /// The opening line, set as large type in the sky instead of a bubble
  /// (first line = 早上好 / 晚上好…, the rest = the invitation).
  final bool greeting;

  /// Only completed AI turns are eligible for subsequent model history.
  /// Local commands, records and safety answers are never shared implicitly.
  final bool aiVisible;

  bool get isUser => role == ChatRole.user;
  bool get isPlan => plan != null;

  ChatMessage copyWith({
    int? chosen,
    bool? aiVisible,
    bool? questionAnswered,
    List<String>? answeredChoices,
  }) => ChatMessage(
    id: id,
    role: role,
    at: at,
    text: text,
    options: options,
    chosen: chosen ?? this.chosen,
    question: question,
    questionAnswered: questionAnswered ?? this.questionAnswered,
    answeredChoices: answeredChoices ?? this.answeredChoices,
    plan: plan,
    validatedPlan: validatedPlan,
    actions: actions,
    request: request,
    greeting: greeting,
    aiVisible: aiVisible ?? this.aiVisible,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'at': at.toIso8601String(),
    if (text.isNotEmpty) 'text': text,
    if (options.isNotEmpty) 'options': [for (final o in options) o.toJson()],
    'chosen': ?chosen,
    'question': ?question?.toJson(),
    if (questionAnswered) 'questionAnswered': true,
    if (answeredChoices.isNotEmpty) 'answeredChoices': answeredChoices,
    'plan': ?plan?.toJson(),
    if (validatedPlan != null || plan?.source == 'ai') 'isAiPlan': true,
    if (actions != null)
      'actionIds': [for (final item in actions!.items) item.id],
    'request': ?(request == null ? null : requestToJson(request!)),
    if (greeting) 'greeting': true,
    if (aiVisible) 'aiVisible': true,
  };

  factory ChatMessage.fromJson(
    Map<String, dynamic> j, {
    RestorableChatEngine? restoreWith,
  }) {
    final request = j['request'] is Map
        ? requestFromJson(Map<String, dynamic>.from(j['request'] as Map))
        : null;
    var plan = j['plan'] is Map
        ? TrainingPlan.fromJson(Map<String, dynamic>.from(j['plan'] as Map))
        : null;
    coach.ValidatedPlan? validatedPlan;
    if (plan != null && (j['isAiPlan'] == true || plan.source == 'ai')) {
      validatedPlan = restoreWith?.restorePlan(plan, request);
      // Stored AI data is untrusted until the current SDK admits it again.
      if (validatedPlan == null) plan = null;
    }
    final actionIds = j['actionIds'];
    final actions = actionIds is List && actionIds.every((id) => id is String)
        ? restoreWith?.restoreActions(actionIds.cast<String>())
        : null;
    return ChatMessage(
      id: j['id'] as String,
      role: j['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime(2026),
      text: j['text'] as String? ?? '',
      options: [
        for (final o in j['options'] as List? ?? const [])
          ChatOption.fromJson(Map<String, dynamic>.from(o as Map)),
      ],
      chosen: (j['chosen'] as num?)?.toInt(),
      question: j['question'] is Map
          ? coach.AskUserGate.check(jsonEncode(j['question'])).question
          : null,
      questionAnswered: j['questionAnswered'] == true,
      answeredChoices: [
        for (final value in j['answeredChoices'] as List? ?? const [])
          if (value is String) value,
      ],
      greeting: j['greeting'] == true,
      aiVisible: j['aiVisible'] == true,
      plan: plan,
      validatedPlan: validatedPlan,
      actions: actions,
      request: request,
    );
  }
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
    for (final e in j['equipment'] as List? ?? const [])
      Equipment.byName(e as String),
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
  equipment: {for (final e in p.equipment) Equipment.byName(e)}
    ..removeWhere((e) => e == Equipment.none),
  minutes: p.targetMinutes,
  level: p.level,
  avoid: p.avoid,
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

  factory Slots.fromRequest(ScenarioRequest request) => Slots(
    goal: request.goal,
    scene: request.scene,
    minutes: request.minutes,
    equipment: request.equipment,
    level: request.level,
    avoid: request.avoid,
    description: request.description,
  );

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
        : (o.equipment!.isEmpty
              ? <Equipment>{}
              : {...?equipment, ...o.equipment!}),
    level: o.level ?? level,
    avoid: {...avoid, ...o.avoid},
    focus: {...focus, ...o.focus},
    description: [
      description,
      o.description,
    ].where((d) => d.isNotEmpty).join('，'),
  );

  Slots copyWith({String? goal, int? minutes, Set<Equipment>? equipment}) =>
      Slots(
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
    minutes:
        minutes ??
        switch (goal) {
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
    this.coachContext,
    this.recentMessages = const [],
    this.asked = const [],
    this.plan,
    this.request,
    this.safetyBlocked = false,
    this.saved = const [],
    this.lastPlan,
    this.history = const [],
    this.appearance = 'system',
    this.systemLight = false,
    this.now,
  });

  /// A plan request still waiting for an answer to a follow-up question.
  final Slots? pending;

  /// Explicit constraints and recent chat for the SDK; workout logs stay local.
  final Slots? coachContext;
  final List<ChatMessage> recentMessages;

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

  /// Workouts, newest first.
  final List<WorkoutLog> history;

  /// 'dark' / 'light' / 'system' (what 「换浅色」 changes).
  final String appearance;

  /// The platform is light right now (what 'system' resolves to).
  final bool systemLight;

  /// The light theme is in effect (chooses 「换深色」 vs 「换浅色」).
  bool get looksLight =>
      appearance == 'light' || (appearance == 'system' && systemLight);

  /// The clock for 「这周」 (null = now).
  final DateTime? now;

  ChatState copyWith({
    Slots? pending,
    Slots? coachContext,
    List<ChatMessage>? recentMessages,
    bool clearPending = false,
    List<String>? asked,
    TrainingPlan? plan,
    ScenarioRequest? request,
    bool? safetyBlocked,
    List<SavedPlan>? saved,
    TrainingPlan? lastPlan,
    List<WorkoutLog>? history,
    String? appearance,
    bool? systemLight,
    DateTime? now,
  }) => ChatState(
    pending: clearPending ? null : (pending ?? this.pending),
    coachContext: coachContext ?? this.coachContext,
    recentMessages: recentMessages ?? this.recentMessages,
    asked: clearPending ? const [] : (asked ?? this.asked),
    plan: plan ?? this.plan,
    request: request ?? this.request,
    safetyBlocked: safetyBlocked ?? this.safetyBlocked,
    saved: saved ?? this.saved,
    lastPlan: lastPlan ?? this.lastPlan,
    history: history ?? this.history,
    appearance: appearance ?? this.appearance,
    systemLight: systemLight ?? this.systemLight,
    now: now ?? this.now,
  );
}

/// One assistant bubble the engine wants to show (ids and times are added
/// by the controller).
class BotMessage {
  const BotMessage(
    this.text, {
    this.options = const [],
    this.question,
    this.plan,
    this.validatedPlan,
    this.actions,
    this.request,
    this.greeting = false,
  });
  final bool greeting;
  final String text;
  final List<ChatOption> options;
  final coach.AskUserQuestion? question;
  final TrainingPlan? plan;
  final coach.ValidatedPlan? validatedPlan;
  final coach.ValidatedActions? actions;
  final ScenarioRequest? request;
}

class ChatReply {
  const ChatReply({
    required this.messages,
    required this.state,
    this.suggestions = const [],
    this.action,
    this.aiTurn = false,
    this.inputAccepted = true,
  });

  final List<BotMessage> messages;
  final ChatState state;

  /// Quick replies for the chips above the input (empty = app defaults).
  final List<String> suggestions;

  /// A command for the app to run after showing the reply (`@library`…).
  final String? action;
  final bool aiTurn;

  /// False when the engine did not consume this input (for example, an
  /// overlong answer). Keep a live clarification available for a valid retry.
  final bool inputAccepted;
}

/// Turns what the user typed into assistant replies. [RuleChatEngine] is
/// the offline implementation; a model-backed engine (with the same plan
/// validation) plugs in here later.
abstract interface class ChatEngine {
  String get id;
  Future<ChatReply> reply(String text, ChatState state);
}

/// Explicit actions from App navigation stay local even while the SDK is
/// awaiting an answer. Model-generated answer text never uses this boundary.
abstract interface class AppCommandChatEngine implements ChatEngine {
  Future<ChatReply> replyAppCommand(String command, ChatState state);
}

/// Correlates UI and engine metadata without sharing conversation payloads.
abstract interface class DiagnosticChatEngine implements ChatEngine {
  set diagnosticOperation(String? operation);
}

/// Engines with an in-flight request owned by the home conversation.
abstract interface class ManagedChatEngine implements ChatEngine {
  void cancelPending();
  void reset();
  void dispose();
}

/// Typed SDK progress only; intermediate model output never enters the UI.
abstract interface class ProgressChatEngine implements ChatEngine {
  Stream<coach.AgentEvent> get events;
}

/// Re-admits stored card IDs/plans through the current SDK and profile.
abstract interface class RestorableChatEngine implements ChatEngine {
  coach.ValidatedActions? restoreActions(List<String> ids);
  coach.ValidatedPlan? restorePlan(TrainingPlan plan, ScenarioRequest? request);
}
