import 'package:flutter/material.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

import '../diagnostics/action_issue.dart';
import '../diagnostics/action_issue_store.dart';
import '../domain/exercise.dart';
import 'action_issue_form.dart';
import 'theme.dart';

/// The fallback id and time belong to the tap, never to a later player build.
/// A completed snapshot carries its own identity across an action switch.
Future<ActionIssueContext> captureActionIssueContext({
  required String actionIdAtTap,
  required ExerciseLibrary library,
  required Future<DrillMediaPlaybackSnapshot?> Function() capturePlayback,
  required bool light,
  DateTime? capturedAt,
}) async {
  final at = capturedAt ?? DateTime.now().toUtc();
  DrillMediaPlaybackSnapshot? snapshot;
  var unavailable = ActionIssueVideoUnavailableReason.notReady;
  try {
    snapshot = await capturePlayback();
  } on Object {
    unavailable = ActionIssueVideoUnavailableReason.unavailable;
  }
  final actionId = snapshot?.mediaId ?? actionIdAtTap;
  final exercise = library.tryGet(actionId);
  final seconds = snapshot?.videoSeconds;
  final position =
      snapshot?.ready == true &&
          seconds != null &&
          seconds.isFinite &&
          seconds >= 0
      ? seconds
      : null;
  if (position == null) {
    if (exercise != null && !exercise.media.videoAvailableFor(light: light)) {
      unavailable = ActionIssueVideoUnavailableReason.noVideo;
    } else if (snapshot?.ready == true) {
      unavailable = ActionIssueVideoUnavailableReason.unavailable;
    }
  }
  return ActionIssueContext(
    actionId: actionId,
    revision: exercise?.media.revision,
    revisionUnavailableReason: exercise?.media.revision == null
        ? 'metadata_not_available'
        : null,
    videoSeconds: position,
    videoPositionUnavailableReason: position == null ? unavailable : null,
    capturedAt: snapshot?.capturedAt ?? at,
  );
}

class ActionIssueMarkButton extends StatefulWidget {
  const ActionIssueMarkButton({
    super.key,
    required this.store,
    required this.library,
    required this.playbackHandle,
    required this.actionIdAtTap,
    this.iconOnly = false,
  });

  final LocalActionIssueStore store;
  final ExerciseLibrary library;
  final DrillMediaPlaybackHandle playbackHandle;
  final String? Function() actionIdAtTap;
  final bool iconOnly;

  @override
  State<ActionIssueMarkButton> createState() => _ActionIssueMarkButtonState();
}

class _ActionIssueMarkButtonState extends State<ActionIssueMarkButton> {
  bool _busy = false;

  Future<void> _mark() async {
    if (_busy || !widget.store.enabled) return;
    final id = widget.actionIdAtTap();
    if (id == null) return;
    final at = DateTime.now().toUtc();
    final light = Theme.of(context).brightness == Brightness.light;
    setState(() => _busy = true);
    try {
      final capture = await captureActionIssueContext(
        actionIdAtTap: id,
        library: widget.library,
        capturePlayback: widget.playbackHandle.capture,
        light: light,
        capturedAt: at,
      );
      // A capture can finish after its training session ended or a close
      // confirmation covered the route. Never put a late form above a pending
      // training receipt; retain the original tap's identity when still valid.
      if (!mounted ||
          widget.actionIdAtTap() == null ||
          ModalRoute.isCurrentOf(context) == false) {
        return;
      }
      final record = await showActionIssueForm(
        context,
        store: widget.store,
        capture: capture,
      );
      if (record != null && mounted) {
        showSfToast(context, '标记已保存在本机，可在设置中保存 JSON 到下载。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.enabled) return const SizedBox.shrink();
    return RepaintBoundary(
      child: widget.iconOnly
          ? SfCircleButton(
              icon: SfGlyph.clipboard,
              size: 48,
              tooltip: '标记动作问题',
              fill: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .85),
              onPressed: _busy ? null : _mark,
            )
          : SfTextAction(
              label: '标记动作问题',
              icon: SfGlyph.clipboard,
              onPressed: _busy ? null : _mark,
            ),
    );
  }
}
