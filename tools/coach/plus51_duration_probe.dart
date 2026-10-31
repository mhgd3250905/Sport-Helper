// Explicit real-model duration gate. It uses the App's admitted catalogue,
// conversation/controller path and SDK engine; it never touches a phone.
import 'dart:convert';
import 'dart:io';

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

const _sdk = '99c14495685f160019e10340ea6f0de6418a65b9';
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
        'tools': response.toolCalls
            .map((tool) => {'name': tool.name, 'arguments': tool.arguments})
            .toList(),
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
    'three real generated durations: 5, 10 and 20 minutes',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const output = String.fromEnvironment('SMARTFIT_LIVE_OUTPUT');
      expect(config.enabled, isTrue);
      expect(config.endpoint, AiCoachConfig.baseUrl);
      expect(output, isNotEmpty);
      final root = Directory(output)..createSync(recursive: true);
      expect(File('${root.path}/summary.json').existsSync(), isFalse);
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
      for (final minutes in [5, 10, 20]) {
        final input =
            '在家徒手$minutes分钟全身训练，初级，没有伤病，没有额外器械。'
            '请直接给一张能按计时或自动计次跟练的完整计划。';
        final store = AppStore(_Memory());
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
        final chat = ChatController(
          engine: engine,
          store: store,
          replyDelay: Duration.zero,
        )..start();
        final watch = Stopwatch()..start();
        final record = <String, Object?>{
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
                  plan.targetMinutes == minutes &&
                  within &&
                  manual.isEmpty &&
                  clock.done,
            });
          } else {
            record['passed'] = false;
            record['messages'] = chat.messages
                .map((message) => message.toJson())
                .toList();
          }
        } on Object catch (error) {
          record.addAll({
            'passed': false,
            'errorType': error.runtimeType.toString(),
          });
        } finally {
          watch.stop();
          record['elapsedMs'] = watch.elapsedMilliseconds;
          record['caseElapsedMicroseconds'] = watch.elapsedMicroseconds;
          record['transportCalls'] = client.calls;
          record.addAll(_callMetrics(client.calls));
          _write(File('${root.path}/plan-$minutes-minutes.json'), record);
          cases.add(record);
          stdout.writeln(
            'DURATION_CASE ${jsonEncode({'minutes': minutes, 'passed': record['passed'], 'coach': record['coachEstimateSeconds'], 'card': record['cardSecondsIncludingPrep'], 'execution': record['executionSecondsIncludingPrep'], 'manualPhases': record['manualWorkPhases'], 'llmCalls': record['llmCallCount'], 'httpAttempts': record['httpAttemptCount'], 'fullTurnMs': record['fullTurnElapsedMs'], 'tokens': record['tokens']})}',
          );
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
        'schema': 'smartfit-plus51-real-duration-probe@2',
        'sdk': _sdk,
        'probeStartedAtUtc': probeStartedAt.toIso8601String(),
        'probeFinishedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'probeElapsedMs': probeWatch.elapsedMilliseconds,
        'caseGenerationCount': cases.length,
        'outerCaseRetries': 0,
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
                  'targetMinutes',
                  'coachEstimateSeconds',
                  'cardSecondsIncludingPrep',
                  'cardLabel',
                  'executionSecondsIncludingPrep',
                  'manualWorkPhases',
                  'withinTenPercent',
                  'passed',
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
      expect(
        cases.every((record) => record['passed'] == true),
        isTrue,
        reason:
            'Every original model result must pass; no target changes or cherry-picking.',
      );
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
