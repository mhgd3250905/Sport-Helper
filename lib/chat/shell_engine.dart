import 'chat_models.dart';

/// Stand-in until the rule engine lands: acknowledges and waits.
class ShellChatEngine implements ChatEngine {
  const ShellChatEngine();
  @override
  String get id => 'shell';
  @override
  Future<ChatReply> reply(String text, ChatState state) async => ChatReply(
    messages: const [BotMessage('收到。训练计划马上就能在这里直接生成。')],
    state: state,
  );
}
