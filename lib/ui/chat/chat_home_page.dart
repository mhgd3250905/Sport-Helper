import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show SessionResult;

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
import '../theme/fixed_glass_policy.dart';
import '../theme/glass.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';
import 'action_card.dart';
import 'chat_widgets.dart';
import 'cosmos.dart';
import 'expand_route.dart';
import 'plan_card.dart';
import 'saved_plans_drawer.dart';
import 'validated_plan_card.dart';

/// The home screen: one conversation floating in an endless sky. No app
/// bar, no borders; the plans drawer opens from the input's left icon.
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

class _ChatHomePageState extends State<ChatHomePage> {
  late ChatController _chat;
  StreamSubscription<String>? _actions;
  late final _scroll = widget.scrollController ?? ScrollController();

  /// Height of the floating glass dock (chips + input, incl. the bottom
  /// safe area); the conversation reserves it as bottom padding so the
  /// newest message can always scroll clear of the glass.
  double _dockHeight = 112;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = FocusNode();

  /// Messages already on screen when the page opened don't animate in.
  final _seen = <String>{};

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
    _actions?.cancel();
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
        _scaffold.currentState?.openDrawer();
    }
  }

  Future<void> _push(Widget page) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: RouteSettings(
        name: switch (page) {
          LibraryPage() => 'library',
          AboutPage() => 'settings',
          CustomPlanPage() => 'custom_plan',
          _ => 'other',
        },
      ),
      builder: (_) => page,
    ),
  );

  /// Close the drawer first so the chat (or the player) is what you see.
  void _fromDrawer(Future<void> Function() then) {
    _scaffold.currentState?.closeDrawer();
    unawaited(then());
  }

  /// The card (or drawer tile) grows into the player and folds back into
  /// the chat afterwards; the summary and the save offer follow.
  Future<void> _start(TrainingPlan p, {OriginRect? from}) async {
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
    final result = await Navigator.of(context).push(
      CardExpandRoute<SessionResult>(
        origin: from,
        settings: const RouteSettings(name: 'player'),
        builder: (_) => PlayerPage(plan: p),
      ),
    );
    if (!mounted) return;
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
    if (mounted && plan != null) await _start(plan);
  }

  void _toast(String text, {SfGlyph icon = SfGlyph.checkCircle}) {
    if (!mounted) return;
    showSfToast(context, text, icon: icon);
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
      child: Scaffold(
        key: _scaffold,
        backgroundColor: SfColors.skyBottom,
        resizeToAvoidBottomInset: true,
        drawerScrimColor: SfColors.isDark
            ? const Color(0x99000000)
            : const Color(0x4D121614),
        drawer: SavedPlansDrawer(
          store: s.store,
          library: s.library,
          onShow: (p) => _fromDrawer(() => _chat.showSaved(p)),
          onStart: (p, from) => _fromDrawer(() => _start(p.plan, from: from)),
          // Nothing saved yet: close the drawer and put the cursor in the chat.
          onCompose: () => _fromDrawer(() async => _input.requestFocus()),
          // Session and App actions stay in the drawer; the conversation has
          // no persistent header. The form opens from 「自己选条件」.
          footer: [
            DrawerEntry(
              key: const ValueKey('chat-new-conversation'),
              icon: SfGlyph.sparkle,
              label: '新对话',
              onTap: () => _fromDrawer(_chat.newConversation),
            ),
            DrawerEntry(
              key: const ValueKey('drawer-library'),
              icon: SfGlyph.grid,
              label: '动作库',
              onTap: () => _fromDrawer(() => _push(const LibraryPage())),
            ),
            DrawerEntry(
              key: const ValueKey('drawer-about'),
              icon: SfGlyph.sliders,
              label: '设置',
              onTap: () => _fromDrawer(() => _push(const AboutPage())),
            ),
          ],
        ),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cards paint a static face; the scrolling conversation is
                // not a texture capture source. Only the internal legacy-card
                // comparison restores that boundary. The fixed input keeps
                // its glass; every conversation uses static suggestion chips.
                LiquidGlassScope(
                  child: ListenableBuilder(
                    listenable: _chat,
                    builder: (context, _) => _withMeasuredGlassDefault(
                      context,
                      Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: SfGlassBackgroundSource(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const SfGlassField(),
                                  SafeArea(bottom: false, child: _messages()),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: SfMeasureSize(
                              onSize: (s) {
                                if (mounted &&
                                    (s.height - _dockHeight).abs() > .5) {
                                  setState(() => _dockHeight = s.height);
                                }
                              },
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
                                      onPlans: () =>
                                          _scaffold.currentState?.openDrawer(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _withMeasuredGlassDefault(BuildContext context, Widget child) {
    // The existing chat notification rebuild also covers newly received and
    // cleared plans. Do not inspect messages from a scroll listener or ticker.
    // An explicit experiment/screenshot scope must remain authoritative.
    if (SfFixedGlassScope.maybeOf(context) != null) return child;
    final hasPlanCards = _chat.messages.any(
      (message) =>
          !message.greeting &&
          (message.validatedPlan != null ||
              (message.isPlan && message.plan!.source != 'ai')),
    );
    return SfFixedGlassScope(
      isPlanContext: hasPlanCards,
      policy: SfFixedGlassPolicy.chat,
      child: child,
    );
  }

  Widget _messages() {
    final rows = <Widget>[];
    final msgs = _chat.messages;
    final now = DateTime.now();
    final still = SfMotion.reduced(context);
    // M4: the messages of one reply land one after another, 120 ms apart
    // (words first, then the card); the user's own line lands at once.
    var queued = 0;
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prev = i == 0 ? null : msgs[i - 1];
      if (prev == null ||
          m.at.difference(prev.at) > const Duration(minutes: 45)) {
        rows.add(TimeMark(m.at, now: now));
      }
      final sameSide = prev != null && prev.isUser == m.isUser;
      rows.add(
        Padding(
          key: ValueKey(m.id),
          padding: EdgeInsets.only(top: sameSide ? SfSpace.x2 : SfSpace.x4),
          child: m.greeting
              // M5: the greeting drifts up 16 px over 600 ms; nothing under
              // reduced motion.
              ? Appear(
                  animate: !_seen.contains(m.id) && !still,
                  duration: const Duration(milliseconds: 600),
                  rise: 16,
                  scaleFrom: 1,
                  child: GreetingBlock(text: m.text),
                )
              // Entrances: the user's line springs up out of the input bar
              // (8 px, .96 → 1, 280 ms, emphasized decelerate); the
              // assistant's words fade and rise one after another; a glass
              // card lands a beat later on a soft spring from .97.
              : Appear(
                  animate: !_seen.contains(m.id),
                  delay: !_seen.contains(m.id) && !m.isUser && !still
                      ? SfMotion.replyStagger * queued++ +
                            (m.isPlan ? SfMotion.replyStagger : Duration.zero)
                      : Duration.zero,
                  anchor: m.isUser
                      ? Alignment.bottomRight
                      : Alignment.bottomLeft,
                  rise: m.isUser ? 8 : (m.isPlan ? 14 : 10),
                  scaleFrom: m.isUser ? .96 : (m.isPlan ? .97 : .98),
                  duration: m.isUser
                      ? SfMotion.medium
                      : (m.isPlan
                            ? const Duration(milliseconds: 520)
                            : SfMotion.appear),
                  curve: m.isUser
                      ? SfMotion.enter
                      : (m.isPlan ? SfMotion.spring : SfMotion.standard),
                  child: RepaintBoundary(
                    child: _message(m, fresh: !_seen.contains(m.id)),
                  ),
                ),
        ),
      );
    }
    if (_chat.typing) {
      rows.add(
        Padding(
          key: ValueKey('typing'),
          padding: EdgeInsets.only(top: SfSpace.x4),
          child: TypingBubble(
            onCancel: _chat.cancelRequest,
            progressLabel: _chat.progressLabel,
          ),
        ),
      );
    }
    final reversed = rows.reversed.toList();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _seen.addAll(msgs.map((m) => m.id)),
    );
    return Stack(
      children: [
        BackdropGroup(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: EdgeInsets.fromLTRB(
              SfSpace.x4,
              48,
              SfSpace.x4,
              _dockHeight + SfSpace.x3,
            ),
            itemCount: reversed.length,
            itemBuilder: (_, i) => reversed[i],
            findChildIndexCallback: (key) {
              final i = reversed.indexWhere((w) => w.key == key);
              return i < 0 ? null : i;
            },
          ),
        ),
        // Messages dissolve into the sky at the top edge.
        IgnorePointer(
          child: SizedBox(
            height: 48,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SfColors.skyTop,
                    SfColors.skyTop.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message(ChatMessage m, {bool fresh = false}) {
    final library = AppServices.of(context).library;
    final hasText = m.text.isNotEmpty || m.options.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasText)
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
            onStart: (plan, from) => _start(plan, from: from),
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
            onStart: (from) => _start(m.plan!, from: from),
            onSave: () => _save(m.plan!),
            onOpen: () => _details(m),
          ),
        ],
      ],
    );
  }
}
