import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import 'chat_models.dart';

const defaultSuggestions = ['办公室 10 分钟肩颈放松', '在家 20 分钟练核心', '睡前拉伸 10 分钟', '跑步前热身'];

/// Owns the chat home's conversation: the message list, the engine's state,
/// and persisting the recent history in [AppStore]. UI-only commands
/// (`@library`, `@drawer`…) come out of [actions].
class ChatController extends ChangeNotifier {
  ChatController({
    required this.engine,
    required this.store,
    this.replyDelay = const Duration(milliseconds: 450),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ChatEngine engine;
  final AppStore store;

  /// A short "typing" pause so replies don't snap in (0 in tests).
  final Duration replyDelay;
  final DateTime Function() _clock;

  final List<ChatMessage> messages = [];
  List<String> suggestions = defaultSuggestions;
  bool typing = false;
  ChatState _state = const ChatState();

  final _actions = StreamController<String>.broadcast();
  Stream<String> get actions => _actions.stream;

  int _seq = 0;
  bool _started = false;

  /// Runs an app command (`@drawer`, `@library`…) as if a bubble asked.
  void command(String action) => _actions.add(action);

  void start() {
    if (_started) return;
    _started = true;
    for (final j in store.chatLog) {
      try {
        messages.add(ChatMessage.fromJson(j));
      } on Object {
        // Skip a message an older build wrote differently.
      }
    }
    final last = messages.isEmpty ? null : messages.last.at;
    if (last == null || _clock().difference(last) > const Duration(hours: 6)) {
      _bot(BotMessage(messages.isEmpty ? '说说今天想怎么练？' : '欢迎回来。今天想怎么练？'));
    }
    suggestions = _defaults();
    notifyListeners();
  }

  ChatState get _context => _state.copyWith(safetyBlocked: store.safetyBlocked);

  /// The user typed [text] (or tapped a chip / option labelled [label]).
  Future<void> send(String text, {String? label}) async {
    final t = text.trim();
    if (t.isEmpty || typing) return;
    _user(label ?? t);
    typing = true;
    notifyListeners();
    final reply = await engine.reply(t, _context);
    if (replyDelay > Duration.zero) await Future<void>.delayed(replyDelay);
    typing = false;
    _state = reply.state;
    for (final m in reply.messages) {
      _bot(m);
    }
    suggestions = reply.suggestions.isEmpty ? _defaults() : reply.suggestions;
    notifyListeners();
    unawaited(_persist());
    if (reply.action != null) _actions.add(reply.action!);
  }

  /// Can [m]'s options still be tapped?
  bool isActive(ChatMessage m) {
    if (m.options.isEmpty || m.chosen != null) return false;
    return true;
  }

  Future<void> choose(ChatMessage m, int index) async {
    if (!isActive(m) || index < 0 || index >= m.options.length || typing) return;
    final o = m.options[index];
    // Links (动作库, 全部计划) stay tappable; answers lock.
    final isLink = o.isCommand;
    if (!isLink) _replace(m.copyWith(chosen: index));
    if (isLink) {
      _actions.add(o.value);
      notifyListeners();
      return;
    }
    await send(o.value, label: o.label);
  }

  // ------------------------------------------------------------ helpers

  List<String> _defaults() => defaultSuggestions;

  ChatMessage _user(String text) => _add(ChatMessage(
    id: _id(),
    role: ChatRole.user,
    at: _clock(),
    text: text,
  ));

  ChatMessage _bot(BotMessage m) => _add(ChatMessage(
    id: _id(),
    role: ChatRole.assistant,
    at: _clock(),
    text: m.text,
    options: m.options,
    plan: m.plan,
    request: m.request,
  ));

  ChatMessage _add(ChatMessage m) {
    messages.add(m);
    return m;
  }

  void _replace(ChatMessage m) {
    final i = messages.indexWhere((x) => x.id == m.id);
    if (i >= 0) messages[i] = m;
  }

  String _id() => 'm${_clock().microsecondsSinceEpoch}-${_seq++}';

  Future<void> _persist() =>
      store.setChatLog([for (final m in messages) m.toJson().cast<String, dynamic>()]);

  @override
  void dispose() {
    _actions.close();
    super.dispose();
  }
}
