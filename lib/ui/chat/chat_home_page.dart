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
    this.showBackButton,
  });
  final CoachChatController? controller;
  final ScrollController? scrollController;
  final DateTime Function()? clock;

  /// SDK CoachChatPage back button; null shows it when the route can pop.
  final bool? showBackButton;

  @override
  Widget build(BuildContext context) => CoachChatPage(
    controller: controller ?? AppServices.of(context).chat,
    scrollController: scrollController,
    clock: clock,
    showBackButton: showBackButton,
  );
}
