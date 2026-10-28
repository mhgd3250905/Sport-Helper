// Explicit live-model probe, excluded from the ordinary test suite.
// Run only after building the APK named by SMARTFIT_SCENE_SMOKE_APK_METADATA.
// Configuration and credentials arrive through dart-defines, never local keys.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartfit/app/build_info.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/developer_log_sanitizer.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

const _packages = ['ugk_coach', 'ugk_coach_ui', 'ugk_trainer'];
const _input = '拉伸一下臀部';
const _answer = '在家';

class _Files implements LocalStateStorage {
  _Files(this.root);
  final Directory root;
  @override
  Future<String?> read(String key) async {
    final file = File('${root.path}/$key.json');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await root.create(recursive: true);
    await File('${root.path}/$key.json').writeAsString(value, flush: true);
  }
}

class _LiveHttp extends HttpOverrides {}

class _Observed implements coach.LlmClient {
  _Observed(this.inner, this.write);
  final coach.OpenAiCompatibleClient inner;
  final void Function(Map<String, Object?>) write;
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
    final row = <String, Object?>{'call': calls.length + 1};
    calls.add(row);
    try {
      final response = await inner.complete(request, cancel: cancel);
      row.addAll({
        'toolNames': response.toolCalls.map((call) => call.name).toList(),
        'httpAttempts': response.httpAttempts,
      });
      return response;
    } on coach.LlmException catch (error) {
      row.addAll({
        'errorType': error.runtimeType.toString(),
        'errorKind': error.kind.name,
        'httpStatus': error.statusCode ?? error.responseDiagnostic?.statusCode,
        'subtype': error.responseDiagnostic?.subtype.name,
        'httpAttempts': error.httpAttempts,
      });
      rethrow;
    } on Object catch (error) {
      row['errorType'] = RuntimeLog.errorType(error);
      rethrow;
    } finally {
      row['elapsedMs'] = watch.elapsedMilliseconds;
      write(row);
    }
  }
}

Future<Map<String, dynamic>> _loadApkMetadata(String path, String sdk) async {
  final metadata = Map<String, dynamic>.from(
    jsonDecode(File(path).readAsStringSync()) as Map,
  );
  expect(metadata['source'], 'apk_aapt');
  expect(metadata['packageName'], 'com.ugk.smartfit.internal');
  expect(metadata['versionName'], isA<String>());
  expect(metadata['versionName'], isNot(isEmpty));
  final build = '${metadata['buildNumber'] ?? metadata['versionCode']}';
  expect(build, matches(RegExp(r'^[1-9][0-9]*$')));
  expect('${metadata['versionCode']}', build);
  final apk = File(metadata['apkPath'] as String);
  expect(apk.existsSync(), isTrue, reason: 'The named APK must exist.');
  final digest = await sha256.bind(apk.openRead()).first;
  expect(digest.toString(), metadata['apkSha256']);

  final lock = File('pubspec.lock').readAsLinesSync();
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map;
  for (final name in _packages) {
    final spec = (metadata['sdk'] as Map)[name];
    expect(
      spec,
      isA<Map>(),
      reason: 'APK metadata must identify all SDK pins.',
    );
    final pin = spec as Map;
    expect(pin['commit'] ?? pin['resolved-ref'] ?? pin['ref'], sdk);
    final index = lock.indexOf('  $name:');
    expect(index, greaterThanOrEqualTo(0));
    final block = lock
        .skip(index + 1)
        .takeWhile((line) => line.isEmpty || line.startsWith('    '))
        .join('\n');
    final ref = RegExp(
      r'''^      resolved-ref: ["']?([a-f0-9]{40})["']?\s*$''',
      multiLine: true,
    ).firstMatch(block)?.group(1);
    expect(ref, sdk, reason: 'APK and host SDK pins must match.');
    final package = (config['packages'] as List).cast<Map>().singleWhere(
      (entry) => entry['name'] == name,
    );
    expect(
      package['rootUri'],
      contains(sdk),
      reason: 'Use the immutable Pub cache for the same SDK commit.',
    );
  }
  await AppBuildInfo.initialize(
    load: () async => PackageInfo(
      appName: 'SmartFit',
      packageName: metadata['packageName'] as String,
      version: metadata['versionName'] as String,
      buildNumber: build,
    ),
  );
  expect(AppBuildInfo.buildNumber, build);
  return metadata;
}

bool _asksScene(coach.AskUserQuestion question) =>
    question.focus == 'scene' ||
    question.fields.any((field) => field.key == 'scene') ||
    RegExp(
      r'地点|场景|哪里|哪儿|在哪|何处|什么环境|location|where|scene',
      caseSensitive: false,
    ).hasMatch(question.question);

List<Map<String, dynamic>> _events(RuntimeLog log, String name) => [
  for (final row in (jsonDecode(log.exportJson()) as Map)['events'] as List)
    if ((row as Map)['event'] == name) Map<String, dynamic>.from(row),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'scene is asked before recommending glute stretches',
    () async {
      const config = AiCoachConfig.fromEnvironment();
      const output = String.fromEnvironment('SMARTFIT_SCENE_SMOKE_OUTPUT');
      const sdk = String.fromEnvironment('SMARTFIT_SCENE_SMOKE_SDK_SHA');
      const metadataPath = String.fromEnvironment(
        'SMARTFIT_SCENE_SMOKE_APK_METADATA',
      );
      expect(config.enabled, isTrue, reason: 'Inject credentials externally.');
      expect(config.endpoint, 'https://ai.uuugk.win/v1');
      expect(config.modelName, 'deepseek-flash');
      expect(config.authMode, 'bearer');
      expect(sdk, matches(RegExp(r'^[a-f0-9]{40}$')));
      expect(output, isNotEmpty);
      expect(metadataPath, isNotEmpty);
      final root = Directory(output).absolute;
      expect(
        !root.existsSync() || root.listSync().isEmpty,
        isTrue,
        reason:
            'Use a fresh output directory; do not replay or overwrite evidence.',
      );
      root.createSync(recursive: true);
      final metadata = await _loadApkMetadata(metadataPath, sdk);
      final sanitizer = DeveloperLogSanitizer([config.token]);
      void writeJson(String name, Object? value) =>
          File('${root.path}/$name').writeAsStringSync(
            const JsonEncoder.withIndent(
              '  ',
            ).convert(sanitizer.sanitize(value)),
            flush: true,
          );

      final previousLog = RuntimeLog.instance;
      final previousHttp = HttpOverrides.current;
      final log = RuntimeLog.instance = RuntimeLog(
        enabled: true,
        storage: _Files(Directory('${root.path}/runtime-store')),
        secrets: [config.token],
      );
      await log.initialize();
      log.record(
        'app.start',
        fields: {
          'version': AppBuildInfo.version,
          'versionName': AppBuildInfo.versionName,
          'buildNumber': AppBuildInfo.buildNumber,
          'source': 'apk_aapt',
          'platform': 'host_test',
          'flavor': 'internal',
        },
      );
      final total = Stopwatch()..start();
      final phases = <Map<String, Object?>>[];
      final observability = <String, Object?>{};
      AiChatEngine? engine;
      ChatController? chat;
      _Observed? client;
      var passed = false;
      String? failureType;
      try {
        HttpOverrides.global = _LiveHttp();
        final store = AppStore(_Files(Directory('${root.path}/app-state')));
        await store.load();
        await store.acceptSafety(blocked: false);
        final device = await DeviceIdentity(
          _Files(Directory('${root.path}/device')),
        ).loadOrCreate();
        client = _Observed(config.createClient(deviceId: device), (row) {
          File('${root.path}/requests.jsonl').writeAsStringSync(
            '${jsonEncode(sanitizer.sanitize(row))}\n',
            mode: FileMode.append,
            flush: true,
          );
        });
        engine = AiChatEngine(
          local: const AppChatActions(),
          catalog: (await PoseHubActionLibrary.load()).toAiCatalog(),
          profile: coach.CoachProfile.fromJson(
            jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
          ),
          client: client,
          memoryStore: store.aiMemoryStore,
          enableUserMemory: store.aiMemoryEnabled,
        );
        chat = ChatController(
          engine: engine,
          store: store,
          replyDelay: Duration.zero,
        )..start();
        final liveEngine = engine;
        final liveChat = chat;
        final liveClient = client;
        expect(liveEngine.agent.sessionState.userTurns, isEmpty);
        expect(liveEngine.agent.sessionState.params, isEmpty);
        expect(await store.aiMemoryStore.load(), isEmpty);

        Future<coach.CoachTurnResult?> run(
          String phase,
          String text,
          Future<void> Function() send,
        ) async {
          final before = liveClient.calls.length;
          final watch = Stopwatch()..start();
          String? exceptionType;
          try {
            await send();
            await liveChat.flushPersistence();
          } on Object catch (error) {
            exceptionType = RuntimeLog.errorType(error);
            rethrow;
          } finally {
            final result = liveEngine.lastResult;
            final calls = liveClient.calls.skip(before).toList();
            phases.add({
              'phase': phase,
              'input': text,
              'elapsedMs': watch.elapsedMilliseconds,
              'calls': calls.length,
              'toolNames': [
                for (final call in calls)
                  ...(call['toolNames'] as List? ?? const []),
              ],
              'status': result?.status.name,
              'question': result?.question?.toJson(),
              'hasRecommendCardData': result?.actions != null,
              'hasPlanCard': result?.plan != null,
              'actionIds': result?.actions?.items
                  .map((item) => item.id)
                  .toList(),
              'errorType':
                  exceptionType ?? result?.error?.runtimeType.toString(),
              'requestErrors': [
                for (final call in calls)
                  if (call['errorType'] != null) call,
              ],
            });
            writeJson(
              'snapshot-$phase.json',
              liveEngine.conversation.exportSession().toJson(),
            );
            writeJson('runtime-$phase.json', jsonDecode(log.exportJson()));
          }
          return liveEngine.lastResult;
        }

        final first = await run(
          'before-answer',
          _input,
          () => liveChat.send(_input),
        );
        expect(first?.status, coach.TurnStatus.ok);
        expect(first?.question, isNotNull);
        expect(
          _asksScene(first!.question!),
          isTrue,
          reason:
              'The SDK must ask about location, not infer one from a body part.',
        );
        expect(first.actions, isNull);
        expect(first.plan, isNull);
        expect(liveEngine.agent.sessionState.params['scene'], isNull);
        final pending = liveChat.messages.lastWhere(
          (message) =>
              message.question != null && liveChat.canAnswerQuestion(message),
        );
        final second = await run(
          'after-answer',
          _answer,
          () => liveChat.answerQuestion(pending, _answer),
        );
        expect(second?.status, coach.TurnStatus.ok);
        expect(second?.question, isNull);
        expect(second?.actions, isNotNull);
        expect(second!.actions!.items, isNotEmpty);
        expect(
          liveChat.messages.any((message) => message.actions != null),
          isTrue,
        );
        final scene = liveEngine.agent.sessionState.params['scene'];
        expect(scene?.value, 'home');
        expect(scene?.source, 'user');
        expect(scene?.quote, isNotNull);
        expect(scene!.quote!, isNotEmpty);
        expect(_answer.contains(scene.quote!), isTrue);

        final users = _events(log, 'chat.user');
        final texts = users.map((row) => (row['data'] as Map)['text']).toList();
        expect(texts, [_input, _answer]);
        final params = [
          for (final row in _events(log, 'ai.tool.requested'))
            if ((row['data'] as Map)['name'] == 'set_params')
              row['data'] as Map,
        ];
        expect(params, isNotEmpty);
        for (final call in params) {
          expect(call['argumentsRaw'], isA<String>());
          final fields = (call['arguments'] as Map)['fields'];
          if (fields is! Map) continue;
          for (final field in fields.entries) {
            expect(
              call['parameters'],
              contains(
                equals({
                  'name': field.key,
                  if (field.value is Map)
                    ...field.value as Map
                  else
                    'value': field.value,
                }),
              ),
            );
          }
        }
        final loggedScene = [
          for (final call in params)
            for (final parameter in call['parameters'] as List)
              if (parameter is Map &&
                  parameter['name'] == 'scene' &&
                  parameter['value'] == 'home' &&
                  parameter['source'] == 'user' &&
                  parameter['quote'] is String &&
                  (parameter['quote'] as String).isNotEmpty &&
                  _answer.contains(parameter['quote'] as String))
                parameter,
        ];
        expect(loggedScene, isNotEmpty);
        observability.addAll({
          'userOriginalsObserved': true,
          'setParamsRawAndFieldsObserved': true,
          'sceneUserProvenanceObserved': true,
          'sceneParameters': loggedScene,
        });
        passed = true;
      } on Object catch (error) {
        failureType = RuntimeLog.errorType(error);
        rethrow;
      } finally {
        await chat?.flushPersistence();
        if (engine != null) {
          writeJson(
            'session-snapshot.json',
            engine.conversation.exportSession().toJson(),
          );
        }
        await log.flush();
        writeJson('runtime.json', jsonDecode(log.exportJson()));
        writeJson('summary.json', {
          'schema': 'smartfit-scene-smoke@1',
          'sdk': sdk,
          'source': 'apk_aapt',
          'nativeDevice': false,
          'apkMetadata': metadata,
          'versionName': AppBuildInfo.versionName,
          'buildNumber': AppBuildInfo.buildNumber,
          'baseUrl': config.endpoint,
          'model': config.modelName,
          'auth': config.authMode,
          'freshConversation': true,
          'passed': passed,
          'failureType': failureType,
          'phases': phases,
          'totalElapsedMs': total.elapsedMilliseconds,
          'totalDialogueElapsedMs': phases.fold<int>(
            0,
            (sum, phase) => sum + (phase['elapsedMs'] as int),
          ),
          'totalCalls': client?.calls.length ?? 0,
          'observability': observability,
        });
        chat?.dispose();
        engine?.dispose();
        client?.inner.close();
        HttpOverrides.global = previousHttp;
        RuntimeLog.instance = previousLog;
        stdout.writeln(
          'SCENE_SMOKE ${jsonEncode({'passed': passed, 'elapsedMs': total.elapsedMilliseconds, 'calls': client?.calls.length ?? 0, 'failureType': failureType, 'source': 'apk_aapt', 'nativeDevice': false})}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
