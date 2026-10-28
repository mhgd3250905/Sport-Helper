import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../data/app_store.dart';
import '../diagnostics/runtime_log.dart';
import '../domain/plan.dart';
import '../domain/saved_plan.dart';
import 'chat_models.dart';
import 'app_chat_actions.dart' show discoverySuggestions;
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
    this.prepareReply,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (engine case final ProgressChatEngine progress) {
      _progressSubscription = progress.events.listen(_onProgress);
    }
    _conversation?.addListener(_onConversationChanged);
  }

  final ChatEngine engine;
  final AppStore store;

  /// A short "typing" pause so replies don't snap in (0 in tests).
  final Duration replyDelay;
  final Future<void> Function()? prepareReply;
  final DateTime Function() _clock;

  final List<ChatMessage> messages = [];
  List<String> suggestions = discoverySuggestions(returning: false);
  bool typing = false;
  StreamSubscription<coach.AgentEvent>? _progressSubscription;
  final _progressEvents = StreamController<coach.AgentEvent>.broadcast();
  final _progressHistory = <coach.AgentEvent>[];

  /// Accepted events for the active turn, including events emitted before the
  /// typing widget has mounted. A cancelled or finished turn is never replayed.
  late final Stream<coach.AgentEvent> progressEvents = Stream.multi((listener) {
    final subscription = _progressEvents.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    for (final event in _progressHistory) {
      listener.add(event);
    }
    listener.onCancel = subscription.cancel;
  }, isBroadcast: true);
  coach.CoachTaskState? _latestTask;
  coach.CoachTaskState? get activeTask => _latestTask;
  String? _progressTurnId;
  final Set<String> _finishedProgressTurns = {};
  bool _progressEnded = true;
  ChatState _state = const ChatState();
  String? _diagnosticOperation;

  coach.CoachConversationController? get _conversation =>
      engine is ConversationChatEngine
      ? (engine as ConversationChatEngine).conversation
      : null;

  void _onConversationChanged() {
    _syncQuestions();
    _schedulePersistence();
    notifyListeners();
  }

  void _syncQuestions({bool appendMissing = false}) {
    final conversation = _conversation;
    if (conversation == null) return;
    final snapshots = {for (final m in conversation.state.messages) m.id: m};
    final existing = <String>{};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final sdkId = m.conversationMessageId ?? (m.aiVisible ? m.id : null);
      final snapshot = snapshots[sdkId];
      if (snapshot == null) continue;
      existing.add(snapshot.id);
      messages[i] = m.copyWith(
        text: snapshot.isUser ? null : snapshot.text,
        question: snapshot.question,
        conversationMessageId: snapshot.id,
        questionAnswered: snapshot.questionAnswered,
        answeredChoices: snapshot.answeredChoices,
        answeredForm: snapshot.answeredForm,
        actions: snapshot.actions,
        clearActions: snapshot.actions == null,
      );
    }
    if (appendMissing) {
      for (final sdk in conversation.state.messages) {
        // An in-flight user message already exists in the App display log.
        if (!sdk.isUser && !existing.contains(sdk.id)) {
          messages.add(_displayMessage(sdk));
        }
      }
    }
  }

  ChatMessage _displayMessage(coach.CoachConversationMessage sdk) {
    final plan = sdk.plan == null
        ? null
        : TrainingPlan.fromJson(sdk.plan!.plan.toJson());
    return ChatMessage(
      id: sdk.id,
      conversationMessageId: sdk.id,
      at: sdk.at,
      role: sdk.isUser ? ChatRole.user : ChatRole.assistant,
      text: sdk.text,
      question: sdk.question,
      questionAnswered: sdk.questionAnswered,
      answeredChoices: sdk.answeredChoices,
      answeredForm: sdk.answeredForm,
      isPlanningFailure: sdk.isFailure || sdk.isPlanningFailure,
      plan: plan,
      validatedPlan: sdk.plan,
      actions: sdk.actions,
      request: plan == null ? null : requestForPlan(plan),
      aiVisible: true,
    );
  }

  coach.CoachConversationMessage _sdkDisplay(ChatMessage m) =>
      coach.CoachConversationMessage(
        id: m.conversationMessageId ?? m.id,
        at: m.at,
        isUser: m.isUser,
        text: m.text,
        question: m.question,
        questionAnswered: m.questionAnswered,
        answeredChoices: m.answeredChoices,
        answeredForm: m.answeredForm,
        isFailure: m.isPlanningFailure,
        isPlanningFailure: m.isPlanningFailure,
        plan: m.validatedPlan,
        actions: m.actions,
      );

  void _schedulePersistence() {
    if (!_started || _restoring || _disposed) return;
    _persistenceTimer?.cancel();
    _persistenceTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(_persist());
    });
  }

  void _onProgress(coach.AgentEvent event) {
    if (event.kind == coach.AgentEventKind.snapshotRestoreFallback) {
      RuntimeLog.instance.record(
        'chat.snapshot_restore_fallback',
        fields: {'reason': event.path ?? 'invalid_snapshot'},
      );
      return;
    }
    if (!typing ||
        _progressEnded ||
        _finishedProgressTurns.contains(event.turnId)) {
      return;
    }
    if (_progressTurnId != null && _progressTurnId != event.turnId) return;
    _progressTurnId ??= event.turnId;
    RuntimeLog.instance.record(
      'chat.progress',
      operation: _diagnosticOperation,
      fields: {'kind': event.kind.name, 'step': event.step},
    );
    if (event.kind == coach.AgentEventKind.node && event.task != null) {
      _latestTask = event.task;
      _schedulePersistence();
      notifyListeners();
    }
    _progressHistory.add(event);
    if (_progressHistory.length > 64) _progressHistory.removeAt(0);
    _progressEvents.add(event);
    if (event.kind == coach.AgentEventKind.done) {
      _endProgress();
    }
  }

  void _endProgress() {
    final turnId = _progressTurnId;
    if (turnId != null) {
      _finishedProgressTurns.add(turnId);
      // The SDK suppresses cancelled events; retain only recent UI turns too.
      if (_finishedProgressTurns.length > 64) {
        _finishedProgressTurns.remove(_finishedProgressTurns.first);
      }
    }
    _progressTurnId = null;
    _progressEnded = true;
    _progressHistory.clear();
  }

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
  bool _restoring = false;
  bool _disposed = false;
  Timer? _persistenceTimer;

  /// Runs an app command (`@drawer`, `@library`…) as if a bubble asked.
  void command(String action) {
    RuntimeLog.instance.record(
      'chat.command',
      fields: {'kind': _commandKind(action)},
    );
    _actions.add(action);
  }

  static String _commandKind(String action) {
    final kind = action.split(':').first;
    const commands = {
      '@drawer',
      '@library',
      '@settings',
      '@custom',
      '@saved',
      '@save',
      '@appearance',
      '@voice',
      '@chimes',
      '@safety',
    };
    return commands.contains(kind) ? kind.substring(1) : 'other';
  }

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
        messages.add(
          ChatMessage.fromJson(
            j,
            restoreWith: engine is RestorableChatEngine
                ? engine as RestorableChatEngine
                : null,
          ),
        );
      } on Object {
        // Skip a message an older build wrote differently.
      }
    }
    final conversation = _conversation;
    if (conversation != null) {
      final sdkMessages = store.coachDisplayMessages.isEmpty
          ? messages.where((m) => m.aiVisible).map(_sdkDisplay).toList()
          : _readSdkDisplay();
      _restoring = true;
      try {
        final encoded = store.coachSessionJson;
        if (encoded == null) {
          conversation.restoreHistory(sdkMessages);
        } else {
          Object? decoded;
          try {
            decoded = jsonDecode(encoded);
          } on FormatException {
            decoded = null;
          }
          conversation.restoreSession(
            coach.CoachSessionSnapshot.fromJson(decoded),
            sdkMessages,
          );
        }
      } finally {
        _restoring = false;
      }
      _syncQuestions(appendMissing: true);
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
      _bot(
        BotMessage(
          '${greetingFor(_clock())}\n${messages.isEmpty ? '说说今天想怎么练？' : '欢迎回来，今天想怎么练？'}',
          greeting: true,
        ),
      );
    }
    suggestions = _defaults();
    notifyListeners();
  }

  static final _none = ChatMessage(
    id: '',
    role: ChatRole.user,
    at: DateTime(2000),
  );

  List<coach.CoachConversationMessage> _readSdkDisplay() {
    final restored = <coach.CoachConversationMessage>[];
    for (final row in store.coachDisplayMessages) {
      try {
        restored.add(
          _sdkDisplay(
            ChatMessage.fromJson(
              row,
              restoreWith: engine is RestorableChatEngine
                  ? engine as RestorableChatEngine
                  : null,
            ),
          ),
        );
      } on Object catch (error) {
        RuntimeLog.instance.record(
          'chat.display_restore_error',
          fields: {'errorType': RuntimeLog.errorType(error)},
        );
      }
    }
    return restored;
  }

  /// Cancels this turn immediately; a late transport response cannot add cards.
  void cancelRequest() {
    if (!typing) return;
    _closeQuestion();
    _cancelDiagnostic('user_cancel');
    _replyEpoch++;
    typing = false;
    _endProgress();
    if (engine case final ManagedChatEngine managed) managed.cancelPending();
    suggestions = _defaults();
    notifyListeners();
    unawaited(_persist());
  }

  /// Starts a fresh SDK conversation while retaining saved plans and safety.
  Future<void>? _newConversationPending;

  Future<void> newConversation() {
    final pending = _newConversationPending;
    if (pending != null) return pending;
    final action = _newConversation();
    _newConversationPending = action;
    return action.whenComplete(() {
      if (identical(_newConversationPending, action)) {
        _newConversationPending = null;
      }
    });
  }

  Future<void> _newConversation() async {
    final log = RuntimeLog.instance;
    final snapshot = log.enabled
        ? _conversation?.exportSession().toJson()
        : null;
    _cancelDiagnostic('new_conversation');
    RuntimeLog.instance.record('chat.conversation.new');
    _replyEpoch++;
    typing = false;
    _endProgress();
    if (engine case final ManagedChatEngine managed) managed.cancelPending();
    if (snapshot != null) await log.archiveSession(snapshot);
    if (_disposed) return;
    if (engine case final ManagedChatEngine managed) managed.reset();
    _state = const ChatState();
    _latestTask = null;
    _safetyStep = null;
    _safetyMessageId = null;
    messages.clear();
    if (!store.safetyAccepted) {
      _beginSafety(firstRun: true);
    } else {
      _bot(BotMessage('${greetingFor(_clock())}\n说说今天想怎么练？', greeting: true));
      suggestions = _defaults();
    }
    notifyListeners();
    await _persist();
  }

  ChatState get _context => _state.copyWith(
    safetyBlocked: !store.trainingAllowed,
    saved: List.unmodifiable(store.savedPlans),
    lastPlan: store.lastPlan,
    history: [
      for (final h in store.history)
        WorkoutLog(
          title: h.title,
          at: h.at,
          minutes: h.minutes,
          completed: h.completed,
          total: h.total,
        ),
    ],
    appearance: store.appearance,
    systemLight:
        PlatformDispatcher.instance.platformBrightness == Brightness.light,
    now: _clock(),
    recentMessages: List.unmodifiable(
      messages.skip(messages.length > 20 ? messages.length - 20 : 0),
    ),
  );

  /// The user typed [text] (or tapped a chip / option labelled [label]).
  Future<void> send(String text, {String? label}) => _send(text, label: label);

  Future<void> _send(
    String text, {
    String? label,
    bool trustedAppCommand = false,
    String? questionId,
    List<String>? choices,
    Map<String, List<String>>? formAnswers,
    bool skipQuestion = false,
  }) async {
    if (_newConversationPending case final reset?) await reset;
    final t = text.trim();
    if (t.isEmpty || typing) return;
    final operation = RuntimeLog.instance.newOperation('chat');
    RuntimeLog.instance.recordDeveloper(
      'chat.user',
      operation: operation,
      fields: {'inputChars': t.length},
      data: {
        'text': text,
        'sentText': t,
        'displayLabel': ?label,
        'appCommand': trustedAppCommand,
        'questionId': ?questionId,
      },
    );
    final userMessage = _user(label ?? t);
    if (inSafetyCheck) {
      _bot(const BotMessage('先把上面的安全确认做完，再帮你排计划。'));
      notifyListeners();
      unawaited(_persist());
      return;
    }
    final epoch = ++_replyEpoch;
    final watch = Stopwatch()..start();
    _diagnosticOperation = operation;
    RuntimeLog.instance.record(
      'chat.send',
      operation: operation,
      fields: {'inputChars': t.length},
    );
    typing = true;
    _latestTask = null;
    _endProgress();
    _progressEnded = false;
    notifyListeners();
    if (prepareReply case final prepare?) {
      RuntimeLog.instance.record('chat.prepare.begin', operation: operation);
      try {
        await prepare();
        RuntimeLog.instance.record(
          'chat.prepare.end',
          operation: operation,
          fields: const {'success': true},
        );
      } on Object catch (error) {
        RuntimeLog.instance.record(
          'chat.prepare.end',
          operation: operation,
          fields: {'success': false, 'errorType': RuntimeLog.errorType(error)},
        );
        // Media availability cannot prevent text or a training plan.
      }
      if (epoch != _replyEpoch) return;
    }
    if (engine case final DiagnosticChatEngine diagnostic) {
      diagnostic.diagnosticOperation = operation;
    } else {
      RuntimeLog.instance.record(
        'chat.route',
        operation: operation,
        fields: const {'route': 'local', 'reason': 'offline_engine'},
      );
    }
    final ChatReply reply;
    try {
      reply = questionId != null && engine is ConversationChatEngine
          ? await (engine as ConversationChatEngine).replyAnswer(
              questionId,
              t,
              _context,
              choices: choices,
              formAnswers: formAnswers,
              skipQuestion: skipQuestion,
            )
          : trustedAppCommand && engine is AppCommandChatEngine
          ? await (engine as AppCommandChatEngine).replyAppCommand(t, _context)
          : await engine.reply(t, _context);
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'chat.error',
        operation: operation,
        fields: {
          'errorType': RuntimeLog.errorType(error),
          'elapsedMs': watch.elapsedMilliseconds,
        },
      );
      if (_diagnosticOperation == operation) _diagnosticOperation = null;
      rethrow;
    }
    if (replyDelay > Duration.zero) await Future<void>.delayed(replyDelay);
    if (epoch != _replyEpoch) {
      RuntimeLog.instance.record(
        'chat.reply.discarded',
        operation: operation,
        fields: {'elapsedMs': watch.elapsedMilliseconds},
      );
      return;
    }
    typing = false;
    _endProgress();
    _state = reply.state;
    if (reply.aiTurn) _replace(userMessage.copyWith(aiVisible: true));
    for (final m in reply.messages) {
      _bot(m, aiVisible: reply.aiTurn);
    }
    _syncQuestions();
    RuntimeLog.instance.record(
      'chat.reply.rendered',
      operation: operation,
      fields: {
        'elapsedMs': watch.elapsedMilliseconds,
        'count': reply.messages.length,
        'hasPlan': reply.messages.any((message) => message.plan != null),
        'hasActions': reply.messages.any((message) => message.actions != null),
      },
    );
    _diagnosticOperation = null;
    // A question with its own options doesn't need the chips too.
    final asks =
        _conversation?.state.pendingQuestion != null ||
        reply.messages.any((m) => m.options.isNotEmpty || m.question != null);
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
      command(a);
    }
  }

  /// A question is interactive only after the SDK send returned and while
  /// it remains the newest unanswered question in this live conversation.
  bool canAnswerQuestion(ChatMessage message) {
    final id = message.conversationMessageId;
    return !typing &&
        !inSafetyCheck &&
        id != null &&
        (_conversation?.canAnswer(id) ?? false);
  }

  Future<void> answerQuestion(ChatMessage message, String text) async {
    if (!canAnswerQuestion(message) || text.trim().isEmpty) return;
    await _send(text, questionId: message.conversationMessageId);
  }

  Future<void> answerChoices(ChatMessage message, List<String> selected) async {
    if (!canAnswerQuestion(message)) return;
    final id = message.conversationMessageId!;
    final text = _conversation?.choiceText(id, selected);
    if (text == null) return;
    await _send(text, questionId: id, choices: selected);
  }

  Future<void> answerForm(
    ChatMessage message,
    Map<String, List<String>> answers,
  ) async {
    if (!canAnswerQuestion(message)) return;
    final question = message.question!;
    final snapshot = {
      for (final entry in answers.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    // This is only the visible user bubble. The SDK receives the original
    // grouped values and owns validation, option ordering and task state.
    final label = [
      for (final field in question.fields)
        if (snapshot[field.key]?.isNotEmpty ?? false)
          '${field.label}：${snapshot[field.key]!.join('、')}',
    ].join('；');
    await _send(
      label,
      questionId: message.conversationMessageId,
      formAnswers: snapshot,
    );
  }

  Future<void> skipQuestion(ChatMessage message) async {
    if (!canAnswerQuestion(message)) return;
    await _send(
      message.question!.skipLabel,
      questionId: message.conversationMessageId,
      skipQuestion: true,
    );
  }

  void _closeQuestion() {
    _conversation?.invalidateQuestion();
    _syncQuestions();
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
    if (!isActive(m) || index < 0 || index >= m.options.length || typing) {
      return;
    }
    final o = m.options[index];
    // Links (动作库, 全部计划) stay tappable; answers lock.
    final isLink =
        o.isCommand &&
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
      command(o.value);
      notifyListeners();
      return;
    }
    await _send(o.value, label: o.label, trustedAppCommand: o.isCommand);
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
    final card = messages.where((m) => m.plan?.id == p.id).lastOrNull;
    final request = card?.request ?? requestForPlan(p);
    if (p.source == 'ai') {
      final managed = engine;
      if (managed is! RestorableChatEngine ||
          managed.restorePlan(p, request) == null) {
        return false;
      }
    }
    final saved = store.savedFor(p);
    if (saved != null) await store.touchPlan(saved.id);
    await store.rememberPlan(p);
    if (!store.trainingAllowed) return false;
    _state = _state.copyWith(plan: p, request: request);
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
    _bot(
      BotMessage(
        offer ? '$text\n要把这套存下来，下次直接用吗？' : text,
        options: offer ? [ChatOption('保存这套', '@save:${p.id}')] : const [],
      ),
    );
    suggestions = _defaults();
    notifyListeners();
    unawaited(_persist());
  }

  /// A saved plan picked in the drawer: show it as a card in the chat.
  Future<void> showSaved(SavedPlan p) =>
      _send('@saved:${p.id}', label: p.name, trustedAppCommand: true);

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
    _closeQuestion();
    _cancelDiagnostic('safety_check');
    _replyEpoch++;
    typing = false;
    _endProgress();
    if (engine case final ManagedChatEngine managed) managed.cancelPending();
    unawaited(store.beginSafetyCheck());
    if (firstRun) {
      messages.clear();
      _bot(const BotMessage(safetyIntro));
    } else {
      _bot(const BotMessage('好，重新做一次安全确认。'));
    }
    _safetyMessageId = _bot(
      const BotMessage(
        safetyDisclaimer,
        options: [ChatOption('我已了解', '@safety:ack')],
      ),
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
    _safetyMessageId = _bot(
      BotMessage(
        safetyQuestionText(i),
        options: const [
          ChatOption('否', '@safety:no'),
          ChatOption('是', '@safety:yes'),
        ],
      ),
    ).id;
  }

  Future<void> _finishSafety({required int? blockedBy}) async {
    _safetyStep = null;
    _safetyMessageId = null;
    await store.acceptSafety(blocked: blockedBy != null);
    if (blockedBy == null) {
      _bot(const BotMessage(safetyAllClear));
      suggestions = _defaults();
    } else {
      _bot(
        BotMessage(
          safetyBlockedText(blockedBy),
          options: const [ChatOption('浏览动作库', '@library')],
        ),
      );
      suggestions = const ['浏览动作库'];
    }
  }

  // ------------------------------------------------------------ helpers

  List<String> _defaults() => discoverySuggestions(
    returning:
        store.lastPlan != null ||
        store.savedPlans.isNotEmpty ||
        store.history.isNotEmpty,
    blocked: store.safetyBlocked,
  );

  ChatMessage _user(String text) => _add(
    ChatMessage(id: _id(), role: ChatRole.user, at: _clock(), text: text),
  );

  ChatMessage _bot(BotMessage m, {bool aiVisible = false}) {
    var plan = m.plan;
    var validatedPlan = m.validatedPlan;
    if (plan != null && plan.source == 'ai' && validatedPlan == null) {
      if (engine case final RestorableChatEngine restorable) {
        validatedPlan = restorable.restorePlan(plan, m.request);
      }
      if (validatedPlan == null) plan = null;
    }
    return _add(
      ChatMessage(
        id: _id(),
        role: ChatRole.assistant,
        at: _clock(),
        text: m.text,
        options: m.options,
        question: m.question,
        conversationMessageId: m.conversationMessageId,
        answeredForm: m.answeredForm,
        isPlanningFailure: m.isPlanningFailure,
        plan: plan,
        validatedPlan: validatedPlan,
        coachTask: aiVisible ? _latestTask : m.coachTask,
        actions: m.actions,
        request: m.request,
        greeting: m.greeting,
        aiVisible: aiVisible,
      ),
    );
  }

  ChatMessage _add(ChatMessage m) {
    messages.add(m);
    return m;
  }

  void _replace(ChatMessage m) {
    final i = messages.indexWhere((x) => x.id == m.id);
    if (i >= 0) messages[i] = m;
  }

  String _id() => 'm${_clock().microsecondsSinceEpoch}-${_seq++}';

  /// Also used at lifecycle boundaries and by explicit local verification.
  Future<void> flushPersistence() => _persist();

  Future<void> _persist() async {
    _persistenceTimer?.cancel();
    try {
      final conversation = _conversation;
      final snapshot = conversation == null
          ? null
          : jsonEncode(conversation.exportSession().toJson());
      final sdkMessages = <Map<String, dynamic>>[
        for (final m
            in conversation?.state.messages ??
                <coach.CoachConversationMessage>[])
          _displayMessage(m).toJson().cast<String, dynamic>(),
      ];
      await store.setConversation(
        [for (final m in messages) m.toJson().cast<String, dynamic>()],
        sessionJson: snapshot,
        sdkMessages: sdkMessages,
      );
    } on Object catch (error) {
      RuntimeLog.instance.record(
        'chat.persist.error',
        fields: {'errorType': RuntimeLog.errorType(error)},
      );
      rethrow;
    }
  }

  void _cancelDiagnostic(String reason) {
    final operation = _diagnosticOperation;
    if (operation == null) return;
    RuntimeLog.instance.record(
      'chat.cancel',
      operation: operation,
      fields: {'reason': reason},
    );
    _diagnosticOperation = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _persistenceTimer?.cancel();
    _conversation?.removeListener(_onConversationChanged);
    _cancelDiagnostic('dispose');
    _replyEpoch++;
    typing = false;
    _endProgress();
    unawaited(_progressSubscription?.cancel());
    unawaited(_progressEvents.close());
    if (_started) unawaited(_persist());
    if (engine case final ManagedChatEngine managed) managed.cancelPending();
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
