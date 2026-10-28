import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'runtime_log.dart';

/// Observes the SDK's public protocol without interpreting or executing tools.
///
/// Completed card batches are not retained in the SDK's public history. Their
/// tool receipts must stay explicitly unavailable; a turn result is evidence
/// of the delivery, never proof that every proposed tool in a batch succeeded.
class CoachToolTrace {
  CoachToolTrace(this.log, {required this.operation});

  final RuntimeLog log;
  final String operation;
  final List<_Batch> _batches = [];
  Map<String, int> _previousGroups = {};
  bool _finished = false;

  void observeResponse(
    coach.LlmResponse response, {
    int step = 0,
    int attempt = 0,
  }) {
    if (!log.enabled || _finished || response.toolCalls.isEmpty) return;
    final batch = _Batch(
      _batches.length + 1,
      response.toolCalls,
      step: step,
      attempt: attempt,
    );
    _batches.add(batch);
    for (final call in batch.calls) {
      Object? arguments;
      var validJson = true;
      try {
        arguments = jsonDecode(call.call.arguments);
      } on FormatException {
        validJson = false;
      }
      log.recordDeveloper(
        'ai.tool.requested',
        operation: operation,
        fields: call.metadata,
        data: {
          ...call.identity,
          'argumentsRaw': call.call.arguments,
          'argumentsValidJson': validJson,
          if (validJson) 'arguments': arguments,
          if (call.call.name == 'set_params' && arguments is Map)
            'parameters': _parameters(arguments['fields']),
        },
      );
    }
  }

  /// Call before each client request, and once with agent.history at finish.
  /// Only matching calls previously observed in this turn can receive receipts.
  void observeMessages(
    Iterable<coach.LlmMessage> messages, {
    String source = 'request',
  }) {
    if (!log.enabled || _finished) return;
    final groups = _groups(messages.toList());
    final currentCounts = <String, int>{};
    for (final group in groups) {
      currentCounts.update(group.signature, (n) => n + 1, ifAbsent: () => 1);
    }
    final fromEnd = <String, int>{};
    final matched = <int>{};
    for (final group in groups.reversed) {
      final ordinal = fromEnd.update(
        group.signature,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
      final newCount =
          (currentCounts[group.signature] ?? 0) -
          (_previousGroups[group.signature] ?? 0);
      _Batch? match;
      for (final batch in _batches.reversed) {
        if (matched.contains(batch.index) ||
            batch.signature != group.signature) {
          continue;
        }
        final sameObjects =
            batch.calls.length == group.calls.length &&
            List.generate(
              batch.calls.length,
              (i) => i,
            ).every((i) => identical(batch.calls[i].call, group.calls[i]));
        // Identity survives the SDK's normal request projection. A new full
        // protocol occurrence also permits adapters which clone the messages.
        // Replayed older groups must not be mistaken for reused call IDs.
        if (sameObjects || ordinal <= newCount) {
          match = batch;
          break;
        }
      }
      if (match == null) continue;
      matched.add(match.index);
      final used = <int>{};
      for (final invocation in match.calls) {
        for (var i = 0; i < group.results.length; i++) {
          if (used.contains(i) ||
              group.results[i].toolCallId != invocation.call.id) {
            continue;
          }
          used.add(i);
          if (invocation.receiptObserved) break;
          invocation.receiptObserved = true;
          log.recordDeveloper(
            'ai.tool.result',
            operation: operation,
            fields: invocation.metadata,
            data: {
              ...invocation.identity,
              'source': source,
              'receiptAvailable': true,
              'summary': _summary(group.results[i].content),
            },
          );
          break;
        }
      }
    }
    _previousGroups = currentCounts;
  }

  void finish({
    Iterable<coach.LlmMessage> history = const [],
    coach.CoachTurnResult? result,
    String? status,
  }) {
    if (!log.enabled || _finished) return;
    observeMessages(history, source: 'history');
    _finished = true;
    final turnStatus = status ?? result?.status.name ?? 'unavailable';
    for (final batch in _batches) {
      for (final call in batch.calls) {
        if (call.receiptObserved) continue;
        log.recordDeveloper(
          'ai.tool.result',
          operation: operation,
          fields: call.metadata,
          data: {
            ...call.identity,
            'source': result == null ? 'unavailable' : 'sdk_turn_result',
            'receiptAvailable': false,
            'reason': turnStatus == 'cancelled'
                ? 'cancelled_without_observed_receipt'
                : 'sdk_receipt_not_exposed',
            'summary': {
              'turnStatus': turnStatus,
              if (result != null) ...{
                'hasPlan': result.plan != null,
                'hasActions': result.actions != null,
                'hasQuestion': result.question != null,
                if (result.plan != null) 'planId': result.plan!.plan.id,
                if (result.actions != null)
                  'actionCount': result.actions!.items.length,
              },
            },
          },
        );
      }
    }
  }

  static List<Map<String, Object?>> _parameters(Object? raw) => [
    if (raw is Map)
      for (final entry in raw.entries)
        {
          'name': entry.key.toString(),
          if (entry.value is Map)
            for (final field in (entry.value as Map).entries)
              field.key.toString(): field.value
          else
            'value': entry.value,
        },
  ];

  static Map<String, Object?> _summary(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {'format': 'text', 'utf8Bytes': utf8.encode(raw).length};
    }
    if (decoded is! Map) {
      return {
        'format': 'json',
        'type': decoded.runtimeType.toString(),
        'utf8Bytes': utf8.encode(raw).length,
        if (decoded is List) 'itemCount': decoded.length,
      };
    }
    const meaningful = {
      'ok',
      'code',
      'field',
      'expected',
      'actual',
      'fix',
      'reason',
      'message',
      'notes',
      'notices',
      'warnings',
      'errors',
      'deferred',
      'noteTruncated',
      'plan_id',
      'version',
      'estimateMinutes',
      'estimateSec',
      'legacyGoal',
      'stamp',
      'changed',
      'changedFields',
      'valueChangedFields',
      'kept',
      'filter',
      'count',
      'hiddenEquipmentCount',
      'fitLog',
      'durationFeasibility',
    };
    return {
      'format': 'json',
      'utf8Bytes': utf8.encode(raw).length,
      'keys': decoded.keys.map((key) => key.toString()).toList(),
      for (final entry in decoded.entries)
        if (meaningful.contains(entry.key))
          entry.key.toString(): _compact(entry.value),
      if (decoded['params'] is Map)
        'parameters': _parameters(decoded['params']),
      for (final entry in decoded.entries)
        if (entry.value is List && !meaningful.contains(entry.key))
          '${entry.key}Count': (entry.value as List).length,
    };
  }

  // Never slice strings before the logger's secret redaction. Keep small
  // structured summaries; omit large nested catalog/skill bodies entirely.
  static Object? _compact(Object? value, [int depth = 0]) {
    if (value is Map) {
      if (depth >= 3) {
        return {'keys': value.keys.map((k) => k.toString()).toList()};
      }
      return {
        for (final e in value.entries.take(12))
          e.key.toString(): _compact(e.value, depth + 1),
      };
    }
    if (value is List) {
      return [for (final e in value.take(8)) _compact(e, depth + 1)];
    }
    return value;
  }
}

class _Invocation {
  _Invocation(this.call, this.batch, this.ordinal, this.step, this.attempt);
  final coach.LlmToolCall call;
  final int batch;
  final int ordinal;
  final int step;
  final int attempt;
  bool receiptObserved = false;

  Map<String, Object?> get identity => {
    'name': call.name,
    'callId': call.id,
    'batch': batch,
    'ordinal': ordinal,
  };
  Map<String, Object?> get metadata => {
    'kind': call.name,
    'step': step,
    'attempt': attempt,
  };
}

class _Batch {
  _Batch(
    this.index,
    List<coach.LlmToolCall> source, {
    required int step,
    required int attempt,
  }) : calls = [
         for (var i = 0; i < source.length; i++)
           _Invocation(source[i], index, i + 1, step, attempt),
       ];
  final int index;
  final List<_Invocation> calls;
  String get signature => _signature(calls.map((c) => c.call));
}

class _ProtocolGroup {
  _ProtocolGroup(this.calls, this.results);
  final List<coach.LlmToolCall> calls;
  final List<coach.LlmMessage> results;
  String get signature => _signature(calls);
}

String _signature(Iterable<coach.LlmToolCall> calls) => jsonEncode([
  for (final call in calls) [call.id, call.name, call.arguments],
]);

List<_ProtocolGroup> _groups(List<coach.LlmMessage> messages) {
  final groups = <_ProtocolGroup>[];
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    if (message.role != coach.LlmRole.assistant || message.toolCalls.isEmpty) {
      continue;
    }
    final results = <coach.LlmMessage>[];
    for (
      var j = i + 1;
      j < messages.length && messages[j].role == coach.LlmRole.tool;
      j++
    ) {
      results.add(messages[j]);
    }
    groups.add(_ProtocolGroup(message.toolCalls, results));
  }
  return groups;
}
