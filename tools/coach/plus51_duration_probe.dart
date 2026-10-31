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
      'roles': request.messages.map((message) => message.role.name).toList(),
    };
    calls.add(call);
    try {
      final response = await inner.complete(request, cancel: cancel);
      call.addAll({
        'model': response.model,
        'httpAttempts': response.httpAttempts,
        'tools': response.toolCalls
            .map((tool) => {'name': tool.name, 'arguments': tool.arguments})
            .toList(),
      });
      return response;
    } on coach.LlmException catch (error) {
      call.addAll({
        'errorKind': error.kind.name,
        'httpStatus': error.statusCode,
      });
      rethrow;
    } finally {
      call['elapsedMs'] = watch.elapsedMilliseconds;
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
        };
        try {
          await chat.send(input);
          await chat.flushPersistence();
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
          record['elapsedMs'] = watch.elapsedMilliseconds;
          record['transportCalls'] = client.calls;
          _write(File('${root.path}/plan-$minutes-minutes.json'), record);
          cases.add(record);
          stdout.writeln(
            'DURATION_CASE ${jsonEncode({'minutes': minutes, 'passed': record['passed'], 'coach': record['coachEstimateSeconds'], 'card': record['cardSecondsIncludingPrep'], 'execution': record['executionSecondsIncludingPrep'], 'manualPhases': record['manualWorkPhases']})}',
          );
          chat.dispose();
          engine.dispose();
          client.inner.close();
          store.dispose();
        }
      }
      _write(File('${root.path}/summary.json'), {
        'sdk': 'caa6817c51b3cb09c46909288d83aa88bdc2dbd4',
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
