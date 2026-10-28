// Explicit three-dialogue live validation; outside the normal test suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

class _Files implements LocalStateStorage {
  @override
  Future<String?> read(String key) async {
    final file = File('.buildlog/skill-agent-smoke/device/$key.json');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = File('.buildlog/skill-agent-smoke/device/$key.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }
}

class _LiveHttp extends HttpOverrides {}

class _Observed implements coach.LlmClient {
  _Observed(this.inner, this.log);
  final coach.OpenAiCompatibleClient inner;
  final File log;
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
    final entry = <String, Object?>{
      'requestBytes': utf8
          .encode(
            jsonEncode({
              'model': model,
              'messages': request.messages.map((m) => m.toJson()).toList(),
              'tools': request.tools.map((t) => t.toJson()).toList(),
            }),
          )
          .length,
    };
    calls.add(entry);
    try {
      final response = await inner.complete(request, cancel: cancel);
      entry.addAll({
        'model': response.model,
        'httpAttempts': response.httpAttempts,
        'tools': response.toolCalls.map((c) => c.name).toList(),
      });
      return response;
    } on coach.LlmException catch (error) {
      entry.addAll({
        'error': error.kind.name,
        'httpStatus': error.statusCode ?? error.responseDiagnostic?.statusCode,
        'subtype': error.responseDiagnostic?.subtype.name,
        'httpAttempts': error.httpAttempts,
      });
      rethrow;
    } finally {
      entry['elapsedMs'] = watch.elapsedMilliseconds;
      log.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Coach v2: plan, recommendation, then replace and shorten',
    () async {
      const key = String.fromEnvironment('SMARTFIT_AI_TOKEN');
      expect(
        key,
        isNotEmpty,
        reason: 'Explicit local build-time key required.',
      );
      const output = String.fromEnvironment(
        'SMARTFIT_SMOKE_OUTPUT',
        defaultValue: '.buildlog/coach-v2-live',
      );
      final root = Directory(output)..createSync(recursive: true);
      final device = await DeviceIdentity(_Files()).loadOrCreate();
      HttpOverrides.global = _LiveHttp();
      final catalog = (await PoseHubActionLibrary.load()).toAiCatalog();
      final profile = coach.CoachProfile.fromJson(
        jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
      );
      final records = <Map<String, Object?>>[];
      final engines = <AiChatEngine>[];
      (AiChatEngine, _Observed) create() {
        final transport = const AiCoachConfig(
          token: key,
        ).createClient(deviceId: device);
        final client = _Observed(
          transport,
          File('${root.path}/requests.jsonl'),
        );
        final engine = AiChatEngine(
          local: const AppChatActions(),
          catalog: catalog,
          profile: profile,
          client: client,
        );
        engines.add(engine);
        return (engine, client);
      }

      Future<ChatReply> run(
        String input,
        AiChatEngine engine,
        _Observed client,
        ChatState state,
      ) async {
        final before = client.calls.length;
        final watch = Stopwatch()..start();
        final reply = await engine.reply(input, state);
        final result = engine.lastResult;
        final calls = client.calls.skip(before).toList();
        final plan = reply.messages
            .where((m) => m.validatedPlan != null)
            .firstOrNull
            ?.validatedPlan;
        final actions = reply.messages
            .where((m) => m.actions != null)
            .firstOrNull
            ?.actions;
        final record = <String, Object?>{
          'input': input,
          'elapsedMs': watch.elapsedMilliseconds,
          'calls': calls.length,
          'requests': calls,
          'status': result?.status.name,
          'hasPlanCard': plan != null,
          'hasRecommendCardData': actions != null,
          'hasQuestion': reply.messages.any((m) => m.question != null),
          'hasFailure': reply.messages.any((m) => m.isPlanningFailure),
          if (plan != null) 'plan': plan.plan.toJson(),
          if (actions != null)
            'actionIds': actions.items.map((i) => i.id).toList(),
          'errorType': result?.error?.runtimeType.toString(),
          'sdkState': engine.agent.sessionState.toJson(),
        };
        records.add(record);
        File('${root.path}/results.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'sdk': 'adbc90890e4b4f0a5717e902f995059a34e52243',
          'baseUrl': AiCoachConfig.baseUrl,
          'model': AiCoachConfig.model,
            'maxRetries': 0,
            'cases': records,
          }),
          flush: true,
        );
        // A compact result, never response bodies, transport credentials or headers.
        stdout.writeln(
          'LIVE_CASE ${jsonEncode({'input': input, 'elapsedMs': record['elapsedMs'], 'calls': calls.length, 'status': record['status'], 'plan': plan != null, 'recommendation': actions != null, 'failure': record['hasFailure']})}',
        );
        return reply;
      }

      try {
        final (planEngine, planClient) = create();
        final first = await run(
          '在家徒手20分钟练核心',
          planEngine,
          planClient,
          const ChatState(),
        );
        final (recommendEngine, recommendClient) = create();
        await run(
          '推荐几个拉大腿内侧的动作',
          recommendEngine,
          recommendClient,
          const ChatState(),
        );
        await run('换一套，缩短到10分钟', planEngine, planClient, first.state);
      } finally {
        for (final engine in engines) {
          engine.dispose();
        }
      }
      expect(records[0]['hasPlanCard'], isTrue);
      expect(records[1]['hasRecommendCardData'], isTrue);
      expect(records[2]['hasPlanCard'], isTrue);
      expect(records.every((r) => r['hasFailure'] == false), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 22)),
  );
}
