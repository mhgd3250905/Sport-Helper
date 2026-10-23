import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../diagnostics/runtime_log.dart';
import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart';
import 'slot_parser.dart';

/// One SDK session for the app lifetime. Only admitted results cross into UI.
class AiChatEngine
    implements
        ManagedChatEngine,
        RestorableChatEngine,
        ProgressChatEngine,
        DiagnosticChatEngine {
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
  Future<coach.CoachTurnResult>? _sdkPending;
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
    session.reset();
    lastResult = null;
    lastOutcome = null;
    lastFallbackReason = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPending();
    session.reset();
    unawaited(agent.dispose());
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
  Future<ChatReply> reply(String input, ChatState state) async {
    final operation =
        _diagnosticOperation ?? RuntimeLog.instance.newOperation('chat');
    _diagnosticOperation = null;
    ChatReply empty() => ChatReply(messages: const [], state: state);
    if (_disposed) {
      RuntimeLog.instance.record(
        'ai.turn.rejected',
        operation: operation,
        fields: const {'reason': 'disposed'},
      );
      return empty();
    }
    // Settle cancellation before accepting a new turn; ordinary sends never queue.
    if (_pending == null && session.isBusy && _sdkPending != null) {
      await _sdkPending;
    }
    if (_disposed) return empty();
    if (_pending != null || session.isBusy) {
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
    final rawLocalReply = local.localReply(input, state);
    // Explicit library navigation stays local. Requests to see/recommend
    // actions belong to the SDK's show_actions tool.
    final opensLibrary = rawLocalReply?.action?.startsWith('@library') ?? false;
    final localReply =
        rawLocalReply == null || (opensLibrary && !input.contains('动作库'))
        ? null
        : _admitLocalCards(rawLocalReply);
    if (localReply != null) {
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
    final turn = _Turn(input, state, _slotsFor(input, state), operation);
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
      final pending = session.send(
        input,
        context: turn.context,
        cancel: turn.cancel,
      );
      _sdkPending = pending;
      final result = await pending;
      if (_disposed || _pending != turn) return empty();
      if (turn.timedOut) {
        final fallback = await _localFallback(turn);
        if (_disposed || _pending != turn) return empty();
        final plan = fallback.messages
            .where((m) => m.plan != null)
            .firstOrNull
            ?.plan;
        lastResult = coach.CoachTurnResult(
          turnId: result.turnId,
          status: coach.TurnStatus.fallback,
          text: fallback.messages.map((m) => m.text).join('\n'),
          plan: plan == null ? null : restorePlan(plan, fallback.state.request),
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
        turn.fallbackReply = fallback;
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
          );
        case coach.TurnStatus.error:
          return ChatReply(
            messages: const [BotMessage('预设方案暂时也无法生成，请调整条件或点「自己选条件」。')],
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
                  turn.context,
                )
          : admitted;
      final plan = validated == null
          ? null
          : TrainingPlan.fromJson(validated.plan.toJson());
      final request = plan == null
          ? null
          : requestForPlan(
              plan,
            ).copyWith(description: input, equipment: turn.slots.equipment);
      final fallback = accepted.status == coach.TurnStatus.fallback;
      final text = [
        if (fallback) _fallbackNotice(accepted),
        if (accepted.text.isNotEmpty) accepted.text,
        if (fallback && turn.fallbackReply?.state.plan != null && plan == null)
          '当前模板未通过安全检查，请调整条件或自己选条件。',
      ].join('\n');
      return ChatReply(
        aiTurn: true,
        messages: [
          BotMessage(
            text,
            plan: plan,
            validatedPlan: validated,
            actions: accepted.actions,
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
        messages: const [BotMessage('预设方案暂时也无法生成，请调整条件或点「自己选条件」。')],
        state: state,
      );
    } finally {
      timer.cancel();
      unawaited(progress.cancel());
      if (_pending == turn) _pending = null;
    }
  }

  String _fallbackNotice(coach.CoachTurnResult result) {
    final error = result.error;
    if (error is coach.AgentRequestFailed) {
      return switch (error.kind) {
        coach.AgentFailureKind.retriesExhausted =>
          error.errorClass == coach.RequestErrorClass.rateLimited
              ? '预设方案 · AI 请求较多，重试后仍未成功，请稍后再试。'
              : '预设方案 · AI 重试后仍未成功，先用本地模板继续。',
        coach.AgentFailureKind.nonRetryable => '预设方案 · AI 暂时无法处理这条请求，先用本地模板继续。',
        coach.AgentFailureKind.turnTimeout => '预设方案 · AI 思考超时，先用本地模板继续。',
      };
    }
    if (error is coach.AgentStalled) {
      return '预设方案 · AI 暂时没能继续完成，先用本地模板继续。';
    }
    if (error is coach.AgentStepLimitExceeded) {
      return '预设方案 · AI 暂时没能完成这次请求，先用本地模板继续。';
    }
    return result.fallbackReason == coach.FallbackReason.rateLimited
        ? '预设方案 · AI 请求较多，请稍后再试。'
        : '预设方案 · AI 暂时不可用，先用本地模板继续。';
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
    final reply = await local.reply(turn.input, state);
    final unsafe = reply.messages.any(
      (m) =>
          m.plan != null &&
          PlanValidator(local.lib).validate(m.plan!, request).isNotEmpty,
    );
    if (!unsafe) return reply;
    final generated = await local.templates.generate(request);
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

  Slots _slotsFor(String input, ChatState state) {
    final request = state.request;
    var slots =
        state.coachContext ??
        state.pending ??
        (request == null ? const Slots() : Slots.fromRequest(request));
    if (state.coachContext == null) {
      final lastPlan = state.recentMessages.lastIndexWhere(
        (m) => m.plan != null,
      );
      for (final message
          in state.recentMessages
              .skip(lastPlan + 1)
              .where((m) => m.isUser && m.aiVisible)) {
        slots = slots.merge(local.parser.parse(message.text));
      }
    }
    slots = slots.merge(
      local.parser.parse(input, asked: state.asked.lastOrNull),
    );
    var minutes = slots.minutes;
    var level = slots.level;
    final explicitMinutes = RegExp(r'(\d+)\s*(分钟|min|分)').firstMatch(input);
    if (explicitMinutes != null) {
      minutes = int.parse(explicitMinutes[1]!).clamp(3, 60);
    }
    if (state.plan case final plan?) {
      final edit = local.parser.parseEdit(input, [
        for (final item in plan.items) ?local.lib.tryGet(item.exerciseId)?.name,
      ]);
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
  _Turn(this.input, this.state, this.slots, this.operation);
  final String input;
  final ChatState state;
  final Slots slots;
  final String operation;
  final watch = Stopwatch()..start();
  int step = 0;
  int attempts = 0;
  final cancel = coach.CancelToken();
  bool timedOut = false;
  ChatReply? fallbackReply;
  coach.CoachContext get context => coach.CoachContext(
    scene: slots.scene,
    equipment: slots.equipment?.map((e) => e.name).toSet(),
    avoid: slots.avoid,
    level: slots.level,
    minutes: slots.minutes,
    goal: slots.goal,
    notes: [
      if (state.plan case final plan?)
        '用户当前明确采用的训练计划，调整请以此为基础：${jsonEncode(plan.toJson())}',
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
