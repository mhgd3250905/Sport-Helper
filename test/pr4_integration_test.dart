import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'app_flow_test.dart' show services;

class _BlockedStorage implements LocalStateStorage {
  final values = <String, String>{};
  final firstStarted = Completer<void>();
  final releaseFirst = Completer<void>();
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (writes++ == 0) {
      firstStarted.complete();
      await releaseFirst.future;
    }
    values[key] = value;
  }
}

SessionResult _completedWorkout() => SessionResult(
  sessionId: 'glass-integration-workout',
  planId: 'core-plan',
  planTitle: '核心训练',
  startedAt: DateTime.utc(2026, 10, 21, 1),
  endedAt: DateTime.utc(2026, 10, 21, 1, 2),
  activeSeconds: 120,
  endedEarly: false,
  completedExercises: 1,
  totalExercises: 1,
  items: const [
    ItemResult(
      exerciseId: 'h-squat',
      blockIndex: 0,
      itemInBlock: 0,
      plannedSets: 1,
      completedSets: 1,
      activeSeconds: 120,
      status: ItemStatus.completed,
    ),
  ],
);

class _PendingAgent implements ManagedChatEngine, ProgressChatEngine {
  final eventBus = StreamController<coach.AgentEvent>.broadcast(sync: true);
  final replies = <Completer<ChatReply>>[];
  final states = <ChatState>[];
  int cancellations = 0;
  int resets = 0;

  @override
  String get id => 'glass-integration-agent';
  @override
  Stream<coach.AgentEvent> get events => eventBus.stream;
  @override
  Future<ChatReply> reply(String text, ChatState state) {
    states.add(state);
    final pending = Completer<ChatReply>();
    replies.add(pending);
    return pending.future;
  }

  @override
  void cancelPending() => cancellations++;
  @override
  void reset() => resets++;
  @override
  void dispose() => unawaited(eventBus.close());
}

void main() {
  for (final glassFirst in [true, false]) {
    test('${glassFirst ? 'glass' : 'trainer'} write in flight preserves '
        'trainer result, memory setting and silent quality changes', () async {
      final storage = _BlockedStorage();
      final store = AppStore(storage);
      addTearDown(store.dispose);
      int notifications = 0;
      store.addListener(() => notifications++);
      final result = _completedWorkout();
      final first = glassFirst
          ? store.setGlassQuality('premium')
          : store.saveSession(result);
      await storage.firstStarted.future;
      // Adaptive quality must not rebuild the app from its frame callback.
      expect(notifications, 0);
      expect(store.sessionResults, isEmpty);
      final second = glassFirst
          ? store.saveSession(result)
          : store.setGlassQuality('premium');
      final memory = store.setAiMemoryEnabled(false);
      final settledQuality = store.setGlassQuality('standard');
      expect(notifications, 1); // Only the memory preference notified.

      storage.releaseFirst.complete();
      await Future.wait([first, second, memory, settledQuality]);
      expect(notifications, 2); // One durable trainer commit, no glass event.
      final restored = AppStore(storage);
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.glassQuality, 'standard');
      expect(restored.aiMemoryEnabled, isFalse);
      expect(restored.sessionResults.single.toJson(), result.toJson());
      expect(restored.history.single.sessionId, result.sessionId);
      expect(restored.history.single.completed, 1);
    });
  }

  testWidgets(
    'phone keyboard leaves glass dock, Agent progress, cancel and new chat reachable',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final app = services();
      await app.store.acceptSafety(blocked: false);
      final engine = _PendingAgent();
      final chat = ChatController(
        engine: engine,
        store: app.store,
        replyDelay: Duration.zero,
      );
      addTearDown(chat.dispose);
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        AppScope(
          services: app,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: chat),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.showKeyboard(find.byKey(const ValueKey('chat-input')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      final input = find.byType(ChatInputBar);
      expect(tester.getRect(input).bottom, lessThanOrEqualTo(524));
      expect(
        find.byKey(const ValueKey('chat-send')).hitTestable(),
        findsOneWidget,
      );

      final pending = chat.send('在家练核心十五分钟');
      engine.eventBus.add(
        const coach.AgentEvent('phone-turn', coach.AgentEventKind.checking),
      );
      await tester.pumpAndSettle();
      final progress = find.text('正在核对计划');
      final cancel = find.byKey(const ValueKey('chat-cancel'));
      expect(progress.hitTestable(), findsOneWidget);
      expect(cancel.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(cancel).bottom,
        lessThan(tester.getRect(input).top),
      );
      expect(tester.widget<ChatInputBar>(input).enabled, isFalse);
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(engine.cancellations, 1);
      expect(chat.typing, isFalse);

      final resetPending = chat.send('再来一套');
      engine.eventBus.add(
        const coach.AgentEvent('reset-turn', coach.AgentEventKind.slow),
      );
      await tester.pumpAndSettle();
      expect(find.text('还在想…').hitTestable(), findsOneWidget);
      final newChat = find.byKey(const ValueKey('chat-new-conversation'));
      expect(newChat, findsNothing);
      await tester.tap(find.byKey(const ValueKey('open-plans')));
      await tester.pumpAndSettle();
      expect(newChat.hitTestable(), findsOneWidget);
      await tester.tap(newChat);
      await tester.pumpAndSettle();
      expect(engine.resets, 1);
      expect(chat.typing, isFalse);
      expect(chat.messages.single.greeting, isTrue);
      expect(tester.widget<ChatInputBar>(input).enabled, isTrue);
      expect(tester.getRect(input).bottom, lessThanOrEqualTo(524));

      for (var i = 0; i < engine.replies.length; i++) {
        engine.replies[i].complete(
          ChatReply(
            messages: const [BotMessage('不应盖过新对话的迟到回复')],
            state: engine.states[i],
          ),
        );
      }
      await Future.wait([pending, resetPending]);
      await tester.pumpAndSettle();
      expect(find.text('不应盖过新对话的迟到回复'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
