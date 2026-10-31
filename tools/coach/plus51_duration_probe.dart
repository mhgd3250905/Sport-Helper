// Explicit real-model duration gate. It uses the App's admitted catalogue,
// conversation/controller path and SDK engine; it never touches a phone.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/session.dart';
import 'package:smartfit/ui/plan_presentation.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

class _Memory implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LiveHttp extends HttpOverrides {}

const _sdk = '700d0100f1cb42ef122e774a6ee0076d1916b5e5';
const _requestedCases = [
  (id: '5m-01', minutes: 5),
  (id: '5m-02', minutes: 5),
  (id: '5m-03', minutes: 5),
  (id: '10m-01', minutes: 10),
  (id: '20m-01', minutes: 20),
];
const _tokenFields = [
  'inputTokens',
  'outputTokens',
  'totalTokens',
  'cachedInputTokens',
  'reasoningOutputTokens',
];

Map<String, Object?> _tokens(coach.TokenUsage usage) => {
  // The SDK normalizes absent fields to zero. Preserve its values separately;
  // a zero cannot establish that the provider actually supplied that field.
  'inputTokens': usage.promptTokens == 0 ? null : usage.promptTokens,
  'outputTokens': usage.completionTokens == 0 ? null : usage.completionTokens,
  'totalTokens': usage.promptTokens == 0 || usage.completionTokens == 0
      ? null
      : usage.totalTokens,
  'cachedInputTokens': usage.cachedTokens == 0 ? null : usage.cachedTokens,
  'reasoningOutputTokens': usage.reasoningTokens == 0
      ? null
      : usage.reasoningTokens,
  'sdkNormalized': {...usage.toJson(), 'totalTokens': usage.totalTokens},
};

Map<String, Object?> _callMetrics(List<Map<String, Object?>> calls) {
  final attempts = calls.map((call) => call['httpAttempts']).whereType<int>();
  final elapsed = calls.map((call) => call['elapsedMs']).whereType<int>();
  final usage = <String, Object?>{};
  final coverage = <String, Object?>{};
  for (final field in _tokenFields) {
    final values = calls
        .map((call) => (call['tokens'] as Map<String, Object?>?)?[field])
        .whereType<int>()
        .toList();
    final subtotal = values.fold<int>(0, (sum, value) => sum + value);
    usage[field] = values.length == calls.length ? subtotal : null;
    coverage[field] = {
      'observedCalls': values.length,
      'unknownCalls': calls.length - values.length,
      'knownSubtotal': subtotal,
    };
  }
  return {
    'llmCallCount': calls.length,
    'successfulLlmCallCount': calls
        .where((call) => call['outcome'] == 'response')
        .length,
    'failedLlmCallCount': calls
        .where(
          (call) =>
              call['outcome'] == 'llmException' ||
              call['outcome'] == 'unexpectedException',
        )
        .length,
    'unfinishedLlmCallCount': calls
        .where((call) => call['outcome'] == 'inFlight')
        .length,
    'httpAttemptCount': attempts.length == calls.length
        ? attempts.fold<int>(0, (sum, count) => sum + count)
        : null,
    'knownHttpAttemptSubtotal': attempts.fold<int>(
      0,
      (sum, count) => sum + count,
    ),
    'unknownHttpAttemptCallCount': calls.length - attempts.length,
    'callElapsedMsSum': elapsed.length == calls.length
        ? elapsed.fold<int>(0, (sum, value) => sum + value)
        : null,
    'knownCallElapsedMsSubtotal': elapsed.fold<int>(
      0,
      (sum, value) => sum + value,
    ),
    'tokens': usage,
    'tokenCoverage': coverage,
  };
}

Map<String, Object?> _requestJson(coach.LlmRequest request) => {
  'messages': [for (final message in request.messages) message.toJson()],
  'maxTokens': request.maxTokens,
  'temperature': request.temperature,
  'jsonMode': request.jsonMode,
  'tools': [for (final tool in request.tools) tool.toJson()],
  'toolChoice': request.toolChoice,
};

Map<String, Object?> _toolJson(coach.LlmToolCall tool) => {
  'id': tool.id,
  'name': tool.name,
  'arguments': tool.arguments,
};

Map<String, Object?>? _turnResultJson(coach.CoachTurnResult? result) =>
    result == null
    ? null
    : {
        'turnId': result.turnId,
        'status': result.status.name,
        'text': result.text,
        'plan': result.plan?.plan.toJson(),
        'planVersion': result.plan?.version,
        'actions': result.actions == null
            ? null
            : [
                for (final action in result.actions!.items)
                  {'id': action.id, 'note': action.note},
              ],
        'question': result.question?.toJson(),
        'warnings': [for (final issue in result.warnings) issue.toJson()],
        'issues': [for (final issue in result.issues) issue.toJson()],
        'submissions': result.submissions,
        'resubmits': result.resubmits,
        'fallbackReason': result.fallbackReason?.name,
        'leaked': result.leaked,
        'errorType': result.error?.runtimeType.toString(),
        'isPlanningFailure': result.isPlanningFailure,
        'steps': result.steps,
        'reads': result.reads,
        'usage': _tokens(result.usage),
        'records': [
          for (final entry in result.records)
            {
              ...entry.toJson()..remove('errorMessage'),
              if (entry.errorMessage != null)
                'errorMessageSha256': sha256
                    .convert(utf8.encode(entry.errorMessage!))
                    .toString(),
            },
        ],
      };

Map<String, Object?> _eventJson(coach.AgentEvent event) => {
  'atUtc': DateTime.now().toUtc().toIso8601String(),
  'turnId': event.turnId,
  'kind': event.kind.name,
  'step': event.step,
  'path': event.path,
  'status': event.status?.name,
  'attempt': event.attempt,
  'maxAttempts': event.maxAttempts,
  'reason': event.reason?.name,
  'delayMs': event.delay?.inMilliseconds,
  'question': event.question?.toJson(),
  'node': event.node?.toJson(),
  'task': event.task?.toJson(),
};

class _Observed implements coach.LlmClient {
  _Observed(this.inner);
  final coach.OpenAiCompatibleClient inner;
  final calls = <Map<String, Object?>>[];
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    final watch = Stopwatch()..start();
    final call = <String, Object?>{
      'callIndex': calls.length + 1,
      'outcome': 'inFlight',
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'roles': request.messages.map((message) => message.role.name).toList(),
      'request': _requestJson(request),
    };
    calls.add(call);
    try {
      final response = await inner.complete(request, cancel: cancel);
      call.addAll({
        'outcome': 'response',
        'model': response.model,
        'httpAttempts': response.httpAttempts,
        'sdkLatencyMs': response.latency.inMilliseconds,
        'sdkLatencyMicroseconds': response.latency.inMicroseconds,
        'tokens': _tokens(response.usage),
        'finishReason': response.finishReason,
        'response': {
          'content': response.content,
          'reasoning': response.reasoning,
          'toolCalls': [for (final tool in response.toolCalls) _toolJson(tool)],
          'model': response.model,
          'finishReason': response.finishReason,
        },
        'tools': response.toolCalls.map(_toolJson).toList(),
      });
      return response;
    } on coach.LlmException catch (error) {
      call.addAll({
        'outcome': 'llmException',
        'errorKind': error.kind.name,
        'httpStatus': error.statusCode,
        'httpAttempts': error.httpAttempts,
        'sdkLatencyMs': error.latency.inMilliseconds,
        'sdkLatencyMicroseconds': error.latency.inMicroseconds,
        'tokens': _tokens(error.usage),
        'finishReason': error.finishReason,
        if (error.responseDiagnostic != null)
          'responseDiagnostic': error.responseDiagnostic!.toJson(),
      });
      rethrow;
    } on Object catch (error) {
      call.addAll({
        'outcome': 'unexpectedException',
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    } finally {
      watch.stop();
      call['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
      call['elapsedMs'] = watch.elapsedMilliseconds;
      call['elapsedMicroseconds'] = watch.elapsedMicroseconds;
      // SDK latency includes auth/response decoding and any SDK retries. No
      // wire-level timing or provider usage-field presence is exposed here.
      call['wireHttpAttemptTimingsMs'] = null;
    }
  }
}

void _write(File file, Object value) {
  if (file.existsSync()) throw StateError('Preserve existing evidence file.');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'five independent real sessions: 5, 5, 5, 10 and 20 minutes',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const output = String.fromEnvironment('SMARTFIT_LIVE_OUTPUT');
      if (!config.enabled ||
          config.endpoint != AiCoachConfig.baseUrl ||
          output.isEmpty) {
        throw StateError(
          'Explicit live configuration and evidence path required.',
        );
      }
      final root = Directory(output)..createSync(recursive: true);
      if (File('${root.path}/summary.json').existsSync() ||
          _requestedCases.any(
            (entry) => File('${root.path}/plan-${entry.id}.json').existsSync(),
          )) {
        throw StateError('Preserve existing run; never resample or overwrite.');
      }
      final probeStartedAt = DateTime.now().toUtc();
      final probeWatch = Stopwatch()..start();
      HttpOverrides.global = _LiveHttp();
      final fixture = AppTestContent.build(
        catalog: AppTestCatalog.fromSdk(await PoseHubActionLibrary.load()),
        legacyLibrary: ExerciseLibrary([]),
      );
      final profile = coach.CoachProfile.fromJson(
        jsonDecode(await rootBundle.loadString('assets/coach/smartfit.json')),
      );
      final cases = <Map<String, Object?>>[];
      final agentInstances = Set<Object>.identity();
      final storageInstances = Set<Object>.identity();
      for (final entry in _requestedCases) {
        final minutes = entry.minutes;
        final input =
            '在家徒手$minutes分钟全身训练，初级，没有伤病，没有额外器械。'
            '请直接给一张能按计时或自动计次跟练的完整计划。';
        final storage = _Memory();
        final storageInitiallyEmpty = storage.values.isEmpty;
        final storageInstanceIsNew = storageInstances.add(storage);
        final store = AppStore(storage);
        await store.load();
        await store.acceptSafety(blocked: false);
        final client = _Observed(
          config.createClient(deviceId: 'smartfit-plus51-duration-gate'),
        );
        final engine = AiChatEngine(
          local: const AppChatActions(),
          catalog: fixture.coachCatalog,
          profile: profile,
          client: client,
          enableUserMemory: false,
        );
        final agentInstanceIsNew = agentInstances.add(engine.agent);
        final events = <Map<String, Object?>>[];
        final eventSubscription = engine.events.listen(
          (event) => events.add(_eventJson(event)),
        );
        final chat = ChatController(
          engine: engine,
          store: store,
          replyDelay: Duration.zero,
        )..start();
        final priorHistory = [
          for (final message in engine.agent.history) message.toJson(),
        ];
        final priorState = engine.agent.sessionState.toJson();
        final emptyPriorConversation =
            priorHistory.isEmpty &&
            engine.agent.turnCount == 0 &&
            engine.agent.sessionState.userTurns.isEmpty &&
            chat.messages.every((message) => message.greeting);
        final watch = Stopwatch()..start();
        final record = <String, Object?>{
          'caseId': entry.id,
          'caseOrdinal': cases.length + 1,
          'caseFile': 'plan-${entry.id}.json',
          'targetMinutes': minutes,
          'targetSeconds': minutes * 60,
          'input': input,
          'syntheticUserInput': true,
          'modelRequests': true,
          'deviceOperated': false,
          'caseGenerationAttempt': 1,
          'sdkTransportMaxRetries': client.inner.config.maxRetries,
          'sendReturned': false,
          'persistenceFlushed': false,
          'sdkSessionId': null,
          'sdkSessionIdAvailability':
              'CoachAgent/CoachSessionState expose no session identifier; caseId is a host evidence ID, never an invented SDK sessionId.',
          'freshStorageInitiallyEmpty': storageInitiallyEmpty,
          'newStorageInstance': storageInstanceIsNew,
          'newAgentInstance': agentInstanceIsNew,
          'emptyPriorConversation': emptyPriorConversation,
          'independentSessionVerified':
              storageInitiallyEmpty &&
              storageInstanceIsNew &&
              agentInstanceIsNew &&
              emptyPriorConversation,
          'priorSdkHistory': priorHistory,
          'priorSdkSessionState': priorState,
          'priorChatMessages': [
            for (final message in chat.messages) message.toJson(),
          ],
          'clarificationAnsweredByProbe': false,
        };
        try {
          final turnWatch = Stopwatch()..start();
          record['turnStartedAtUtc'] = DateTime.now().toUtc().toIso8601String();
          try {
            try {
              await chat.send(input);
              record['sendReturned'] = true;
            } finally {
              record['userTurnElapsedMs'] = turnWatch.elapsedMilliseconds;
              record['userTurnElapsedMicroseconds'] =
                  turnWatch.elapsedMicroseconds;
            }
            await chat.flushPersistence();
            record['persistenceFlushed'] = true;
          } finally {
            turnWatch.stop();
            record['fullTurnElapsedMs'] = turnWatch.elapsedMilliseconds;
            record['fullTurnElapsedMicroseconds'] =
                turnWatch.elapsedMicroseconds;
            record['turnFinishedAtUtc'] = DateTime.now()
                .toUtc()
                .toIso8601String();
          }
          record['status'] = engine.lastResult?.status.name;
          final messages = chat.messages.where(
            (message) => message.plan != null,
          );
          final plan = messages.lastOrNull?.plan;
          record['admittedPlan'] =
              engine.lastResult?.plan != null && plan != null;
          if (plan != null) {
            final sdkPlan = trainerPlan(plan);
            final builder = SessionBuilder(fixture.library);
            final phases = builder.phases(plan);
            final seconds = builder.totalSeconds(plan);
            final card = planDurationLabel(plan, fixture.library);
            final coachSeconds = const coach.PlanDuration().estimateSeconds(
              sdkPlan,
              fixture.coachCatalog,
            );
            final manual = phases.where(
              (phase) => phase.isWork && phase.selfPaced,
            );
            final clock = SessionEngine(phases);
            var elapsed = 0.0;
            if (manual.isEmpty) {
              for (final phase in phases.where(
                (phase) => phase.kind != PhaseKind.done,
              )) {
                elapsed += phase.seconds;
                clock.update(elapsed);
              }
            }
            final within = (seconds - minutes * 60).abs() <= minutes * 60 * .10;
            final work = <Map<String, Object?>>[
              for (final phase in phases.where((phase) => phase.isWork))
                {
                  'id': phase.exerciseId,
                  'seconds': phase.seconds,
                  'set': phase.set,
                  'sets': phase.sets,
                  'round': phase.round,
                  'rounds': phase.rounds,
                  'side': phase.side?.name,
                  'selfPaced': phase.selfPaced,
                  'reps': phase.reps,
                  'repSeconds': phase.repSeconds,
                  'rhythm': phase.rhythm?.toJson(),
                },
            ];
            record.addAll({
              'plan': plan.toJson(),
              'coachEstimateSeconds': coachSeconds,
              'cardSecondsIncludingPrep': seconds,
              'cardLabel': card,
              'executionSecondsIncludingPrep': seconds,
              'executionSecondsExcludingPrep': builder.planSeconds(plan),
              'preparationSeconds': phases
                  .where((p) => p.kind == PhaseKind.prep)
                  .fold<double>(0.0, (sum, p) => sum + p.seconds),
              'coachToExecutionDifferenceSeconds': seconds - coachSeconds,
              'withinTenPercent': within,
              'manualWorkPhases': manual.length,
              'executionDurationKind': manual.isEmpty ? '自动排程' : '估算',
              'manualStagesCountedAsFailure': false,
              'automaticClockReplayPerformed': manual.isEmpty,
              'estimatedWorkPhases': [
                for (final phase in manual)
                  {
                    'id': phase.exerciseId,
                    'reps': phase.reps,
                    'estimatedSeconds': phase.seconds,
                    'estimatePerRepSeconds':
                        phase.reps == null || phase.reps! <= 0
                        ? null
                        : phase.seconds / phase.reps!,
                    'requiresUserCompletion': true,
                  },
              ],
              'engineFullyFinished': clock.done && !clock.endedEarly,
              'engineElapsedSeconds': elapsed,
              'workPhases': work,
              'phaseSchedule': [
                for (final phase in phases)
                  {
                    'kind': phase.kind.name,
                    'seconds': phase.seconds,
                    'id': phase.exerciseId,
                    'round': phase.round,
                    'side': phase.side?.name,
                  },
              ],
              'passed':
                  engine.lastResult?.plan != null &&
                  engine.lastResult?.status == coach.TurnStatus.ok &&
                  engine.lastResult?.question == null &&
                  plan.targetMinutes == minutes &&
                  within &&
                  (manual.isNotEmpty || (clock.done && !clock.endedEarly)),
            });
          } else {
            record['passed'] = false;
            record['messages'] = chat.messages
                .map((message) => message.toJson())
                .toList();
          }
        } on Object catch (error, stack) {
          record.addAll({
            'passed': false,
            'errorType': error.runtimeType.toString(),
            'errorStackTrace': stack.toString(),
          });
        } finally {
          watch.stop();
          record['elapsedMs'] = watch.elapsedMilliseconds;
          record['caseElapsedMicroseconds'] = watch.elapsedMicroseconds;
          record['transportCalls'] = client.calls;
          record.addAll(_callMetrics(client.calls));
          record['sdkTurnResult'] = _turnResultJson(engine.lastResult);
          record['clarification'] = engine.lastResult?.question?.toJson();
          record['acceptedClarification'] = engine.lastResult?.question != null;
          record['messages'] = [
            for (final message in chat.messages) message.toJson(),
          ];
          record['sdkHistory'] = [
            for (final message in engine.agent.history) message.toJson(),
          ];
          record['sdkSessionState'] = engine.agent.sessionState.toJson();
          record['agentEvents'] = events;
          record['recoveryAnalysis'] = {
            'pendingOfflineAnalysis': true,
            'durationFitFailureTriggerCount': null,
            'redraftAfterDurationFailureCount': null,
            'blockedAskUserCount': null,
            'otherInfeasibleRecoveryCount': null,
            'deduplicationRequired':
                'Scope toolCallId to case and response/assistant batch occurrence; repeated request history is not another execution. IDs can be reused across responses.',
            'receiptSources':
                'Actual request.messages role=tool plus final sdkHistory only. Terminal receipts missing from public history remain unavailable; sdkTurnResult/records are separate evidence, not invented tool receipts.',
            'durationFailureClassification':
                'Only real receipt.code duration_fit_failed; ask_user with that code is a blocked attempt, not another fit failure or delivered clarification. Skip receipts do not prove draft execution.',
          };
          final userTurnMs = record['userTurnElapsedMs'] as int?;
          final fullTurnMs = record['fullTurnElapsedMs'] as int?;
          record['userTurnOver20000Ms'] = userTurnMs == null
              ? null
              : userTurnMs > 20000;
          record['fullTurnOver20000Ms'] = fullTurnMs == null
              ? null
              : fullTurnMs > 20000;
          record['llmCallsOver8'] = client.calls.length > 8;
          record['abnormal'] =
              fullTurnMs == null ||
              fullTurnMs > 20000 ||
              client.calls.length > 8;
          record['abnormalReasons'] = [
            if (fullTurnMs == null) 'full_turn_time_unavailable',
            if (fullTurnMs != null && fullTurnMs > 20000)
              'full_turn_over_20000_ms',
            if (client.calls.length > 8) 'llm_calls_over_8',
          ];
          _write(File('${root.path}/plan-${entry.id}.json'), record);
          cases.add(record);
          stdout.writeln(
            'DURATION_CASE ${jsonEncode({'caseId': entry.id, 'minutes': minutes, 'passed': record['passed'], 'abnormal': record['abnormal'], 'coach': record['coachEstimateSeconds'], 'card': record['cardSecondsIncludingPrep'], 'execution': record['executionSecondsIncludingPrep'], 'manualPhases': record['manualWorkPhases'], 'llmCalls': record['llmCallCount'], 'httpAttempts': record['httpAttemptCount'], 'fullTurnMs': record['fullTurnElapsedMs'], 'tokens': record['tokens']})}',
          );
          await eventSubscription.cancel();
          chat.dispose();
          engine.dispose();
          client.inner.close();
          store.dispose();
        }
      }
      probeWatch.stop();
      final allCalls = [
        for (final record in cases)
          ...(record['transportCalls']! as List<Map<String, Object?>>),
      ];
      _write(File('${root.path}/summary.json'), {
        'schema': 'smartfit-plus51-real-duration-probe@4',
        'sdk': _sdk,
        'probeStartedAtUtc': probeStartedAt.toIso8601String(),
        'probeFinishedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'probeElapsedMs': probeWatch.elapsedMilliseconds,
        'caseGenerationCount': cases.length,
        'requestedCases': [
          for (final entry in _requestedCases)
            {'caseId': entry.id, 'minutes': entry.minutes},
        ],
        'outerCaseRetries': 0,
        'manualStagesCountedAsFailure': false,
        'allIndependentSessions': cases.every(
          (record) => record['independentSessionVerified'] == true,
        ),
        'allPerformanceThresholdsMet': cases.every(
          (record) => record['abnormal'] == false,
        ),
        'abnormalCaseIds': [
          for (final record in cases)
            if (record['abnormal'] == true) record['caseId'],
        ],
        ..._callMetrics(allCalls),
        'metricsSemantics': {
          'httpAttempts':
              'SDK-reported LlmResponse/LlmException.httpAttempts, not a wire-level observer; App transport retries remain unchanged',
          'tokens':
              'SDK-normalized usage; zero is null because provider field presence is not exposed; original normalized values remain in each call.tokens.sdkNormalized',
          'totalTokens':
              'Exact SDK input plus output sum when both are known; cache and reasoning are already included, never added again',
          'tokenCoverage':
              'A complete aggregate is null when any call is unknown; knownSubtotal and observedCalls retain available values without estimating missing calls',
          'userTurnElapsedMs':
              'Await chat.send only, including SDK step retries',
          'fullTurnElapsedMs': 'Await chat.send and chat.flushPersistence',
          'elapsedMs':
              'Entire case through duration validation and execution-clock replay, before writing its evidence file',
          'wireHttpAttemptTimingsMs':
              'Unavailable from SDK public API; null, never inferred from LLM latency',
          'rawProtocol':
              'Public LlmRequest messages/tools and LlmResponse content/reasoning/toolCalls, actual chat messages, sdkTurnResult and public final agent history; private auth headers/configuration are never serialized.',
          'recoveryCounts':
              'Pending exact offline parsing of raw tool receipts by scoped toolCallId; keyword occurrences are not execution counts. Successful terminal TurnResult/records can establish accepted delivery without inventing missing receipts.',
          'abnormal':
              'Primary: fullTurnElapsedMs > 20000 or LLM calls > 8; userTurn > 20000 is also recorded separately. Duration correctness passed is independent of these flags.',
          'manualExecution':
              'Per user instruction, self-paced work phases are labeled 估算 and do not fail duration acceptance. Their scheduled seconds are estimates; automatic natural completion is not claimed.',
        },
        'baseUrl': config.endpoint,
        'model': config.modelName,
        'sameAppCatalogAndExecution': true,
        'catalogLoader':
            'PoseHubActionLibrary.load -> AppTestCatalog.fromSdk -> AppTestContent.build',
        'fixedLeadPreserved': true,
        'evidenceScope':
            'real model generation and SDK execution-clock replay; no device session',
        'allPassed': cases.every((record) => record['passed'] == true),
        'cases': cases
            .map(
              (record) => {
                for (final key in [
                  'caseId',
                  'caseOrdinal',
                  'caseFile',
                  'targetMinutes',
                  'coachEstimateSeconds',
                  'cardSecondsIncludingPrep',
                  'cardLabel',
                  'executionSecondsIncludingPrep',
                  'manualWorkPhases',
                  'executionDurationKind',
                  'automaticClockReplayPerformed',
                  'withinTenPercent',
                  'passed',
                  'independentSessionVerified',
                  'acceptedClarification',
                  'userTurnOver20000Ms',
                  'fullTurnOver20000Ms',
                  'llmCallsOver8',
                  'abnormal',
                  'abnormalReasons',
                  'llmCallCount',
                  'successfulLlmCallCount',
                  'failedLlmCallCount',
                  'unfinishedLlmCallCount',
                  'httpAttemptCount',
                  'knownHttpAttemptSubtotal',
                  'unknownHttpAttemptCallCount',
                  'userTurnElapsedMs',
                  'fullTurnElapsedMs',
                  'elapsedMs',
                  'callElapsedMsSum',
                  'knownCallElapsedMsSubtotal',
                  'caseGenerationAttempt',
                  'sdkTransportMaxRetries',
                  'sendReturned',
                  'persistenceFlushed',
                  'tokens',
                  'tokenCoverage',
                ])
                  key: record[key],
              },
            )
            .toList(),
      });
      expect(cases, hasLength(_requestedCases.length));
      expect(
        cases.every((record) => record['independentSessionVerified'] == true),
        isTrue,
      );
      expect(
        cases.every((record) => record['passed'] == true),
        isTrue,
        reason:
            'Every original model result must pass; no target changes or cherry-picking.',
      );
    },
    timeout: const Timeout(Duration(minutes: 45)),
  );
}
