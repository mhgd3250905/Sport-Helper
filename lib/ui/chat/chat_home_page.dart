import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show SessionResult;
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import '../../app/services.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../diagnostics/performance_lab.dart';
import '../about_page.dart';
import '../custom_plan_page.dart';
import '../library_page.dart';
import '../plan_page.dart';
import '../player_page.dart';
import '../theme/app_theme.dart';
import '../theme/solid_surface.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../training_route.dart';
import '../training_entry_placeholder.dart';
import 'chat_widgets.dart';
import 'chat_composer_dock.dart';
import 'coach_ui_adapter.dart';
import 'cosmos.dart';
import 'coach_task_bubble.dart';
import 'coach_delivery_transition.dart';
import 'plan_card.dart';
import 'saved_plans_page.dart';
import 'validated_plan_card.dart';
import 'chat_timeline.dart';
import 'training_card_media.dart';

/// The home screen: one conversation floating in an endless sky. No app
/// bar, no borders; the input's left icon opens the feature panel.
class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key, this.controller, this.scrollController});

  /// Injected by tests; otherwise the app-wide [AppServices.chat].
  final ChatController? controller;

  /// Internal scripted comparisons share the production conversation viewport.
  /// A supplied controller remains owned by its caller.
  final ScrollController? scrollController;

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage>
    with WidgetsBindingObserver {
  late ChatController _chat;
  StreamSubscription<String>? _actions;
  late final _scroll = widget.scrollController ?? ScrollController();

  /// Only the reverse list's viewport follows the dock. Its cached subtree
  /// keeps message state while the menu animates; the page is not rebuilt.
  final _dockExtent = ValueNotifier<double>(112);
  String? _pendingDeliveryId;
  String? _pendingUserId;
  DateTime? _pendingDeliveryAt;
  Set<String> _replyStartIds = {};
  final Map<String, String> _deliveryEntryIds = {};
  final Map<String, GlobalKey> _deliveryKeys = {};
  final _trainingMedia = <String, TrainingCardMediaRegistry>{};
  final _finishedEntries = <String>{};
  final _finishedSessions = <String>{};
  final _input = FocusNode();
  bool _panelOpen = false;
  bool _trainingInFlight = false;
  int _trainingLaunchEpoch = 0;

  /// Messages already on screen when the page opened don't animate in.
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _dismissInput() {
    _input.unfocus(disposition: UnfocusDisposition.scope);
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  void _togglePanel() {
    if (_panelOpen) {
      _closePanel();
      return;
    }
    setState(() => _panelOpen = true);
  }

  void _closePanel() {
    if (!_panelOpen) return;
    setState(() => _panelOpen = false);
  }

  void _inputTapped() {
    _closePanel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _trainingLaunchEpoch++;
      unawaited(_chat.flushPersistence());
    }
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.resumed) &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _dismissInput();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_actions != null) return;
    final s = AppServices.of(context);
    _chat = widget.controller ?? s.chat;
    _chat.start();
    _seen.addAll(_chat.messages.map((m) => m.id));
    _actions = _chat.actions.listen(_onAction);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actions?.cancel();
    if (widget.scrollController == null) _scroll.dispose();
    _input.dispose();
    _dockExtent.dispose();
    for (final registry in _trainingMedia.values) {
      registry.dispose();
    }
    super.dispose();
  }

  void _onAction(String a) {
    if (!mounted) return;
    switch (a) {
      case '@library':
        _push(const LibraryPage());
      case final c when c.startsWith('@library:'):
        _push(LibraryPage(initial: ExerciseCategory.byName(c.substring(9))));
      case '@settings':
        _push(const AboutPage());
      case '@custom':
        _push(const CustomPlanPage());
      case '@drawer':
        _openPlans();
    }
  }

  Future<void> _push(Widget page) async {
    _closePanel();
    _dismissInput();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: switch (page) {
            LibraryPage() => 'library',
            AboutPage() => 'settings',
            CustomPlanPage() => 'custom_plan',
            SavedPlansPage() => 'saved_plans',
            _ => 'other',
          },
        ),
        builder: (_) => page,
      ),
    );
    if (mounted) _dismissInput();
  }

  void _openPlans() {
    final s = AppServices.of(context);
    unawaited(
      _push(
        SavedPlansPage(
          store: s.store,
          library: s.library,
          onShow: (p) {
            Navigator.of(context).pop();
            unawaited(_chat.showSaved(p));
          },
          onStart: (p, _) {
            Navigator.of(context).pop();
            unawaited(_start(p.plan));
          },
          onCompose: () {
            Navigator.of(context).pop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _input.requestFocus();
            });
          },
        ),
      ),
    );
  }

  /// Open the stable video stage directly; the summary follows back in chat.
  Future<void> _start(TrainingPlan p, {String? messageId}) async {
    if (_trainingInFlight) return;
    final s = AppServices.of(context);
    if (p.items.any((item) => !s.library.contains(item.exerciseId))) {
      _toast('计划包含尚未可用的动作，暂时无法开始；已保存计划仍保留。');
      return;
    }
    if (!s.store.trainingAllowed) {
      _toast(
        s.store.safetyAccepted
            ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。'
            : '请先在对话里完成安全确认，再开始训练。',
        icon: SfGlyph.shield,
      );
      return;
    }
    // Capture the image and begin decode on the tap, before persistence yields.
    final source = messageId == null
        ? null
        : _trainingMedia[messageId]?.capture();
    final first = p.items.firstOrNull;
    if (first != null) {
      unawaited(
        TrainingTransitionPoster.precache(context, s.library[first.exerciseId]),
      );
    }
    _trainingInFlight = true;
    final launchEpoch = _trainingLaunchEpoch;
    try {
      if (!await _chat.started(p) ||
          !mounted ||
          launchEpoch != _trainingLaunchEpoch) {
        return;
      }
      s.prefetchPlan(p);
      _dismissInput();
      final route = TrainingRoute<SessionResult>(
        context: context,
        source: source,
        settings: const RouteSettings(name: 'player'),
        builder: (_) => PlayerPage(plan: p),
      );
      final result = await Navigator.of(context).push(route);
      await route.completed;
      // The zero-duration route has gone, but its still-only shrink/crossfade
      // overlay owns the visual exit until this future completes.
      await route.visualCompleted;
      if (!mounted) return;
      _dismissInput();
      if (result != null) await _finishTraining(p, result);
    } finally {
      _trainingInFlight = false;
    }
  }

  Future<void> _finishTraining(TrainingPlan plan, SessionResult result) async {
    if (!mounted || !_finishedSessions.add(result.sessionId)) return;
    final previous = _chat.messages.map((message) => message.id).toSet();
    _chat.finished(
      plan,
      completed: result.completedExercises,
      total: result.totalExercises,
    );
    final added = _chat.messages.where(
      (message) => !previous.contains(message.id),
    );
    if (added.isEmpty) return;
    setState(() => _finishedEntries.addAll(added.map((message) => message.id)));
    // The new row's first layout has zero height, including padding. Older
    // visible rows therefore keep their exact positions in this frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        _scroll.position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _save(TrainingPlan p) async {
    SfHaptic.selection.play();
    final saved = await _chat.save(p);
    _toast('已保存为「${saved.name}」');
  }

  Future<void> _savePlanCard(
    ChatMessage message, {
    bool saveAsCopy = false,
  }) async {
    SfHaptic.selection.play();
    final updating = _chat.savedTargetFor(message) != null && !saveAsCopy;
    final saved = await _chat.savePlanCard(message, saveAsCopy: saveAsCopy);
    _toast(updating ? '已更新「${saved.name}」' : '已保存为「${saved.name}」');
  }

  Future<void> _details(ChatMessage m, {TrainingPlan? validatedPlan}) async {
    _dismissInput();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'plan'),
        builder: (_) => PlanPage(
          plan: validatedPlan ?? m.plan!,
          request: m.request,
          onTrainingStarting: _chat.started,
          onTrainingFinished: (plan, result) =>
              unawaited(_finishTraining(plan, result)),
        ),
      ),
    );
    if (!mounted) return;
    _dismissInput();
  }

  void _toast(String text, {SfGlyph icon = SfGlyph.checkCircle}) {
    if (!mounted) return;
    showSfSolidToast(
      context,
      text,
      icon: SfIcon(icon, size: 18, color: SfColors.accentText, filled: true),
    );
  }

  Future<void> _send(String text, {String? label}) async {
    if (_scroll.hasClients && _scroll.offset > 0) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
    await _chat.send(text, label: label);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppServices.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sfOverlay,
      child: PopScope(
        canPop: !_panelOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _panelOpen) _closePanel();
        },
        child: Scaffold(
          backgroundColor: SfColors.skyBottom,
          resizeToAvoidBottomInset: false,
          body: ListenableBuilder(
            listenable: PerformanceLab.buildEnabled
                ? Listenable.merge([s.store, PerformanceLab.instance])
                : s.store,
            builder: (context, _) => CosmosBackground(
              showStars: PerformanceLab.buildEnabled
                  ? PerformanceLab.instance.starsVisible
                  : true,
              animate: PerformanceLab.buildEnabled
                  ? PerformanceLab.instance.starfieldFor(s.store.starfield)
                  : s.store.starfield,
              child: ListenableBuilder(
                listenable: _chat,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _dockExtent,
                      child: RepaintBoundary(
                        key: const ValueKey('chat-messages-boundary'),
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _closePanel,
                          child: _messages(),
                        ),
                      ),
                      builder: (context, extent, child) =>
                          Positioned.fill(bottom: extent, child: child!),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: RepaintBoundary(
                        key: const ValueKey('chat-composer-dock-boundary'),
                        child: ChatComposerDock(
                          panelOpen: _panelOpen,
                          focusNode: _input,
                          extent: _dockExtent,
                          planFocusTitle: _chat.planFocus?.title,
                          onClearPlanFocus: () =>
                              unawaited(_chat.clearPlanFocus()),
                          suggestions: SuggestionStrip(
                            items: _chat.typing ? const [] : _chat.suggestions,
                            onTap: _send,
                          ),
                          input: ChatInputBar(
                            focusNode: _input,
                            onSend: _send,
                            enabled: !_chat.typing,
                            onPlans: _togglePanel,
                            panelOpen: _panelOpen,
                            onTextTap: _inputTapped,
                          ),
                          panel: _featurePanel(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ChatFeaturePanel _featurePanel() {
    final entries =
        <({String key, String label, SfGlyph icon, VoidCallback tap})>[
          (
            key: 'panel-plans',
            label: '我的计划',
            icon: SfGlyph.bookmark,
            tap: _openPlans,
          ),
          (
            key: 'chat-new-conversation',
            label: '新对话',
            icon: SfGlyph.sparkle,
            tap: () {
              _closePanel();
              unawaited(_chat.newConversation());
            },
          ),
          (
            key: 'panel-library',
            label: '动作库',
            icon: SfGlyph.grid,
            tap: () => unawaited(_push(const LibraryPage())),
          ),
          (
            key: 'panel-settings',
            label: '设置',
            icon: SfGlyph.sliders,
            tap: () => unawaited(_push(const AboutPage())),
          ),
        ];
    return ChatFeaturePanel(
      key: const ValueKey('chat-feature-panel'),
      actions: [
        for (final entry in entries)
          ChatPanelAction(
            key: ValueKey(entry.key),
            label: entry.label,
            icon: entry.icon,
            onTap: entry.tap,
          ),
      ],
    );
  }

  Widget _messages() {
    final msgs = _chat.messages;
    final messageIds = msgs.map((m) => m.id).toSet();
    _deliveryEntryIds.removeWhere((id, _) => !messageIds.contains(id));
    if (_pendingDeliveryId != null && !messageIds.contains(_pendingUserId)) {
      _pendingDeliveryId = null;
      _pendingUserId = null;
      _replyStartIds = {};
    }
    if (_chat.typing && _pendingDeliveryId == null) {
      final user = msgs.where((m) => m.isUser).lastOrNull;
      _pendingUserId = user?.id;
      _pendingDeliveryId = 'coach-delivery-${user?.id ?? msgs.length}';
      _pendingDeliveryAt = user?.at ?? msgs.lastOrNull?.at ?? DateTime.now();
      _replyStartIds = msgs.map((m) => m.id).toSet();
    } else if (!_chat.typing && _pendingDeliveryId != null) {
      final replies = msgs.where(
        (m) => !m.isUser && !m.greeting && !_replyStartIds.contains(m.id),
      );
      final delivered =
          replies.where((m) => m.isPlan || m.actions != null).firstOrNull ??
          replies.firstOrNull;
      if (delivered != null) {
        _deliveryEntryIds[delivered.id] = _pendingDeliveryId!;
      }
      _pendingDeliveryId = null;
      _pendingUserId = null;
    }
    final liveDeliveries = {..._deliveryEntryIds.values, ?_pendingDeliveryId};
    _deliveryKeys.removeWhere((id, _) => !liveDeliveries.contains(id));
    GlobalKey deliveryKey(String id) =>
        _deliveryKeys.putIfAbsent(id, GlobalKey.new);
    final rows = [
      for (final m in msgs)
        CoachChatEntry(
          id: _deliveryEntryIds[m.id] ?? m.id,
          at: m.at,
          isUser: m.isUser,
          isCard: m.isPlan || m.actions != null,
          greeting: m.greeting,
          child: _deliveryEntryIds.containsKey(m.id)
              ? CoachDeliveryTransition(
                  key: deliveryKey(_deliveryEntryIds[m.id]!),
                  preparing: false,
                  successful:
                      !m.isPlanningFailure && (m.isPlan || m.actions != null),
                  interrupted: _chat.typing,
                  child: _message(m),
                )
              : m.greeting
              ? GreetingBlock(text: m.text)
              : _message(m, fresh: !_seen.contains(m.id)),
        ),
      if (_chat.typing)
        CoachChatEntry(
          id: _pendingDeliveryId!,
          at: _pendingDeliveryAt!,
          isUser: false,
          isCard: true,
          child: CoachDeliveryTransition(
            key: deliveryKey(_pendingDeliveryId!),
            preparing: true,
            child: CoachTaskBubble(
              task: _chat.activeTask,
              sessionState: _chat.activeSessionState,
              library: AppServices.of(context).library,
              waiting: true,
              onCancel: _chat.cancelRequest,
            ),
          ),
        ),
    ];
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _seen.addAll(msgs.map((m) => m.id)),
    );
    return withSmartfitCoachUi(
      context,
      ChatTimeline(
        entries: rows,
        controller: _scroll,
        initiallySeen: _seen,
        finishedEntries: _finishedEntries,
        // Keep the viewport behind Android's transparent status bar. The
        // initial safe clearance belongs to the scrollable content instead.
        topInset: MediaQuery.paddingOf(context).top,
        timeMarkBuilder: (at, now) => TimeMark(at, now: now),
      ),
    );
  }

  Widget _message(ChatMessage m, {bool fresh = false}) {
    final library = AppServices.of(context).library;
    final hasText =
        m.question != null || m.text.isNotEmpty || m.options.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.isPlanningFailure)
          CoachFailureBubble(
            key: ValueKey('coach-planning-failure-${m.id}'),
            enabled: !_chat.typing,
            onRetry: () => _chat.send('重试'),
          ),
        if (m.question case final question?)
          CoachQuestionBubble(
            key: ValueKey('coach-question-${m.id}'),
            question: toCoachQuestionData(m),
            enabled: _chat.canAnswerQuestion(m),
            onTextAnswer: (answer) =>
                question.mode == coach.AskUserMode.form &&
                    answer == question.skipLabel
                ? _chat.skipQuestion(m)
                : _chat.answerQuestion(m, answer),
            onChoiceAnswer: (choices) => _chat.answerChoices(m, choices),
            onFormAnswer: (answers) => _chat.answerForm(m, answers),
            onSkip: () => _chat.skipQuestion(m),
          ),
        if (!m.isPlanningFailure &&
            m.actions == null &&
            hasText &&
            (m.question == null ||
                (m.text.isNotEmpty && m.text != m.question!.question)))
          MessageBubble(
            message: m,
            optionsActive: !_chat.typing && _chat.isActive(m),
            onOption: (i) => _chat.choose(m, i),
          ),
        if (m.actions case final actions?) ...[
          withSmartfitRecommendUi(
            context,
            CoachRecommendCard(
              key: ValueKey('coach-recommendation-${m.id}'),
              actionIds: actions.items.map((action) => action.id).toList(),
              note: m.text,
              library: CoachExerciseLibrary([
                for (final action in actions.items)
                  if (library.tryGet(action.id) case final exercise?)
                    toCoachRecommendationExercise(exercise),
              ]),
              onOpenAction: (id) {
                if (library.tryGet(id) case final exercise?) {
                  unawaited(showExerciseDetails(context, exercise));
                }
              },
              onPlanFromActions: _chat.typing
                  ? null
                  : (_) => unawaited(_chat.send('请把刚才推荐的动作排成计划。')),
            ),
          ),
        ],
        if (m.validatedPlan case final validated?) ...[
          if (hasText) const SizedBox(height: SfSpace.x3),
          _trainingCard(
            m,
            ValidatedPlanCard(
              validatedPlan: validated,
              library: library,
              landing: fresh,
              isSaved: _chat.isSaved,
              updatingSavedPlan: _chat.savedTargetFor(m) != null,
              savedOverride: _chat.isPlanCardSaved(m),
              onSaveCopy: _chat.savedTargetFor(m) == null
                  ? null
                  : (_) => unawaited(_savePlanCard(m, saveAsCopy: true)),
              onStart: (plan, _) => _start(plan, messageId: m.id),
              onSave: (_) => unawaited(_savePlanCard(m)),
              onOpen: (plan) => _details(m, validatedPlan: plan),
            ),
          ),
        ] else if (m.isPlan &&
            (m.plan!.source != 'ai' || m.isSavedPlanDisplay)) ...[
          if (hasText) const SizedBox(height: SfSpace.x3),
          _trainingCard(
            m,
            PlanCard(
              plan: m.plan!,
              landing: fresh,
              library: library,
              saved: _chat.isSaved(m.plan!),
              onStart: (_) => _start(m.plan!, messageId: m.id),
              onSave: () => _save(m.plan!),
              onOpen: () => _details(m),
            ),
          ),
        ],
      ],
    );
  }

  Widget _trainingCard(ChatMessage message, Widget child) {
    final plan =
        message.plan ??
        (message.validatedPlan == null
            ? null
            : TrainingPlan.fromJson(message.validatedPlan!.plan.toJson()));
    final exerciseId = plan?.items.firstOrNull?.exerciseId;
    if (exerciseId == null) return child;
    final registry = _trainingMedia.putIfAbsent(
      message.id,
      () => TrainingCardMediaRegistry(exerciseId),
    );
    return TrainingCardMedia(registry: registry, child: child);
  }
}
