import 'dart:async';
import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../diagnostics/runtime_log.dart';
import '../diagnostics/coach_tool_trace.dart';
import '../domain/plan.dart';
import '../domain/scenario.dart';
import 'app_chat_actions.dart';
import 'chat_models.dart';

/// Transport, storage and presentation adapter for one SDK-owned session.
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
    this.turnTimeout = const Duration(seconds: 390),
  }) : _initialMemoryEnabled = enableUserMemory;

  final AppChatActions local;
  final coach.Catalog catalog;
  final coach.CoachProfile profile;
  final coach.LlmClient client;
  final Duration turnTimeout;
  final coach.UserMemoryStore? memoryStore;
  final bool _initialMemoryEnabled;
  final usage = coach.MemoryUsageSink();
  coach.CoachTurnResult? lastResult;
  coach.TurnOutcome? lastOutcome;
  coach.FallbackReason? lastFallbackReason;
  _Turn? _pending;
  bool _disposed = false;
  String? _diagnosticOperation;

  @override
  set diagnosticOperation(String? operation) =>
      _diagnosticOperation = operation;

  // All planning, task, retry and context budgets use SDK defaults.
  late final agent = coach.CoachAgent(
    client: _CancellableClient(client, () => _pending),
    catalog: () => catalog,
    profile: profile,
    usage: usage,
    memoryStore: memoryStore,
    enableUserMemory: _initialMemoryEnabled,
  );
  @override
  late final conversation = coach.CoachConversationController(agent: agent);
  coach.CoachAgent get session => agent;
  @override
  Stream<coach.AgentEvent> get events => agent.events;
  bool get enableUserMemory => agent.enableUserMemory;
  set enableUserMemory(bool value) => agent.enableUserMemory = value;

  Future<void> clearMemory() async {
    await agent.clearMemory();
    if ((await agent.memoryStore.load()).isNotEmpty) {
      throw StateError('AI memory could not be cleared from local storage');
    }
  }

  @override
  String get id => 'ugk_coach:smartfit:agent-v2';
  @override
  void cancelPending() {
    conversation.cancel();
    final turn = _pending;
    if (turn == null) return;
    lastOutcome = coach.TurnOutcome.cancelled;
    lastFallbackReason = null;
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
      agent.gateFor(catalog).check('', [
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
  ) => agent
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
      )
      ?.withSessionVersion(agent.sessionState);

  @override
  Future<ChatReply> reply(String input, ChatState state) =>
      _reply(input, state);

  @override
  Future<ChatReply> replyAppCommand(String command, ChatState state) async {
    final reply = await local.replyAppCommand(command, state);
    return ChatReply(
      messages: [
        for (final message in reply.messages)
          if (message.plan?.source == 'ai')
            BotMessage(
              message.text,
              plan: message.plan,
              validatedPlan: restorePlan(message.plan!, message.request),
              request: message.request,
              options: message.options,
            )
          else
            message,
      ],
      state: reply.state,
      action: reply.action,
      suggestions: reply.suggestions,
    );
  }

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
    String? questionId,
    List<String>? choices,
    Map<String, List<String>>? formAnswers,
    bool skipQuestion = false,
  }) async {
    ChatReply empty() =>
        ChatReply(messages: const [], state: state, inputAccepted: false);
    if (_disposed || _pending != null || conversation.state.isWaiting) {
      return empty();
    }
    lastResult = null;
    lastOutcome = null;
    lastFallbackReason = null;
    final turn = _Turn(
      _diagnosticOperation ?? RuntimeLog.instance.newOperation('chat'),
    );
    _diagnosticOperation = null;
    _pending = turn;
    final progress = events.listen((event) {
      if (_pending != turn) return;
      turn.step = event.step;
      RuntimeLog.instance.record(
        'ai.progress',
        operation: turn.operation,
        fields: {'kind': event.kind.name, 'step': event.step},
      );
      RuntimeLog.instance.recordDeveloper(
        'ai.agent.event',
        operation: turn.operation,
        fields: {'kind': event.kind.name, 'step': event.step},
        data: {
          'turnId': event.turnId,
          'name': event.kind.name,
          if (event.path != null) 'path': event.path,
          if (event.node != null) 'node': event.node!.toJson(),
          if (event.task != null) 'task': event.task!.toJson(),
          if (event.kind == coach.AgentEventKind.node)
            'params': {
              for (final entry in agent.sessionState.params.entries)
                entry.key: entry.value.toJson(),
            },
        },
      );
    });
    final timer = Timer(turnTimeout, () {
      turn.timedOut = true;
      turn.cancel.cancel('turn timeout');
    });
    try {
      // No inferred or inherited App parameters enter CoachContext.
      const context = coach.CoachContext();
      final result = questionId == null
          ? await conversation.send(
              input,
              context: context,
              cancel: turn.cancel,
            )
          : skipQuestion
          ? await conversation.skipQuestion(
              questionId,
              context: context,
              cancel: turn.cancel,
            )
          : formAnswers != null
          ? await conversation.answerForm(
              questionId,
              formAnswers,
              context: context,
              cancel: turn.cancel,
            )
          : choices == null
          ? await conversation.answerText(
              questionId,
              input,
              context: context,
              cancel: turn.cancel,
            )
          : await conversation.answerChoices(
              questionId,
              choices,
              context: context,
              cancel: turn.cancel,
            );
      turn.result = result;
      if (_disposed || _pending != turn) return empty();
      if (turn.timedOut) return _failure(state);
      if (result == null) return empty();
      lastResult = result;
      lastFallbackReason = result.fallbackReason;
      lastOutcome = switch (result.status) {
        coach.TurnStatus.ok =>
          result.records.lastOrNull?.turnOutcome ?? coach.TurnOutcome.model,
        coach.TurnStatus.cancelled => coach.TurnOutcome.cancelled,
        _ => coach.TurnOutcome.error,
      };
      RuntimeLog.instance.record(
        'ai.turn.end',
        operation: turn.operation,
        fields: {
          'status': result.status.name,
          'elapsedMs': turn.watch.elapsedMilliseconds,
          'steps': result.steps,
          'count': result.records.length,
          'hasPlan': result.plan != null,
          'hasActions': result.actions != null,
        },
      );
      switch (result.status) {
        case coach.TurnStatus.cancelled:
        case coach.TurnStatus.busy:
          return empty();
        case coach.TurnStatus.inputTooLong:
          return ChatReply(
            messages: [BotMessage('请把这一条缩短到 ${agent.maxInputChars} 字以内再发送。')],
            state: state,
            inputAccepted: false,
          );
        case coach.TurnStatus.error:
        case coach.TurnStatus.limitReached:
        case coach.TurnStatus.fallback:
          return _failure(state);
        case coach.TurnStatus.ok:
          break;
      }
      final output = conversation.state.messages
          .where((m) => !m.isUser && m.turnId == result.turnId)
          .lastOrNull;
      final validated = result.plan;
      // SDK owns plan identity, versions, conditions and the admitted payload.
      final plan = validated == null
          ? null
          : TrainingPlan.fromJson(validated.plan.toJson());
      final request = plan == null ? null : requestForPlan(plan);
      return ChatReply(
        aiTurn: true,
        messages: [
          BotMessage(
            output?.text ?? result.text,
            plan: plan,
            validatedPlan: validated,
            actions: result.actions,
            question: result.question,
            conversationMessageId: output?.id,
            answeredForm: output?.answeredForm ?? const {},
            request: request,
          ),
        ],
        state: state.copyWith(plan: plan, request: request),
        suggestions: plan == null ? const [] : planSuggestions,
      );
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'ai.turn.error',
        operation: turn.operation,
        fields: {
          'errorType': RuntimeLog.errorType(error),
          'elapsedMs': turn.watch.elapsedMilliseconds,
        },
      );
      if (_disposed ||
          _pending != turn ||
          (turn.cancel.isCancelled && !turn.timedOut)) {
        return empty();
      }
      return _failure(state);
    } finally {
      turn.trace.finish(
        history: _pending == turn ? agent.history : const [],
        result: turn.result,
        status: turn.timedOut
            ? 'timeout'
            : turn.cancel.isCancelled
            ? 'cancelled'
            : turn.result?.status.name,
      );
      timer.cancel();
      unawaited(progress.cancel());
      if (_pending == turn) _pending = null;
    }
  }

  ChatReply _failure(ChatState state) {
    lastOutcome = coach.TurnOutcome.error;
    return ChatReply(
      aiTurn: true,
      messages: const [BotMessage('', isPlanningFailure: true)],
      state: state,
    );
  }
}

class _Turn {
  _Turn(this.operation)
    : trace = CoachToolTrace(RuntimeLog.instance, operation: operation);
  final String operation;
  final CoachToolTrace trace;
  coach.CoachTurnResult? result;
  final watch = Stopwatch()..start();
  final cancel = coach.CancelToken();
  int step = 0;
  int attempts = 0;
  bool timedOut = false;
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
    turn?.trace.observeMessages(request.messages);
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
        turn?.trace.observeResponse(response, step: step, attempt: attempt);
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
