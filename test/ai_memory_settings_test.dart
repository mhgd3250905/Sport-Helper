import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/user_memory_store.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/ai_coach_config.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/about_page.dart';
import 'package:smartfit/ui/settings_widgets.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  String? failWriteKey;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failWriteKey) throw StateError('Storage unavailable');
    values[key] = value;
  }
}

AppServices _services(_Storage storage, {AppStore? store, bool ai = false}) {
  final packs = loadPacksSync();
  return AppServices(
    library: loadLibrary(),
    catalog: loadCatalog(),
    store: store ?? AppStore(storage),
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    coachCatalog: ai
        ? const coach.DrillPackAdapter().build(
            version: 'memory-settings-test',
            packs: {for (final pack in packs.exercises) pack.id: pack.json},
          )
        : null,
    coachProfile: ai
        ? coach.CoachProfile.fromJson(
            jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
          )
        : null,
    aiConfig: ai
        ? const AiCoachConfig(token: 'memory-test-only')
        : const AiCoachConfig(),
    deviceId: ai ? '7a318be8-d0b7-4c83-8b7a-2a5aaecf9f66' : null,
    chatReplyDelay: Duration.zero,
  );
}

Future<void> _show(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(SfPalette.dark),
        home: const AboutPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _confirmClear(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('ai-memory-clear')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('ai-memory-confirm')));
}

void main() {
  testWidgets('no Key hides AI memory controls and AI service copy', (
    tester,
  ) async {
    final s = _services(_Storage());
    addTearDown(s.dispose);
    await _show(tester, s);
    expect(find.byKey(const ValueKey('ai-memory-switch')), findsNothing);
    expect(find.byKey(const ValueKey('ai-memory-clear')), findsNothing);
    expect(find.text('AI 记忆'), findsNothing);
    expect(find.text('隐私与 AI'), findsNothing);
    expect(find.textContaining('api.uuugk.win'), findsNothing);
    expect(find.text('隐私'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'AI service initializes from the saved setting and switches the live agent',
    () async {
      final storage = _Storage();
      final persisted = AppStore(storage);
      await persisted.aiMemoryStore.save([
        coach.MemoryEntry(
          coach.MemoryKind.level,
          '新手',
          at: DateTime.utc(2026, 10, 21),
        ),
      ]);
      await persisted.setAiMemoryEnabled(false);
      final store = AppStore(storage);
      await store.load();
      final s = _services(storage, store: store, ai: true);
      final engine = s.chatEngine as AiChatEngine;
      addTearDown(engine.dispose);
      expect(engine.enableUserMemory, isFalse);
      expect(engine.agent.memoryStore, same(store.aiMemoryStore));

      await s.setAiMemoryEnabled(true);
      expect(engine.enableUserMemory, isTrue);
      expect(store.aiMemoryEnabled, isTrue);
      storage.failWriteKey = AppStore.key;
      await expectLater(s.setAiMemoryEnabled(false), throwsStateError);
      expect(engine.enableUserMemory, isFalse);
      expect(store.aiMemoryEnabled, isFalse);
      expect((await engine.agent.memory()).single.text, '新手');

      storage.failWriteKey = null;
      await s.setAiMemoryEnabled(false);
      final restarted = AppStore(storage);
      await restarted.load();
      expect(restarted.aiMemoryEnabled, isFalse);
      expect((await restarted.aiMemoryStore.load()).single.text, '新手');
    },
  );

  test(
    'AI clear detects a swallowed SDK write failure and a retry clears disk and cache',
    () async {
      final storage = _Storage();
      final s = _services(storage, ai: true);
      final engine = s.chatEngine as AiChatEngine;
      addTearDown(engine.dispose);
      await s.store.aiMemoryStore.save([
        coach.MemoryEntry(
          coach.MemoryKind.equipment,
          '家里有哑铃',
          at: DateTime.utc(2026, 10, 21),
        ),
      ]);
      expect((await engine.agent.memory()).single.text, '家里有哑铃');
      storage.failWriteKey = LocalUserMemoryStore.key;

      await expectLater(s.clearAiMemory(), throwsStateError);
      expect((await s.store.aiMemoryStore.load()).single.text, '家里有哑铃');
      storage.failWriteKey = null;
      await s.clearAiMemory();
      expect(await engine.agent.memory(), isEmpty);
      expect(await AppStore(storage).aiMemoryStore.load(), isEmpty);
    },
  );

  testWidgets('memory switch persists and clear works while memory is off', (
    tester,
  ) async {
    final storage = _Storage();
    final s = _services(storage, ai: true);
    addTearDown(s.dispose);
    await s.store.aiMemoryStore.save([
      coach.MemoryEntry(
        coach.MemoryKind.equipment,
        '家里有哑铃',
        at: DateTime.utc(2026, 10, 21),
      ),
    ]);
    await _show(tester, s);
    final toggle = find.byKey(const ValueKey('ai-memory-switch'));
    expect(tester.widget<SfSettingsSwitchRow>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SfSettingsSwitchRow>(toggle).value, isFalse);
    final restarted = AppStore(storage);
    await restarted.load();
    expect(restarted.aiMemoryEnabled, isFalse);
    expect((await restarted.aiMemoryStore.load()).single.text, '家里有哑铃');

    await _confirmClear(tester);
    await tester.pumpAndSettle();
    expect(await restarted.aiMemoryStore.load(), isEmpty);
    expect(find.text('AI 记忆已清除'), findsOneWidget);
    expect(s.store.aiMemoryEnabled, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed clear reports failure and keeps saved memory', (
    tester,
  ) async {
    final storage = _Storage();
    final s = _services(storage, ai: true);
    addTearDown(s.dispose);
    await s.store.aiMemoryStore.save([
      coach.MemoryEntry(
        coach.MemoryKind.level,
        '新手',
        at: DateTime.utc(2026, 10, 21),
      ),
    ]);
    storage.failWriteKey = LocalUserMemoryStore.key;
    await _show(tester, s);
    await _confirmClear(tester);
    await tester.pumpAndSettle();
    expect(find.text('清除记忆失败，请重试'), findsOneWidget);
    expect(find.text('AI 记忆已清除'), findsNothing);
    expect((await s.store.aiMemoryStore.load()).single.text, '新手');
    storage.failWriteKey = null;
    await _confirmClear(tester);
    await tester.pumpAndSettle();
    expect(await s.store.aiMemoryStore.load(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling memory confirmation preserves remembered data', (
    tester,
  ) async {
    final storage = _Storage();
    final services = _services(storage, ai: true);
    addTearDown(services.dispose);
    await services.store.aiMemoryStore.save([
      coach.MemoryEntry(
        coach.MemoryKind.level,
        '新手',
        at: DateTime.utc(2026, 10, 21),
      ),
    ]);
    await _show(tester, services);
    await tester.tap(find.byKey(const ValueKey('ai-memory-clear')));
    await tester.pumpAndSettle();
    expect((await services.store.aiMemoryStore.load()).single.text, '新手');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect((await services.store.aiMemoryStore.load()).single.text, '新手');
    expect(find.text('AI 记忆已清除'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed preference save reports error and allows retry', (
    tester,
  ) async {
    final storage = _Storage()..failWriteKey = AppStore.key;
    final s = _services(storage, ai: true);
    addTearDown(s.dispose);
    await _show(tester, s);
    final toggle = find.byKey(const ValueKey('ai-memory-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SfSettingsSwitchRow>(toggle).value, isFalse);
    expect(find.text('记忆开关保存失败，请重试'), findsOneWidget);
    storage.failWriteKey = null;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final restarted = AppStore(storage);
    await restarted.load();
    expect(restarted.aiMemoryEnabled, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
