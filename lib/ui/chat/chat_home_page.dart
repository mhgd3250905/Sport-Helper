import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../../domain/plan.dart';
import '../about_page.dart';
import '../custom_plan_page.dart';
import '../library_page.dart';
import '../plan_page.dart';
import '../player_page.dart';
import '../theme/app_theme.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import 'chat_widgets.dart';
import 'cosmos.dart';
import 'expand_route.dart';
import 'plan_card.dart';
import 'saved_plans_drawer.dart';

/// The home screen: one conversation floating in an endless sky. No app
/// bar, no borders; the plans drawer opens from the input's left icon.
class ChatHomePage extends StatefulWidget {
  const ChatHomePage({super.key, this.controller});

  /// Injected by tests; otherwise the app-wide [AppServices.chat].
  final ChatController? controller;

  @override
  State<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends State<ChatHomePage> {
  late ChatController _chat;
  StreamSubscription<String>? _actions;
  final _scroll = ScrollController();
  final _scaffold = GlobalKey<ScaffoldState>();

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
    _scroll.dispose();
    super.dispose();
  }

  void _onAction(String a) {
    if (!mounted) return;
    switch (a) {
      case '@library':
        _push(const LibraryPage());
      case '@drawer':
        _scaffold.currentState?.openDrawer();
    }
  }

  Future<void> _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  /// Close the drawer first so the chat (or the player) is what you see.
  void _fromDrawer(Future<void> Function() then) {
    _scaffold.currentState?.closeDrawer();
    unawaited(then());
  }

  /// The card (or drawer tile) grows into the player and folds back into
  /// the chat afterwards; the summary and the save offer follow.
  Future<void> _start(TrainingPlan p, {OriginRect? from}) async {
    final s = AppServices.of(context);
    if (!s.store.trainingAllowed) {
      _toast(s.store.safetyAccepted
          ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。'
          : '请先在对话里完成安全确认，再开始训练。');
      return;
    }
    HapticFeedback.lightImpact();
    if (!await _chat.started(p)) return;
    final before = s.store.history.length;
    if (!mounted) return;
    await Navigator.of(context).push(CardExpandRoute<void>(
      origin: from,
      settings: const RouteSettings(name: 'player'),
      builder: (_) => PlayerPage(plan: p),
    ));
    if (!mounted) return;
    if (s.store.history.length > before) {
      final h = s.store.history.first;
      _chat.finished(p, completed: h.completed, total: h.total);
    }
  }

  Future<void> _save(TrainingPlan p) async {
    HapticFeedback.selectionClick();
    final saved = await _chat.save(p);
    _toast('已保存为「${saved.name}」');
  }

  Future<void> _details(ChatMessage m) async {
    final plan = await Navigator.of(context).push<TrainingPlan>(
      MaterialPageRoute(
        builder: (_) => PlanPage(
          plan: m.plan!,
          request: m.request,
          returnPlanOnStart: true,
        ),
      ),
    );
    if (mounted && plan != null) await _start(plan);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 96),
        content: Text(text),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _send(String text, {String? label}) async {
    HapticFeedback.selectionClick();
    if (_scroll.hasClients && _scroll.offset > 0) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
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
        drawerScrimColor: SfColors.isDark ? const Color(0x99000000) : const Color(0x4D121614),
        drawer: SavedPlansDrawer(
          store: s.store,
          library: s.library,
          onShow: (p) => _fromDrawer(() => _chat.showSaved(p)),
          onStart: (p, from) => _fromDrawer(() => _start(p.plan, from: from)),
          footer: [
            DrawerEntry(
              key: const ValueKey('drawer-library'),
              icon: SfGlyph.grid,
              label: '动作库',
              hint: '${s.library.length} 个动作的示范',
              onTap: () => _fromDrawer(() => _push(const LibraryPage())),
            ),
            DrawerEntry(
              key: const ValueKey('drawer-custom'),
              icon: SfGlyph.sliders,
              label: '自定义计划',
              hint: '用表单选目标、器械和时长',
              onTap: () => _fromDrawer(() => _push(const CustomPlanPage())),
            ),
            DrawerEntry(
              key: const ValueKey('drawer-about'),
              icon: SfGlyph.info,
              label: '关于与设置',
              hint: '外观、语音、安全确认、素材署名',
              onTap: () => _fromDrawer(() => _push(const AboutPage())),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: s.store,
          builder: (context, _) => CosmosBackground(
            animate: s.store.starfield,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _chat,
                builder: (context, _) => Column(
                  children: [
                    Expanded(child: _messages()),
                    SuggestionStrip(
                      items: _chat.typing ? const [] : _chat.suggestions,
                      onTap: _send,
                    ),
                    ChatInputBar(
                      onSend: _send,
                      enabled: !_chat.typing,
                      onPlans: () => _scaffold.currentState?.openDrawer(),
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

  Widget _messages() {
    final rows = <Widget>[];
    final msgs = _chat.messages;
    final now = DateTime.now();
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prev = i == 0 ? null : msgs[i - 1];
      if (prev == null || m.at.difference(prev.at) > const Duration(minutes: 45)) {
        rows.add(TimeMark(m.at, now: now));
      }
      final sameSide = prev != null && prev.isUser == m.isUser;
      rows.add(
        Padding(
          key: ValueKey(m.id),
          padding: EdgeInsets.only(top: sameSide ? SfSpace.x2 : SfSpace.x4),
          child: Appear(
            animate: !_seen.contains(m.id) && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false),
            child: _message(m),
          ),
        ),
      );
    }
    if (_chat.typing) {
      rows.add(const Padding(
        key: ValueKey('typing'),
        padding: EdgeInsets.only(top: SfSpace.x4),
        child: TypingBubble(),
      ));
    }
    final reversed = rows.reversed.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seen.addAll(msgs.map((m) => m.id)));
    return Stack(
      children: [
        BackdropGroup(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.fromLTRB(SfSpace.x4, 48, SfSpace.x4, SfSpace.x3),
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
                  colors: [SfColors.skyTop, SfColors.skyTop.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message(ChatMessage m) => m.isPlan
      ? PlanCard(
          plan: m.plan!,
          library: AppServices.of(context).library,
          saved: _chat.isSaved(m.plan!),
          onStart: (from) => _start(m.plan!, from: from),
          onSave: () => _save(m.plan!),
          onOpen: () => _details(m),
        )
      : MessageBubble(
    message: m,
    optionsActive: _chat.isActive(m),
    onOption: (i) => _chat.choose(m, i),
  );
}
