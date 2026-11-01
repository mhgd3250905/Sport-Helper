import 'package:flutter/material.dart';
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../../app/services.dart';

/// App lifetime and dependency lookup only; the SDK owns the conversation page.
class ChatHomePage extends StatelessWidget {
  const ChatHomePage({
    super.key,
    this.controller,
    this.scrollController,
    this.clock,
  });
  final CoachChatController? controller;
  final ScrollController? scrollController;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => CoachChatPage(
    controller: controller ?? AppServices.of(context).chat,
    scrollController: scrollController,
    clock: clock,
  );
}
