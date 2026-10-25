/// Action review is available only in the installed internal test flavor.
const actionIssueBuildEnabled =
    String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
    bool.fromEnvironment('SMARTFIT_ACTION_ISSUES');

enum ActionIssueTag {
  clipping('clipping', '穿模'),
  pose('pose', '姿势不对'),
  highlight('highlight', '高亮不对'),
  framing('framing', '镜头裁切'),
  naming('naming', '名称说明不对');

  const ActionIssueTag(this.code, this.label);
  final String code;
  final String label;
}

enum ActionIssueVideoUnavailableReason {
  notReady('not_ready', '视频尚未就绪'),
  noVideo('no_video', '这个动作没有视频'),
  unavailable('unavailable', '播放器未提供当前时间');

  const ActionIssueVideoUnavailableReason(this.code, this.label);
  final String code;
  final String label;
}

/// Capture this when the user marks the action, before opening the form.
/// Null media metadata is explicit; no session time or guessed revision is used.
class ActionIssueContext {
  ActionIssueContext({
    required String actionId,
    required String? revision,
    required this.videoSeconds,
    this.videoPositionUnavailableReason,
    String? revisionUnavailableReason,
    DateTime? capturedAt,
  }) : actionId = actionId.trim(),
       revision = revision?.trim(),
       revisionUnavailableReason = revisionUnavailableReason?.trim(),
       capturedAt = (capturedAt ?? DateTime.now()).toUtc() {
    if (this.actionId.isEmpty) throw ArgumentError('Action id is required');
    if (this.revision == null) {
      if (this.revisionUnavailableReason?.isNotEmpty != true) {
        throw ArgumentError('A missing revision needs an explicit reason');
      }
    } else if (this.revision!.isEmpty ||
        this.revisionUnavailableReason != null) {
      throw ArgumentError('Invalid action revision');
    }
    if (videoSeconds == null) {
      if (videoPositionUnavailableReason == null) {
        throw ArgumentError(
          'A missing video position needs an explicit reason',
        );
      }
    } else if (!videoSeconds!.isFinite ||
        videoSeconds! < 0 ||
        videoPositionUnavailableReason != null) {
      throw ArgumentError('Invalid video position');
    }
  }

  final String actionId;
  final String? revision;
  final String? revisionUnavailableReason;
  final double? videoSeconds;
  final ActionIssueVideoUnavailableReason? videoPositionUnavailableReason;
  final DateTime capturedAt;

  Map<String, Object?> toJson() => {
    'actionId': actionId,
    'revision': revision,
    'revisionUnavailableReason': revisionUnavailableReason,
    'videoSeconds': videoSeconds,
    'videoPositionUnavailableReason': videoPositionUnavailableReason?.code,
    'capturedAt': capturedAt.toIso8601String(),
  };

  factory ActionIssueContext.fromJson(Map<String, dynamic> json) {
    final unavailable = json['videoPositionUnavailableReason'] as String?;
    return ActionIssueContext(
      actionId: json['actionId'] as String,
      revision: json['revision'] as String?,
      revisionUnavailableReason: json['revisionUnavailableReason'] as String?,
      videoSeconds: (json['videoSeconds'] as num?)?.toDouble(),
      videoPositionUnavailableReason: unavailable == null
          ? null
          : ActionIssueVideoUnavailableReason.values.firstWhere(
              (reason) => reason.code == unavailable,
              orElse: () => throw const FormatException('Unknown video reason'),
            ),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }
}

class ActionIssue {
  ActionIssue({
    required this.id,
    required this.capture,
    Iterable<ActionIssueTag> tags = const [],
    String note = '',
  }) : tags = List.unmodifiable([
         for (final tag in ActionIssueTag.values)
           if (tags.contains(tag)) tag,
       ]),
       note = note.trim().replaceAll(RegExp(r'\s+'), ' ') {
    if (id.isEmpty) throw ArgumentError('Issue id is required');
    if (this.note.length > noteLimit) {
      throw ArgumentError('Issue note exceeds $noteLimit characters');
    }
  }

  static const noteLimit = 200;
  final String id;
  final ActionIssueContext capture;
  final List<ActionIssueTag> tags;
  final String note;

  Map<String, Object?> toJson() => {
    'id': id,
    ...capture.toJson(),
    'tags': [for (final tag in tags) tag.code],
    'note': note,
  };

  factory ActionIssue.fromJson(Map<String, dynamic> json) => ActionIssue(
    id: json['id'] as String,
    capture: ActionIssueContext.fromJson(json),
    tags: [
      for (final code in json['tags'] as List)
        ActionIssueTag.values.firstWhere(
          (tag) => tag.code == code,
          orElse: () => throw const FormatException('Unknown issue tag'),
        ),
    ],
    note: json['note'] as String,
  );
}
