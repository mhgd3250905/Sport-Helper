import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import 'chat_models.dart';
import 'rule_chat_engine.dart' show discoverySuggestions;
import 'safety_script.dart';

/// Owns the chat home's conversation: the message list, the engine's state,
/// the safety talk (first launch and re-checks), saving plans, and
/// persisting the recent history in [AppStore]. UI-only commands
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
  List<String> suggestions = discoverySuggestions(returning: false);
  bool typing = false;
  ChatState _state = const ChatState();

  /// Index into [safetyQuestions] while the safety talk runs (-1 = waiting
  /// for "我已了解"); null when no safety talk is open.
  int? _safetyStep;
  String? _safetyMessageId;

  bool get inSafetyCheck => _safetyStep != null;

  final _actions = StreamController<String>.broadcast();
  Stream<String> get actions => _actions.stream;

  int _seq = 0;
  int _replyEpoch = 0;
  bool _started = false;

  /// Runs an app command (`@drawer`, `@library`…) as if a bubble asked.
  void command(String action) => _actions.add(action);

  void start() {
    if (_started) return;
    _started = true;
    if (!store.safetyAccepted) {
      _beginSafety(firstRun: true);
      notifyListeners();
      return;
    }
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
      _bot(BotMessage(
        '${greetingFor(_clock())}\n${messages.isEmpty ? '说说今天想怎么练？' : '欢迎回来，今天想怎么练？'}',
        greeting: true,
      ));
    }
    suggestions = _defaults();
    notifyListeners();
  }

  static final _none = ChatMessage(id: '', role: ChatRole.user, at: DateTime(2000));

  ChatState get _context => _state.copyWith(
    safetyBlocked: !store.trainingAllowed,
    saved: List.unmodifiable(store.savedPlans),
    lastPlan: store.lastPlan,
    history: [
      for (final h in store.history)
        WorkoutLog(title: h.title, at: h.at, minutes: h.minutes, completed: h.completed, total: h.total),
    ],
    appearance: store.appearance,
    now: _clock(),
  );

  /// The user typed [text] (or tapped a chip / option labelled [label]).
  Future<void> send(String text, {String? label}) async {
    final t = text.trim();
    if (t.isEmpty || typing) return;
    _user(label ?? t);
    if (inSafetyCheck) {
      _bot(const BotMessage('先把上面的安全确认做完，再帮你排计划。'));
      notifyListeners();
      unawaited(_persist());
      return;
    }
    final epoch = ++_replyEpoch;
    typing = true;
    notifyListeners();
    final reply = await engine.reply(t, _context);
    if (replyDelay > Duration.zero) await Future<void>.delayed(replyDelay);
    if (epoch != _replyEpoch) return;
    typing = false;
    _state = reply.state;
    for (final m in reply.messages) {
      _bot(m);
    }
    // A question with its own options doesn't need the chips too.
    final asks = reply.messages.any((m) => m.options.isNotEmpty);
    suggestions = reply.suggestions.isNotEmpty
        ? reply.suggestions
        : (asks ? const [] : _defaults());
    notifyListeners();
    unawaited(_persist());
    if (reply.action case final a?) _run(a);
  }

  /// Settings the conversation changes itself (外观, 语音, 安全确认); the
  /// rest (`@library`, `@settings`, `@custom`, `@drawer`) go to the UI.
  void _run(String a) {
    if (a.startsWith('@appearance:')) {
      unawaited(store.setAppearance(a.substring(12)));
    } else if (a.startsWith('@voice:') || a.startsWith('@chimes:')) {
      final v = store.voice;
      final next = switch (a) {
        '@voice:off' => v.copyWith(voice: false),
        '@voice:on' => v.copyWith(voice: true),
        '@voice:mute' => v.copyWith(voice: false, chimes: false),
        '@chimes:off' => v.copyWith(chimes: false),
        '@chimes:on' => v.copyWith(chimes: true),
        _ => v,
      };
      unawaited(store.setVoice(next));
    } else if (a == '@safety') {
      startSafetyCheck();
    } else {
      _actions.add(a);
    }
  }

  /// Can [m]'s options still be tapped?
  bool isActive(ChatMessage m) {
    if (m.options.isEmpty || m.chosen != null) return false;
    if (m.options.any((o) => o.value.startsWith('@safety:'))) {
      return m.id == _safetyMessageId;
    }
    return true;
  }

  Future<void> choose(ChatMessage m, int index) async {
    if (!isActive(m) || index < 0 || index >= m.options.length || typing) return;
    final o = m.options[index];
    // Links (动作库, 全部计划) stay tappable; answers lock.
    final isLink = o.isCommand &&
        !o.value.startsWith('@save:') &&
        !o.value.startsWith('@saved:') &&
        !o.value.startsWith('@safety');
    if (!isLink) _replace(m.copyWith(chosen: index));
    if (o.value.startsWith('@safety:')) return _safetyAnswer(o);
    if (o.value == '@safety') {
      startSafetyCheck();
      return;
    }
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
  Future<bool> started(TrainingPlan p) async {
    if (!store.trainingAllowed) return false;
    final saved = store.savedFor(p);
    if (saved != null) await store.touchPlan(saved.id);
    await store.rememberPlan(p);
    if (!store.trainingAllowed) return false;
    final card = messages.where((m) => m.plan?.id == p.id).lastOrNull;
    final request = card?.request ?? requestForPlan(p);
    _state = _state.copyWith(clearPending: true, plan: p, request: request);
    // A plan edited in its detail page is a distinct version. Keep that
    // exact snapshot so the post-workout save offer survives a restart.
    if (card == null) _bot(BotMessage('', plan: p, request: request));
    notifyListeners();
    await _persist();
    return store.trainingAllowed;
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

  /// A saved plan picked in the drawer: show it as a card in the chat.
  Future<void> showSaved(SavedPlan p) => send('@saved:${p.id}', label: p.name);

  TrainingPlan? _planById(String id) {
    for (final m in messages.reversed) {
      if (m.plan?.id == id) return m.plan;
    }
    return null;
  }

  // ------------------------------------------------------------ safety

  void startSafetyCheck() {
    _beginSafety(firstRun: false);
    notifyListeners();
  }

  void _beginSafety({required bool firstRun}) {
    _replyEpoch++;
    typing = false;
    unawaited(store.beginSafetyCheck());
    if (firstRun) {
      messages.clear();
      _bot(const BotMessage(safetyIntro));
    } else {
      _bot(const BotMessage('好，重新做一次安全确认。'));
    }
    _safetyMessageId = _bot(
      const BotMessage(safetyDisclaimer, options: [ChatOption('我已了解', '@safety:ack')]),
    ).id;
    _safetyStep = -1;
    suggestions = const [];
  }

  Future<void> _safetyAnswer(ChatOption o) async {
    final step = _safetyStep;
    if (step == null) return;
    _user(o.label);
    if (o.value == '@safety:ack') {
      _bot(const BotMessage(safetyLead));
      _askSafety(0);
    } else if (o.value == '@safety:no') {
      if (step + 1 < safetyQuestions.length) {
        _askSafety(step + 1);
      } else {
        await _finishSafety(blockedBy: null);
      }
    } else {
      await _finishSafety(blockedBy: step);
    }
    notifyListeners();
    unawaited(_persist());
  }

  void _askSafety(int i) {
    _safetyStep = i;
    _safetyMessageId = _bot(BotMessage(
      safetyQuestionText(i),
      options: const [ChatOption('否', '@safety:no'), ChatOption('是', '@safety:yes')],
    )).id;
  }

  Future<void> _finishSafety({required int? blockedBy}) async {
    _safetyStep = null;
    _safetyMessageId = null;
    await store.acceptSafety(blocked: blockedBy != null);
    if (blockedBy == null) {
      _bot(const BotMessage(safetyAllClear));
      suggestions = _defaults();
    } else {
      _bot(BotMessage(
        safetyBlockedText(blockedBy),
        options: const [ChatOption('浏览动作库', '@library')],
      ));
      suggestions = const ['浏览动作库'];
    }
  }

  // ------------------------------------------------------------ helpers

  List<String> _defaults() => discoverySuggestions(
    returning: store.lastPlan != null || store.savedPlans.isNotEmpty || store.history.isNotEmpty,
    blocked: store.safetyBlocked,
  );

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
    greeting: m.greeting,
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
    _replyEpoch++;
    _actions.close();
    super.dispose();
  }
}

/// 早上好 / 中午好 / 下午好 / 晚上好 / 夜深了, by the hour of [t].
String greetingFor(DateTime t) => switch (t.hour) {
  >= 5 && < 11 => '早上好',
  >= 11 && < 13 => '中午好',
  >= 13 && < 18 => '下午好',
  >= 18 && < 23 => '晚上好',
  _ => '夜深了',
};
