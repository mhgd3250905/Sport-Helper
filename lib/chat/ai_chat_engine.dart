import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../domain/plan.dart';
import '../domain/plan_validator.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart';
import 'slot_parser.dart';

/// SDK answers and validates; the existing rules remain the offline path.
class AiChatEngine implements ManagedChatEngine {
  AiChatEngine({
    required this.local,
    required this.catalog,
    required this.profile,
    required this.client,
    this.turnTimeout = const Duration(seconds: 75),
  });

  final RuleChatEngine local;
  final coach.Catalog catalog;
  final coach.CoachProfile profile;
  final coach.LlmClient client;
  final Duration turnTimeout;
  final usage = coach.MemoryUsageSink();
  coach.TurnOutcome? lastOutcome;
  coach.FallbackReason? lastFallbackReason;
  coach.CancelToken? _pending;
  bool _disposed = false;

  @override
  String get id => 'ugk_coach:smartfit';

  @override
  void cancelPending() {
    if (_pending != null) {
      lastOutcome = coach.TurnOutcome.cancelled;
      lastFallbackReason = null;
    }
    _pending?.cancel();
    _pending = null;
  }

  @override
  void dispose() {
    _disposed = true;
    cancelPending();
    if (client is coach.OpenAiCompatibleClient) {
      (client as coach.OpenAiCompatibleClient).close();
    }
  }

  @override
  Future<ChatReply> reply(String input, ChatState state) async {
    if (_disposed) return ChatReply(messages: const [], state: state);
    final localReply = local.localReply(input, state);
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

    cancelPending();
    final cancel = coach.CancelToken();
    _pending = cancel;
    var timedOut = false;
    final timer = Timer(turnTimeout, () {
      timedOut = true;
      cancel.cancel('turn timeout');
    });
    final slots = _slotsFor(input, state);
    final context = coach.CoachContext(
      scene: slots.scene,
      equipment: slots.equipment?.map((e) => e.name).toSet(),
      avoid: slots.avoid,
      level: slots.level,
      minutes: slots.minutes,
      goal: slots.goal,
    );
    ChatReply? fallbackReply;
    Future<ChatReply> fallback() async {
      // The offline engine must receive constraints established by AI too.
      final fallbackState = state.copyWith(
        coachContext: slots,
        pending: slots,
        asked: state.asked,
        request: state.request == null
            ? null
            : slots.toRequest(fallbackGoal: state.plan?.goal),
      );
      return local.reply(input, fallbackState);
    }

    final assistant = coach.CoachAssistant(
      client: _CancellableClient(client),
      catalog: () => catalog,
      profile: profile,
      maxRewrites: 1,
      usage: usage,
      extraRules: [
        (plan, _, conditions) {
          final mapped = TrainingPlan.fromJson(plan.toJson());
          final request = requestForPlan(mapped);
          return [
            for (final issue in PlanValidator(
              local.lib,
            ).validate(mapped, request))
              coach.PlanIssue('smartfit_plan', issue),
          ];
        },
      ],
      fallback: coach.FallbackFn((request) async {
        fallbackReply = await fallback();
        final messages = fallbackReply!.messages;
        final plan = messages.where((m) => m.plan != null).firstOrNull?.plan;
        final text = messages
            .map((m) => m.text)
            .where((s) => s.isNotEmpty)
            .join('\n');
        if (plan != null) {
          return coach.CoachReply.plan(
            text,
            const coach.PlanCodec().decode(plan.toJson()),
          );
        }
        return coach.CoachReply.text(text);
      }),
    );
    try {
      // Each turn gets an isolated SDK history. Cancelled/late responses
      // cannot mutate the controller's persisted conversation or plan.
      final result = await assistant.ask(
        input,
        context: context,
        conversation: _conversationFor(state),
        cancel: cancel,
      );
      if (_disposed || _pending != cancel) {
        return ChatReply(messages: const [], state: state);
      }
      if (timedOut) {
        lastOutcome = coach.TurnOutcome.fallback;
        lastFallbackReason = coach.FallbackReason.timeout;
        return _withFallbackNotice(await fallback());
      }
      if (cancel.isCancelled) {
        return ChatReply(messages: const [], state: state);
      }
      lastOutcome = result.outcome;
      lastFallbackReason = result.fallbackReason;
      if (fallbackReply != null) return _withFallbackNotice(fallbackReply!);
      if (!result.fromModel || result.reply == null) {
        return _withFallbackNotice(await fallback());
      }
      final reply = result.reply!;
      final plan = reply.plan == null
          ? null
          : TrainingPlan.fromJson(reply.plan!.toJson());
      final request = plan == null
          ? null
          : requestForPlan(plan).copyWith(description: input);
      final asking = reply.kind == coach.ReplyKind.ask;
      return ChatReply(
        aiTurn: true,
        messages: [
          BotMessage(
            reply.text,
            plan: plan,
            request: request,
            options: [
              for (final option in reply.options)
                if (option.trim().isNotEmpty &&
                    !option.trimLeft().startsWith('@'))
                  ChatOption(option),
            ],
          ),
        ],
        state: state.copyWith(
          coachContext: slots,
          pending: asking ? slots : null,
          clearPending: !asking,
          asked: asking ? [_askedSlot(reply.text)] : null,
          plan: plan,
          request: request,
        ),
        suggestions: plan == null ? const [] : planSuggestions,
      );
    } on Object {
      if (_disposed ||
          _pending != cancel ||
          (cancel.isCancelled && !timedOut)) {
        return ChatReply(messages: const [], state: state);
      }
      lastOutcome = coach.TurnOutcome.fallback;
      lastFallbackReason = timedOut
          ? coach.FallbackReason.timeout
          : coach.FallbackReason.server;
      return _withFallbackNotice(await fallback());
    } finally {
      timer.cancel();
      if (_pending == cancel) _pending = null;
    }
  }

  Slots _slotsFor(String input, ChatState state) {
    final request = state.request;
    var slots =
        state.coachContext ??
        state.pending ??
        (request == null ? const Slots() : Slots.fromRequest(request));
    // Restore explicit constraints even after restarting during an AI question.
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
        for (final item in plan.items) local.lib[item.exerciseId].name,
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

  coach.CoachConversation _conversationFor(ChatState state) {
    final conversation = coach.CoachConversation();
    final history = state.recentMessages.where((m) => m.aiVisible).toList();
    if (history.lastOrNull?.isUser ?? false) history.removeLast();
    for (final message in history) {
      if (message.isUser) {
        conversation.addUser(message.text, message.at);
      } else {
        final plan = message.plan;
        conversation.addAssistant(
          plan == null
              ? coach.CoachReply.text(message.text)
              : coach.CoachReply.plan(
                  message.text,
                  const coach.PlanCodec().decode(plan.toJson()),
                ),
          message.at,
        );
      }
    }
    if (state.plan case final plan? when conversation.lastPlan?.id != plan.id) {
      final now = state.now ?? DateTime.now();
      conversation.addUser('当前采用的训练计划，后续调整请以此为基础。', now);
      conversation.addAssistant(
        coach.CoachReply.plan(
          plan.summary,
          const coach.PlanCodec().decode(plan.toJson()),
        ),
        now,
      );
    }
    return conversation;
  }

  static String _askedSlot(String text) {
    if (RegExp('时间|多久|分钟|几分').hasMatch(text)) return 'minutes';
    if (RegExp('器械|哑铃|弹力带|徒手').hasMatch(text)) return 'equipment';
    if (RegExp('哪[里儿]|场所|在家|办公室').hasMatch(text)) return 'scene';
    return 'goal';
  }

  ChatReply _withFallbackNotice(ChatReply reply) => ChatReply(
    messages: [
      BotMessage(
        lastFallbackReason == coach.FallbackReason.rateLimited
            ? 'AI 请求较多，请稍后再试，先用本地模板继续。'
            : 'AI 暂时不可用，先用本地模板继续。',
      ),
      ...reply.messages,
    ],
    state: reply.state,
    suggestions: reply.suggestions,
    action: reply.action,
  );
}

/// Also guards late custom clients: cancellation wins without committing
/// their eventual response to the SDK conversation.
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
