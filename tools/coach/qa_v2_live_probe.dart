// Opt-in synthetic live conversations through the production SF QA controller.
// Run explicitly with flutter test; never reads a real App/device transcript.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/app_ai_tags.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach/ugk_coach_qa_v2.dart';
import 'package:ugk_coach_chat/ugk_coach_chat.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

const qaProbeModel = 'deepseek-v4.1-flash';
const _sdk = '9dd93163e9f355665e5c923f374c64f03bf65a86';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _LiveHttp extends HttpOverrides {}

/// The concrete client contract must survive observation. In particular, the
/// SDK builds each HTTP body itself; we inspect the same request via buildBody
/// and forward it unchanged. No messages, headers or reasoning are persisted.
class ObservedQaClient implements coach.OpenAiCompatibleClient {
  ObservedQaClient(this.inner);
  final coach.OpenAiCompatibleClient inner;
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
    final body = buildBody(request);
    final thinking = body['thinking'];
    final valid =
        body['model'] == qaProbeModel &&
        body['reasoning_effort'] == 'max' &&
        thinking is Map &&
        thinking['type'] == 'enabled';
    final row = <String, Object?>{
      'call': calls.length + 1,
      'turn': turn,
      'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'model': body['model'],
      'reasoning_effort': body['reasoning_effort'],
      'thinking': {'type': thinking is Map ? thinking['type'] : null},
      'requestContractVerified': valid,
      'bodyBytes': utf8.encode(jsonEncode(body)).length,
      'bodyMeasurement': 'utf8(jsonEncode(OpenAiCompatibleClient.buildBody))',
      'tools': [for (final tool in request.tools) tool.name],
      'transportRetries': config.maxRetries,
    };
    calls.add(row);
    if (!valid) {
      row['outcome'] = 'blocked-before-http';
      throw StateError('QA request model/thinking/max contract changed.');
    }
    final watch = Stopwatch()..start();
    try {
      final response = await inner.complete(request, cancel: cancel);
      row.addAll({
        'outcome': 'response',
        'responseModel': response.model,
        'finishReason': response.finishReason,
        'httpAttempts': response.httpAttempts,
        'usage': response.usage.toJson(),
      });
      return response;
    } on coach.LlmException catch (error) {
      row.addAll({
        'outcome': 'llmException',
        'kind': error.kind.name,
        'statusCode': error.statusCode,
        'httpAttempts': error.httpAttempts,
        'usage': error.usage.toJson(),
      });
      rethrow;
    } on Object catch (error) {
      row.addAll({'outcome': 'exception', 'errorType': '${error.runtimeType}'});
      rethrow;
    } finally {
      row['elapsedMs'] = watch.elapsedMilliseconds;
    }
  }
}

class _Scenario {
  const _Scenario(
    this.id,
    this.input, {
    this.place = '健身房',
    this.equipment = '徒手',
    this.followUp,
  });
  final String id, input, place, equipment;
  final String? followUp;
}

const _scenarios = [
  _Scenario('back-home-bodyweight', '想练背', place: '居家'),
  _Scenario('abs-gym', '想练腹肌'),
  _Scenario('abs-swap-second', '推荐几个练腹肌的动作', followUp: '第二个换掉'),
  _Scenario('shoulder-pain-chest', '肩痛练胸'),
  _Scenario(
    'home-dumbbell-twenty',
    '在家只有哑铃，20 分钟全身',
    place: '居家',
    equipment: '哑铃',
  ),
];

// Supplemental coverage is opt-in and never reruns a failed original case.
const _extraScenarios = [
  _Scenario('equipment-multiselect', '想练背', place: '居家'),
];

/// Simulation policy only: select an option exactly as the model displayed it.
/// Never synthesize a free-text answer to an unexpected open-ended question.
String? selectProbeAnswer(
  CoachQaReply reply, {
  required String place,
  required String equipment,
}) {
  final options = reply.question?.options ?? const <String>[];
  if (options.isEmpty) return null;
  final aliases = switch (reply.askStep) {
    QaAskStep.place => place == '居家' ? ['居家', '在家', '家里'] : [place],
    QaAskStep.equipment => equipment == '徒手' ? ['徒手', '都没有'] : [equipment],
    _ => const <String>[],
  };
  for (final alias in aliases) {
    for (final option in options) {
      if (option.contains(alias)) return option;
    }
  }
  return options.first;
}

Map<String, Object?> qaReplyRecord(CoachQaReply reply) => {
  ...reply.toJson(),
  'usage': reply.usage.toJson(),
  // The free-text form.note and internal reasoning are deliberately excluded.
  'structuredForm': {
    for (final entry in reply.form.entries)
      if (entry.key != 'note') entry.key: entry.value,
  },
  'toolTrace': reply.toolTrace,
  'orderedIds': reply.plan != null
      ? reply.planOrderedIds
      : reply.cards.map((c) => c.id).toList(),
  'planMainIds': reply.planMainIds,
};

QaQuery _scope(CoachQaAgent agent, {Set<String> exclude = const {}}) {
  final s = agent.state;
  final f = s.focus ?? const QaFocus();
  return QaQuery(
    scene: s.place ?? agent.profile.defaultScene,
    equipment: {...s.equipment},
    strict: s.placeKnown && (s.place != 'home' || s.equipmentKnown),
    muscles: {...f.muscles},
    stretchMuscles: {...f.stretchMuscles},
    types: {...f.types},
    goals: {...f.goals},
    roles: {...f.roles},
    patterns: {...f.patterns},
    avoidJoints: {...s.avoidJoints},
    noFloor: s.noFloor,
    smallSpace: s.smallSpace,
    maxImpact: s.quiet ? 'none' : null,
    maxDifficulty: s.easy ? 2 : null,
    targetDifficulty: s.easy ? 1 : 2,
    preferEquipment: s.equipment.difference(const {'mat', 'chair'}),
    exclude: exclude,
  );
}

List<String> _shown(CoachQaAgent agent) => agent.state.lastShown.isNotEmpty
    ? [...agent.state.lastShown]
    : [...?agent.state.lastPlan?.orderedIds];

Map<String, Object?> _turnObservation(
  CoachQaAgent agent,
  CoachQaReply reply,
  List<String> before,
  CoachQaAgent beforeAgent,
) {
  final ordered = reply.plan != null
      ? reply.planOrderedIds
      : reply.cards.map((c) => c.id).toList();
  final scope = _scope(agent);
  final outside = [
    for (final id in ordered)
      if (agent.index[id] == null ||
          !agent.finder.passes(agent.index[id]!, scope))
        id,
  ];
  final intent = reply.form['intent'];
  final replacement = intent == 'swap' && before.length >= 2;
  final inPlan =
      beforeAgent.state.lastShown.isEmpty && beforeAgent.state.lastPlan != null;
  final roles = inPlan
      ? [
          for (final block in beforeAgent.state.lastPlan!.plan.blocks)
            for (final _ in block.items)
              switch (block.type) {
                coach.BlockType.warmup => 'warmup',
                coach.BlockType.cooldown => 'cooldown',
                _ => 'main',
              },
        ]
      : List.filled(before.length, 'main');
  final sessionRegion = {
    for (var i = 0; i < before.length; i++)
      if (roles[i] == 'main') ...?agent.index[before[i]]?.primaryMuscles,
  };
  final candidates = replacement
      ? agent.finder
            .swapCandidates(
              agent.index[before[1]]!,
              _scope(agent, exclude: before.toSet()),
              focus: agent.state.focus?.muscles ?? const {},
              sessionRegion: sessionRegion,
              role: inPlan ? roles[1] : null,
            )
            .map((a) => a.id)
            .toList()
      : null;
  return {
    'sdkFailure': reply.kind == 'error',
    'scope': scope.toJson(),
    'outsideScopeIds': outside,
    if (replacement)
      'replacement': {
        'requestedPosition': 2,
        'requestedRole': roles[1],
        'beforeOrderedIds': before,
        'afterOrderedIds': ordered,
        'sameScopeCandidateIds': candidates,
        'outcome': candidates!.isEmpty && _same(before, ordered)
            ? 'no-eligible-replacement-in-scope'
            : _same(before, ordered)
            ? 'unchanged-review-required'
            : 'changed',
        'onlyRequestedPositionChanged':
            before.length == ordered.length &&
            [
              for (var i = 0; i < before.length; i++)
                if (i != 1) before[i] == ordered[i],
            ].every((v) => v),
      },
    if (intent == 'safety')
      'safety': {
        'intent': intent,
        'avoidJoints': agent.state.avoidJoints.toList(),
        'textRequiresHumanReview': true,
        'shoulderModerateOrHigherIds': [
          for (final id in ordered)
            if (stressLevel(agent.index[id]?.jointStress['shoulder']) >= 2) id,
        ],
      },
    if (reply.planSeconds case final int seconds)
      'duration': {
        'requestedMinutes': agent.state.focus?.minutes,
        'planSeconds': seconds,
        if (agent.state.focus?.minutes case final int minutes)
          'withinSdkTwelvePercent':
              (seconds - minutes * 60).abs() <= minutes * 60 * .12,
        'scopeLimitedShortPlanIsKnownSdkLimitation':
            agent.state.focus?.minutes != null &&
            seconds < agent.state.focus!.minutes! * 60 * .88,
        'nativeTrainingStopwatch': false,
      },
  };
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((v) => v);

/// Raw user-facing text, question/options, cards and plan survive unabridged.
String renderProbeMarkdown(Map<String, Object?> report) {
  final out = StringBuffer('# SF QA v2 real-model conversations\n\n')
    ..writeln('Synthetic independent conversations; no device acceptance.')
    ..writeln(
      'Source: `${report['sourceCommit']}`; SDK: `${report['sdk']}`; model: `${report['model']}`.\n',
    );
  for (final raw in report['conversations'] as List) {
    final conversation = Map<String, Object?>.from(raw as Map);
    out.writeln('## ${conversation['id']}\n');
    out.writeln('Tag coverage: `${conversation['tagCoverage']}`.\n');
    for (final rawTurn in conversation['turns'] as List) {
      final turn = Map<String, Object?>.from(rawTurn as Map);
      out.writeln('### Turn ${turn['turn']}\n\nUser (verbatim):\n');
      out.writeln(turn['input']);
      if (turn['reply'] case final Map reply) {
        out.writeln('\nAssistant text (verbatim):\n');
        out.writeln(reply['text']);
        if (reply['question'] case final Map q) {
          out.writeln('\nQuestion (verbatim):\n\n${q['question']}\n');
          for (final option in q['options'] as List? ?? const []) {
            out.writeln('- $option');
          }
        }
        if (reply['assumption'] case final String assumption) {
          out.writeln('\nAssumption (verbatim):\n\n$assumption');
        }
        out.writeln('\nCards (display order; name/reason verbatim):\n');
        final cards = reply['cards'] as List? ?? const [];
        for (final (index, rawCard) in cards.indexed) {
          final card = rawCard as Map;
          out.writeln(
            '${index + 1}. ${card['name']} (`${card['id']}`) — ${card['why']}',
          );
        }
        if (reply['plan'] != null) {
          out.writeln('\nPlan (complete original JSON):\n\n```json');
          out.writeln(
            const JsonEncoder.withIndent('  ').convert(reply['plan']),
          );
          out.writeln('```\n\nPlan numbering (includes warmup/cooldown):\n');
          for (final (index, id) in (reply['orderedIds'] as List).indexed) {
            out.writeln('${index + 1}. `$id`');
          }
        }
        out.writeln('\nChips (verbatim):\n');
        for (final chip in reply['chips'] as List? ?? const []) {
          out.writeln('- $chip');
        }
        out.writeln('\nSteps / token counts:\n\n```json');
        out.writeln(
          jsonEncode({
            'kind': reply['kind'],
            'steps': reply['steps'],
            'usage': reply['usage'],
            'llmCalls': reply['llmCalls'],
            'ms': reply['ms'],
          }),
        );
        out.writeln('```\n');
      } else {
        out.writeln('\nNo reply: `${turn['errorType']}`.\n');
      }
      if (turn['nativeResult'] != null) {
        out.writeln(
          'Native SDK delivery and display rows (complete):\n\n```json',
        );
        out.writeln(
          const JsonEncoder.withIndent('  ').convert({
            'nativeApi': turn['nativeApi'],
            'result': turn['nativeResult'],
            'selectedOriginalOptions': turn['selectedOriginalOptions'],
            'selectedOriginalChip': turn['selectedOriginalChip'],
            'displayMessages': turn['displayMessages'],
          }),
        );
        out.writeln('```\n');
      }
    }
    out.writeln('Observation (separate from raw dialogue):\n\n```json');
    out.writeln(
      const JsonEncoder.withIndent('  ').convert(conversation['observations']),
    );
    out.writeln('```\n');
  }
  return out.toString();
}

String _redact(String value, String token) =>
    value.replaceAll(token, '[REDACTED]');

void _persist(Directory output, Map<String, Object?> report, String token) {
  File('${output.path}/qa-v2-live.json').writeAsStringSync(
    _redact('${const JsonEncoder.withIndent('  ').convert(report)}\n', token),
    flush: true,
  );
  File(
    '${output.path}/conversations.md',
  ).writeAsStringSync(_redact(renderProbeMarkdown(report), token), flush: true);
}

String _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) throw StateError('Cannot bind source state.');
  return '${result.stdout}'.trimRight();
}

Map<String, Object?> _nativeResultRecord(coach.CoachTurnResult? result) => {
  'status': result?.status.name,
  'steps': result?.steps,
  'usage': result?.usage.toJson(),
  'errorType': result?.error?.runtimeType.toString(),
  'admissionGateRejected':
      result?.error is StateError &&
      result!.error.toString().contains('admission gate'),
  'nullResult': result == null,
};

ChatMessage? _latestQuestion(CoachChatController controller) {
  for (final message in controller.messages.reversed) {
    if (message.qaV2 &&
        message.question != null &&
        controller.canAnswerQuestion(message)) {
      return message;
    }
  }
  return null;
}

String? _originalOption(List<String> options, List<String> aliases) {
  for (final alias in aliases) {
    for (final option in options) {
      if (option.contains(alias)) return option;
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'five native SDK QA conversations and native question/chip/ordinal follow-ups',
    () async {
      const outputPath = String.fromEnvironment('SMARTFIT_LIVE_OUTPUT');
      const source = String.fromEnvironment('SMARTFIT_BUILD_SOURCE');
      const token = String.fromEnvironment('SMARTFIT_AI_TOKEN');
      const scenarioSelection = String.fromEnvironment('SMARTFIT_QA_SCENARIOS');
      final requestedIds = scenarioSelection
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();
      final available = {
        for (final s in [..._scenarios, ..._extraScenarios]) s.id: s,
      };
      if (requestedIds.any((id) => !available.containsKey(id))) {
        throw StateError('Unknown explicit QA scenario ID.');
      }
      final selectedScenarios = requestedIds.isEmpty
          ? _scenarios
          : [for (final id in requestedIds) available[id]!];
      if (outputPath.isEmpty || source.length != 40 || token.isEmpty) {
        throw StateError(
          'Explicit output/source and private runner token required.',
        );
      }
      if (!const bool.fromEnvironment('SMARTFIT_POSEHUB_PACK') ||
          !const bool.fromEnvironment('SMARTFIT_ALPHA_CARDS') ||
          !const bool.fromEnvironment('UGK_INTERNAL_MEDIA_PREVIEW')) {
        throw StateError('Use all three production internal-content flags.');
      }
      if (_git(['rev-parse', 'HEAD']) != source) {
        throw StateError('Source SHA must match current HEAD.');
      }
      final output = Directory(outputPath);
      if (output.existsSync()) {
        throw StateError('Use a fresh output directory.');
      }
      final lock = File('pubspec.lock').readAsStringSync();
      if (RegExp('resolved-ref: "?$_sdk"?').allMatches(lock).length != 5) {
        throw StateError(
          'All five resolved SDK packages must match v0.7.1 source.',
        );
      }
      final config = AiCoachConfig(token: token, modelName: qaProbeModel);
      final report = <String, Object?>{
        'schema': 'smartfit-native-sdk-qa-v2-live-conversations@3',
        'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'sourceCommit': source,
        'sourceWorkingTreeStatus': _git([
          'status',
          '--porcelain=v1',
          '--untracked-files=all',
        ]),
        'sdk': _sdk,
        'model': qaProbeModel,
        'syntheticConversations': true,
        'nativeDevice': false,
        'productionConstructor':
            'createSmartfitChat(AppServices(agentMode: qaV2, appAiTags: await loadAppAiTags()), gateway: observed lease)',
        'nativePath':
            'CoachChatController.send / answerQuestion / answerChoices; SDK admission and ChatMessage rendering',
        'tagsLoading': 'same production loadAppAiTags rootBundle loader',
        'outerRetries': 0,
        'scenarioSelection': [for (final s in selectedScenarios) s.id],
        'supplementalOnly': selectedScenarios.every(
          (s) => _extraScenarios.contains(s),
        ),
        'answerPolicy':
            'original option text; preferred place/equipment, otherwise first model option; open question stops; native multiselect chooses original dumbbell and mat options',
        'conversations': <Map<String, Object?>>[],
        'failures': <String>[],
        'sourceFileSha256': <String, String>{},
      };
      for (final path in [
        'lib/app/app_ai_tags.dart',
        'lib/app/services.dart',
        'lib/app/coach_chat.dart',
        'lib/main.dart',
        'lib/chat/ai_coach_config.dart',
        'assets/coach/ai-tags/actions.json',
        'assets/coach/ai-tags/provenance.json',
        'tools/coach/qa_v2_live_probe.dart',
        'pubspec.yaml',
        'pubspec.lock',
      ]) {
        (report['sourceFileSha256'] as Map)[path] = sha256
            .convert(File(path).readAsBytesSync())
            .toString();
      }
      output.createSync(recursive: true);
      _persist(output, report, token);
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = _LiveHttp();
      addTearDown(() => HttpOverrides.global = previousHttp);
      final (legacy, templates, voices, _) = await AppServices.loadContent();
      final sdkCatalog = await PoseHubActionLibrary.load();
      final testCatalog = AppTestCatalog.fromSdk(sdkCatalog);
      final content = AppTestContent.build(
        catalog: testCatalog,
        legacyLibrary: legacy,
      );
      final profile = coach.CoachProfile.fromJson(
        jsonDecode(await rootBundle.loadString('assets/coach/smartfit.json')),
      );
      final tags = await loadAppAiTags();
      final failures = report['failures'] as List<String>;
      final conversations =
          report['conversations'] as List<Map<String, Object?>>;
      for (final scenario in selectedScenarios) {
        final store = AppStore(_Storage());
        await store.load();
        await store.acceptSafety(blocked: false);
        final services = AppServices(
          library: content.library,
          catalog: templates,
          store: store,
          voiceLibrary: voices,
          voiceOutput: const MutedVoiceOutput(),
          coachCatalog: content.coachCatalog,
          coachProfile: profile,
          testCatalog: testCatalog,
          poseHubCatalog: sdkCatalog,
          agentMode: CoachChatAgentMode.qaV2,
          appAiTags: tags,
          aiConfig: config,
          deviceId: 'smartfit-native-qa-synthetic-${scenario.id}',
          chatReplyDelay: Duration.zero,
        );
        final observed = ObservedQaClient(
          config.createClient(deviceId: services.deviceId!),
        );
        final controller = createSmartfitChat(
          services,
          gateway: CoachGatewayBinding(
            create: () =>
                CoachClientLease.owned(observed, release: observed.close),
          ),
        );
        final turns = <Map<String, Object?>>[];
        final observations = <Map<String, Object?>>[];
        final conversation = <String, Object?>{
          'id': scenario.id,
          'sourceCommit': source,
          'sdk': _sdk,
          'model': qaProbeModel,
          'turns': turns,
          'observations': observations,
          'calls': observed.calls,
        };
        conversations.add(conversation);
        try {
          final started = await controller.start();
          if (!started.ok) {
            throw StateError('Native SDK controller start failed.');
          }
          expect(controller.profile.agentMode, CoachChatAgentMode.qaV2);
          conversation.addAll({
            'tagCoverage': controller.qaAgent.tagCoverage,
            'catalogCount': controller.qaAgent.index.length,
            'taggedCount': controller.qaAgent.index.taggedCount,
            'untaggedIds': controller.qaAgent.index.untaggedIds,
            'initialDisplayMessages': [
              for (final m in controller.messages) m.toJson(),
            ],
          });
          expect(controller.qaAgent.index.length, 211);
          expect(controller.qaAgent.index.taggedCount, 209);
          var input = scenario.input;
          var followUpSent = false;
          var questionCount = 0;
          // Last original scenario gets extra native interactions after its
          // original 20-minute plan: ordinal swap -> actual venue chip ->
          // original home option -> actual dumbbell+mat multiselect.
          var nativeFollowUp = 0;
          ChatMessage? question;
          List<String>? choices;
          var api = 'send';
          var multiselectObserved = false;
          while (true) {
            observed.turn = turns.length + 1;
            final beforeAgent = controller.qaAgent;
            final before = _shown(beforeAgent);
            final previousIds = controller.messages.map((m) => m.id).toSet();
            final turn = <String, Object?>{
              'turn': observed.turn,
              'input': input,
              'nativeApi': api,
              'selectedOriginalOptions': ?choices,
              if (question != null) 'answeredQuestionId': question.id,
            };
            turns.add(turn);
            final result = question == null
                ? await controller.send(input)
                : choices == null
                ? await controller.answerQuestion(question, input)
                : await controller.answerChoices(question, choices);
            question = null;
            choices = null;
            api = 'send';
            turn['nativeResult'] = _nativeResultRecord(result);
            turn['displayMessages'] = [
              for (final m in controller.messages)
                if (!previousIds.contains(m.id)) m.toJson(),
            ];
            if (result?.status != coach.TurnStatus.ok) {
              turn['errorType'] =
                  result?.error?.runtimeType.toString() ?? 'NullNativeResult';
              failures.add(
                '${scenario.id}:native-sdk-result:${result?.status.name ?? 'null'}',
              );
              observations.add({
                'sdkFailure': true,
                'admissionGateRejected':
                    (turn['nativeResult'] as Map)['admissionGateRejected'],
              });
              _persist(output, report, token);
              break;
            }
            final reply = controller.lastQaReply;
            if (reply == null) {
              throw StateError('Successful native turn has no QA reply.');
            }
            turn['reply'] = qaReplyRecord(reply);
            final agent = controller.qaAgent;
            observations.add(
              _turnObservation(agent, reply, before, beforeAgent),
            );
            final assistant = controller.messages.lastWhere((m) => !m.isUser);
            final displayedIds = assistant.plan != null
                ? [
                    for (final block in assistant.plan!.blocks)
                      for (final item in block.items) item.exerciseId,
                  ]
                : assistant.actions?.items.map((item) => item.id).toList() ??
                      <String>[];
            final replyIds = reply.plan != null
                ? reply.planOrderedIds
                : reply.cards.map((c) => c.id).toList();
            turn['displayAndQaOrderEqual'] = _same(displayedIds, replyIds);
            turn['admittedPlan'] = assistant.validatedPlan != null;
            if (!_same(displayedIds, replyIds)) {
              failures.add('${scenario.id}:display-qa-order-mismatch');
            }
            _persist(output, report, token);
            if (reply.kind == 'ask') {
              if (++questionCount > 8) {
                failures.add('${scenario.id}:question-budget-exceeded');
                break;
              }
              question = _latestQuestion(controller);
              if (question == null) {
                throw StateError('Missing answerable native question.');
              }
              if (((scenario.id == 'home-dumbbell-twenty' &&
                          nativeFollowUp == 2) ||
                      (scenario.id == 'equipment-multiselect' &&
                          nativeFollowUp == 0)) &&
                  reply.askStep == QaAskStep.equipment) {
                final options = question.question!.options;
                final dumbbell = _originalOption(options, ['哑铃']);
                final mat = _originalOption(options, ['瑜伽垫']);
                if (!question.question!.multiple ||
                    dumbbell == null ||
                    mat == null) {
                  failures.add(
                    '${scenario.id}:native-multiselect-options-unavailable',
                  );
                  break;
                }
                choices = [dumbbell, mat];
                input = choices.join('、');
                api = 'answerChoices';
                multiselectObserved = true;
              } else {
                final answer = selectProbeAnswer(
                  reply,
                  place:
                      scenario.id == 'equipment-multiselect' &&
                          nativeFollowUp == 2
                      ? '健身房'
                      : scenario.place,
                  equipment: scenario.equipment,
                );
                if (answer == null) {
                  conversation['needsHumanAnswer'] = true;
                  failures.add(
                    '${scenario.id}:open-question-needs-human-answer',
                  );
                  break;
                }
                input = answer;
                api = 'answerQuestion';
              }
            } else if (scenario.followUp != null && !followUpSent) {
              input = scenario.followUp!;
              followUpSent = true;
            } else if (scenario.id == 'equipment-multiselect' &&
                nativeFollowUp == 0) {
              conversation['conditionsBeforeVenueChange'] = reply.conditions;
              final chip = _originalOption(assistant.quickActions, [
                '换场地',
                '换个场地',
                '换个地方',
              ]);
              if (chip == null) {
                turn['quickActionNotEmitted'] = true;
                input = '换场地';
                api = 'typed-send';
              } else {
                turn['selectedOriginalChip'] = chip;
                input = chip;
                api = 'send(original-quickAction)';
              }
              nativeFollowUp = 2;
            } else if (scenario.id == 'home-dumbbell-twenty' &&
                nativeFollowUp == 0) {
              if (reply.plan == null || reply.planOrderedIds.length < 2) {
                failures.add(
                  '${scenario.id}:no-plan-for-native-ordinal-follow-up',
                );
                break;
              }
              conversation['nativeOrdinalPlanRoles'] = [
                for (final block in reply.plan!.blocks)
                  for (final _ in block.items) block.type.name,
              ];
              input = '第二个换掉';
              nativeFollowUp = 1;
            } else if (scenario.id == 'home-dumbbell-twenty' &&
                nativeFollowUp == 1) {
              final chip = _originalOption(assistant.quickActions, [
                '换场地',
                '换个场地',
                '换个地方',
              ]);
              if (chip == null) {
                turn['quickActionNotEmitted'] = true;
                input = '换场地';
                api = 'typed-send';
              } else {
                turn['selectedOriginalChip'] = chip;
                input = chip;
                api = 'send(original-quickAction)';
              }
              nativeFollowUp = 2;
            } else {
              break;
            }
          }
          conversation['allActualRequestsThinkingMax'] =
              observed.calls.isNotEmpty &&
              observed.calls.every((c) => c['requestContractVerified'] == true);
          if (scenario.id == 'home-dumbbell-twenty' ||
              scenario.id == 'equipment-multiselect') {
            conversation['nativeMultiselectObserved'] = multiselectObserved;
            if (!multiselectObserved) {
              failures.add('${scenario.id}:native-multiselect-not-exercised');
            }
          }
          if (scenario.id == 'equipment-multiselect') {
            conversation['finalPlace'] = controller.qaAgent.state.place;
            if (controller.qaAgent.state.place != 'gym') {
              failures.add('${scenario.id}:venue-change-not-completed');
            }
          }
          for (final observation in observations) {
            if ((observation['outsideScopeIds'] as List? ?? const [])
                .isNotEmpty) {
              failures.add('${scenario.id}:outside-scope-ids');
            }
          }
          if (observed.calls.isEmpty) {
            failures.add('${scenario.id}:no-model-calls');
          }
          if (observed.calls.any((c) => c['requestContractVerified'] != true)) {
            failures.add('${scenario.id}:request-contract');
          }
        } on Object catch (error) {
          if (turns.isNotEmpty && !turns.last.containsKey('reply')) {
            turns.last['errorType'] = '${error.runtimeType}';
          }
          conversation['errorType'] = '${error.runtimeType}';
          failures.add('${scenario.id}:exception:${error.runtimeType}');
        } finally {
          await controller.flushPersistence();
          await controller.close();
          controller.dispose();
          _persist(output, report, token);
        }
      }
      report['finishedAtUtc'] = DateTime.now().toUtc().toIso8601String();
      report['automatedStructuralChecksPassed'] = failures.isEmpty;
      report['semanticReviewRequired'] = true;
      report['knownLimitations'] = [
        'No eligible swap in the existing scope is distinct from SDK failure.',
        'Pain-response wording requires human review; this is synthetic input.',
        'Narrow scopes can produce a plan shorter than requested; duration observation is reported separately.',
        'No native-device, large-text or small-screen acceptance is claimed.',
      ];
      _persist(output, report, token);
      expect(
        failures,
        isEmpty,
        reason: 'See complete JSON and conversations.md.',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}
