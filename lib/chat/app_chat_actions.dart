/// Explicit App navigation and settings actions. Conversation semantics belong
/// to the SDK; this boundary never interprets prose or creates a training plan.
library;

import '../domain/plan.dart';
import 'chat_models.dart';

const defaultSuggestions = [
  '办公室 10 分钟肩颈放松',
  '在家 20 分钟练核心',
  '睡前拉伸 10 分钟',
  '跑步前热身',
];

const discoveryChips = ['你能做什么'];
const planSuggestions = ['再短一点', '难一点', '换掉第 2 个', '换一套'];

List<String> discoverySuggestions({
  required bool returning,
  bool blocked = false,
}) => blocked ? const [] : const [...defaultSuggestions, '你能做什么'];

class AppChatActions implements AppCommandChatEngine {
  const AppChatActions();

  @override
  String get id => 'app-actions';

  @override
  Future<ChatReply> reply(String text, ChatState state) async =>
      state.safetyBlocked
      ? _blocked(state)
      : ChatReply(
          messages: const [
            BotMessage(
              'AI 教练暂不可用，可以先浏览动作库或打开已保存计划。',
              options: [
                ChatOption('动作库', '@library'),
                ChatOption('我的计划', '@drawer'),
              ],
            ),
          ],
          state: state,
        );

  @override
  Future<ChatReply> replyAppCommand(String command, ChatState state) async {
    if (command.startsWith('@saved:')) {
      final saved = state.saved
          .where((entry) => entry.id == command.substring(7))
          .firstOrNull;
      if (saved == null) {
        return ChatReply(
          messages: const [BotMessage('这套计划已经删掉了。')],
          state: state,
        );
      }
      if (state.safetyBlocked) return _blocked(state);
      return _showPlan(saved.plan, state, '「${saved.name}」来了。');
    }
    if (command == '@last') {
      final plan = state.lastPlan;
      if (plan == null) {
        return ChatReply(
          messages: const [BotMessage('还没有训练过的计划。')],
          state: state,
        );
      }
      if (state.safetyBlocked) return _blocked(state);
      return _showPlan(plan, state, '这是你上次的「${plan.title}」。');
    }
    if (command == '@history') return _history(state);
    const navigation = {
      '@library',
      '@settings',
      '@custom',
      '@drawer',
      '@safety',
    };
    const library = {
      '@library:strength',
      '@library:core',
      '@library:cardio',
      '@library:mobility',
      '@library:stretch',
    };
    if (navigation.contains(command) || library.contains(command)) {
      return ChatReply(messages: const [], state: state, action: command);
    }
    const appearance = {
      '@appearance:light': 'light',
      '@appearance:dark': 'dark',
      '@appearance:system': 'system',
    };
    if (appearance[command] case final value?) {
      return ChatReply(
        messages: const [],
        state: state.copyWith(appearance: value),
        action: command,
      );
    }
    const audio = {
      '@voice:on',
      '@voice:off',
      '@voice:mute',
      '@chimes:on',
      '@chimes:off',
    };
    return ChatReply(
      messages: const [],
      state: state,
      action: audio.contains(command) ? command : null,
    );
  }

  ChatReply _showPlan(TrainingPlan plan, ChatState state, String text) {
    final request = requestForPlan(plan);
    return ChatReply(
      messages: [BotMessage(text, plan: plan, request: request)],
      state: state.copyWith(plan: plan, request: request),
    );
  }

  ChatReply _blocked(ChatState state) => ChatReply(
    messages: const [
      BotMessage(
        '根据你的安全确认，先不生成训练计划；可以先浏览动作库或重新确认。',
        options: [ChatOption('动作库', '@library'), ChatOption('重新确认', '@safety')],
      ),
    ],
    state: state,
  );

  ChatReply _history(ChatState state) {
    if (state.history.isEmpty) {
      return ChatReply(messages: const [BotMessage('还没有训练记录。')], state: state);
    }
    final last = state.history.first;
    return ChatReply(
      messages: [
        BotMessage(
          '上次训练「${last.title}」，完成 ${last.completed}/${last.total} 个动作。',
          options: state.lastPlan != null && !state.safetyBlocked
              ? const [ChatOption('再来一次', '@last')]
              : const [],
        ),
      ],
      state: state,
    );
  }
}
