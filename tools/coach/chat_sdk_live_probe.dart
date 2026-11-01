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
const _sdk = 'b025ee88bd1a6d69564ce96a473302739c981c3b';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LiveHttp extends HttpOverrides {}

class _Observed implements coach.LlmClient {
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
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    final watch = Stopwatch()..start();
    final row = <String, Object?>{
      'call': calls.length + 1,
      'turn': turn,
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'three real turns through the SF shared chat module',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const output = String.fromEnvironment('SMARTFIT_LIVE_OUTPUT');
      const source = String.fromEnvironment('SMARTFIT_BUILD_SOURCE');
      if (!config.enabled ||
          config.endpoint != AiCoachConfig.baseUrl ||
          output.isEmpty ||
          source.length != 40) {
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
      HttpOverrides.global = _LiveHttp();
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
        deviceId: 'smartfit-chat-sdk-plus52-validation',
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
        _write(
          File('${root.path}/initial-snapshot.json'),
          controller.exportSnapshot().toJson(),
        );
        for (final (index, input) in _inputs.indexed) {
          observed.turn = index + 1;
          final firstCall = observed.calls.length;
          final watch = Stopwatch()..start();
          final result = await controller.send(input);
          watch.stop();
          final plan = result?.plan?.plan;
          final problems = <String>[];
          Map<String, Object?>? timing;
          if (result?.status != coach.TurnStatus.ok) {
            problems.add('turn_not_ok');
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
          } else if (plan == null || plan.items.isEmpty) {
            problems.add('plan_missing');
          } else {
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
          final row = <String, Object?>{
            'turn': index + 1,
            'input': input,
            'status': result?.status.name,
            'text': result?.text,
            'errorType': result?.error?.runtimeType.toString(),
            'elapsedMs': watch.elapsedMilliseconds,
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
          stdout.writeln(
            'SF shared chat turn ${index + 1}: ${watch.elapsedMilliseconds}ms; ${observed.calls.length - firstCall} calls; passed=${problems.isEmpty}',
          );
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
        timer.stop();
        _write(File('${root.path}/events.json'), events);
        _write(File('${root.path}/storage.json'), storage.values);
        _write(File('${root.path}/summary.json'), {
          'schema': 'smartfit-coach-chat-live@1',
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
          'elapsedMs': timer.elapsedMilliseconds,
          'metrics': _metrics(observed.calls),
          'turns': [
            for (final t in turns) {...t}..remove('snapshot'),
          ],
          'failures': failures,
          'passed': failures.isEmpty && turns.length == 3,
        });
      }
      expect(failures, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
