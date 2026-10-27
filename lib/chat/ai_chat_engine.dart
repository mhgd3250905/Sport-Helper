import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../diagnostics/runtime_log.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_generator.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import '../domain/template.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart';
import 'slot_parser.dart';

/// One SDK session for the app lifetime. Only admitted results cross into UI.
class AiChatEngine
    implements
        ManagedChatEngine,
        AppCommandChatEngine,
        RestorableChatEngine,
        ProgressChatEngine,
        DiagnosticChatEngine,
        ConversationChatEngine {
  AiChatEngine({
    required this.local,
    required this.catalog,
    required this.profile,
    required this.client,
    this.memoryStore,
    bool enableUserMemory = true,
    // Agent owns its 360-second total budget, retries and request timeouts.
    // This outer guard leaves time for its admitted local fallback to finish.
    this.turnTimeout = const Duration(seconds: 390),
  }) : _initialMemoryEnabled = enableUserMemory;

  final RuleChatEngine local;
  final coach.Catalog catalog;
  final coach.CoachProfile profile;
  final coach.LlmClient client;
  final Duration turnTimeout;
  final coach.UserMemoryStore? memoryStore;
  final bool _initialMemoryEnabled;
  final usage = coach.MemoryUsageSink();
  final _random = Random.secure();
  coach.CoachTurnResult? lastResult;
  coach.TurnOutcome? lastOutcome;
  coach.FallbackReason? lastFallbackReason;
  _Turn? _pending;
  bool _disposed = false;
  String? _diagnosticOperation;

  @override
  set diagnosticOperation(String? operation) =>
      _diagnosticOperation = operation;

  late final agent = coach.CoachAgent(
    client: _CancellableClient(client, () => _pending),
    catalog: () => catalog,
    profile: profile,
    maxResubmits: 2,
    usage: usage,
    memoryStore: memoryStore,
    enableUserMemory: _initialMemoryEnabled,
    extraRules: [
      (plan, _, context) {
        final mapped = TrainingPlan.fromJson(plan.toJson());
        final request = requestForPlan(mapped).copyWith(
          scene: context.scene,
          equipment: context.equipment?.map(Equipment.byName).toSet(),
          avoid: context.avoid,
        );
        return [
          for (final issue in PlanValidator(
            local.lib,
          ).validate(mapped, request))
            coach.PlanIssue('smartfit_plan', issue),
        ];
      },
    ],
    fallback: (request) async {
      final turn = _pending;
      if (turn == null || turn.cancel.isCancelled) {
        return const coach.SessionFallbackReply('');
      }
      final reply = await _localFallback(turn);
      turn.fallbackReply = reply;
      final plan = reply.messages
          .where((m) => m.plan != null)
          .firstOrNull
          ?.plan;
      return coach.SessionFallbackReply(
        reply.messages.map((m) => m.text).where((s) => s.isNotEmpty).join('\n'),
        plan: plan == null
            ? null
            : const coach.PlanCodec().decode(plan.toJson()),
      );
    },
  );

  @override
  late final conversation = coach.CoachConversationController(agent: agent);

  /// Transitional alias for diagnostics and existing App integrations.
  coach.CoachAgent get session => agent;

  @override
  Stream<coach.AgentEvent> get events => agent.events;

  bool get enableUserMemory => agent.enableUserMemory;
  set enableUserMemory(bool value) => agent.enableUserMemory = value;

  Future<void> clearMemory() async {
    await agent.clearMemory();
    // The SDK awaits durable storage and throws on failure. Also verify the
    // App storage boundary before confirming removal to the user.
    if ((await agent.memoryStore.load()).isNotEmpty) {
      throw StateError('AI memory could not be cleared from local storage');
    }
  }

  @override
  String get id => 'ugk_coach:smartfit:agent';

  @override
  void cancelPending() {
    // The controller may still be in its presentation delay after send has
    // returned. A discarded question must not keep the next send in answer mode.
    conversation.cancel();
    final turn = _pending;
    if (turn == null) return;
    lastOutcome = coach.TurnOutcome.cancelled;
    lastFallbackReason = null;
    RuntimeLog.instance.record(
      'ai.turn.cancel',
      operation: turn.operation,
      fields: {'elapsedMs': turn.watch.elapsedMilliseconds},
    );
    turn.cancel.cancel();
    _pending = null;
  }

  @override
  void reset() {
    cancelPending();
    conversation.newConversation();
    lastResult = null;
    lastOutcome = null;
    lastFallbackReason = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    unawaited(conversation.dispose());
    if (client is coach.OpenAiCompatibleClient) {
      (client as coach.OpenAiCompatibleClient).close();
    }
  }

  @override
  coach.ValidatedActions? restoreActions(List<String> ids) =>
      session.gateFor(catalog).check('', [
        coach.LlmToolCall(
          id: 'stored-actions',
          name: coach.CoachTools.showActions,
          arguments: jsonEncode({
            'items': [
              for (final id in ids) {'actionId': id},
            ],
          }),
        ),
      ]).actions;

  @override
  coach.ValidatedPlan? restorePlan(
    TrainingPlan plan,
    ScenarioRequest? request,
  ) => session
      .gateFor(catalog)
      .admitTemplate(
        const coach.PlanCodec().decode(plan.toJson()),
        request == null
            ? const coach.CoachContext()
            : coach.CoachContext(
                scene: request.scene,
                equipment: request.equipment.map((e) => e.name).toSet(),
                minutes: request.minutes,
                level: request.level,
                avoid: request.avoid,
              ),
      );

  @override
  Future<ChatReply> reply(String input, ChatState state) =>
      _reply(input, state);

  @override
  Future<ChatReply> replyAppCommand(String command, ChatState state) =>
      _reply(command, state, trustedAppCommand: true);

  @override
  Future<ChatReply> replyAnswer(
    String questionId,
    String text,
    ChatState state, {
    List<String>? choices,
    Map<String, List<String>>? formAnswers,
    bool skipQuestion = false,
  }) => _reply(
    text,
    state,
    questionId: questionId,
    choices: choices,
    formAnswers: formAnswers,
    skipQuestion: skipQuestion,
  );

  Future<ChatReply> _reply(
    String input,
    ChatState state, {
    bool trustedAppCommand = false,
    String? questionId,
    List<String>? choices,
    Map<String, List<String>>? formAnswers,
    bool skipQuestion = false,
  }) async {
    final operation =
        _diagnosticOperation ?? RuntimeLog.instance.newOperation('chat');
    _diagnosticOperation = null;
    ChatReply empty() =>
        ChatReply(messages: const [], state: state, inputAccepted: false);
    if (_disposed) {
      RuntimeLog.instance.record(
        'ai.turn.rejected',
        operation: operation,
        fields: const {'reason': 'disposed'},
      );
      return empty();
    }
    if (_pending != null || conversation.state.isWaiting) {
      RuntimeLog.instance.record(
        'ai.turn.rejected',
        operation: operation,
        fields: const {'reason': 'busy'},
      );
      lastResult = const coach.CoachTurnResult(
        turnId: '',
        status: coach.TurnStatus.busy,
      );
      return empty();
    }
    // Diagnostics always describe this accepted turn, including local routes.
    lastResult = null;
    lastOutcome = null;
    lastFallbackReason = null;
    // An answer is an ordinary SDK send in the same task, even when the
    // supplied option text happens to look like a local command or shortcut.
    final rawLocalReply =
        (questionId != null || conversation.state.pendingQuestion != null) &&
            !trustedAppCommand
        ? null
        : local.localReply(input, state);
    // Explicit library navigation stays local. Requests to see/recommend
    // actions belong to the SDK's show_actions tool.
    final opensLibrary = rawLocalReply?.action?.startsWith('@library') ?? false;
    final localReply =
        rawLocalReply == null || (opensLibrary && !input.contains('动作库'))
        ? null
        : _admitLocalCards(rawLocalReply);
    if (localReply != null) {
      conversation.invalidateQuestion();
      RuntimeLog.instance.record(
        'chat.route',
        operation: operation,
        fields: const {'route': 'local', 'reason': 'local_shortcut'},
      );
      final adopted = localReply.state.plan;
      if (adopted != null && adopted.id != state.plan?.id) {
        final request = localReply.state.request ?? requestForPlan(adopted);
        return ChatReply(
          messages: localReply.messages,
          state: localReply.state.copyWith(
            coachContext: Slots.fromRequest(
              request,
            ).merge(Slots(avoid: state.coachContext?.avoid ?? const {})),
          ),
          action: localReply.action,
          suggestions: localReply.suggestions,
        );
      }
      return localReply;
    }
    if (state.safetyBlocked) {
      RuntimeLog.instance.record(
        'chat.route',
        operation: operation,
        fields: const {'route': 'local', 'reason': 'safety'},
      );
      return local.reply(input, state);
    }
    final edit =
        questionId == null && conversation.state.pendingQuestion == null
        ? _editFor(input, state)
        : null;
    final turn = _Turn(
      input,
      state,
      _slotsFor(input, state, edit: edit),
      operation,
      usesCurrentPlan: edit != null,
      currentGoal: _saidSlots(input).goal,
      previousParameters: _previousParameters(state),
    );
    _pending = turn;
    RuntimeLog.instance.record(
      'chat.route',
      operation: operation,
      fields: const {'route': 'sdk'},
    );
    final progress = events.listen((event) {
      if (_pending != turn) return;
      turn.step = event.step;
      RuntimeLog.instance.record(
        'ai.progress',
        operation: operation,
        fields: {
          'kind': event.kind.name,
          'step': event.step,
          if (event.status case final status?) 'status': status.name,
          if (event.reason case final reason?) 'reason': reason.name,
          if (event.kind == coach.AgentEventKind.retrying) ...{
            'attempt': event.attempt,
            'total': event.maxAttempts,
            'durationMs': event.delay?.inMilliseconds ?? 0,
          },
        },
      );
    });
    final timer = Timer(turnTimeout, () {
      RuntimeLog.instance.record(
        'ai.turn.timeout',
        operation: operation,
        fields: {'elapsedMs': turn.watch.elapsedMilliseconds},
      );
      turn.timedOut = true;
      turn.cancel.cancel('turn timeout');
    });
    try {
      final received = questionId == null
          ? await conversation.send(
              input,
              context: turn.context,
              cancel: turn.cancel,
            )
          : skipQuestion
          ? await conversation.skipQuestion(
              questionId,
              context: turn.context,
              cancel: turn.cancel,
            )
          : formAnswers != null
          ? await conversation.answerForm(
              questionId,
              formAnswers,
              context: turn.context,
              cancel: turn.cancel,
            )
          : choices == null
          ? await conversation.answerText(
              questionId,
              input,
              context: turn.context,
              cancel: turn.cancel,
            )
          : await conversation.answerChoices(
              questionId,
              choices,
              context: turn.context,
              cancel: turn.cancel,
            );
      if (_disposed || _pending != turn) return empty();
      final result =
          received ??
          (turn.timedOut
              ? const coach.CoachTurnResult(
                  turnId: '',
                  status: coach.TurnStatus.cancelled,
                )
              : null);
      if (result == null) return empty();
      if (turn.timedOut) {
        lastResult = coach.CoachTurnResult(
          turnId: result.turnId,
          status: coach.TurnStatus.error,
          isPlanningFailure: true,
          fallbackReason: coach.FallbackReason.timeout,
          error: const coach.AgentRequestFailed(
            coach.AgentFailureKind.turnTimeout,
            errorClass: coach.RequestErrorClass.timeout,
            attempts: 0,
          ),
          records: result.records,
          steps: result.steps,
          reads: result.reads,
          submissions: result.submissions,
        );
      } else {
        lastResult = result;
      }
      final accepted = lastResult!;
      final tokens = accepted.usage;
      RuntimeLog.instance.record(
        'ai.turn.end',
        operation: operation,
        fields: {
          'status': accepted.status.name,
          'route': accepted.status == coach.TurnStatus.ok
              ? 'ai'
              : accepted.status == coach.TurnStatus.fallback
              ? 'fallback'
              : 'sdk',
          if (accepted.fallbackReason case final reason?) 'reason': reason.name,
          if (accepted.error case final error?)
            'errorType': RuntimeLog.errorType(error),
          'elapsedMs': turn.watch.elapsedMilliseconds,
          'steps': accepted.steps,
          'submissions': accepted.submissions,
          'reads': accepted.reads.length,
          'count': accepted.records.length,
          'hasPlan': accepted.plan != null,
          'hasActions': accepted.actions != null,
          'promptTokens': tokens.promptTokens,
          'completionTokens': tokens.completionTokens,
          'reasoningTokens': tokens.reasoningTokens,
        },
      );
      if (accepted.status == coach.TurnStatus.cancelled ||
          accepted.status == coach.TurnStatus.busy) {
        return empty();
      }
      lastFallbackReason = accepted.fallbackReason;
      lastOutcome = switch (accepted.status) {
        coach.TurnStatus.ok =>
          accepted.records.lastOrNull?.turnOutcome ?? coach.TurnOutcome.model,
        coach.TurnStatus.fallback => coach.TurnOutcome.fallback,
        _ => coach.TurnOutcome.error,
      };
      switch (accepted.status) {
        case coach.TurnStatus.limitReached:
          return ChatReply(
            messages: const [BotMessage('这段对话已到上限，请点「新对话」继续。')],
            state: state,
          );
        case coach.TurnStatus.inputTooLong:
          return ChatReply(
            messages: const [BotMessage('请把这一条缩短到 500 字以内再发送。')],
            state: state,
            inputAccepted: false,
          );
        case coach.TurnStatus.error:
          final failure = conversation.state.messages
              .where(
                (message) =>
                    !message.isUser && message.turnId == accepted.turnId,
              )
              .lastOrNull;
          return ChatReply(
            aiTurn: true,
            messages: accepted.isPlanningFailure
                ? [
                    BotMessage(
                      '',
                      isPlanningFailure: true,
                      conversationMessageId: failure?.id,
                    ),
                  ]
                : const [BotMessage('网络不太稳，请稍后重试。')],
            state: state,
          );
        default:
          break;
      }
      final admitted = accepted.plan;
      // Model-provided IDs may repeat. Allocate an App identity only after
      // admission, and obtain a new SDK gate value for the renamed snapshot.
      final validated = admitted == null
          ? null
          : accepted.status == coach.TurnStatus.ok
          ? session
                .gateFor(catalog)
                .admitTemplate(
                  admitted.plan.copyWith(
                    id: 'ai-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x100000000).toRadixString(16)}',
                  ),
                  coach.CoachContext(
                    scene: admitted.plan.scene,
                    equipment: admitted.plan.equipment.toSet(),
                    minutes: admitted.plan.targetMinutes,
                    level: admitted.plan.level,
                    goal: admitted.plan.goal,
                    avoid: turn.slots.avoid,
                  ),
                )
          : admitted;
      final plan = validated == null
          ? null
          : TrainingPlan.fromJson(validated.plan.toJson());
      final request = plan == null
          ? null
          : requestForPlan(plan).copyWith(description: input);
      final fallback = accepted.status == coach.TurnStatus.fallback;
      final output = conversation.state.messages
          .where((m) => !m.isUser && m.turnId == accepted.turnId)
          .lastOrNull;
      // The App assigns a unique ID to every admitted plan. Bind the SDK's
      // matching task snapshot to the re-admitted card's new ID as well.
      final sdkPlanState = output?.planState;
      final planState =
          validated != null &&
              admitted != null &&
              sdkPlanState?.planId == admitted.plan.id
          ? session.planStateFor(validated)
          : null;
      final text = output?.text ?? accepted.text;
      return ChatReply(
        aiTurn: true,
        messages: [
          BotMessage(
            text,
            plan: plan,
            validatedPlan: validated,
            planState: planState,
            actions: accepted.actions,
            question: accepted.question,
            conversationMessageId: output?.id,
            answeredForm: output?.answeredForm ?? const {},
            isPlanningFailure: output?.isPlanningFailure ?? false,
            request: request,
            options: fallback && plan == null
                ? turn.fallbackReply?.messages
                          .expand((m) => m.options)
                          .toList() ??
                      const []
                : const [],
          ),
        ],
        state: state.copyWith(
          coachContext: turn.slots,
          clearPending: plan != null || !fallback,
          pending: fallback && plan == null
              ? turn.fallbackReply?.state.pending
              : null,
          asked: turn.fallbackReply?.state.asked,
          plan: plan,
          request: request,
        ),
        suggestions: plan == null ? const [] : planSuggestions,
      );
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'ai.turn.error',
        operation: operation,
        fields: {
          'errorType': RuntimeLog.errorType(error),
          'elapsedMs': turn.watch.elapsedMilliseconds,
          'reason': turn.timedOut ? 'timeout' : 'error',
          'available': !_disposed && _pending == turn,
        },
      );
      if (_disposed ||
          _pending != turn ||
          (turn.cancel.isCancelled && !turn.timedOut)) {
        return empty();
      }
      lastOutcome = coach.TurnOutcome.error;
      lastFallbackReason = turn.timedOut
          ? coach.FallbackReason.timeout
          : coach.FallbackReason.server;
      return ChatReply(
        aiTurn: true,
        messages: const [BotMessage('', isPlanningFailure: true)],
        state: state,
      );
    } finally {
      timer.cancel();
      unawaited(progress.cancel());
      if (_pending == turn) _pending = null;
    }
  }

  ChatReply _admitLocalCards(ChatReply reply) => ChatReply(
    messages: [
      for (final message in reply.messages)
        if (message.plan?.source != 'ai') message else _admitLocalCard(message),
    ],
    state: reply.state,
    suggestions: reply.suggestions,
    action: reply.action,
  );

  BotMessage _admitLocalCard(BotMessage message) {
    final validated = restorePlan(message.plan!, message.request);
    return BotMessage(
      validated == null ? '这套已存计划未通过当前安全检查，请重新生成。' : message.text,
      plan: validated == null ? null : message.plan,
      validatedPlan: validated,
      request: message.request,
      options: message.options,
      greeting: message.greeting,
    );
  }

  Future<ChatReply> _localFallback(_Turn turn) async {
    RuntimeLog.instance.record(
      'ai.fallback.begin',
      operation: turn.operation,
      fields: {'elapsedMs': turn.watch.elapsedMilliseconds},
    );
    final request = turn.slots
        .toRequest(fallbackGoal: turn.state.plan?.goal)
        .copyWith(description: turn.input);
    final state = turn.state.copyWith(
      coachContext: turn.slots,
      pending: turn.slots,
      request: turn.state.request == null ? null : request,
    );
    // The ordinary local planner assumes common home/office equipment. An AI
    // fallback must instead honor the same explicit equipment facts as the SDK.
    var fallback = local;
    if (turn.slots.equipment case final equipment?) {
      final allowed = equipment.map((e) => e.name).toSet();
      final library = ExerciseLibrary([
        for (final exercise in local.lib.all)
          if (exercise.effectiveEquipmentIds.every(
            (id) => id == 'none' || allowed.contains(id),
          ))
            exercise,
      ]);
      // Old host templates can carry an obsolete unit. Use the SDK default
      // dose only for incompatible entries, before the existing duration fit.
      PlanItem canonicalItem(PlanItem item) {
        final drill = catalog[item.exerciseId];
        if (drill == null || item.mode.name == drill.defaultDose.mode.name) {
          return item;
        }
        final dose = drill.defaultDose;
        return PlanItem(
          exerciseId: item.exerciseId,
          mode: dose.mode == coach.DoseMode.reps
              ? DoseMode.reps
              : DoseMode.time,
          sets: dose.sets,
          reps: dose.reps,
          workSeconds: dose.seconds,
          restSeconds: dose.restSeconds,
          perSide: drill.unilateral,
          note: item.note,
          replacedFrom: item.replacedFrom,
          segments: item.segments,
        );
      }

      final templates = TemplateCatalog([
        for (final template in local.templates.catalog.templates)
          PlanTemplate(
            id: template.id,
            name: template.name,
            summary: template.summary,
            goal: template.goal,
            scenes: template.scenes,
            equipment: template.equipment,
            minutes: template.minutes,
            minLevel: template.minLevel,
            maxLevel: template.maxLevel,
            keywords: template.keywords,
            blocks: [
              for (final block in template.blocks)
                block.copyWith(items: block.items.map(canonicalItem).toList()),
            ],
          ),
      ]);
      fallback = RuleChatEngine(
        lib: library,
        parser: local.parser,
        templates: TemplatePlanGenerator(
          lib: library,
          catalog: templates,
          matcher: local.templates.matcher,
          preferredExerciseIds: local.templates.preferredExerciseIds,
          onGenerated: local.templates.onGenerated,
        ),
      );
    }
    // A previously adopted card may contain equipment no longer available.
    // Generate afresh before the filtered planner tries to edit those IDs.
    final oldPlanUnavailable =
        state.plan?.items.any(
          (item) =>
              !fallback.lib.contains(item.exerciseId) ||
              item.segments.any(
                (segment) => !fallback.lib.contains(segment.exerciseId),
              ),
        ) ??
        false;
    if (!oldPlanUnavailable) {
      final reply = await fallback.reply(turn.input, state);
      final unsafe = reply.messages.any(
        (m) =>
            m.plan != null &&
            PlanValidator(fallback.lib).validate(m.plan!, request).isNotEmpty,
      );
      if (!unsafe) return reply;
    }
    final generated = await fallback.templates.generate(request);
    final plan = generated.plan;
    return ChatReply(
      messages: [
        plan == null
            ? const BotMessage('当前条件下暂时没有合适的预设方案，可以调整条件后再试。')
            : BotMessage('按刚确认的条件，改用这套预设方案。', plan: plan, request: request),
      ],
      state: state.copyWith(clearPending: true, plan: plan, request: request),
      suggestions: plan == null ? const [] : planSuggestions,
    );
  }

  PlanEdit? _editFor(String input, ChatState state) {
    final plan = state.plan;
    if (plan == null) return null;
    // A fresh request for an easy workout is not "make this card easier".
    if (RegExp(r'安排|生成|制定|一组训练|新的训练').hasMatch(input) &&
        !RegExp(r'这套|当前|刚才|原来|上面').hasMatch(input)) {
      return null;
    }
    return local.parser.parseEdit(input, [
      for (final item in plan.items) ?local.lib.tryGet(item.exerciseId)?.name,
    ]);
  }

  Slots _saidSlots(String text, {String? asked}) {
    final said = local.parser.parse(text, asked: asked);
    final minutes = RegExp(r'(\d+)\s*(分钟|min|分)').firstMatch(text);
    return minutes == null
        ? said
        : said.copyWith(minutes: int.parse(minutes[1]!).clamp(3, 60));
  }

  Slots? _previousParameters(ChatState state) {
    final plan = state.plan;
    final card = plan == null
        ? null
        : state.recentMessages
              .where((message) => message.plan?.id == plan.id)
              .lastOrNull;
    final snapshot = card?.planState?.planId == plan?.id
        ? card?.planState
        : null;
    final storedEquipment = snapshot?.context.equipment;
    final previous = snapshot != null
        ? Slots(
            scene: snapshot.context.scene,
            minutes: snapshot.context.minutes,
            equipment:
                storedEquipment == null ||
                    storedEquipment.any(
                      (name) =>
                          !Equipment.values.any((item) => item.name == name),
                    )
                ? null
                : {
                    for (final item in Equipment.values)
                      if (storedEquipment.contains(item.name)) item,
                  },
          )
        : plan == null
        ? state.pending ?? state.coachContext
        : Slots.fromRequest(state.request ?? requestForPlan(plan));
    if (agent.history.any((message) => message.role == coach.LlmRole.user)) {
      return previous;
    }
    // The SDK restores visible history but not its inference history. If the
    // user corrected conditions after the last card, prefer those as optional
    // suggestions rather than silently prefilling the older card's values.
    final messages = state.recentMessages;
    final lastCard = messages.lastIndexWhere((message) => message.plan != null);
    var scene = previous?.scene;
    var minutes = previous?.minutes;
    var equipment = previous?.equipment;
    for (final message in messages.skip(lastCard + 1)) {
      if (!message.isUser || !message.aiVisible) continue;
      final text = message.text;
      final said = _saidSlots(text);
      if (said.scene != null || text.contains('健身房')) {
        scene = RegExp(r'不在|不去|不是|没在|以外|之外').hasMatch(text)
            ? null
            : text.contains('健身房')
            ? 'gym'
            : said.scene;
      }
      if (said.minutes != null) {
        minutes = RegExp(r'不|没|无|别|除|以外|之外').hasMatch(text)
            ? null
            : said.minutes;
      }
      if (RegExp(r'徒手|空手|器械|椅|凳|墙|垫|弹力带|拉力带|阻力带|哑铃|杠铃').hasMatch(text)) {
        // The local parser covers only part of the SDK equipment vocabulary.
        // Avoid retaining a stale gear suggestion after an ambiguous update.
        equipment =
            RegExp(r'徒手|空手').hasMatch(text) &&
                !RegExp(r'不|没|无|别|除|椅|凳|墙|垫|弹力带|拉力带|阻力带|哑铃|杠铃').hasMatch(text)
            ? <Equipment>{}
            : null;
      }
    }
    if (previous == null &&
        scene == null &&
        minutes == null &&
        equipment == null) {
      return null;
    }
    return Slots(scene: scene, equipment: equipment, minutes: minutes);
  }

  Slots _slotsFor(String input, ChatState state, {PlanEdit? edit}) {
    // Aggregated state may contain defaults from a generated/restored card.
    // Only the live conversation's original user text establishes facts.
    // The SDK conversation also retains normalized explicit form answers.
    final rawMessages = conversation.state.messages;
    final userTexts = [
      for (final message in state.recentMessages)
        if (message.isUser && message.aiVisible) message.text,
      for (final message in rawMessages)
        if (message.isUser) message.text,
    ];
    var slots = Slots(
      avoid: {
        ...?state.coachContext?.avoid,
        ...?state.pending?.avoid,
        ...?state.request?.avoid,
        ...?state.plan?.avoid,
      },
    );
    for (final text in userTexts) {
      slots = slots.merge(_saidSlots(text));
    }
    if (edit != null) {
      // Explicit edits may reuse the selected card, including its defaults.
      slots = slots.merge(
        Slots.fromRequest(state.request ?? requestForPlan(state.plan!)),
      );
    }
    slots = slots.merge(_saidSlots(input, asked: state.asked.lastOrNull));
    var minutes = slots.minutes;
    var level = slots.level;
    final explicitMinutes = RegExp(r'(\d+)\s*(分钟|min|分)').firstMatch(input);
    if (explicitMinutes != null) {
      minutes = int.parse(explicitMinutes[1]!).clamp(3, 60);
    }
    if (state.plan case final plan?) {
      switch (edit?.kind) {
        case EditKind.shorter:
          minutes = (plan.targetMinutes * .7).round().clamp(3, 60);
        case EditKind.longer:
          minutes = (plan.targetMinutes * 1.3).round().clamp(3, 60);
        case EditKind.easier:
          level = (plan.level - 1).clamp(1, 3);
        case EditKind.harder:
          level = (plan.level + 1).clamp(1, 3);
        default:
          break;
      }
    }
    return Slots(
      goal: slots.goal,
      scene: slots.scene,
      minutes: minutes,
      equipment: slots.equipment,
      level: level,
      avoid: slots.avoid,
      focus: slots.focus,
      description: slots.description,
    );
  }
}

class _Turn {
  _Turn(
    this.input,
    this.state,
    this.slots,
    this.operation, {
    this.usesCurrentPlan = false,
    this.currentGoal,
    this.previousParameters,
  });
  final String input;
  final ChatState state;
  final Slots slots;
  final String operation;
  final bool usesCurrentPlan;
  final String? currentGoal;
  final Slots? previousParameters;
  final watch = Stopwatch()..start();
  int step = 0;
  int attempts = 0;
  final cancel = coach.CancelToken();
  bool timedOut = false;
  ChatReply? fallbackReply;
  coach.CoachContext get context => coach.CoachContext(
    // r2 treats supplied conditions as previous selections for a new task;
    // the user's current text and confirmed form supply the actual facts.
    scene: usesCurrentPlan ? slots.scene : previousParameters?.scene,
    equipment:
        (usesCurrentPlan ? slots.equipment : previousParameters?.equipment)
            ?.map((e) => e.name)
            .toSet(),
    avoid: slots.avoid,
    level: slots.level,
    minutes: usesCurrentPlan ? slots.minutes : previousParameters?.minutes,
    goal: usesCurrentPlan ? slots.goal : currentGoal,
    notes: [
      if (usesCurrentPlan && state.plan != null)
        '用户当前明确采用的训练计划，调整请以此为基础：${jsonEncode(state.plan!.toJson())}',
    ],
  );
}

/// Cancellation also wins over a custom transport that ignores its token.
class _CancellableClient implements coach.LlmClient {
  _CancellableClient(this.inner, this.currentTurn);
  final coach.LlmClient inner;
  final _Turn? Function() currentTurn;
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) {
    // Capture before awaiting: a cancelled transport can finish in a later turn.
    final turn = currentTurn();
    final operation = turn?.operation;
    final attempt = turn == null ? 0 : ++turn.attempts;
    final step = turn?.step ?? 0;
    final watch = Stopwatch()..start();
    var finished = false;
    void record(String event, Map<String, Object?> fields) =>
        RuntimeLog.instance.record(
          event,
          operation: operation,
          fields: {
            'model': model,
            'attempt': attempt,
            'step': step,
            'elapsedMs': watch.elapsedMilliseconds,
            ...fields,
          },
        );
    record('ai.request.begin', const {});
    Future<coach.LlmResponse> transport() async {
      try {
        final response = await inner.complete(request, cancel: cancel);
        record('ai.request.end', {
          'status': 'ok',
          'available': cancel?.isCancelled != true,
          'count': response.httpAttempts,
          'promptTokens': response.usage.promptTokens,
          'completionTokens': response.usage.completionTokens,
          'reasoningTokens': response.usage.reasoningTokens,
        });
        for (final call in response.toolCalls) {
          // Tool arguments may contain health information, memory or plans.
          const names = {
            'read',
            'ls',
            'check_plan',
            'remember',
            'forget',
            'ask_user',
            coach.CoachTools.showPlan,
            coach.CoachTools.showActions,
          };
          record('ai.tool.requested', {
            'kind': names.contains(call.name) ? call.name : 'unknown',
          });
        }
        return response;
      } on Object catch (error) {
        record('ai.request.error', {
          'errorType': RuntimeLog.errorType(error),
          'available': cancel?.isCancelled != true,
          if (error is coach.LlmException) ...{
            'kind': error.kind.name,
            'httpStatus':
                error.statusCode ?? error.responseDiagnostic?.statusCode,
            'reason': error.responseDiagnostic?.subtype.name,
            'count': error.httpAttempts,
            'promptTokens': error.usage.promptTokens,
            'completionTokens': error.usage.completionTokens,
            'reasoningTokens': error.usage.reasoningTokens,
          },
        });
        rethrow;
      } finally {
        finished = true;
      }
    }

    return Future.any([
      transport(),
      if (cancel != null)
        cancel.whenCancelled.then<coach.LlmResponse>((_) {
          if (!finished) record('ai.request.cancel', const {});
          throw const coach.LlmException(
            coach.LlmErrorKind.cancelled,
            'cancelled',
          );
        }),
    ]);
  }
}
