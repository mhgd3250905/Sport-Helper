import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show SessionResult;

import '../app/services.dart';
import '../app/training_transition_activity.dart';
import '../domain/plan.dart';
import 'player_page.dart';
import 'theme.dart';
import 'training_poster_image.dart';
import 'training_route.dart';

final _openTrainingByNavigator = Expando<Object>();

/// The only host push into training. The lock includes poster decode, durable
/// start bookkeeping, both slides and any SDK save still pending offscreen.
Future<SessionResult?> openTraining(
  BuildContext context, {
  required TrainingPlan plan,
  String sourceEntry = 'plan',
  Future<bool> Function()? onStarting,
}) async {
  final navigator = Navigator.of(context);
  if (_openTrainingByNavigator[navigator] != null) return null;
  final services = AppServices.of(context);
  if (!services.store.trainingAllowed) {
    showSfToast(
      context,
      services.store.safetyAccepted
          ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。'
          : '请先在对话里完成安全确认，再开始训练。',
      icon: SfGlyph.shield,
    );
    return null;
  }
  if (plan.items.isEmpty ||
      plan.items.any((item) => !services.library.contains(item.exerciseId))) {
    showSfToast(context, '计划包含尚未可用的动作，暂时无法开始。');
    return null;
  }
  final identity = Object();
  _openTrainingByNavigator[navigator] = identity;
  final release = TrainingTransitionActivity.instance.hold();
  final watch = _LaunchLifecycle();
  WidgetsBinding.instance.addObserver(watch);
  try {
    final first = services.library[plan.items.first.exerciseId];
    final ready = await TrainingPosterImages.prepare(
      context,
      first,
    ).timeout(const Duration(milliseconds: 150), onTimeout: () => false);
    if (!context.mounted || !navigator.mounted || watch.interrupted) {
      return null;
    }
    if (!ready) {
      // A decode timeout must not turn into an empty first training frame.
      // Prewarming continues; the current complete source page stays visible.
      showSfToast(context, '画面还在准备，请再点一次开始。');
      return null;
    }
    if (onStarting != null && !await onStarting()) return null;
    if (!context.mounted || !navigator.mounted || watch.interrupted) {
      return null;
    }
    final route = TrainingRoute<SessionResult>(
      context: context,
      sourceEntry: sourceEntry,
      settings: const RouteSettings(name: 'player'),
      builder: (_) => PlayerPage(plan: plan),
    );
    final popped = navigator.push(route);
    release();
    final result = await popped;
    await route.completed;
    return result;
  } finally {
    WidgetsBinding.instance.removeObserver(watch);
    release();
    if (identical(_openTrainingByNavigator[navigator], identity)) {
      _openTrainingByNavigator[navigator] = null;
    }
  }
}

class _LaunchLifecycle extends WidgetsBindingObserver {
  bool interrupted = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) interrupted = true;
  }
}
