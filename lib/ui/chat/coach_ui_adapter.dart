import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import '../../chat/chat_models.dart' show ChatMessage;
import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../app/posehub_asset_bundle.dart';
import '../alpha_artwork.dart';
import '../theme.dart' show levelZh;
import '../theme/media_theme.dart';
import '../theme/sf_icons.dart';
import '../theme/solid_surface.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// Product tokens, trusted media and controls; the SDK owns conversation and
/// routine rendering. Navigation, storage and credentials remain App concerns.
Widget withSmartfitCoachUi(BuildContext context, Widget child) =>
    CoachUiTheme.contains(context)
    ? child
    : CoachUiTheme(style: smartfitCoachUiStyle(), child: child);

/// Recommendation layout and surfaces stay SDK-owned, with only App colors
/// and localized fixed labels injected into its own theme scope.
Widget withSmartfitRecommendUi(BuildContext context, Widget child) {
  final defaults = CoachUiStyle.fromTheme(Theme.of(context));
  return CoachUiTheme(
    style: CoachUiStyle(
      colors: smartfitCoachUiStyle().colors,
      typography: defaults.typography,
      strings: const CoachUiStrings(
        planFromActions: '排成计划',
        actionUnavailable: '动作暂不可用',
      ),
    ),
    child: child,
  );
}

CoachMediaPalette coachMediaPalette(SfPalette p) => CoachMediaPalette(
  mediaStage: p.mediaStage,
  onStage: p.onStage,
  onStageMuted: p.onStageMuted,
);

CoachQuestionData toCoachQuestionData(ChatMessage message) {
  final question = message.question!;
  return CoachQuestionData(
    id: message.id,
    question: question.question,
    mode: switch (question.mode) {
      coach.AskUserMode.text => CoachQuestionMode.text,
      coach.AskUserMode.choice => CoachQuestionMode.choice,
      coach.AskUserMode.form => CoachQuestionMode.form,
    },
    options: question.options,
    multiple: question.multiple,
    answered: message.questionAnswered,
    answeredChoices: message.answeredChoices,
    answeredForm: message.answeredForm,
    isConfirmation: question.isConfirmation,
    focus: question.focus,
    defaultSelections: question.defaultSelections,
    fields: [
      for (final field in question.fields)
        CoachQuestionField(
          key: field.key,
          label: field.label,
          options: field.options,
          multiple: field.multiple,
          initialSelections: field.preselected,
          previousSelections: field.previousSelections,
          optionsByScene: field.optionsByScene,
        ),
    ],
    skipLabel: question.skipLabel,
  );
}

CoachUiStyle smartfitCoachUiStyle() {
  final p = SfColors.palette;
  return CoachUiStyle(
    colors: CoachUiColors(
      brightness: p.brightness,
      text: p.text,
      muted: p.muted,
      faint: p.faint,
      background: p.background,
      surface: p.surface,
      surfaceRaised: p.surfaceHigh,
      outline: p.line,
      shadow: p.shadow,
      accent: p.accent,
      accentText: p.accentText,
      accentSoft: p.accentSoft,
      onAccent: p.onAccent,
      userBubble: p.userBubble,
      assistantBubble: p.assistantBubble,
      stage: coachMediaPalette(p),
      emphasis: p.accent,
      onEmphasis: p.onAccent,
      onMedia: p.text,
      mediaLabelSurface: p.surfaceHigh,
    ),
    typography: CoachUiTypography(
      body: SfType.body,
      callout: SfType.callout,
      label: SfType.label,
      caption: SfType.caption,
      greeting: SfType.greeting,
    ),
    strings: const CoachUiStrings(
      expand: '展开',
      collapse: '收起',
      expandDetails: '展开详情',
      collapseDetails: '收起详情',
      save: '保存',
      saved: '已保存',
      start: '开始训练',
      cancel: '取消',
      preparing: '正在准备回复…',
      progressHint: '助理会分步查动作和核对计划，可能需要几分钟',
      answerHint: '说说你的情况…',
      submitAnswer: '确认回答',
      multipleHint: '可以选择多项',
      planDetails: _planDetails,
      timeLabel: _timeLabel,
    ),
    builders: CoachUiBuilders(
      media: (context, request) => _isTrainerStandingAsset(request.asset)
          ? Image.asset(
              request.asset,
              fit: request.fit,
              alignment: request.alignment,
              semanticLabel: request.semanticLabel,
              excludeFromSemantics: request.semanticLabel == null,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : SfAlphaCards.enabledOf(context) &&
                (request.asset.startsWith('assets/app_test_pack/') ||
                    PoseHubAssetBundle.handles(request.asset))
          ? SfAlphaAsset(
              asset: request.asset,
              fit: request.cutout ? request.fit : BoxFit.contain,
              alignment: request.cutout ? request.alignment : Alignment.center,
              semanticLabel: request.semanticLabel,
            )
          : null,
      pressable: (_, c) => SfPressable(
        onTap: c.onTap,
        semanticLabel: c.semanticLabel,
        tooltip: c.tooltip,
        scale: c.scale,
        expanded: c.expanded,
        haptic: SfHaptic.values[c.haptic.index],
        child: c.child,
      ),
      controlFace: (_, c) => SfColors.isDark
          ? ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.minHeight),
              child: SfSolidSurface(
                level: SfSurfaceLevel.raised,
                radius: c.minHeight / 2,
                padding: c.padding,
                control: true,
                child: c.child,
              ),
            )
          : c.child,
      textAction: (_, c) => SfTextAction(
        label: c.label,
        onPressed: c.onPressed,
        icon: c.icon == null ? null : _glyph(c.icon!),
        iconFilled: c.iconFilled,
        color: c.color,
        boxed: false,
      ),
      surface: (context, c) => SfAlphaCardScope.of(context)
          ? SfAlphaCardSurface(
              radius: c.radius,
              padding: c.padding,
              width: c.width,
              child: c.child,
            )
          : SfSolidSurface(
              radius: c.radius,
              padding: c.padding,
              width: c.width,
              child: c.child,
            ),
      icon: (_, c) => SfIcon(
        _glyph(c.glyph),
        size: c.size,
        color: c.color,
        filled: c.filled,
        strokeWidth: c.strokeWidth,
      ),
      startButton: (_, c) => SfPressable(
        semanticLabel: '开始训练',
        tooltip: '开始训练',
        onTap: c.onTap,
        haptic: SfHaptic.medium,
        child: Container(
          key: const ValueKey('start-disc'),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SfColors.accent,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: SfIcon(
                SfGlyph.play,
                size: 18,
                filled: true,
                color: SfColors.onAccent,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

SfGlyph _glyph(CoachGlyph glyph) => switch (glyph) {
  CoachGlyph.bookmark => SfGlyph.bookmark,
  CoachGlyph.chevronRight => SfGlyph.chevronRight,
  CoachGlyph.play => SfGlyph.play,
  CoachGlyph.stop => SfGlyph.stop,
};

String _planDetails(String title) => '计划详情：$title';
String _timeLabel(DateTime at, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final hm =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  return switch (today.difference(day).inDays) {
    0 => '今天 $hm',
    1 => '昨天 $hm',
    _ => '${at.month}月${at.day}日 $hm',
  };
}

const _trainerStandingPrefix =
    'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/';

bool _isTrainerStandingAsset(String asset) => RegExp(
  r'^packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/[A-Za-z0-9_-]+\.webp$',
).hasMatch(asset);

String? _trainerStandingFor(Exercise exercise) {
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(exercise.id)) return null;
  // This is the catalog-bound image key created by AppTestContent, not an
  // arbitrary user-supplied asset path. Other exercise sources keep their own
  // existing still images.
  final cover =
      '${PoseHubAssetBundle.prefix}${Uri.encodeComponent(exercise.id)}/cover';
  if (exercise.media.alphaCover != cover) return null;
  return '$_trainerStandingPrefix${exercise.id}.webp';
}

CoachExercise toCoachExercise(
  Exercise e, {
  bool alphaCards = SfAlphaCards.enabled,
}) {
  final alpha = SfAlphaCards.hasCover(e, enabled: alphaCards);
  final palette = sfStageFor(e);
  final gear = e.effectiveEquipmentIds
      .where((id) => id != 'none' && id.isNotEmpty)
      .toSet();
  return CoachExercise(
    id: e.id,
    name: e.name,
    // The SDK chooses its own thumbnail/cutout treatment for each card state.
    poster: alpha ? e.media.alphaThumbnail ?? e.media.alphaCover! : sfPoster(e),
    stage: alpha
        ? CoachMediaPalette(
            mediaStage: Colors.transparent,
            onStage: palette.text,
            onStageMuted: palette.muted,
          )
        : coachMediaPalette(palette),
    categoryLabel: e.category.zh,
    levelLabel: levelZh(e.level),
    equipmentLabel: gear.isEmpty ? '徒手' : gear.map(equipmentLabel).join('、'),
    cues: e.cues,
    cutout: alpha
        ? _trainerStandingFor(e) ?? e.media.alphaCover
        : SfCutouts.has(e)
        ? SfCutouts.asset(e)
        : null,
    stillCutout: alpha
        ? _trainerStandingFor(e) ?? e.media.alphaCover
        : SfCutouts.has(e)
        ? SfCutouts.asset(e, still: true)
        : null,
  );
}

/// The action browser and recommendations share the SDK's bundled first frame.
/// Media IDs are resolved from the trusted catalog, never from model text.
CoachExercise toCoachRecommendationExercise(Exercise exercise) {
  final adapted = toCoachExercise(exercise);
  return CoachExercise(
    id: adapted.id,
    name: adapted.name,
    poster: adapted.poster,
    stage: adapted.stage,
    categoryLabel: adapted.categoryLabel,
    levelLabel: adapted.levelLabel,
    equipmentLabel: adapted.equipmentLabel,
    cues: adapted.cues,
    cutout: adapted.cutout,
    stillCutout: _trainerStandingFor(exercise) ?? adapted.stillCutout,
  );
}

CoachRoutine toCoachRoutine(TrainingPlan p, ExerciseLibrary library) {
  // The admitted plan carries equipment for the exercises it actually uses.
  // Do not hide furniture that the user must prepare for those exercises.
  final gear = p.equipment.where((id) => id != 'none' && id.isNotEmpty).toSet();
  final gearText = gear.isEmpty ? '徒手' : gear.map(equipmentLabel).join('、');
  final duration = '${p.targetMinutes} 分钟';
  final items = [
    for (final b in p.blocks)
      for (final i in b.items)
        CoachRoutineItem(
          exerciseId: i.exerciseId,
          dose: i.doseText(),
          detailDose: b.type == BlockType.circuit
              ? i.copyWith(sets: 1).doseText()
              : i.doseText(),
        ),
  ];
  return CoachRoutine(
    id: p.id,
    title: p.title,
    items: items,
    durationLabel: duration,
    gearLabel: gearText,
    levelLabel: levelZh(p.level),
    metaLabel: [duration, '${items.length} 个动作', gearText].join(' · '),
    adjustmentsLabel: p.notes.isEmpty ? null : '已按你的情况调整 ${p.notes.length} 处',
  );
}
