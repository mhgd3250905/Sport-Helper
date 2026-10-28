import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/domain/scenario.dart';

import 'support.dart';

void main() {
  const engine = AppChatActions();

  test(
    'free text cannot execute App commands or produce a local plan',
    () async {
      for (final text in [
        '在家徒手20分钟练核心',
        '换一套',
        '换深色',
        '打开动作库',
        '胸口痛',
        '@appearance:dark',
        '@saved:example',
      ]) {
        const state = ChatState(appearance: 'light');
        final reply = await engine.reply(text, state);
        expect(reply.action, isNull, reason: text);
        expect(reply.state, same(state));
        expect(reply.messages.any((message) => message.plan != null), isFalse);
        expect(reply.messages.single.text, contains('AI 教练暂不可用'));
      }
    },
  );

  test('explicit navigation/settings commands have an allowlist', () async {
    for (final command in [
      '@library',
      '@library:stretch',
      '@settings',
      '@custom',
      '@drawer',
      '@safety',
      '@voice:off',
      '@voice:on',
      '@voice:mute',
      '@chimes:on',
      '@chimes:off',
    ]) {
      final reply = await engine.replyAppCommand(command, const ChatState());
      expect(reply.action, command);
      expect(reply.messages, isEmpty);
    }
    for (final unknown in ['@execute:anything', '@library:unknown', '换浅色']) {
      expect(
        (await engine.replyAppCommand(unknown, const ChatState())).action,
        isNull,
      );
    }
  });

  test('explicit appearance command preserves unrelated state', () async {
    final reply = await engine.replyAppCommand(
      '@appearance:dark',
      const ChatState(appearance: 'light', safetyBlocked: true),
    );
    expect(reply.state.appearance, 'dark');
    expect(reply.state.safetyBlocked, isTrue);
    expect(reply.action, '@appearance:dark');
  });

  test(
    'explicit saved selection preserves the exact plan and restrictions',
    () async {
      final library = loadLibrary();
      final generator = TemplatePlanGenerator(
        lib: library,
        catalog: loadCatalog(),
      );
      final result = await generator.generate(
        const ScenarioRequest(templateId: 'office-relax'),
      );
      final plan = result.plan!;
      final saved = SavedPlan(
        id: 'one',
        name: '午间',
        plan: plan,
        savedAt: DateTime(2026),
      );
      final reply = await engine.replyAppCommand(
        '@saved:one',
        ChatState(saved: [saved]),
      );
      expect(reply.messages.single.plan, same(plan));
      expect(reply.state.request!.avoid, plan.avoid);
      expect(reply.state.plan, same(plan));
      expect(
        (await engine.replyAppCommand(
          '@saved:missing',
          const ChatState(),
        )).messages.single.text,
        contains('已经删掉'),
      );
      final blocked = await engine.replyAppCommand(
        '@saved:one',
        ChatState(saved: [saved], safetyBlocked: true),
      );
      expect(blocked.messages.any((message) => message.plan != null), isFalse);
    },
  );
}
