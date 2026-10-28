// Explicit three-dialogue live validation; outside the normal test suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

class _Files implements LocalStateStorage {
  _Files(this.root);
  final Directory root;
  File file(String key) => File('${root.path}/$key.json');
  @override
  Future<String?> read(String key) async =>
      file(key).existsSync() ? file(key).readAsStringSync() : null;
  @override
  Future<void> write(String key, String value) async {
    await root.create(recursive: true);
    await file(key).writeAsString(value, flush: true);
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
      'requestBytes': utf8.encode(jsonEncode(inner.buildBody(request))).length,
      'roles': request.messages.map((m) => m.role.name).toList(),
      'hasHistoricalReasoning': request.messages.any(
        (m) => m.reasoning?.isNotEmpty == true,
      ),
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
    'Coach v2: four dialogues with a real process restart',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const phase = String.fromEnvironment('SMARTFIT_SMOKE_PHASE');
      const output = String.fromEnvironment('SMARTFIT_SMOKE_OUTPUT');
      expect(config.token, isNotEmpty);
      expect(config.endpoint, 'https://ai.uuugk.win/v1');
      expect(config.modelName, 'deepseek-flash');
      expect(config.authMode, 'bearer');
      expect(['before_restart', 'after_restart'], contains(phase));
      final root = Directory(output).absolute..createSync(recursive: true);
      final device = await DeviceIdentity(
        _Files(Directory('.buildlog/skill-agent-smoke/device')),
      ).loadOrCreate();
      HttpOverrides.global = _LiveHttp();
      final catalog = (await PoseHubActionLibrary.load()).toAiCatalog();
      final profile = coach.CoachProfile.fromJson(
        jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
      );
      final resultFile = File('${root.path}/results.json');
      final records = <Map<String, dynamic>>[
        if (resultFile.existsSync())
          for (final row
              in (jsonDecode(resultFile.readAsStringSync()) as Map)['cases']
                  as List)
            Map<String, dynamic>.from(row as Map),
      ];
      final engines = <AiChatEngine>[];
      final chats = <ChatController>[];
      Future<(ChatController, AiChatEngine, _Observed, _Files)> create(
        String name,
      ) async {
        final files = _Files(Directory('${root.path}/$name'));
        final store = AppStore(files);
        await store.load();
        if (!store.safetyAccepted) await store.acceptSafety(blocked: false);
        final client = _Observed(
          config.createClient(deviceId: device),
          File('${root.path}/requests-$phase.jsonl'),
        );
        final engine = AiChatEngine(
          local: const AppChatActions(),
          catalog: catalog,
          profile: profile,
          client: client,
          memoryStore: store.aiMemoryStore,
          enableUserMemory: store.aiMemoryEnabled,
        );
        final chat = ChatController(
          engine: engine,
          store: store,
          replyDelay: Duration.zero,
        )..start();
        engines.add(engine);
        chats.add(chat);
        return (chat, engine, client, files);
      }

      Future<void> run(
        String input,
        ChatController chat,
        AiChatEngine engine,
        _Observed client,
      ) async {
        final before = client.calls.length;
        final watch = Stopwatch()..start();
        await chat.send(input);
        await chat.flushPersistence();
        final result = engine.lastResult;
        final calls = client.calls.skip(before).toList();
        final record = <String, dynamic>{
          'input': input,
          'phase': phase,
          'elapsedMs': watch.elapsedMilliseconds,
          'calls': calls.length,
          'requests': calls,
          'status': result?.status.name,
          'hasPlanCard': result?.plan != null,
          'hasRecommendCardData': result?.actions != null,
          'hasQuestion': result?.question != null,
          'hasFailure': result?.status != coach.TurnStatus.ok,
          if (result?.plan != null) 'plan': result!.plan!.plan.toJson(),
          if (result?.actions != null)
            'actionIds': result!.actions!.items.map((i) => i.id).toList(),
          'errorType': result?.error?.runtimeType.toString(),
          'sessionSnapshot': engine.conversation.exportSession().toJson(),
          'sdkRecommendWidget': true,
        };
        records.add(record);
        resultFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'sdk': '32d2839a4edb6d47e5ffe362215ec1a94b208824',
            'baseUrl': config.endpoint,
            'model': config.modelName,
            'auth': config.authMode,
            'maxRetries': 0,
            'cases': records,
          }),
          flush: true,
        );
        stdout.writeln(
          'LIVE_CASE ${jsonEncode({'case': records.length, 'elapsedMs': record['elapsedMs'], 'calls': calls.length, 'status': record['status'], 'plan': record['hasPlanCard'], 'recommendation': record['hasRecommendCardData'], 'failure': record['hasFailure']})}',
        );
      }

      try {
        if (phase == 'before_restart') {
          expect(
            records,
            isEmpty,
            reason: 'Each requested dialogue runs only once.',
          );
          final (chat, engine, client, _) = await create('plan-state');
          await run('在家徒手20分钟练核心', chat, engine, client);
          await run('换一套，缩短到10分钟', chat, engine, client);
          final (recChat, recEngine, recClient, files) = await create(
            'recommend-state',
          );
          await run('推荐几个拉大腿内侧的动作', recChat, recEngine, recClient);
          final state = files.file(AppStore.key);
          File('${root.path}/restart-checkpoint.json').writeAsStringSync(
            jsonEncode({
              'stateFile': state.path,
              'sha256': sha256.convert(state.readAsBytesSync()).toString(),
              'cases': records.length,
              'processId': pid,
            }),
            flush: true,
          );
          stdout.writeln('RESTART_CHECKPOINT_READY');
          // The host terminates this exact process tree after durable saving,
          // then starts after_restart in a new Flutter process.
          await Future<void>.delayed(const Duration(minutes: 10));
          fail(
            'The explicit process-restart harness did not terminate this phase.',
          );
        } else {
          expect(records, hasLength(3));
          final checkpoint =
              jsonDecode(
                    File(
                      '${root.path}/restart-checkpoint.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          expect(pid, isNot(checkpoint['processId']));
          final saved = File(checkpoint['stateFile'] as String);
          expect(
            sha256.convert(saved.readAsBytesSync()).toString(),
            checkpoint['sha256'],
          );
          final (chat, engine, client, _) = await create('recommend-state');
          final snapshot = engine.conversation.exportSession();
          expect(snapshot.recommendations, isNotEmpty);
          expect(chat.messages.any((m) => m.actions != null), isTrue);
          File('${root.path}/restart-restored.json').writeAsStringSync(
            jsonEncode({
              'newProcessId': pid,
              'previousProcessId': checkpoint['processId'],
              'sameSavedBytes': true,
              'restoredRecommendationCount': snapshot.recommendations.length,
              'restoredTask': snapshot.sessionState.task?.toJson(),
            }),
            flush: true,
          );
          await run('把这几个排成15分钟', chat, engine, client);
          expect(records, hasLength(4));
          expect(records[0]['hasPlanCard'], isTrue);
          expect(records[1]['hasPlanCard'], isTrue);
          expect(records[2]['hasRecommendCardData'], isTrue);
          expect(records[3]['hasPlanCard'], isTrue);
          expect((records[1]['plan'] as Map)['targetMinutes'], 10);
          expect((records[3]['plan'] as Map)['targetMinutes'], 15);
          expect(records.every((r) => r['hasFailure'] == false), isTrue);
        }
      } finally {
        for (final chat in chats) {
          await chat.flushPersistence();
          chat.dispose();
        }
        for (final engine in engines) {
          engine.dispose();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 35)),
  );
}
