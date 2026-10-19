import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart' show defaultSuggestions;

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
    final lastCard = messages.lastWhere((m) => m.isPlan, orElse: () => _none);
    if (lastCard != _none) {
      _state = ChatState(
        plan: lastCard.plan,
        request: lastCard.request ?? requestForPlan(lastCard.plan!),
      );
    }
    final last = messages.isEmpty ? null : messages.last.at;
    if (last == null || _clock().difference(last) > const Duration(hours: 6)) {
      _bot(BotMessage(messages.isEmpty ? '说说今天想怎么练？' : '欢迎回来。今天想怎么练？'));
    }
    suggestions = _defaults();
    notifyListeners();
  }

  static final _none = ChatMessage(id: '', role: ChatRole.user, at: DateTime(2000));

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
    final isLink = o.isCommand && !o.value.startsWith('@save:');
    if (!isLink) _replace(m.copyWith(chosen: index));
    if (o.value.startsWith('@save:')) {
      final plan = _planById(o.value.substring(6));
      _user(o.label);
      if (plan != null) {
        final saved = await save(plan);
        _bot(BotMessage('存好了，叫「${saved.name}」。下次说「上次那个」或者从左下角的计划里一键开始。'));
      }
      notifyListeners();
      unawaited(_persist());
      return;
    }
    if (isLink) {
      _actions.add(o.value);
      notifyListeners();
      return;
    }
    await send(o.value, label: o.label);
  }

  // ------------------------------------------------------------ plans

  /// The plan on the latest card (what "再短一点" edits).
  TrainingPlan? get currentPlan => _state.plan;

  bool isSaved(TrainingPlan p) => store.savedFor(p) != null;

  Future<SavedPlan> save(TrainingPlan p) async {
    final saved = await store.savePlan(p);
    notifyListeners();
    return saved;
  }

  /// Called right before the player opens: becomes "上次那个".
  Future<void> started(TrainingPlan p) async {
    final saved = store.savedFor(p);
    if (saved != null) await store.touchPlan(saved.id);
    await store.rememberPlan(p);
  }

  /// Back from the player: a short word about it, and an offer to keep an
  /// unsaved plan that was actually trained.
  void finished(TrainingPlan p, {required int completed, required int total}) {
    if (total <= 0) return;
    final done = completed >= total;
    final text = done
        ? '练完「${p.title}」了，辛苦！记得喝点水。'
        : completed == 0
        ? '这次先到这儿。想换个更轻松的，跟我说「简单点」。'
        : '完成了 $completed/$total 个动作，已经不错了。';
    final offer = completed > 0 && !isSaved(p);
    _bot(BotMessage(
      offer ? '$text\n要把这套存下来，下次直接用吗？' : text,
      options: offer ? [ChatOption('保存这套', '@save:${p.id}')] : const [],
    ));
    suggestions = _defaults();
    notifyListeners();
    unawaited(_persist());
  }

  TrainingPlan? _planById(String id) {
    for (final m in messages.reversed) {
      if (m.plan?.id == id) return m.plan;
    }
    return null;
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
