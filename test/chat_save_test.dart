// Saving plans from the chat and keeping the conversation on the device.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/scenario.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

void main() {
  final lib = loadLibrary();
  final templates = TemplatePlanGenerator(lib: lib, catalog: loadCatalog());

  Future<(ChatController, AppStore, MemoryStorage)> chat({
    MemoryStorage? storage,
  }) async {
    final mem = storage ?? MemoryStorage();
    final store = AppStore(mem);
    await store.load();
    if (!store.safetyAccepted) await store.acceptSafety(blocked: false);
    final c = ChatController(
      engine: const AppChatActions(),
      store: store,
      replyDelay: Duration.zero,
    )..start();
    return (c, store, mem);
  }

  TrainingPlan lastCard(ChatController c) =>
      c.messages.lastWhere((m) => m.isPlan).plan!;

  // Saving, recall and safety do not depend on prose interpretation. Feed a
  // manual-plan fixture through the same controller boundary as training.
  Future<TrainingPlan> showCard(
    ChatController c, {
    String template = 'core',
  }) async {
    final generated = await templates.generate(
      ScenarioRequest(templateId: template),
    );
    final plan = generated.plan!;
    await c.started(plan);
    return plan;
  }

  test('保存 keeps a plan once, with a unique name', () async {
    final (c, store, _) = await chat();
    await showCard(c);
    final p = lastCard(c);
    expect(c.isSaved(p), isFalse);
    final a = await c.save(p);
    final again = await c.save(p);
    expect(again.id, a.id);
    expect(store.savedPlans, hasLength(1));
    expect(a.name, p.title);

    final next = p.copyWith(id: '${p.id}-edited');
    await c.started(next);
    final b = await c.save(next);
    expect(store.savedPlans, hasLength(2));
    expect(b.name, '${p.title} 2');
  });

  test('rename, delete and start update the saved list', () async {
    final (c, store, _) = await chat();
    await showCard(c, template: 'office-relax');
    final saved = await c.save(lastCard(c));
    await store.renamePlan(saved.id, '午休放松');
    expect(store.savedPlans.single.name, '午休放松');
    await store.renamePlan(saved.id, '   ');
    expect(store.savedPlans.single.name, '午休放松');
    await c.started(store.savedPlans.single.plan);
    expect(store.savedPlans.single.lastUsedAt, isNotNull);
    expect(store.lastPlan?.id, saved.plan.id);
    await store.deletePlan(saved.id);
    expect(store.savedPlans, isEmpty);
  });

  test(
    'saved plans, the conversation and the current plan survive a restart',
    () async {
      final (c, _, mem) = await chat();
      await showCard(c);
      await c.save(lastCard(c));
      final count = c.messages.length;

      final (c2, store2, _) = await chat(storage: mem);
      expect(store2.savedPlans, hasLength(1));
      expect(c2.messages.length, greaterThanOrEqualTo(count));
      expect(c2.messages.where((m) => m.isPlan), isNotEmpty);
      expect(c2.currentPlan?.templateId, 'core');
      // App restore preserves the exact card; later semantics belong to SDK.
      expect(lastCard(c2).id, lastCard(c).id);
      expect(lastCard(c2).level, lastCard(c).level);
    },
  );

  test('only the most recent messages are kept', () async {
    final (c, store, _) = await chat();
    for (var i = 0; i < 40; i++) {
      await c.send('讲个笑话');
    }
    expect(store.chatLog.length, AppStore.chatLogLimit);
  });

  test('after a workout an unsaved plan is offered for saving', () async {
    final (c, store, _) = await chat();
    await showCard(c);
    final p = lastCard(c);
    c.finished(p, completed: 8, total: 10);
    final offer = c.messages.last;
    expect(offer.text, contains('8/10'));
    expect(offer.options.single.value, '@save:${p.id}');
    await c.choose(offer, 0);
    expect(store.savedFor(p), isNotNull);
    expect(c.messages.last.text, contains('存好了'));
  });

  test('messages round-trip through JSON', () {
    final m = ChatMessage(
      id: 'x',
      role: ChatRole.assistant,
      at: DateTime(2026, 10, 19, 13, 40),
      text: '想练哪方面？',
      options: const [ChatOption('放松拉伸'), ChatOption('全部计划', '@drawer')],
      chosen: 1,
    );
    final back = ChatMessage.fromJson(m.toJson().cast<String, dynamic>());
    expect(back.text, m.text);
    expect(back.options.last.value, '@drawer');
    expect(back.chosen, 1);
    expect(back.at, m.at);
  });

  group('safety talk', () {
    Future<(ChatController, AppStore)> fresh() async {
      final store = AppStore(MemoryStorage());
      final c = ChatController(
        engine: const AppChatActions(),
        store: store,
        replyDelay: Duration.zero,
      )..start();
      return (c, store);
    }

    ChatMessage open(ChatController c) => c.messages.lastWhere(c.isActive);

    test(
      'first launch: disclaimer → four 否 → accepted, plans allowed',
      () async {
        final (c, store) = await fresh();
        expect(c.inSafetyCheck, isTrue);
        expect(c.messages.last.text, contains('不是医疗诊断'));
        await c.choose(open(c), 0); // 我已了解
        for (var i = 0; i < 4; i++) {
          expect(open(c).text, startsWith('${i + 1}/4'));
          await c.choose(open(c), 0); // 否
        }
        expect(c.inSafetyCheck, isFalse);
        expect(store.safetyAccepted, isTrue);
        expect(store.safetyBlocked, isFalse);
        final allowed = await showCard(c);
        expect(c.currentPlan?.id, allowed.id);
      },
    );

    test(
      'any 是 → advice, blocked; an old question cannot be re-answered',
      () async {
        final (c, store) = await fresh();
        await c.choose(open(c), 0);
        final q1 = open(c);
        await c.choose(q1, 0); // 否
        await c.choose(open(c), 0); // 2/4 否
        await c.choose(open(c), 1); // 3/4 是
        expect(store.safetyBlocked, isTrue);
        expect(c.messages.last.text, contains('先休息'));
        expect(c.isActive(q1), isFalse);
        await c.send('在家 15 分钟练核心');
        expect(c.messages.where((m) => m.isPlan), isEmpty);
      },
    );

    test(
      'typing before finishing waits; a re-check can lift the block',
      () async {
        final (c, store) = await fresh();
        await c.send('在家 15 分钟练核心');
        expect(c.messages.last.text, contains('先把上面的安全确认做完'));
        await c.choose(open(c), 0);
        await c.choose(open(c), 1); // 1/4 是
        expect(store.safetyBlocked, isTrue);

        c.startSafetyCheck();
        await c.choose(open(c), 0);
        for (var i = 0; i < 4; i++) {
          await c.choose(open(c), 0);
        }
        expect(store.safetyBlocked, isFalse);
      },
    );
  });
}
