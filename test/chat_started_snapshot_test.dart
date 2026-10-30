import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/training_route.dart';

import 'app_flow_test.dart' show MemoryStorage, services, tall;

class _ObservedStorage extends MemoryStorage {
  Completer<void>? _nextWrite;

  Future<void> get nextWrite => (_nextWrite = Completer<void>()).future;

  @override
  Future<void> write(String key, String value) async {
    await super.write(key, value);
    _nextWrite?.complete();
    _nextWrite = null;
  }
}

const _original = TrainingPlan(
  id: 'details-original',
  source: 'template',
  title: '核心',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: ['band'],
  level: 2,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'b',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-russian-twist',
          mode: DoseMode.reps,
          sets: 1,
          reps: 10,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets(
    'a detail replacement saves the trained version and keeps the original saved plan',
    (tester) async {
      tall(tester);
      final s = services();
      await s.store.acceptSafety(blocked: false);
      await s.store.savePlan(_original);
      await s.store.setChatLog([
        ChatMessage(
          id: 'original-card',
          role: ChatRole.assistant,
          at: DateTime.now(),
          plan: _original,
        ).toJson().cast<String, dynamic>(),
      ]);
      await tester.pumpWidget(SmartFitApp(services: s));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('plan-open-details-original')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('换一个'));
      await tester.tap(find.byTooltip('换一个'));
      await tester.pumpAndSettle();
      final modified = s.store.lastPlan!;
      expect(modified.id, isNot(_original.id));
      expect(modified.exerciseIds, {'h-band-pallof'});

      await tester.tap(find.byKey(const ValueKey('start')));
      await tester.pump();
      // Retire preview playback, then keep the real trainer behind its gate.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      final entering = find.byType(PlayerPage, skipOffstage: false);
      expect(entering, findsOneWidget);
      expect(
        TrainingTransitionScope.maybeOf(tester.element(entering))!.entered,
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 560));
      await tester.pump();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(s.chat.currentPlan?.id, modified.id);
      expect(s.store.lastPlan?.exerciseIds, {'h-band-pallof'});
      for (var i = 0; i < 12 && s.store.history.isEmpty; i++) {
        await tester.tap(find.byKey(const ValueKey('skip')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(s.store.history, hasLength(1));
      expect(s.store.history.single.completed, 0);
      await tester.tap(find.byKey(const ValueKey('finish')));
      await tester.pumpAndSettle();
      // Training returns to its retained article source, not directly to chat.
      expect(find.byType(PlanPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlanPage))).pop();
      await tester.pumpAndSettle();
      // Skipping all work no longer creates a completion/save offer. The
      // exact started snapshot can still be saved from its own plan card.
      expect(s.chat.messages.last.options, isEmpty);
      final expand = find.byKey(ValueKey('plan-expand-${modified.id}'));
      await tester.ensureVisible(expand);
      await tester.tap(expand);
      await tester.pumpAndSettle();
      final save = find.byKey(ValueKey('plan-save-${modified.id}'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(s.store.savedPlans, hasLength(2));
      expect(s.store.savedFor(_original)!.plan.exerciseIds, {
        'h-russian-twist',
      });
      expect(s.store.savedFor(modified)!.plan.exerciseIds, {'h-band-pallof'});
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'the actual started snapshot and its save offer survive a restart',
    () async {
      final mem = _ObservedStorage();
      final s = services();
      final store = AppStore(mem);
      await store.acceptSafety(blocked: false);
      final c = ChatController(
        engine: s.chatEngine,
        store: store,
        replyDelay: Duration.zero,
      )..start();
      const original = _original;
      expect(await c.started(original), isTrue);
      await c.save(original);
      final modified = original.copyWith(
        id: '${original.id}~detail-edit',
        blocks: [
          original.blocks.first.copyWith(
            items: const [
              PlanItem(
                exerciseId: 'h-crunch',
                mode: DoseMode.reps,
                sets: 1,
                reps: 10,
                perSide: false,
                restSeconds: 0,
              ),
            ],
          ),
        ],
      );
      expect(await c.started(modified), isTrue);
      final finishedSaved = mem.nextWrite;
      c.finished(modified, completed: 1, total: 1);
      // finished() deliberately persists asynchronously; restart only once
      // its queued storage write has completed.
      await finishedSaved;

      final loaded = AppStore(mem);
      await loaded.load();
      final afterRestart = ChatController(
        engine: c.engine,
        store: loaded,
        replyDelay: Duration.zero,
      )..start();
      expect(afterRestart.currentPlan?.id, modified.id);
      final offer = afterRestart.messages.lastWhere(
        (m) => m.options.any((o) => o.value == '@save:${modified.id}'),
      );
      await afterRestart.choose(offer, 0);
      expect(loaded.savedPlans, hasLength(2));
      expect(loaded.savedFor(modified)!.plan.exerciseIds, {'h-crunch'});
      expect(loaded.savedFor(original)!.plan.exerciseIds, original.exerciseIds);
      c.dispose();
      afterRestart.dispose();
    },
  );
}
