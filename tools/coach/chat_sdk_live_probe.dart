// Explicit live validation of the production SF profile and storage adapters.
// This tool only uses synthetic conversation data and never opens a device.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/domain/plan.dart' as sf;
import 'package:smartfit/domain/session.dart' as sf;
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

const _inputs = [
  '在家拉伸5分钟，入门，徒手和瑜伽垫，重点大腿内侧和髋部，无不适',
  '推荐几个拉大腿内侧的动作',
  '换一套，缩短到3分钟',
];
const _sdk = String.fromEnvironment(
  'SMARTFIT_EXPECT_SDK',
  defaultValue: '693cbc02cdf284163409868e117e438515c6a8d8',
);
const _continueLongSession = bool.fromEnvironment('SMARTFIT_LONG_SESSION');
const _normalTurns = 50;
const _limitTurn = _normalTurns + 1;
const _expectedHardLimitBytes = 256 * 1024;
// The first three inputs above remain the original acceptance conversation.
// Repeat these follow-ups in that same controller until fifty normal turns;
// never reset the controller or apply an outer retry to reach the count.
const _longInputs = [
  '先不改方案，解释一下刚才计划第一个动作怎么做，哪些地方要注意',
  '推荐两个适合入门的大腿内侧拉伸动作',
  '换一套，保持3分钟，还是在家徒手加瑜伽垫，无不适',
  '这套计划中呼吸和发力应当怎么配合',
  '推荐两个放松髋部的动作',
  '换一套，保持3分钟，避免和上一套完全相同',
  '如果拉伸时感觉轻微紧绷，怎样调整到舒适范围，先不改方案',
  '推荐两个适合办公室间隙的大腿内侧拉伸动作',
  '换回在家练的一套3分钟拉伸，徒手和瑜伽垫，入门',
  '帮我解释一下刚才方案的动作顺序理由，先不修改',
  '推荐两个简单的髋部活动度动作',
  '换一套3分钟拉伸，仍然重点大腿内侧和髋部，无不适',
  '这套动作练完以后，明天是否需要休息，先不改方案',
  '推荐两个坐姿放松大腿内侧的动作',
  '换一套3分钟的入门拉伸，仍在家徒手和瑜伽垫',
  '说明一下刚才计划如何避免代偿，保持计划不变',
  '推荐两个适合结束训练后放松髋部的动作',
];
const _limitInput = '继续推荐两个轻松的大腿内侧拉伸动作';
const _turnResultEvent = 'coach_chat.chat.turn.result';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LiveHttp extends HttpOverrides {}

class _Observed implements coach.OpenAiCompatibleClient {
  _Observed(this.inner, this.output);
  final coach.OpenAiCompatibleClient inner;
  final Directory output;
  final calls = <Map<String, Object?>>[];
  int turn = 0;
  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  coach.LlmConfig get config => inner.config;
  @override
  coach.AuthProvider get auth => inner.auth;
  @override
  Map<String, Object?> buildBody(coach.LlmRequest request) =>
      inner.buildBody(request);
  @override
  void close() => inner.close();

  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    final watch = Stopwatch()..start();
    final row = <String, Object?>{
      'call': calls.length + 1,
      'turn': turn,
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'bodyBytes': utf8.encode(jsonEncode(inner.buildBody(request))).length,
      'bodyBytesMeasurement':
          'utf8(jsonEncode(OpenAiCompatibleClient.buildBody))',
      'request': {
        'messages': [for (final m in request.messages) m.toJson()],
        'maxTokens': request.maxTokens,
        'temperature': request.temperature,
        'jsonMode': request.jsonMode,
        'tools': [for (final tool in request.tools) tool.toJson()],
        'toolChoice': request.toolChoice,
      },
    };
    calls.add(row);
    try {
      final result = await inner.complete(request, cancel: cancel);
      row.addAll({
        'outcome': 'response',
        'httpAttempts': result.httpAttempts,
        'model': result.model,
        'finishReason': result.finishReason,
        'usage': result.usage.toJson(),
        'usageLimit':
            'SDK-normalized usage; zero does not prove provider presence',
        'response': {
          'content': result.content,
          'reasoning': result.reasoning,
          'toolCalls': [
            for (final tool in result.toolCalls)
              {'id': tool.id, 'name': tool.name, 'arguments': tool.arguments},
          ],
        },
      });
      return result;
    } on coach.LlmException catch (error) {
      row.addAll({
        'outcome': 'llmException',
        'kind': error.kind.name,
        'statusCode': error.statusCode,
        'httpAttempts': error.httpAttempts,
        'usage': error.usage.toJson(),
        'diagnostic': error.responseDiagnostic?.toJson(),
      });
      rethrow;
    } on Object catch (error) {
      row.addAll({'outcome': 'exception', 'errorType': '${error.runtimeType}'});
      rethrow;
    } finally {
      watch.stop();
      row['elapsedMs'] = watch.elapsedMilliseconds;
      _write(
        File(
          '${output.path}/call-${calls.length.toString().padLeft(2, '0')}.json',
        ),
        row,
      );
    }
  }
}

void _write(File file, Object? value) {
  if (file.existsSync()) throw StateError('Preserve previous evidence.');
  var text = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  const token = String.fromEnvironment('SMARTFIT_AI_TOKEN');
  if (token.isNotEmpty) text = text.replaceAll(token, '[REDACTED]');
  file.writeAsStringSync(text, flush: true);
}

Map<String, Object?> _metrics(List<Map<String, Object?>> calls) {
  final attempts = [
    for (final c in calls)
      if (c['httpAttempts'] case final int n) n,
  ];
  return {
    'llmCalls': calls.length,
    'httpAttempts': attempts.length == calls.length
        ? attempts.fold<int>(0, (a, b) => a + b)
        : null,
    'usage': {
      for (final key in [
        'promptTokens',
        'completionTokens',
        'cachedTokens',
        'reasoningTokens',
      ])
        key: {
          'sdkNormalizedTotal': calls.fold<int>(
            0,
            (sum, c) =>
                sum + (((c['usage'] as Map?)?[key] as num?)?.toInt() ?? 0),
          ),
          'callsWithPositiveValue': calls
              .where((c) => (((c['usage'] as Map?)?[key] as num?) ?? 0) > 0)
              .length,
        },
    },
  };
}

List<Map<String, Object?>> _runtimeEvents(RuntimeLog log) {
  final envelope = jsonDecode(log.exportJson()) as Map<String, dynamic>;
  return [
    for (final event in envelope['events'] as List)
      if (event is Map) Map<String, Object?>.from(event),
  ];
}

List<Map<String, Object?>> _runtimeTurnRows(
  RuntimeLog log, {
  int afterSequence = 0,
}) => [
  for (final event in _runtimeEvents(log))
    if (event['event'] == _turnResultEvent &&
        (event['seq'] as int? ?? 0) > afterSequence)
      event,
];

List<String> _diagnosticProblems(
  coach.CoachTurnResult? result,
  List<Map<String, Object?>> requests,
  List<Map<String, Object?>> logged, {
  required bool expectLimit,
}) {
  final problems = <String>[];
  if (logged.length != 1) {
    problems.add('turn_result_event_count_${logged.length}');
  } else {
    final detail = logged.single['data'];
    if (detail is! Map) {
      problems.add('turn_result_data_missing');
    } else {
      if (!detail.containsKey('errorType')) {
        problems.add('turn_result_error_type_missing');
      }
      if (detail['status'] != result?.status.name ||
          detail['turnId'] != result?.turnId) {
        problems.add('turn_result_identity_mismatch');
      }
      if (detail['errorType'] != result?.error?.runtimeType.toString()) {
        problems.add('turn_result_error_type_mismatch');
      }
      if (jsonEncode(detail['contextRequests']) != jsonEncode(requests)) {
        problems.add('turn_result_context_diagnostics_mismatch');
      }
      if (expectLimit && detail['failureKind'] != 'conversationLimit') {
        problems.add('limit_failure_kind_mismatch');
      }
      if (!expectLimit &&
          result?.status != coach.TurnStatus.ok &&
          detail['failureKind'] is! String) {
        problems.add('failure_kind_missing');
      }
    }
  }
  if (requests.isEmpty && !expectLimit) {
    problems.add('request_bytes_missing');
  }
  for (final request in requests) {
    for (final field in [
      'beforeBytes',
      'afterBytes',
      'softLimitBytes',
      'hardLimitBytes',
      'tailStateBytes',
      'completedTurnsFolded',
      'receiptBodiesFolded',
      'ledgerTurnsCompacted',
      'restoredMessagesFolded',
      'ledgerBytes',
      'seedBytes',
    ]) {
      if (request[field] is! int || (request[field] as int) < 0) {
        problems.add('invalid_context_diagnostic_$field');
      }
    }
    if (request['measurement'] is! String) {
      problems.add('request_byte_measurement_missing');
    }
    if (request['hardLimitBytes'] != _expectedHardLimitBytes) {
      problems.add('unexpected_sdk_hard_limit');
    }
    if (request['fitsHardLimit'] != true ||
        request['afterBytes'] is! int ||
        request['hardLimitBytes'] is! int ||
        (request['afterBytes'] as int) > (request['hardLimitBytes'] as int)) {
      problems.add('request_above_hard_limit');
    }
  }
  return problems;
}

Map<String, Object?> _byteSummary(
  List<Map<String, Object?>> turns,
  List<Map<String, Object?>> calls,
) {
  final requests = [
    for (final turn in turns)
      for (final request in turn['contextRequests'] as List)
        Map<String, Object?>.from(request as Map),
  ];
  int maximum(String field) => requests.fold<int>(
    0,
    (current, request) => (request[field] as int? ?? 0) > current
        ? request[field] as int
        : current,
  );
  return {
    'requests': requests.length,
    'maximumRequestBytes': calls.fold<int>(
      0,
      (current, call) => (call['bodyBytes'] as int) > current
          ? call['bodyBytes'] as int
          : current,
    ),
    'maximumDiagnosedAfterBytes': maximum('afterBytes'),
    'maximumBeforeCompactionBytes': maximum('beforeBytes'),
    'maximumTailStateBytes': maximum('tailStateBytes'),
    'maximumLedgerBytes': maximum('ledgerBytes'),
    'maximumSeedBytes': maximum('seedBytes'),
    'measurements': {
      for (final request in requests) request['measurement'],
    }.toList(),
    'maximumUses':
        'Actual UTF-8 JSON body bytes immediately before HTTP; beforeBytes is separate',
    'allRequestsFitHardLimit':
        requests.isNotEmpty &&
        requests.every((request) => request['fitsHardLimit'] == true),
    'contextCompactionObserved': requests.any(
      (request) =>
          request['folded'] == true ||
          (request['completedTurnsFolded'] as int? ?? 0) > 0 ||
          (request['receiptBodiesFolded'] as int? ?? 0) > 0 ||
          (request['ledgerTurnsCompacted'] as int? ?? 0) > 0 ||
          (request['restoredMessagesFolded'] as int? ?? 0) > 0,
    ),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    _continueLongSession
        ? 'original three turns then same-session fifty and limit boundary'
        : 'three real turns through the SF shared chat module',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const output = String.fromEnvironment('SMARTFIT_LIVE_OUTPUT');
      const source = String.fromEnvironment('SMARTFIT_BUILD_SOURCE');
      if (!config.enabled ||
          config.endpoint != AiCoachConfig.baseUrl ||
          output.isEmpty ||
          source.length != 40 ||
          _sdk.length != 40) {
        throw StateError(
          'An explicit live config, output path and fixed source are required.',
        );
      }
      final root = Directory(output);
      if (root.existsSync()) {
        throw StateError('Use a fresh evidence directory.');
      }
      root.createSync(recursive: true);
      final previousHttp = HttpOverrides.current;
      final previousLog = RuntimeLog.instance;
      final diagnosticStorage = _Storage();
      final runtimeLog = RuntimeLog(
        enabled: true,
        storage: diagnosticStorage,
        encode: (request) async => encodeRuntimeLogSnapshot(request),
      );
      RuntimeLog.instance = runtimeLog;
      await runtimeLog.initialize();
      HttpOverrides.global = _LiveHttp();
      addTearDown(() {
        HttpOverrides.global = previousHttp;
        RuntimeLog.instance = previousLog;
      });
      final storage = _Storage();
      final store = AppStore(storage);
      await store.load();
      await store.acceptSafety(blocked: false);
      final (legacy, templates, voices, _) = await AppServices.loadContent();
      final sdkCatalog = await PoseHubActionLibrary.load();
      final testCatalog = AppTestCatalog.fromSdk(sdkCatalog);
      final content = AppTestContent.build(
        catalog: testCatalog,
        legacyLibrary: legacy,
      );
      final services = AppServices(
        library: content.library,
        catalog: templates,
        store: store,
        voiceLibrary: voices,
        voiceOutput: const MutedVoiceOutput(),
        coachCatalog: content.coachCatalog,
        coachProfile: coach.CoachProfile.fromJson(
          jsonDecode(await rootBundle.loadString('assets/coach/smartfit.json')),
        ),
        testCatalog: testCatalog,
        poseHubCatalog: sdkCatalog,
        chatReplyDelay: Duration.zero,
        deviceId: 'smartfit-chat-sdk-50-turn-validation',
      );
      final observed = _Observed(
        config.createClient(deviceId: services.deviceId!),
        root,
      );
      final controller = createSmartfitChat(
        services,
        gateway: CoachGatewayBinding(
          create: () =>
              CoachClientLease.owned(observed, release: observed.inner.close),
        ),
      );
      final events = <Map<String, Object?>>[];
      final turns = <Map<String, Object?>>[];
      final failures = <String>[];
      final inputs = _continueLongSession
          ? [
              ..._inputs,
              for (
                var index = 0;
                index < _normalTurns - _inputs.length;
                index++
              )
                _longInputs[index % _longInputs.length],
              _limitInput,
            ]
          : _inputs;
      var originalCallCount = 0;
      var originalElapsedMs = 0;
      var originalCompleted = false;
      var runtimePersistenceVerified = false;
      final timer = Stopwatch()..start();
      final subscription = controller.events.listen(
        (e) => events.add({
          'kind': e.kind.name,
          'step': e.step,
          'path': e.path,
          'status': e.status?.name,
          'reason': e.reason?.name,
          'turnId': e.turnId,
        }),
      );
      final native = sf.SessionBuilder(content.library);
      try {
        final started = await controller.start();
        if (!started.ok) {
          throw StateError(
            'SF module failed to initialize: ${started.error.runtimeType}',
          );
        }
        expect(observed.calls, isEmpty);
        expect(controller.profile.allowedActionIds.length, 219);
        expect(controller.catalog.length, 211);
        expect(controller.agent.turnCount, 0);
        expect(controller.agent.history, isEmpty);
        final originalAgent = controller.agent;
        expect(_longInputs.length, 17);
        if (_continueLongSession) expect(inputs.length, _limitTurn);
        _write(
          File('${root.path}/initial-snapshot.json'),
          controller.exportSnapshot().toJson(),
        );
        for (final (index, input) in inputs.indexed) {
          observed.turn = index + 1;
          final firstCall = observed.calls.length;
          final firstDiagnostic =
              controller.agent.contextRequestDiagnostics.length;
          final beforeMessages = controller.messages.map((m) => m.id).toSet();
          final priorEvents = _runtimeEvents(runtimeLog);
          final firstRuntimeSequence = priorEvents.isEmpty
              ? 0
              : priorEvents.last['seq'] as int;
          final watch = Stopwatch()..start();
          final result = await controller.send(input);
          watch.stop();
          final expectLimit = _continueLongSession && index == _normalTurns;
          final contextRequests = [
            for (final diagnostic
                in controller.agent.contextRequestDiagnostics.skip(
                  firstDiagnostic,
                ))
              diagnostic.toJson(),
          ];
          final loggedTurn = _runtimeTurnRows(
            runtimeLog,
            afterSequence: firstRuntimeSequence,
          );
          final newMessages = [
            for (final message in controller.messages)
              if (!beforeMessages.contains(message.id)) message,
          ];
          final plan = result?.plan?.plan;
          final problems = _diagnosticProblems(
            result,
            contextRequests,
            loggedTurn,
            expectLimit: expectLimit,
          );
          final diagnosedBodies = {
            for (final request in contextRequests) request['afterBytes'],
          };
          if (observed.calls
              .sublist(firstCall)
              .any((call) => !diagnosedBodies.contains(call['bodyBytes']))) {
            problems.add('context_after_bytes_do_not_match_http_body');
          }
          Map<String, Object?>? timing;
          Map<String, Object?>? limitBoundary;
          if (!identical(controller.agent, originalAgent)) {
            problems.add('agent_replaced_during_conversation');
          }
          if (expectLimit) {
            final failureMessages = newMessages
                .where(
                  (message) => !message.isUser && message.isPlanningFailure,
                )
                .toList();
            final expectedText =
                controller.profile.strings.conversationLimitReached;
            final textMatches =
                failureMessages.length == 1 &&
                failureMessages.single.text == expectedText &&
                expectedText.contains('新对话') &&
                !expectedText.contains('网络') &&
                !expectedText.contains('不太稳');
            final noModelRequest = observed.calls.length == firstCall;
            if (result?.status != coach.TurnStatus.limitReached) {
              problems.add('fifty_first_turn_not_limit_reached');
            }
            if (!textMatches) {
              problems.add('limit_copy_or_new_chat_guidance_wrong');
            }
            if (!noModelRequest || contextRequests.isNotEmpty) {
              problems.add('limit_turn_unexpected_model_request');
            }
            if (controller.agent.turnCount != _normalTurns) {
              problems.add('limit_turn_changed_conversation_count');
            }
            limitBoundary = {
              'attemptedTurn': _limitTurn,
              'expectedMaximumNormalTurns': _normalTurns,
              'expectedStatus': 'limitReached',
              'expectedFailureKind': 'conversationLimit',
              'expectedText': expectedText,
              'actualFailureMessages': [
                for (final message in failureMessages) message.toJson(),
              ],
              'copyMatchesAndGuidesNewConversation': textMatches,
              'noNetworkMisreport': textMatches,
              'modelRequestMade': !noModelRequest,
              'requestBytes': null,
              'requestBytesReason': 'No request at the SDK conversation limit',
              'conversationResetPerformed': false,
            };
          } else if (result?.status != coach.TurnStatus.ok) {
            problems.add('turn_not_ok');
          }
          if (_continueLongSession &&
              !expectLimit &&
              controller.agent.turnCount != index + 1) {
            problems.add('conversation_turn_count_mismatch');
          }
          if (!expectLimit && observed.calls.length == firstCall) {
            problems.add('successful_turn_without_model_request');
          }
          if (index == 1) {
            if (plan != null || result?.actions?.items.isNotEmpty != true) {
              problems.add('recommendations_missing');
            }
            if (result?.actions case final actions?) {
              if (!controller.profile.allowedActionIds.containsAll(
                actions.items.map((a) => a.id),
              )) {
                problems.add('recommendation_outside_scope');
              }
            }
          } else if (index < 3 && (plan == null || plan.items.isEmpty)) {
            problems.add('plan_missing');
          } else if (index < 3 && plan != null) {
            final target = (index == 0 ? 5 : 3) * 60;
            if (plan.targetMinutes * 60 != target) problems.add('wrong_target');
            if (!controller.profile.allowedActionIds.containsAll(
              plan.exerciseIds,
            )) {
              problems.add('plan_outside_scope');
            }
            final evaluation = coach.evaluatePlanExecutionTiming(
              plan,
              controller.profile.executionTiming,
            );
            final phases = native.phases(
              sf.TrainingPlan.fromJson(plan.toJson()),
            );
            final actual = phases.fold<double>(0, (sum, p) => sum + p.seconds);
            final card = evaluation.totalSeconds;
            final catalogEstimate = const coach.PlanDuration().estimateSeconds(
              plan,
              controller.catalog,
            );
            if ((card - actual).abs() > 1e-9) {
              problems.add('card_player_mismatch');
            }
            for (final seconds in [card, actual, catalogEstimate]) {
              if (seconds < target * .9 || seconds > target * 1.1) {
                problems.add('duration_outside_tolerance');
              }
            }
            timing = {
              'targetSeconds': target,
              'cardSeconds': card,
              'executionIncludingPrepSeconds': actual,
              'catalogEstimateSeconds': catalogEstimate,
              'cardUses': 'SDK toCoachRoutine profile.executionTiming',
              'isEstimate': evaluation.containsManualCounting,
              'manualLabel': evaluation.containsManualCounting ? '估算' : null,
              'manualWorkPhases': [
                for (final phase in phases.where((p) => p.selfPaced))
                  {
                    'actionId': phase.exerciseId,
                    'seconds': phase.seconds,
                    'label': '估算',
                  },
              ],
              'phases': [
                for (final phase in phases)
                  {
                    'kind': phase.kind.name,
                    'seconds': phase.seconds,
                    'actionId': phase.exerciseId,
                    'selfPaced': phase.selfPaced,
                    'block': phase.blockIndex,
                    'set': phase.set,
                    'round': phase.round,
                    'side': phase.side?.name,
                    'segmentId': phase.segmentId,
                  },
              ],
            };
          }
          await controller.flushPersistence();
          await runtimeLog.flush();
          final loggedDetail = loggedTurn.length == 1
              ? loggedTurn.single['data']
              : null;
          final row = <String, Object?>{
            'turn': index + 1,
            'input': input,
            'status': result?.status.name,
            'text': result?.text,
            'errorType': result?.error?.runtimeType.toString(),
            'failureKind': loggedDetail is Map
                ? loggedDetail['failureKind']
                : null,
            'elapsedMs': watch.elapsedMilliseconds,
            'agentTurnCount': controller.agent.turnCount,
            'sameAgentInstance': identical(controller.agent, originalAgent),
            'contextRequests': contextRequests,
            'runtimeTurnEvents': loggedTurn,
            'newMessages': [
              for (final message in newMessages) message.toJson(),
            ],
            'limitBoundary': limitBoundary,
            'plan': plan?.toJson(),
            'actions': [
              for (final a
                  in result?.actions?.items ?? <coach.ValidatedAction>[])
                {'id': a.id, 'note': a.note},
            ],
            'question': result?.question?.toJson(),
            'timing': timing,
            'metrics': _metrics(observed.calls.sublist(firstCall)),
            'issueCodes': {
              for (final r in result?.records ?? <coach.UsageRecord>[])
                ...r.issueCodes,
            }.toList(),
            'snapshot': controller.exportSnapshot().toJson(),
            'failures': problems,
            'passed': problems.isEmpty,
          };
          turns.add(row);
          failures.addAll(problems.map((p) => 'turn${index + 1}:$p'));
          _write(File('${root.path}/turn-${index + 1}.json'), row);
          if (index == 2) {
            originalCallCount = observed.calls.length;
            originalElapsedMs = timer.elapsedMilliseconds;
            originalCompleted = true;
          }
          stdout.writeln(
            'SF shared chat turn ${index + 1}: ${watch.elapsedMilliseconds}ms; ${observed.calls.length - firstCall} calls; passed=${problems.isEmpty}',
          );
          if (_continueLongSession &&
              !expectLimit &&
              result?.status != coach.TurnStatus.ok) {
            // Preserve the first failure rather than retrying or silently
            // replacing the controller to reach a requested turn count.
            break;
          }
        }
      } on Object catch (error) {
        failures.add('exception:${error.runtimeType}');
        rethrow;
      } finally {
        await controller.close();
        await subscription.cancel();
        controller.dispose();
        store.dispose();
        HttpOverrides.global = previousHttp;
        await runtimeLog.flush();
        final restoredLog = RuntimeLog(
          enabled: true,
          storage: diagnosticStorage,
          secrets: [config.token],
          encode: (request) async => encodeRuntimeLogSnapshot(request),
        );
        await restoredLog.initialize();
        runtimePersistenceVerified =
            jsonEncode(_runtimeTurnRows(runtimeLog)) ==
            jsonEncode(_runtimeTurnRows(restoredLog));
        if (!runtimePersistenceVerified) {
          failures.add('runtime_turn_diagnostics_not_persisted');
        }
        timer.stop();
        _write(File('${root.path}/events.json'), events);
        _write(File('${root.path}/storage.json'), storage.values);
        _write(
          File('${root.path}/runtime-log.json'),
          jsonDecode(runtimeLog.exportJson()),
        );
        _write(
          File('${root.path}/runtime-log-restored.json'),
          jsonDecode(restoredLog.exportJson()),
        );
        RuntimeLog.instance = previousLog;
        final firstThree = turns.take(3).toList();
        final originalFailures = <String>[
          for (final turn in firstThree)
            for (final failure in turn['failures'] as List)
              'turn${turn['turn']}:$failure',
          if (!originalCompleted || firstThree.length != 3)
            'original_three_turns_incomplete',
          if (!runtimePersistenceVerified)
            'runtime_turn_diagnostics_not_persisted',
        ];
        final originalCalls = originalCompleted
            ? observed.calls.take(originalCallCount).toList()
            : observed.calls;
        final originalSummary = <String, Object?>{
          'schema': 'smartfit-coach-chat-live@2',
          'source': source,
          'sdk': _sdk,
          'configuredModel': config.modelName,
          'configuredEndpoint': config.endpoint,
          'transportMaxRetries': observed.inner.config.maxRetries,
          'controller':
              'production createSmartfitChat with SF profile and storage bindings',
          'gatewayOverrideOnly': true,
          'syntheticInput': true,
          'deviceOperated': false,
          'sessionCount': 1,
          'outerRetries': 0,
          'inputs': _inputs,
          'elapsedMs': originalCompleted
              ? originalElapsedMs
              : timer.elapsedMilliseconds,
          'metrics': _metrics(originalCalls),
          'bytes': _byteSummary(firstThree, originalCalls),
          'runtimePersistenceVerified': runtimePersistenceVerified,
          'continuedSameSession': _continueLongSession,
          'continuedSummary': _continueLongSession
              ? 'long-session-summary.json'
              : null,
          'turns': [
            for (final t in firstThree) {...t}..remove('snapshot'),
          ],
          'failures': originalFailures,
          'passed': originalFailures.isEmpty && firstThree.length == 3,
        };
        _write(File('${root.path}/summary.json'), originalSummary);
        if (_continueLongSession) {
          final bytes = _byteSummary(turns, observed.calls);
          final normalTurns = turns.take(_normalTurns).toList();
          final normalPassed = normalTurns
              .where((turn) => turn['status'] == 'ok' && turn['passed'] == true)
              .length;
          final limitPassed =
              turns.length == _limitTurn &&
              turns.last['turn'] == _limitTurn &&
              turns.last['passed'] == true;
          if (normalPassed != _normalTurns) {
            failures.add('fifty_turns_not_all_passed');
          }
          if (!limitPassed) failures.add('fifty_first_boundary_not_passed');
          _write(File('${root.path}/long-session-summary.json'), {
            'schema': 'smartfit-coach-chat-same-session-50-plus-limit@1',
            'source': source,
            'sdk': _sdk,
            'sessionCount': 1,
            'sameProductionController': true,
            'sameAgentInstanceAcrossTurns': turns.every(
              (turn) => turn['sameAgentInstance'] == true,
            ),
            'originalThreeSummary': 'summary.json',
            'originalThreePassed': originalSummary['passed'],
            'normalTurnsRequested': _normalTurns,
            'normalTurnsPassed': normalPassed,
            'limitTurn': _limitTurn,
            'limitTurnAttempted': turns.length == _limitTurn,
            'limitBoundaryPassed': limitPassed,
            'fiftyFirstAttempted': turns.length == _limitTurn,
            'fiftyFirstBoundaryPassed': limitPassed,
            'expectedHardLimitBytes': _expectedHardLimitBytes,
            'inputs': inputs,
            'elapsedMs': timer.elapsedMilliseconds,
            'metrics': _metrics(observed.calls),
            'bytes': bytes,
            'runtimePersistenceVerified': runtimePersistenceVerified,
            'turnResultsCaptured': turns.fold<int>(
              0,
              (count, turn) =>
                  count + (turn['runtimeTurnEvents'] as List).length,
            ),
            'runtimeRetention':
                'Production defaults. Each turn JSON preserves its event before retention.',
            'syntheticInput': true,
            'deviceOperated': false,
            'outerRetries': 0,
            'conversationResets': 0,
            'turns': [
              for (final t in turns) {...t}..remove('snapshot'),
            ],
            'failures': failures,
            'passed':
                failures.isEmpty && normalPassed == _normalTurns && limitPassed,
          });
        }
      }
      expect(failures, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: _continueLongSession ? 90 : 25)),
  );
}
