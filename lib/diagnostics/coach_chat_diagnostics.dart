import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import 'coach_tool_trace.dart';
import 'runtime_log.dart';

/// Read-only observation of public SDK state/protocol. It never selects tools,
/// edits a request/response or changes cancellation, retries and admission.
class CoachChatDiagnostics {
  final log = RuntimeLog.instance;
  CoachChatController? _controller;
  CoachToolTrace? _trace;
  Stopwatch? _watch;
  String? _operation, _turnId;
  int _step = 0, _attempt = 0;
  final _seen = <String>{};
  final _userInputs = <String, CoachChatUserInput>{};
  bool _initial = true;

  CoachGatewayBinding observeGateway(CoachGatewayBinding gateway) =>
      CoachGatewayBinding(
        create: () async {
          final lease = await gateway.create();
          final client = _ObservedChatClient(lease.client, this);
          final release = lease.release;
          return release == null
              ? CoachClientLease.shared(client)
              : CoachClientLease.owned(client, release: release);
        },
      );

  void attach(CoachChatController controller) {
    _controller = controller;
    controller.addListener(_changed);
    controller.events.listen(
      (_) {},
      onDone: () {
        _finish();
        _userInputs.clear();
        controller.removeListener(_changed);
        _controller = null;
      },
    );
  }

  void observe(String event, Object? detail) {
    if (event == 'chat.user' && detail is CoachChatUserInput) {
      if (!_seen.contains(detail.messageId)) {
        // SDK publishes this before the display notification starts the trace.
        _userInputs[detail.messageId] = detail;
      }
      return;
    }
    if (detail is! coach.AgentEvent) {
      log.record(
        'coach_chat.$event',
        fields: {if (detail != null) 'errorType': RuntimeLog.errorType(detail)},
      );
      return;
    }
    _step = detail.step;
    _turnId = detail.turnId;
    log.record(
      'ai.progress',
      operation: _operation,
      fields: {'kind': detail.kind.name, 'step': detail.step},
    );
    log.recordDeveloper(
      'ai.agent.event',
      operation: _operation,
      fields: {'kind': detail.kind.name, 'step': detail.step},
      data: {
        'turnId': detail.turnId,
        'name': detail.kind.name,
        if (detail.path != null) 'path': detail.path,
        if (detail.node != null) 'node': detail.node!.toJson(),
        if (detail.task != null) 'task': detail.task!.toJson(),
        if (detail.kind == coach.AgentEventKind.node)
          'params': {
            for (final entry in _controller!.agent.sessionState.params.entries)
              entry.key: entry.value.toJson(),
          },
      },
    );
  }

  void _changed() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.typing && _trace == null) {
      _operation = log.newOperation('chat');
      _watch = Stopwatch()..start();
      _trace = CoachToolTrace(log, operation: _operation!);
      _step = 0;
      _attempt = 0;
      _turnId = null;
      log.record('chat.request.begin', operation: _operation);
    }
    for (final message in controller.messages) {
      if (!_seen.add(message.id) || _initial || !message.isUser) continue;
      final input = _userInputs.remove(message.id);
      log.recordDeveloper(
        'chat.user',
        operation: _operation,
        data: {'text': input?.rawText ?? message.text},
      );
    }
    _initial = false;
    if (!controller.typing && _trace != null) _finish();
  }

  Future<void> archiveConversation(CoachChatSnapshot snapshot) {
    log.record('chat.conversation.new');
    return log.archiveSession(snapshot.session.toJson());
  }

  void _finish() {
    if (_trace == null) return;
    final controller = _controller;
    final candidate = controller?.lastResult;
    final result = candidate?.turnId == _turnId ? candidate : null;
    _trace?.finish(
      history: controller?.agent.history ?? const [],
      result: result,
      status: result?.status.name ?? 'unavailable',
    );
    if (_trace != null) {
      log.record(
        'ai.turn.end',
        operation: _operation,
        fields: {
          'status': result?.status.name ?? 'unavailable',
          'elapsedMs': _watch?.elapsedMilliseconds,
          'steps': result?.steps,
          'hasPlan': result?.plan != null,
          'hasActions': result?.actions != null,
        },
      );
    }
    _trace = null;
    _watch = null;
  }
}

class _ObservedChatClient implements coach.LlmClient {
  _ObservedChatClient(this.inner, this.owner);
  final coach.LlmClient inner;
  final CoachChatDiagnostics owner;
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;

  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    // A cancelled transport may return while a newer SDK turn is active.
    // Retain this call's observer/identity rather than touching the new trace.
    final trace = owner._trace;
    final operation = owner._operation;
    final step = owner._step;
    trace?.observeMessages(request.messages);
    final attempt = ++owner._attempt;
    final watch = Stopwatch()..start();
    void record(String event, Map<String, Object?> fields) => owner.log.record(
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
    try {
      final response = await inner.complete(request, cancel: cancel);
      trace?.observeResponse(response, step: step, attempt: attempt);
      record('ai.request.end', {
        'status': 'ok',
        'available': cancel?.isCancelled != true,
        'count': response.httpAttempts,
        'promptTokens': response.usage.promptTokens,
        'completionTokens': response.usage.completionTokens,
        'reasoningTokens': response.usage.reasoningTokens,
      });
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
    }
  }
}
