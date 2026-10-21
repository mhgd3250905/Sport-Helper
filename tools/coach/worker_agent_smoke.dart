// Explicit opt-in live smoke. Never runs with the normal test/ suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../test/support.dart';

class _Files implements LocalStateStorage {
  _Files(this.root);
  final Directory root;
  File file(String key) => File('${root.path}/$key.json');
  @override
  Future<String?> read(String key) async {
    final f = file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await root.create(recursive: true);
    await file(key).writeAsString(value, flush: true);
  }
}

/// Observe the public request contract, never credentials or raw responses.
class _ObservedClient implements coach.LlmClient {
  _ObservedClient(this.inner, this.requestTimes);
  final coach.OpenAiCompatibleClient inner;
  final List<DateTime> requestTimes;
  final requests = <coach.LlmRequest>[];
  final responseProtocol = <Map<String, Object?>>[];

  // Keep a full ten-step budget below the Worker's 30 requests / 10 minutes.
  // Wait between cases, outside the measured turn, and reuse the same UUID.
  Future<void> waitForTurnBudget() async {
    while (true) {
      final cutoff = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      requestTimes.removeWhere((time) => time.isBefore(cutoff));
      if (requestTimes.length < 20) return;
      stdout.writeln('SMOKE_RATE_WAIT waiting for the existing device budget');
      await Future<void>.delayed(const Duration(seconds: 30));
    }
  }

  @override
  String get model => inner.model;
  @override
  coach.Pricing? get pricing => inner.pricing;
  @override
  Future<coach.LlmResponse> complete(
    coach.LlmRequest request, {
    coach.CancelToken? cancel,
  }) async {
    requests.add(request);
    requestTimes.add(DateTime.now().toUtc());
    final response = await inner.complete(request, cancel: cancel);
    responseProtocol.add({
      'requestIndex': requests.length,
      'reasoningPresent': response.reasoning != null,
      'reasoningLength': response.reasoning?.length,
    });
    return response;
  }
}

String _callLabel(coach.CallOutcome outcome) => switch (outcome) {
  coach.CallOutcome.passed => 'passed',
  coach.CallOutcome.rewritten => 'rewritten',
  coach.CallOutcome.rejected => 'rejected',
  coach.CallOutcome.error => 'error',
  coach.CallOutcome.cancelled => 'cancelled',
  coach.CallOutcome.toolStep => 'toolStep',
};

void main() {
  const live = bool.fromEnvironment('SMARTFIT_RUN_LIVE');
  const memoryOnly = bool.fromEnvironment('SMARTFIT_SMOKE_MEMORY_ONLY');
  test(
    'real Worker CoachAgent first multi-step smoke',
    () async {
      const key = String.fromEnvironment('SMARTFIT_AI_TOKEN');
      expect(
        key.trim(),
        isNotEmpty,
        reason: 'Supply Worker key through dart-define.',
      );
      final root = Directory(
        '.buildlog/skill-agent-smoke/${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}',
      );
      await root.create(recursive: true);
      final deviceFiles = _Files(
        Directory('.buildlog/skill-agent-smoke/device'),
      );
      final deviceId = await DeviceIdentity(deviceFiles).loadOrCreate();
      final files = _Files(Directory('${root.path}/local-state'));
      final store = AppStore(files);
      await store.load();
      await store.acceptSafety(blocked: false);
      final packs = loadPacksSync();
      final library = loadLibrary();
      final catalog = const coach.DrillPackAdapter().build(
        version: 'smartfit-bundled-1.1.0',
        packs: {for (final p in packs.exercises) p.id: p.json},
      );
      final profile = coach.CoachProfile.fromJson(
        jsonDecode(await File('assets/coach/smartfit.json').readAsString()),
      );
      final transport = const AiCoachConfig(
        token: key,
      ).createClient(deviceId: deviceId);
      final previousRequests = <DateTime>[];
      for (final previous in Directory(
        '.buildlog/skill-agent-smoke',
      ).listSync()) {
        if (previous is! Directory) continue;
        final previousEvents = File('${previous.path}/events.jsonl');
        if (!previousEvents.existsSync()) continue;
        for (final line in previousEvents.readAsLinesSync()) {
          final e = jsonDecode(line) as Map<String, dynamic>;
          if (e['kind'] == 'thinking') {
            previousRequests.add(DateTime.parse(e['at'] as String));
          }
        }
      }
      final client = _ObservedClient(transport, previousRequests);
      final engine = AiChatEngine(
        local: RuleChatEngine(
          lib: library,
          templates: TemplatePlanGenerator(
            lib: library,
            catalog: loadCatalog(),
          ),
        ),
        catalog: catalog,
        profile: profile,
        client: client,
        memoryStore: store.aiMemoryStore,
        enableUserMemory: false,
      );
      final chat = ChatController(
        engine: engine,
        store: store,
        replyDelay: Duration.zero,
      )..start();
      final events = <Map<String, Object?>>[];
      final eventFile = File('${root.path}/events.jsonl');
      final subscription = engine.events.listen((event) {
        final e = <String, Object?>{
          'at': DateTime.now().toUtc().toIso8601String(),
          'turnId': event.turnId,
          'kind': event.kind.name,
          'step': event.step,
          'path': event.path,
          'status': event.status?.name,
        };
        events.add(e);
        eventFile.writeAsStringSync(
          '${jsonEncode(e)}\n',
          mode: FileMode.append,
        );
        stdout.writeln(
          'AGENT_PROGRESS ${jsonEncode({'kind': event.kind.name, 'step': event.step, 'path': event.path})}',
        );
      });
      final results = <Map<String, Object?>>[];
      final failures = <String>[];
      Future<void> run(
        String id,
        String question, {
        bool memory = false,
        bool reset = true,
      }) async {
        await client.waitForTurnBudget();
        engine.enableUserMemory = memory;
        await store.setAiMemoryEnabled(memory);
        if (reset) await chat.newConversation();
        final before = client.requests.length;
        final eventBefore = events.length;
        final started = DateTime.now().toUtc();
        final watch = Stopwatch()..start();
        stdout.writeln(
          'SMOKE_START ${jsonEncode({'id': id, 'question': question, 'memoryEnabled': memory})}',
        );
        await chat.send(question);
        watch.stop();
        final r = engine.lastResult;
        if (r == null) {
          failures.add('$id did not reach the Agent');
          return;
        }
        final sent = client.requests.skip(before).toList();
        // Agent commits its in-memory view before the asynchronous store write
        // completes. Wait briefly for that write before checking durability.
        var memoryEntries = await store.aiMemoryStore.load();
        if (memory) {
          final committed = await engine.agent.memory();
          for (
            var attempt = 0;
            attempt < 40 &&
                jsonEncode(memoryEntries.map((e) => e.toJson()).toList()) !=
                    jsonEncode(committed.map((e) => e.toJson()).toList());
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            memoryEntries = await store.aiMemoryStore.load();
          }
        }
        final system = sent.isEmpty ? '' : sent.first.messages.first.content;
        final memoryAt = system.indexOf('# 用户记忆（');
        final memorySummary = memoryAt < 0 ? '' : system.substring(memoryAt);
        final tools = sent.isEmpty
            ? <String>[]
            : sent.first.tools.map((t) => t.name).toList();
        final plan = chat.currentPlan;
        final itemIds =
            plan?.items.map((i) => i.exerciseId).toList() ?? <String>[];
        final result = <String, Object?>{
          'id': id,
          'question': question,
          'startedAt': started.toIso8601String(),
          'elapsedMs': watch.elapsedMilliseconds,
          'status': r.status.name,
          'outcome': engine.lastOutcome?.name,
          'fallback': r.status == coach.TurnStatus.fallback,
          'fallbackReason': r.fallbackReason?.name,
          'error': r.error?.toString(),
          'steps': r.steps,
          'reads': r.reads,
          'submissions': r.submissions,
          'usage': {...r.usage.toJson(), 'totalTokens': r.usage.totalTokens},
          'calls': [
            for (final record in r.records)
              {
                'outcome': _callLabel(record.outcome),
                'httpAttempts': record.httpAttempts,
                'latencyMs': record.latency.inMilliseconds,
                'usage': record.usage.toJson(),
                'issues': record.issueCodes,
                'errorKind': record.errorKind,
              },
          ],
          'responseProtocol': client.responseProtocol
              .where((p) => (p['requestIndex'] as int) > before)
              .toList(),
          'assistantProtocol': [
            for (final request in sent)
              [
                for (final message in request.messages)
                  if (message.role == coach.LlmRole.assistant)
                    {
                      'reasoningPresent': message.toJson().containsKey(
                        'reasoning_content',
                      ),
                      'reasoningLength': message.reasoning?.length,
                    },
              ],
          ],
          'events': events.skip(eventBefore).toList(),
          'text': r.text,
          'actions': r.actions?.items.map((a) => a.id).toList(),
          'planTitle': plan?.title,
          'planId': plan?.id,
          'planLevel': plan?.level,
          'planMinutes': plan?.targetMinutes,
          'planAvoid': plan?.avoid.toList(),
          'planActions': itemIds,
          'memoryEnabled': memory,
          'memory': memoryEntries.map((e) => e.toJson()).toList(),
          'memoryToolsPresent':
              tools.contains('remember') || tools.contains('forget'),
          'memorySummaryIncluded': memorySummary.isNotEmpty,
          'memorySummaryMentionsDumbbell': memorySummary.contains('哑铃'),
          'memorySummaryMentionsBeginner': memorySummary.contains('新手'),
        };
        results.add(result);
        await File('${root.path}/results.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert(results),
          flush: true,
        );
        stdout.writeln('SMOKE_RESULT ${jsonEncode(result)}');
        if (r.status != coach.TurnStatus.ok) {
          failures.add('$id: ${r.status.name} ${r.fallbackReason?.name}');
        }
        if (id == 'actions' && r.actions == null) {
          failures.add('actions: no ValidatedActions');
        }
        if (id == 'core' && r.plan == null) {
          failures.add('core: no ValidatedPlan');
        }
        if (id == 'remember' &&
            (!memoryEntries.any((e) => e.kind == coach.MemoryKind.level) ||
                !memoryEntries.any(
                  (e) => e.kind == coach.MemoryKind.equipment,
                ))) {
          failures.add('remember: no durable level/equipment memories');
        }
        if (id == 'memory-on-plan' && !memorySummary.contains('哑铃')) {
          failures.add('enabled: memory not in system');
        }
        if (id == 'memory-off-plan' &&
            (tools.contains('remember') ||
                tools.contains('forget') ||
                memorySummary.isNotEmpty)) {
          failures.add('disabled: remembered-only information in cold request');
        }
        if (id == 'back-protection' &&
            plan != null &&
            itemIds.any((id) => library[id].cautions.contains('腰'))) {
          failures.add('back-protection: unsafe action');
        }
      }

      try {
        if (!memoryOnly) {
          await run('core', '在家 15 分钟练核心，徒手');
          await run('actions', '臀桥怎么做');
          await run('back-protection', '我腰不太舒服，想练腿 20 分钟');
        }
        await run('remember', '我是新手，家里有哑铃', memory: true);
        // A fresh chat removes explicit Slots/history. The durable memory store
        // alone must provide remembered facts, then disappear when disabled.
        await run('memory-on-plan', '请给我排一个15分钟的居家力量训练计划', memory: true);
        await run('memory-off-plan', '请给我排一个15分钟的居家力量训练计划');
        await File('${root.path}/verdict.json').writeAsString(
          jsonEncode({
            'failures': failures,
            'maxSteps': engine.agent.maxSteps,
            'memoryOnly': memoryOnly,
          }),
          flush: true,
        );
        stdout.writeln('SMOKE_REPORT ${root.path}/results.json');
        expect(
          failures,
          isEmpty,
          reason: 'See the recorded real Worker results.',
        );
      } finally {
        await subscription.cancel();
        chat.dispose();
        engine.dispose();
        transport.close();
      }
    },
    skip: live
        ? false
        : 'Use run_agent_smoke.ps1 to explicitly authorize live Worker calls.',
    timeout: const Timeout(Duration(minutes: 150)),
  );
}
