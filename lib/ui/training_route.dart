import 'dart:async';

import 'package:flutter/material.dart';

import '../diagnostics/frame_recorder.dart';
import '../diagnostics/runtime_log.dart';
import '../domain/exercise.dart';
import 'theme/trainer_theme.dart';
import 'training_entry_placeholder.dart';

part 'training_transition.dart';

/// A host-owned image. Entry freezes the tap position; return rechecks it.
class TrainingTransitionSource {
  const TrainingTransitionSource({
    required this.rect,
    required this.opacity,
    this.initialRect,
    this.repaintKey,
  });
  final Rect? Function() rect;
  final Rect? initialRect;
  final ValueNotifier<double> opacity;
  final GlobalKey? repaintKey;

  void show(double value) {
    if (repaintKey != null && repaintKey!.currentContext == null) return;
    opacity.value = value;
  }
}

/// Zero-time overlay route: the host animates a still image, never a video
/// texture. Its independent return layer survives the SDK's ordinary pop.
class TrainingRoute<T> extends PageRouteBuilder<T> {
  TrainingRoute({
    required BuildContext context,
    required WidgetBuilder builder,
    this.source,
    super.settings,
  }) : _sourceRoute = ModalRoute.of(context),
       super(
         opaque: false,
         transitionDuration: Duration.zero,
         reverseTransitionDuration: Duration.zero,
         pageBuilder: (context, _, _) => _TrainingTransitionHost(
           route: ModalRoute.of(context)! as TrainingRoute,
           builder: builder,
         ),
       );

  final TrainingTransitionSource? source;
  final ModalRoute<dynamic>? _sourceRoute;
  final _visual = Completer<void>();
  _TrainingTransitionHostState? _host;
  OverlayEntry? _returnEntry;
  bool _returning = false;
  bool _finishingVisual = false;
  LocalHistoryEntry? _returnHistory;

  /// Includes the post-pop shrink and the 120ms source-image cross-fade.
  Future<void> get visualCompleted => _visual.future;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  bool didPop(T? result) {
    _host?.prepareReturn();
    return super.didPop(result);
  }

  void _finishVisual() {
    if (_finishingVisual) return;
    _finishingVisual = true;
    final entry = _returnEntry;
    _returnEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
    source?.show(1);
    _returnHistory?.remove();
    _returnHistory = null;
    FrameRecorder.instance.endScenario(FrameScenario.trainingRouteExit);
    if (!_visual.isCompleted) _visual.complete();
  }

  @override
  void dispose() {
    if (!_returning) _finishVisual();
    super.dispose();
  }
}
