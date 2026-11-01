import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_fixture.dart';
import 'package:smartfit/domain/exercise.dart';

import '../app_flow_test.dart' show services;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'long chat is 72 identical offline messages on every generation',
    () async {
      final app = services();
      final first = PerformanceFixture.create(
        services: app,
        scenario: FrameScenario.longChatScroll,
      );
      final second = PerformanceFixture.create(
        services: app,
        scenario: FrameScenario.longChatScroll,
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      expect((await first.controller.start()).ok, isTrue);
      expect((await second.controller.start()).ok, isTrue);
      final messages = first.controller.messages;
      expect(messages, hasLength(72));
      expect(messages.where((message) => message.isPlan), isEmpty);
      expect(messages.map((message) => message.id).toSet(), hasLength(72));
      expect(messages.first.at, PerformanceFixture.referenceTime);
      expect(messages.last.at, DateTime.utc(2000, 1, 1, 8, 23, 40));
      expect(
        first.controller.agent.client.model,
        'offline_performance_fixture',
      );
      expect(first.controller.typing, isFalse);
      expect(first.controller.inSafetyCheck, isFalse);
      expect(
        jsonEncode(messages.map((message) => message.toJson()).toList()),
        jsonEncode(
          second.controller.messages
              .map((message) => message.toJson())
              .toList(),
        ),
      );
      first.controller.start();
      expect(first.controller.messages, hasLength(72));
    },
  );

  test(
    'mixed fixture has 12 fixed real plan cards and the same 72 timestamps',
    () async {
      final app = services();
      final library = app.library;
      final fixture = PerformanceFixture.create(
        services: app,
        scenario: FrameScenario.planCardScroll,
      );
      final other = PerformanceFixture.create(
        services: app,
        scenario: FrameScenario.planCardScroll,
      );
      addTearDown(fixture.dispose);
      addTearDown(other.dispose);
      final started = await fixture.controller.start();
      expect(started.ok, isTrue, reason: '${started.issues} ${started.error}');
      expect((await other.controller.start()).ok, isTrue);
      final messages = fixture.controller.messages;
      expect(messages, hasLength(72));
      final cards = messages.where((message) => message.isPlan).toList();
      expect(cards, hasLength(12));
      expect(cards.map((message) => message.plan!.id).toSet(), {
        'performance_plan_v1',
      });
      for (final card in cards) {
        expect(card.isUser, isFalse);
        expect(card.plan!.source, 'template');
        expect(
          card.plan!.items.map((item) => item.exerciseId),
          PerformanceFixture.exerciseIds,
        );
        expect(
          card.plan!.items.every((item) => library.contains(item.exerciseId)),
          isTrue,
        );
        expect(card.request, isNotNull);
      }
      expect(
        jsonEncode(messages.map((message) => message.toJson()).toList()),
        jsonEncode(
          other.controller.messages.map((message) => message.toJson()).toList(),
        ),
      );
    },
  );

  test(
    'fixture activity cannot change the real store or its conversation',
    () async {
      final real = services();
      real.store.chatLog.add({'id': 'real-message', 'text': 'keep'});
      final before = jsonEncode(real.store.chatLog);
      final fixture = PerformanceFixture.create(
        services: real,
        scenario: FrameScenario.longChatScroll,
        starfield: real.store.starfield,
        appearance: real.store.appearance,
      );
      expect(identical(fixture.store, real.store), isFalse);
      await fixture.controller.newConversation();
      expect(fixture.controller.messages, hasLength(1));
      fixture.dispose();
      expect(jsonEncode(real.store.chatLog), before);
      expect(real.store.history, isEmpty);
      expect(real.store.savedPlans, isEmpty);
      real.store.dispose();
    },
  );

  test('never substitutes another exercise set or unsupported workload', () {
    expect(
      () => PerformanceFixture.create(
        services: services(exerciseLibrary: ExerciseLibrary([])),
        scenario: FrameScenario.planCardScroll,
      ),
      throwsStateError,
    );
    expect(
      () => PerformanceFixture.create(
        services: services(),
        scenario: FrameScenario.actionListScroll,
      ),
      throwsArgumentError,
    );
  });
}
