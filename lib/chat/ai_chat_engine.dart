import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../domain/exercise.dart';
import '../domain/plan.dart';
import '../domain/plan_validator.dart';
import '../domain/scenario.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart';
import 'slot_parser.dart';

/// One SDK session for the app lifetime. Only admitted results cross into UI.
class AiChatEngine implements ManagedChatEngine, RestorableChatEngine {
  AiChatEngine({
    required this.local,
    required this.catalog,
    required this.profile,
    required this.client,
    // Three 120-second submissions can be needed for gate corrections.
    this.turnTimeout = const Duration(seconds: 365),
  });

  final RuleChatEngine local;
  final coach.Catalog catalog;
  final coach.CoachProfile profile;
  final coach.LlmClient client;
  final Duration turnTimeout;
  final usage = coach.MemoryUsageSink();
  final _random = Random.secure();
  coach.CoachTurnResult? lastResult;
  coach.TurnOutcome? lastOutcome;
  coach.FallbackReason? lastFallbackReason;
  _Turn? _pending;
  Future<coach.CoachTurnResult>? _sdkPending;
  bool _disposed = false;

  late final session = coach.CoachSession(
    client: _CancellableClient(client),
    catalog: () => catalog,
    profile: profile,
    maxResubmits: 2,
    usage: usage,
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
  String get id => 'ugk_coach:smartfit:tools';

  @override
  void cancelPending() {
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
    ChatReply empty() => ChatReply(messages: const [], state: state);
    if (_disposed) return empty();
    // Settle cancellation before accepting a new turn; ordinary sends never queue.
    if (_pending == null && session.isBusy && _sdkPending != null) {
      await _sdkPending;
    }
    if (_disposed) return empty();
    if (_pending != null || session.isBusy) {
      lastResult = const coach.CoachTurnResult(
        turnId: '',
        status: coach.TurnStatus.busy,
      );
      return empty();
    }
    final rawLocalReply = local.localReply(input, state);
    // Explicit library navigation stays local. Requests to see/recommend
    // actions belong to the SDK's show_actions tool.
    final opensLibrary = rawLocalReply?.action?.startsWith('@library') ?? false;
    final localReply =
        rawLocalReply == null || (opensLibrary && !input.contains('动作库'))
        ? null
        : _admitLocalCards(rawLocalReply);
    if (localReply != null) {
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
    if (state.safetyBlocked) return local.reply(input, state);
    final turn = _Turn(input, state, _slotsFor(input, state));
    _pending = turn;
    final timer = Timer(turnTimeout, () {
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
        );
        turn.fallbackReply = fallback;
      } else {
        lastResult = result;
      }
      final accepted = lastResult!;
      if (accepted.status == coach.TurnStatus.cancelled ||
          accepted.status == coach.TurnStatus.busy) {
        return empty();
      }
      lastFallbackReason = accepted.fallbackReason;
      lastOutcome = switch (accepted.status) {
        coach.TurnStatus.ok =>
          accepted.submissions > 1
              ? coach.TurnOutcome.rewritten
              : coach.TurnOutcome.model,
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
        if (fallback)
          accepted.fallbackReason == coach.FallbackReason.rateLimited
              ? '预设方案 · AI 请求较多，请稍后再试。'
              : '预设方案 · AI 暂时不可用，先用本地模板继续。',
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
    } on Object {
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
  _Turn(this.input, this.state, this.slots);
  final String input;
  final ChatState state;
  final Slots slots;
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
    notes: [if (state.plan case final plan?)
      '用户当前明确采用的训练计划，调整请以此为基础：${jsonEncode(plan.toJson())}'],
  );
}

/// Cancellation also wins over a custom transport that ignores its token.
class _CancellableClient implements coach.LlmClient {
  _CancellableClient(this.inner);
  final coach.LlmClient inner;
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) => Future.any([
    inner.complete(request, cancel: cancel),
    if (cancel != null)
      cancel.whenCancelled.then<coach.LlmResponse>(
        (_) => throw const coach.LlmException(
          coach.LlmErrorKind.cancelled,
          'cancelled',
        ),
      ),
  ]);
}
