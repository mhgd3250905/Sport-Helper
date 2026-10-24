// Offline-testable observations for the explicit live Worker smoke only.
import 'dart:convert';

import 'package:ugk_coach/ugk_coach.dart' as coach;

String? _finishReason(String? value) => switch (value) {
  null => null,
  'stop' ||
  'length' ||
  'tool_calls' ||
  'content_filter' ||
  'function_call' => value,
  _ => 'unknown',
};

Map<String, Object?> smokeResponseProtocol(
  int requestIndex,
  coach.LlmResponse response,
) => {
  'requestIndex': requestIndex,
  'reasoningPresent': response.reasoning != null,
  'reasoningLength': response.reasoning?.length,
  'usage': response.usage.toJson(),
  'finishReason': _finishReason(response.finishReason),
  'tools': [for (final call in response.toolCalls) smokeToolSummary(call)],
};

/// SDK response diagnostics retain shapes, counts and hashes, never raw bodies.
Map<String, Object?> smokeErrorProtocol(
  int requestIndex,
  coach.LlmException error,
) => {
  'requestIndex': requestIndex,
  'errorKind': error.kind.name,
  'httpStatus': error.statusCode ?? error.responseDiagnostic?.statusCode,
  'usage': error.usage.toJson(),
  'finishReason': _finishReason(error.finishReason),
  'responseDiagnostic': error.responseDiagnostic?.toJson(),
};

/// Retain protocol labels and action IDs, excluding text, memory and arguments.
Map<String, Object?> smokeToolSummary(coach.LlmToolCall call) {
  const knownTools = {
    'read',
    'ls',
    'check_plan',
    'remember',
    'forget',
    coach.CoachTools.showPlan,
    coach.CoachTools.showActions,
  };
  Object? arguments;
  var validJson = true;
  try {
    arguments = jsonDecode(call.arguments);
  } on FormatException {
    validJson = false;
  }
  final ids = <String>[];
  void visit(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if ((entry.key == 'actionId' || entry.key == 'exerciseId') &&
            entry.value is String) {
          ids.add(entry.value as String);
        } else {
          visit(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  if (const {
    coach.CoachTools.showPlan,
    coach.CoachTools.showActions,
    'check_plan',
  }.contains(call.name)) {
    visit(arguments);
  }
  return {
    'name': knownTools.contains(call.name) ? call.name : 'unknown',
    'argumentsJson': validJson,
    if (ids.isNotEmpty) 'actionIds': ids,
  };
}

/// Count raw proposals, including rejected attempts, only in the current turn.
List<String> smokeUnknownActionIds(
  Iterable<Map<String, Object?>> protocols, {
  required int afterRequest,
  required bool Function(String) containsAction,
}) => [
  for (final protocol in protocols)
    if ((protocol['requestIndex'] as int) > afterRequest)
      for (final tool in protocol['tools'] as List? ?? const [])
        for (final id in (tool as Map)['actionIds'] as List? ?? const [])
          if (!containsAction(id as String)) id,
];

/// Historical 0.3.3 six-case acceptance targets, not global Agent limits.
/// The remember case and explicit actions-card supplement have no speed gate.
List<String> smokePerformanceFailures({
  required String caseId,
  required int steps,
  required int elapsedMs,
  required int totalTokens,
}) {
  const planCases = {
    'core',
    'back-protection',
    'memory-on-plan',
    'memory-off-plan',
  };
  if (planCases.contains(caseId)) {
    return [
      if (steps > 4) '$caseId: steps $steps > 4',
      if (elapsedMs > 60000) '$caseId: elapsedMs $elapsedMs > 60000',
      if (totalTokens > 30000) '$caseId: totalTokens $totalTokens > 30000',
    ];
  }
  if (caseId == 'actions') {
    return [
      if (steps > 2) '$caseId: steps $steps > 2',
      if (elapsedMs > 30000) '$caseId: elapsedMs $elapsedMs > 30000',
    ];
  }
  return [];
}
