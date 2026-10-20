import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/domain/session.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// Deliberately ignores cancellation to model a response already queued by
/// a provider. App turn isolation must reject it even if transport is late.
class _LateClient implements coach.LlmClient {
  final started = Completer<void>();
  final late = Completer<coach.LlmResponse>();
  final requests = <coach.LlmRequest>[];
  coach.CancelToken? token;
  @override
  String get model => 'late-test-model';
  @override
  coach.Pricing? get pricing => null;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) {
    requests.add(request);
    token = cancel;
    if (requests.length == 1) {
      started.complete();
      return late.future;
    }
    return Future.value(
      const coach.LlmResponse(content: '{"kind":"reply","text":"新的回复"}'),
    );
  }
}

/// Loopback HTTP exercises the SDK's actual OpenAI wire parser and abort
/// trigger without any key, external service, or new test dependency.
class _Gateway {
  _Gateway(this.server);
  final HttpServer server;
  final bodies = <Map<String, dynamic>>[];
  final sockets = <Socket>[];
  final requestStarted = Completer<void>();
  final aborted = Completer<void>();

  static Future<_Gateway> start(
    List<Object> envelopes, {
    bool hold = false,
    int status = HttpStatus.ok,
  }) async {
    final gateway = _Gateway(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    gateway.server.listen((request) async {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      gateway.bodies.add(body);
      if (!gateway.requestStarted.isCompleted) {
        gateway.requestStarted.complete();
      }
      if (status != HttpStatus.ok) {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'error': {'message': 'test quota exceeded'},
          }),
        );
        await request.response.close();
        return;
      }
      if (hold) {
        final socket = await request.response.detachSocket(writeHeaders: false);
        gateway.sockets.add(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!gateway.aborted.isCompleted) gateway.aborted.complete();
          },
          onError: (Object _) {
            if (!gateway.aborted.isCompleted) gateway.aborted.complete();
          },
        );
        return;
      }
      final envelope = envelopes[gateway.bodies.length - 1];
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'model': 'loopback-test',
          'choices': [
            {
              'message': {
                'content': envelope is String ? envelope : jsonEncode(envelope),
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      await request.response.close();
    });
    return gateway;
  }

  coach.OpenAiCompatibleClient client() => coach.OpenAiCompatibleClient(
    config: coach.LlmConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      model: 'loopback-test',
      timeout: const Duration(seconds: 2),
      maxRetries: 0,
    ),
  );

  Future<void> close() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close(force: true);
  }
}

void main() {
  final library = loadLibrary();
  final packs = loadPacksSync();
  final catalog = const coach.DrillPackAdapter().build(
    version: 'smartfit-test-assets',
    packs: {for (final pack in packs.exercises) pack.id: pack.json},
  );
  late coach.CoachProfile profile;

  setUpAll(() {
    profile = coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    );
  });

  RuleChatEngine local() => RuleChatEngine(
    lib: library,
    templates: TemplatePlanGenerator(lib: library, catalog: loadCatalog()),
  );

  AiChatEngine engine(coach.LlmClient client, {Duration? deadline}) {
    final result = AiChatEngine(
      local: local(),
      catalog: catalog,
      profile: profile,
      client: client,
      turnTimeout: deadline ?? const Duration(seconds: 75),
    );
    addTearDown(result.dispose);
    return result;
  }

  TrainingPlan plan({
    String id = 'ai-plan-one',
    List<String> ids = const ['h-calf-raise'],
  }) => TrainingPlan(
    id: id,
    source: 'ai',
    title: 'AI 徒手训练',
    summary: '按已确认条件编排。',
    goal: 'fullbody',
    scene: 'home',
    equipment: const [],
    level: 1,
    targetMinutes: 10,
    blocks: [
      PlanBlock(
        id: 'main',
        name: '主训练',
        type: BlockType.main,
        rounds: 1,
        restBetweenRoundsSeconds: 0,
        items: [
          for (final id in ids)
            PlanItem(
              exerciseId: id,
              mode: library.tryGet(id)?.dose.mode ?? DoseMode.reps,
              sets: 1,
              reps: library.tryGet(id)?.dose.mode == DoseMode.time ? null : 10,
              workSeconds: library.tryGet(id)?.dose.mode == DoseMode.time
                  ? 30
                  : null,
              perSide: library.tryGet(id)?.unilateral ?? false,
              restSeconds: 10,
            ),
        ],
      ),
    ],
  );

  Map<String, Object?> envelope({TrainingPlan? value}) => {
    'kind': 'plan',
    'text': '按你的条件排好了。',
    'plan': (value ?? plan()).toJson(),
  };

  String texts(ChatReply reply) => reply.messages.map((m) => m.text).join('\n');
  TrainingPlan? replyPlan(ChatReply reply) =>
      reply.messages.map((m) => m.plan).whereType<TrainingPlan>().firstOrNull;

  void expectLocalPreserved(ChatReply actual, ChatReply expected) {
    expect(actual.state.pending.toString(), expected.state.pending.toString());
    expect(actual.state.asked, expected.state.asked);
    expect(actual.state.safetyBlocked, expected.state.safetyBlocked);
    expect(actual.state.plan?.toJson(), expected.state.plan?.toJson());
    expect(
      actual.state.request?.toString(),
      expected.state.request?.toString(),
    );
    expect(actual.suggestions, expected.suggestions);
    expect(actual.action, expected.action);
    for (final message in expected.messages) {
      expect(actual.messages.any((m) => m.text == message.text), isTrue);
      expect(
        actual.messages.expand((m) => m.options).map((o) => o.toJson()),
        containsAll(message.options.map((o) => o.toJson())),
      );
    }
  }

  test(
    'SDK reply and ask reach App bubbles while command-shaped options are removed',
    () async {
      final client = coach.FakeLlmClient([
        {'kind': 'reply', 'text': '动作慢一点，保持自然呼吸。'},
        {
          'kind': 'ask',
          'text': '想在哪儿练？',
          'options': ['在家', '@drawer', ' @saved:unsafe', '办公室'],
        },
      ], latency: Duration.zero);
      final ai = engine(client);
      final answer = await ai.reply('训练时怎么呼吸更舒服？', const ChatState());
      expect(texts(answer), contains('动作慢一点，保持自然呼吸。'));
      expect(answer.aiTurn, isTrue);
      final ask = await ai.reply('帮我安排一下', answer.state);
      expect(texts(ask), contains('想在哪儿练？'));
      final options = ask.messages.expand((m) => m.options).toList();
      expect(options.map((o) => o.value), ['在家', '办公室']);
      expect(options.any((o) => o.isCommand), isFalse);
      expect(ask.action, isNull);
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      expect(client.requests, hasLength(2));
    },
  );

  test(
    'validated AI plan starts the shared engine and survives App saved-plan reload',
    () async {
      final client = coach.FakeLlmClient([envelope()], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      final chosen = replyPlan(reply)!;
      expect(chosen.source, 'ai');
      expect(
        PlanValidator(library).validate(chosen, reply.state.request),
        isEmpty,
      );
      final phases = SessionBuilder(library).phases(chosen);
      final session = SessionEngine(phases);
      session.update(
        phases.fold<double>(0, (total, phase) => total + phase.seconds) + 1,
      );
      expect(session.done, isTrue);
      expect(session.completedExercises, chosen.items.length);
      final storage = _Storage();
      final store = AppStore(storage);
      await store.savePlan(chosen);
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(reloaded.savedPlans.single.plan.toJson(), chosen.toJson());
      expect(reply.state.plan?.id, chosen.id);
      expect(ai.lastFallbackReason, isNull);
    },
  );

  test(
    'unknown ids, unavailable gear and protected knees are sent back together for one rewrite',
    () async {
      final invalid = plan(ids: ['unknown-drill', 'h-db-row', 'h-squat']);
      final client = coach.FakeLlmClient([
        envelope(value: invalid),
        envelope(),
      ], latency: Duration.zero);
      final ai = engine(client);
      final reply = await ai.reply('在家 10 分钟练全身，徒手，保护膝', const ChatState());
      expect(ai.lastOutcome, coach.TurnOutcome.rewritten);
      expect(client.requests, hasLength(2));
      final feedback = client.requests.last.messages.last.content;
      expect(feedback, contains('unknown-drill'));
      expect(feedback, contains('h-db-row'));
      expect(feedback, contains('h-squat'));
      expect(feedback, contains('E_EQUIP'));
      expect(feedback, contains('E_AVOID'));
      expect(replyPlan(reply)!.exerciseIds, {'h-calf-raise'});
      expect(replyPlan(reply)!.avoid, contains('膝'));
    },
  );

  test(
    'two invalid HTTP outputs make exactly two calls and preserve the complete local follow-up',
    () async {
      final invalid = envelope(value: plan(ids: ['unknown-drill']));
      final gateway = await _Gateway.start([invalid, invalid]);
      addTearDown(gateway.close);
      final client = gateway.client();
      addTearDown(client.close);
      final ai = engine(client);
      const state = ChatState();
      final expected = await local().reply('在家练全身', state);
      final reply = await ai.reply('在家练全身', state);
      expect(gateway.bodies, hasLength(2));
      expect(ai.lastOutcome, coach.TurnOutcome.fallback);
      expect(ai.lastFallbackReason, coach.FallbackReason.invalidOutput);
      expect(texts(reply), contains('AI 暂时不可用'));
      expectLocalPreserved(reply, expected);
      expect(reply.state.pending, isNotNull);
      expect(reply.messages.expand((m) => m.options), isNotEmpty);
    },
  );

  test(
    'offline and request timeout each fall back once without model rewrites',
    () async {
      for (final pair in [
        (coach.LlmErrorKind.network, coach.FallbackReason.offline),
        (coach.LlmErrorKind.timeout, coach.FallbackReason.timeout),
      ]) {
        final client = coach.FakeLlmClient([
          coach.LlmException(pair.$1, 'test-unavailable'),
        ], latency: Duration.zero);
        final ai = engine(client);
        final expected = await local().reply('在家练全身', const ChatState());
        final reply = await ai.reply('在家练全身', const ChatState());
        expect(client.requests, hasLength(1));
        expect(ai.lastFallbackReason, pair.$2);
        expectLocalPreserved(reply, expected);
      }
    },
  );

  test(
    'App commands, recalled plans, history, red flags and blocked safety stay local',
    () async {
      final client = coach.FakeLlmClient([], latency: Duration.zero);
      final ai = engine(client);
      final savedPlan = plan();
      final state = ChatState(
        lastPlan: savedPlan,
        saved: [
          SavedPlan(
            id: 'saved-one',
            name: '我的训练',
            plan: savedPlan,
            savedAt: DateTime(2026, 10, 20),
          ),
        ],
        history: [
          WorkoutLog(
            title: '昨天训练',
            at: DateTime(2026, 10, 19),
            minutes: 10,
            completed: 1,
            total: 1,
          ),
        ],
      );
      for (final input in [
        '看看动作库',
        '@saved:saved-one',
        '我的计划',
        '上次练了什么',
        '上次那个',
        '换浅色',
        '胸口疼',
      ]) {
        expectLocalPreserved(
          await ai.reply(input, state),
          await local().reply(input, state),
        );
        expect(client.requests, isEmpty, reason: 'App-owned input: $input');
      }
      final blocked = state.copyWith(safetyBlocked: true);
      expectLocalPreserved(
        await ai.reply('在家 10 分钟练全身，徒手', blocked),
        await local().reply('在家 10 分钟练全身，徒手', blocked),
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'follow-up conditions and the previous full plan survive a shorter-plan request',
    () async {
      final client = coach.FakeLlmClient([
        {
          'kind': 'ask',
          'text': '有几分钟？',
          'options': ['10 分钟', '20 分钟'],
        },
        envelope(),
        envelope(value: plan(id: 'ai-plan-shorter')),
      ], latency: Duration.zero);
      final ai = engine(client);
      // The App controller supplies rendered chat history, including the
      // current user message. Exercise the engine with that same contract.
      final history = <ChatMessage>[];
      var state = const ChatState();
      Future<ChatReply> turn(String text) async {
        history.add(
          ChatMessage(
            id: 'user-${history.length}',
            role: ChatRole.user,
            at: DateTime(2026, 10, 20),
            text: text,
            aiVisible: true,
          ),
        );
        final reply = await ai.reply(
          text,
          state.copyWith(recentMessages: List.of(history)),
        );
        state = reply.state;
        for (final message in reply.messages) {
          history.add(
            ChatMessage(
              id: 'bot-${history.length}',
              role: ChatRole.assistant,
              at: DateTime(2026, 10, 20),
              text: message.text,
              aiVisible: true,
              options: message.options,
              plan: message.plan,
              request: message.request,
            ),
          );
        }
        return reply;
      }

      await turn('在家练全身，保护膝');
      final second = await turn('10 分钟，徒手');
      expect(replyPlan(second), isNotNull);
      final followup = client.requests[1].messages
          .map((m) => m.content)
          .join('\n');
      expect(followup, contains('在家练全身'));
      expect(followup, contains('膝'));
      expect(second.state.request!.scene, 'home');
      expect(second.state.request!.minutes, 10);
      expect(second.state.request!.avoid, contains('膝'));
      final third = await turn('再短一点');
      final previousPlan = client.requests[2].messages
          .where((m) => m.role == coach.LlmRole.assistant)
          .map((m) => m.content)
          .join('\n');
      expect(previousPlan, contains(replyPlan(second)!.id));
      expect(previousPlan, contains('"blocks"'));
      expect(previousPlan, contains('h-calf-raise'));
      expect(replyPlan(third)!.id, isNot(replyPlan(second)!.id));
      expect(replyPlan(third)!.targetMinutes, 7);
      expect(replyPlan(third)!.exerciseIds, {'h-calf-raise'});
      expect(client.requests, hasLength(3));
    },
  );

  test(
    'cancelPending returns promptly and never remembers an ignored late plan',
    () async {
      final client = _LateClient();
      final ai = engine(client);
      final pending = ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      await client.started.future;
      ai.cancelPending();
      final cancelled = await pending.timeout(const Duration(seconds: 1));
      expect(client.token?.isCancelled, isTrue);
      expect(replyPlan(cancelled), isNull);
      expect(ai.lastOutcome, coach.TurnOutcome.cancelled);
      final latePlan = TrainingPlan.fromJson({
        ...plan().toJson(),
        'title': '晚到取消训练，不应进入任何历史',
      });
      client.late.complete(
        coach.LlmResponse(content: jsonEncode(envelope(value: latePlan))),
      );
      await Future<void>.delayed(Duration.zero);
      final next = await ai.reply('有什么建议？', cancelled.state);
      expect(replyPlan(next), isNull);
      final history = client.requests.last.messages
          .map((m) => m.content)
          .join('\n');
      expect(history, isNot(contains('晚到取消训练，不应进入任何历史')));
      expect(texts(next), contains('新的回复'));
    },
  );

  test(
    'the total turn deadline aborts actual HTTP and falls back without a late plan',
    () async {
      final gateway = await _Gateway.start([], hold: true);
      addTearDown(gateway.close);
      final client = gateway.client();
      addTearDown(client.close);
      final ai = engine(client, deadline: const Duration(milliseconds: 150));
      final pending = ai.reply('在家练全身', const ChatState());
      await gateway.requestStarted.future.timeout(const Duration(seconds: 1));
      final reply = await pending.timeout(const Duration(seconds: 2));
      expect(ai.lastFallbackReason, coach.FallbackReason.timeout);
      expect(replyPlan(reply), isNull);
      expect(texts(reply), contains('AI 暂时不可用'));
      await gateway.aborted.future.timeout(const Duration(seconds: 1));
      expect(gateway.bodies, hasLength(1));
    },
  );

  test(
    'disposing a pending engine cancels it and drops the late reply',
    () async {
      final client = _LateClient();
      final ai = engine(client);
      final pending = ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      await client.started.future;
      ai.dispose();
      final reply = await pending.timeout(const Duration(seconds: 1));
      expect(client.token?.isCancelled, isTrue);
      expect(replyPlan(reply), isNull);
      client.late.complete(coach.LlmResponse(content: jsonEncode(envelope())));
      await Future<void>.delayed(Duration.zero);
      expect(reply.state.plan, isNull);
    },
  );

  test(
    'network fallback retains conditions confirmed by an ordinary AI reply',
    () async {
      final client = coach.FakeLlmClient([
        {'kind': 'reply', 'text': '记住了：办公室、徒手，避开膝部负担。'},
        const coach.LlmException(coach.LlmErrorKind.network, 'test offline'),
      ], latency: Duration.zero);
      final ai = engine(client);
      final confirmed = await ai.reply('办公室，徒手，保护膝', const ChatState());
      final fallback = await ai.reply('10 分钟全身', confirmed.state);
      final selected = replyPlan(fallback)!;
      expect(ai.lastFallbackReason, coach.FallbackReason.offline);
      expect(selected.scene, 'office');
      expect(selected.avoid, contains('膝'));
      expect(fallback.state.request!.equipment, isEmpty);
      expect(
        PlanValidator(library).validate(selected, fallback.state.request),
        isEmpty,
      );
      for (final item in selected.items) {
        final exercise = library[item.exerciseId];
        expect(exercise.isFloor, isFalse, reason: exercise.id);
        expect(exercise.cautions, isNot(contains('膝')), reason: exercise.id);
        expect(
          exercise.equipment.every(
            (e) => const {
              Equipment.none,
              Equipment.chair,
              Equipment.wall,
            }.contains(e),
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'adopting an office saved or last plan replaces older AI scene and retains protections',
    () async {
      final office = TrainingPlan.fromJson({
        ...plan(id: 'office-saved', ids: ['o-stand-sidebend']).toJson(),
        'scene': 'office',
        'avoid': ['肩'],
      });
      for (final input in ['@saved:office', '上次那个']) {
        final client = coach.FakeLlmClient([
          {'kind': 'reply', 'text': '按这套办公室训练继续调整。'},
        ], latency: Duration.zero);
        final ai = engine(client);
        final previous = ChatState(
          plan: plan(),
          request: requestForPlan(plan()),
          coachContext: const Slots(
            scene: 'home',
            equipment: {},
            avoid: {'膝'},
            minutes: 10,
          ),
          lastPlan: office,
          saved: [
            SavedPlan(
              id: 'office',
              name: '工位训练',
              plan: office,
              savedAt: DateTime(2026, 10, 20),
            ),
          ],
        );
        final adopted = await ai.reply(input, previous);
        expect(client.requests, isEmpty);
        expect(adopted.state.plan!.scene, 'office');
        final edited = await ai.reply('再短一点', adopted.state);
        expect(edited.state.coachContext!.scene, 'office');
        expect(edited.state.coachContext!.avoid, containsAll(['肩', '膝']));
        expect(
          client.requests.single.messages.last.content,
          contains('办公室（office）'),
        );
        expect(client.requests.single.messages.last.content, contains('肩'));
        expect(client.requests.single.messages.last.content, contains('膝'));
      }
    },
  );

  test(
    'controller excludes local workout history and safety answers from later AI prompts',
    () async {
      final client = coach.FakeLlmClient([
        {'kind': 'reply', 'text': 'AI 轮次一：保持稳定节奏。'},
        {'kind': 'reply', 'text': 'AI 轮次二：再逐步增加强度。'},
      ], latency: Duration.zero);
      final ai = engine(client);
      final store = AppStore(_Storage());
      store.history.add(
        HistoryEntry(
          title: '仅留本机的敏感训练记录',
          at: DateTime(2026, 10, 20),
          minutes: 10,
          completed: 1,
          total: 1,
        ),
      );
      final controller = ChatController(
        engine: ai,
        store: store,
        replyDelay: Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.start();
      var question = controller.messages.lastWhere((m) => m.options.isNotEmpty);
      await controller.choose(
        question,
        question.options.indexWhere((o) => o.value == '@safety:ack'),
      );
      while (controller.inSafetyCheck) {
        question = controller.messages.lastWhere((m) => m.options.isNotEmpty);
        await controller.choose(
          question,
          question.options.indexWhere((o) => o.value == '@safety:no'),
        );
      }
      final safetyMessages = List<ChatMessage>.of(controller.messages);
      await controller.send('上次练了什么');
      expect(controller.messages.last.text, contains('仅留本机的敏感训练记录'));
      await controller.send('请解释训练节奏');
      await controller.send('再讲得具体一点');
      expect(client.requests, hasLength(2));
      final prompt = client.requests.last.messages
          .map((m) => m.content)
          .join('\n');
      expect(prompt, contains('AI 轮次一：保持稳定节奏。'));
      expect(prompt, contains('请解释训练节奏'));
      expect(prompt, isNot(contains('上次练了什么')));
      expect(prompt, isNot(contains('仅留本机的敏感训练记录')));
      expect(prompt, isNot(contains('我已了解')));
      expect(safetyMessages.every((m) => !m.aiVisible), isTrue);
      expect(controller.messages.last.aiVisible, isTrue);
      expect(
        ChatMessage.fromJson(controller.messages.last.toJson()).aiVisible,
        isTrue,
      );
    },
  );

  test(
    'restart during a new office question restores latest AI conditions over the old home card',
    () async {
      final oldPlan = TrainingPlan.fromJson({
        ...plan().toJson(),
        'avoid': ['腰'],
      });
      final at = DateTime(2026, 10, 20);
      final storedMessages = [
        ChatMessage(
          id: 'old-user',
          role: ChatRole.user,
          at: at,
          text: '在家 10 分钟练全身，徒手，保护腰',
          aiVisible: true,
        ),
        ChatMessage(
          id: 'old-plan',
          role: ChatRole.assistant,
          at: at,
          text: '居家计划。',
          plan: oldPlan,
          request: requestForPlan(oldPlan),
          aiVisible: true,
        ),
        ChatMessage(
          id: 'new-user',
          role: ChatRole.user,
          at: at,
          text: '现在改在办公室，徒手，保护膝',
          aiVisible: true,
        ),
        ChatMessage(
          id: 'new-question',
          role: ChatRole.assistant,
          at: at,
          text: '这次有几分钟？',
          options: const [ChatOption('10 分钟')],
          aiVisible: true,
        ),
      ];
      final storage = _Storage();
      final initialStore = AppStore(storage);
      await initialStore.acceptSafety(blocked: false);
      await initialStore.setChatLog(
        storedMessages.map((m) => m.toJson()).toList(),
      );
      final store = AppStore(storage);
      await store.load();
      final officePlan = TrainingPlan.fromJson({
        ...plan(id: 'office-after-restart', ids: ['o-stand-sidebend']).toJson(),
        'scene': 'office',
      });
      final client = coach.FakeLlmClient([
        envelope(value: officePlan),
      ], latency: Duration.zero);
      final ai = engine(client);
      final controller = ChatController(
        engine: ai,
        store: store,
        replyDelay: Duration.zero,
        clock: () => at,
      );
      addTearDown(controller.dispose);
      controller.start();
      expect(controller.currentPlan!.scene, 'home');
      await controller.send('10 分钟全身');
      expect(ai.lastOutcome, coach.TurnOutcome.model);
      expect(controller.currentPlan!.scene, 'office');
      expect(controller.currentPlan!.avoid, containsAll(['腰', '膝']));
      expect(
        client.requests.single.messages.last.content,
        contains('办公室（office）'),
      );
    },
  );

  test(
    '100 and 120 minutes are clamped as whole numbers to 60, never parsed from their tails',
    () async {
      final client = coach.FakeLlmClient([
        envelope(),
        envelope(),
      ], latency: Duration.zero);
      final ai = engine(client);
      for (final minutes in [100, 120]) {
        final reply = await ai.reply('在家 $minutes 分钟练全身，徒手', const ChatState());
        expect(ai.lastOutcome, coach.TurnOutcome.model);
        expect(reply.state.coachContext!.minutes, 60);
        expect(replyPlan(reply)!.targetMinutes, 60);
      }
      expect(client.requests, hasLength(2));
    },
  );

  test(
    'HTTP 429 with retries disabled asks to try later and retains the local fallback',
    () async {
      final gateway = await _Gateway.start(
        [],
        status: HttpStatus.tooManyRequests,
      );
      addTearDown(gateway.close);
      final client = gateway.client();
      addTearDown(client.close);
      final ai = engine(client);
      final reply = await ai.reply('在家练全身', const ChatState());
      expect(gateway.bodies, hasLength(1));
      expect(ai.lastFallbackReason, coach.FallbackReason.rateLimited);
      expect(texts(reply), contains('稍后再试'));
      expectLocalPreserved(
        reply,
        await local().reply('在家练全身', const ChatState()),
      );
    },
  );

  test(
    'fallback revalidates retimed old plans against newly protected knees or an office scene',
    () async {
      final base = plan(ids: ['h-squat', 'h-forearm-plank']);
      final old = TrainingPlan.fromJson({
        ...base.toJson(),
        'targetMinutes': 20,
        'blocks': [
          {
            ...base.blocks.single.toJson(),
            'items': [
              {
                ...base.blocks.single.items.first.toJson(),
                'sets': 6,
                'reps': 30,
                'restSeconds': 30,
              },
              {
                ...base.blocks.single.items.last.toJson(),
                'sets': 3,
                'workSeconds': 120,
                'restSeconds': 30,
              },
            ],
          },
        ],
      });
      expect(SessionBuilder(library).planSeconds(old), greaterThan(600));
      for (final scenario in [
        ('再短一点，保护膝', 'home', const {'膝'}),
        ('再短一点，改在办公室，徒手', 'office', const <String>{}),
      ]) {
        final client = coach.FakeLlmClient([
          const coach.LlmException(coach.LlmErrorKind.network, 'test offline'),
        ], latency: Duration.zero);
        final ai = engine(client);
        final reply = await ai.reply(
          scenario.$1,
          ChatState(
            plan: old,
            request: requestForPlan(old),
            coachContext: const Slots(
              scene: 'home',
              minutes: 20,
              equipment: {},
            ),
          ),
        );
        expect(ai.lastFallbackReason, coach.FallbackReason.offline);
        expect(reply.aiTurn, isTrue);
        final merged = requestForPlan(old).copyWith(
          scene: scenario.$2,
          avoid: scenario.$3,
          equipment: {},
          minutes: 14,
        );
        final plans = reply.messages
            .map((m) => m.plan)
            .whereType<TrainingPlan>();
        // A safe rebuilt template or an explanatory message is acceptable;
        // forwarding the old unchecked squat/floor plan is not.
        for (final candidate in plans) {
          expect(candidate.scene, scenario.$2);
          expect(candidate.avoid, containsAll(scenario.$3));
          expect(PlanValidator(library).validate(candidate, merged), isEmpty);
        }
        expect(texts(reply).trim(), isNotEmpty);
        expect(client.requests, hasLength(1));
      }
    },
  );

  test(
    'different accepted AI plans with the same model id get distinct App ids and both reload',
    () async {
      final client = coach.FakeLlmClient([
        envelope(
          value: plan(id: 'model-reused-id', ids: ['h-calf-raise']),
        ),
        envelope(
          value: plan(id: 'model-reused-id', ids: ['h-squat']),
        ),
      ], latency: Duration.zero);
      final ai = engine(client);
      final firstReply = await ai.reply('在家 10 分钟练全身，徒手', const ChatState());
      final secondReply = await ai.reply('换一套', firstReply.state);
      final first = replyPlan(firstReply)!;
      final second = replyPlan(secondReply)!;
      expect(first.id, isNot('model-reused-id'));
      expect(second.id, isNot('model-reused-id'));
      expect(first.id, isNot(second.id));
      expect(first.exerciseIds, {'h-calf-raise'});
      expect(second.exerciseIds, {'h-squat'});
      final storage = _Storage();
      final store = AppStore(storage);
      await store.savePlan(first);
      await store.savePlan(second);
      final reloaded = AppStore(storage);
      await reloaded.load();
      expect(reloaded.savedPlans, hasLength(2));
      expect(reloaded.savedPlans.map((p) => p.plan.id).toSet(), {
        first.id,
        second.id,
      });
      expect(
        reloaded.savedPlans.map((p) => p.plan.exerciseIds),
        containsAll([
          {'h-calf-raise'},
          {'h-squat'},
        ]),
      );
    },
  );
}
