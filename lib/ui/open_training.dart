import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show SessionResult, PoseHubSinglePracticePage;

import '../app/services.dart';
import '../app/training_transition_activity.dart';
import '../domain/plan.dart';
import 'player_page.dart';
import 'single_practice_page.dart';
import 'theme.dart';
import 'training_poster_image.dart';
import 'training_route.dart';

final _openTrainingByNavigator = Expando<Object>();

/// The only host push into training. The lock includes poster decode, durable
/// start bookkeeping, both slides and any SDK save still pending offscreen.
Future<SessionResult?> openTraining(
  BuildContext context, {
  TrainingPlan? plan,
  PoseHubSinglePracticePage? practice,
  String sourceEntry = 'plan',
  Future<bool> Function()? onStarting,
}) async {
  if ((plan == null) == (practice == null)) {
    throw ArgumentError('Provide exactly one plan or SDK practice page.');
  }
  final navigator = Navigator.of(context);
  if (_openTrainingByNavigator[navigator] != null) return null;
  final services = context.getInheritedWidgetOfExactType<AppScope>()?.services;
  if (plan != null && services == null) {
    throw StateError('Plan training needs the host AppScope.');
  }
  if (plan != null && !services!.store.trainingAllowed) {
    showSfToast(
      context,
      services.store.safetyAccepted
          ? '根据你的安全确认，暂不开始训练；可以在动作库里看示范。'
          : '请先在对话里完成安全确认，再开始训练。',
      icon: SfGlyph.shield,
    );
    return null;
  }
  if (plan != null &&
      (plan.items.isEmpty ||
          plan.items.any(
            (item) => !services!.library.contains(item.exerciseId),
          ))) {
    showSfToast(context, '计划包含尚未可用的动作，暂时无法开始。');
    return null;
  }
  if (practice != null && !practice.action.trainingDefinitionComplete) {
    showSfToast(context, '此动作暂未开放训练');
    return null;
  }
  final identity = Object();
  _openTrainingByNavigator[navigator] = identity;
  final release = TrainingTransitionActivity.instance.hold();
  final watch = _LaunchLifecycle();
  WidgetsBinding.instance.addObserver(watch);
  try {
    final poster = practice == null
        ? TrainingPosterImages.prepare(
            context,
            services!.library[plan!.items.first.exerciseId],
          )
        : TrainingPosterImages.prepareAsset(
            context,
            'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/${practice.action.id}.webp',
          );
    final ready = await poster.timeout(
      const Duration(milliseconds: 150),
      onTimeout: () => false,
    );
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
      trainerTheme: practice?.theme,
      settings: const RouteSettings(name: 'player'),
      builder: (_) => practice == null
          ? PlayerPage(plan: plan!)
          : SinglePracticePage(
              page: practice,
              exercise: services?.library.tryGet(practice.action.id),
            ),
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
