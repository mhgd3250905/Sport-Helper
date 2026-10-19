import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/services.dart';
import '../../chat/chat_controller.dart';
import '../../chat/chat_models.dart';
import '../../domain/session.dart';
import '../library_page.dart';
import '../plan_page.dart';
import '../theme.dart' show minutesZh;
import 'chat_widgets.dart';
import 'cosmos.dart';
import 'glass.dart';

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
    }
  }

  Future<void> _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

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
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: CosmosColors.skyBottom,
      ),
      child: Scaffold(
        backgroundColor: CosmosColors.skyBottom,
        resizeToAvoidBottomInset: true,
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
                    ChatInputBar(onSend: _send, enabled: !_chat.typing),
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
          padding: EdgeInsets.only(top: sameSide ? 6 : 14),
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
        padding: EdgeInsets.only(top: 14),
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
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 12),
            itemCount: reversed.length,
            itemBuilder: (_, i) => reversed[i],
            findChildIndexCallback: (key) {
              final i = reversed.indexWhere((w) => w.key == key);
              return i < 0 ? null : i;
            },
          ),
        ),
        // Messages dissolve into the sky at the top edge.
        const IgnorePointer(
          child: SizedBox(
            height: 40,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xE60B1022), Color(0x000B1022)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message(ChatMessage m) => m.isPlan ? _planPreview(m) : MessageBubble(
    message: m,
    optionsActive: _chat.isActive(m),
    onOption: (i) => _chat.choose(m, i),
  );

  Widget _planPreview(ChatMessage m) {
    final s = AppServices.of(context);
    final p = m.plan!;
    final secs = SessionBuilder(s.library).planSeconds(p);
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _push(PlanPage(plan: p, request: m.request)),
        child: Glass(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${p.title} · ${minutesZh(secs)} · ${p.items.length} 个动作  ›',
            style: const TextStyle(color: CosmosColors.text, fontSize: 15.5),
          ),
        ),
      ),
    );
  }
}
