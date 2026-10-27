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
import '../theme/measure_size.dart';
import '../theme/solid_surface.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import '../training_route.dart';
import 'action_card.dart';
import 'chat_widgets.dart';
import 'coach_ui_adapter.dart';
import 'cosmos.dart';
import 'plan_card.dart';
import 'saved_plans_page.dart';
import 'validated_plan_card.dart';

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
  late Stream<CoachTypingEvent> _typingEvents;
  StreamSubscription<String>? _actions;
  late final _scroll = widget.scrollController ?? ScrollController();

  /// Height of the input dock (chips + input, incl. the bottom
  /// safe area); the conversation reserves it as bottom padding so the
  /// newest message can always scroll clear of the controls.
  double _dockHeight = 112;
  final _input = FocusNode();
  bool _panelOpen = false;
  bool _switchingToKeyboard = false;
  Timer? _keyboardHeightTimer;
  Timer? _keyboardTransitionTimer;

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
    _keyboardTransitionTimer?.cancel();
    setState(() {
      _panelOpen = true;
      _switchingToKeyboard = false;
    });
    _dismissInput();
  }

  void _closePanel() {
    _keyboardTransitionTimer?.cancel();
    if (!_panelOpen && !_switchingToKeyboard) return;
    setState(() {
      _panelOpen = false;
      _switchingToKeyboard = false;
    });
  }

  void _inputTapped() {
    if (!_panelOpen) return;
    setState(() {
      _panelOpen = false;
      _switchingToKeyboard = true;
    });
    _keyboardTransitionTimer?.cancel();
    _keyboardTransitionTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && _switchingToKeyboard) {
        setState(() => _switchingToKeyboard = false);
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted || _actions == null) return;
    final view = View.of(context);
    final height = view.viewInsets.bottom / view.devicePixelRatio;
    if (_switchingToKeyboard &&
        height >= AppServices.of(context).store.lastKeyboardHeight - 20) {
      _keyboardTransitionTimer?.cancel();
      setState(() => _switchingToKeyboard = false);
    }
    _keyboardHeightTimer?.cancel();
    if (height >= 160 && height <= 650 && !_panelOpen) {
      _keyboardHeightTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || _panelOpen) return;
        final current = view.viewInsets.bottom / view.devicePixelRatio;
        if ((current - height).abs() < 1) {
          unawaited(
            AppServices.of(context).store.setLastKeyboardHeight(height),
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    _typingEvents = _chat.progressEvents.map(
      (event) => CoachTypingEvent(event.kind.name, path: event.path),
    );
    _chat.start();
    _seen.addAll(_chat.messages.map((m) => m.id));
    _actions = _chat.actions.listen(_onAction);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _actions?.cancel();
    _keyboardHeightTimer?.cancel();
    _keyboardTransitionTimer?.cancel();
    if (widget.scrollController == null) _scroll.dispose();
    _input.dispose();
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
  Future<void> _start(TrainingPlan p) async {
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
    if (!await _chat.started(p)) return;
    if (!mounted) return;
    s.prefetchPlan(p);
    _dismissInput();
    final result = await Navigator.of(context).push(
      TrainingRoute<SessionResult>(
        settings: const RouteSettings(name: 'player'),
        builder: (_) => PlayerPage(plan: p),
      ),
    );
    if (!mounted) return;
    _dismissInput();
    if (result != null) {
      _chat.finished(
        p,
        completed: result.completedExercises,
        total: result.totalExercises,
      );
    }
  }

  Future<void> _save(TrainingPlan p) async {
    SfHaptic.selection.play();
    final saved = await _chat.save(p);
    _toast('已保存为「${saved.name}」');
  }

  Future<void> _details(ChatMessage m, {TrainingPlan? validatedPlan}) async {
    _dismissInput();
    final plan = await Navigator.of(context).push<TrainingPlan>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'plan'),
        builder: (_) => PlanPage(
          plan: validatedPlan ?? m.plan!,
          request: m.request,
          returnPlanOnStart: true,
        ),
      ),
    );
    if (!mounted) return;
    _dismissInput();
    if (plan != null) await _start(plan);
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
    final media = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: sfOverlay,
      child: PopScope(
        canPop: !_panelOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _panelOpen) _closePanel();
        },
        child: Scaffold(
          backgroundColor: SfColors.skyBottom,
          resizeToAvoidBottomInset: true,
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
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _panelOpen ? _closePanel : null,
                        child: _messages(),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SfMeasureSize(
                        onSize: (s) {
                          if (mounted && (s.height - _dockHeight).abs() > .5) {
                            setState(() => _dockHeight = s.height);
                          }
                        },
                        child: RepaintBoundary(
                          key: const ValueKey('chat-composer-dock-boundary'),
                          child: DecoratedBox(
                            key: const ValueKey('chat-composer-dock'),
                            decoration: BoxDecoration(
                              gradient: SfComposerTokens.dockGradient,
                            ),
                            child: SafeArea(
                              top: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SuggestionStrip(
                                    items: _chat.typing
                                        ? const []
                                        : _chat.suggestions,
                                    onTap: _send,
                                  ),
                                  ChatInputBar(
                                    focusNode: _input,
                                    onSend: _send,
                                    enabled: !_chat.typing,
                                    onPlans: _togglePanel,
                                    panelOpen: _panelOpen,
                                    onTextTap: _inputTapped,
                                  ),
                                  if (_panelOpen || _switchingToKeyboard)
                                    _featurePanel(s, media),
                                ],
                              ),
                            ),
                          ),
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

  Widget _featurePanel(AppServices services, MediaQueryData media) {
    // The system inset and this panel share one footprint while the keyboard
    // is moving, preventing the input from jumping by a full keyboard height.
    final target =
        (services.store.lastKeyboardHeight - media.viewPadding.bottom).clamp(
          0.0,
          media.size.height * .65,
        );
    final visible = (target - media.viewInsets.bottom).clamp(0.0, target);
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
    return SizedBox(
      key: const ValueKey('chat-feature-panel'),
      height: visible,
      width: double.infinity,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: target,
          maxHeight: target,
          child: IgnorePointer(
            ignoring: !_panelOpen,
            child: ColoredBox(
              color: SfColors.surface,
              child: GridView.count(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                crossAxisCount: 4,
                childAspectRatio: .8,
                children: [
                  for (final entry in entries)
                    SfPressable(
                      key: ValueKey(entry.key),
                      semanticLabel: entry.label,
                      onTap: entry.tap,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: SfColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: SfColors.line),
                            ),
                            child: Center(
                              child: SfIcon(
                                entry.icon,
                                size: 24,
                                color: SfColors.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(entry.label, style: SfType.label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _messages() {
    final msgs = _chat.messages;
    final rows = [
      for (final m in msgs)
        CoachChatEntry(
          id: m.id,
          at: m.at,
          isUser: m.isUser,
          isCard: m.isPlan,
          greeting: m.greeting,
          child: m.greeting
              ? GreetingBlock(text: m.text)
              : _message(m, fresh: !_seen.contains(m.id)),
        ),
    ];
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _seen.addAll(msgs.map((m) => m.id)),
    );
    return withSmartfitCoachUi(
      context,
      CoachChatList(
        entries: rows,
        controller: _scroll,
        initiallySeen: _seen,
        dockHeight: _dockHeight,
        // Keep the viewport behind Android's transparent status bar. The
        // initial safe clearance belongs to the scrollable content instead.
        topInset: MediaQuery.paddingOf(context).top,
        fadeTop: false,
        timeMarkBuilder: (at, now) => TimeMark(at, now: now),
        typing: _chat.typing
            ? TypingBubble(onCancel: _chat.cancelRequest, events: _typingEvents)
            : null,
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
            hasText &&
            (m.question == null ||
                (m.text.isNotEmpty && m.text != m.question!.question)))
          MessageBubble(
            message: m,
            optionsActive: !_chat.typing && _chat.isActive(m),
            onOption: (i) => _chat.choose(m, i),
          ),
        if (m.actions case final actions?) ...[
          if (hasText) const SizedBox(height: SfSpace.x3),
          ActionCard(
            actions: actions,
            library: library,
            onOpen: (exercise) => showExerciseDetails(context, exercise),
          ),
        ],
        if (m.validatedPlan case final validated?) ...[
          if (hasText) const SizedBox(height: SfSpace.x3),
          ValidatedPlanCard(
            validatedPlan: validated,
            library: library,
            landing: fresh,
            isSaved: _chat.isSaved,
            onStart: (plan, _) => _start(plan),
            onSave: _save,
            onOpen: (plan) => _details(m, validatedPlan: plan),
          ),
        ] else if (m.isPlan && m.plan!.source != 'ai') ...[
          if (hasText) const SizedBox(height: SfSpace.x3),
          PlanCard(
            plan: m.plan!,
            landing: fresh,
            library: library,
            saved: _chat.isSaved(m.plan!),
            onStart: (_) => _start(m.plan!),
            onSave: () => _save(m.plan!),
            onOpen: () => _details(m),
          ),
        ],
      ],
    );
  }
}
