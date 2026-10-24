import 'package:flutter/material.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../../domain/session.dart';
import '../theme.dart' show levelZh;
import '../theme/glass.dart';
import '../theme/media_theme.dart';
import '../theme/sf_icons.dart';
import '../theme/tokens.dart';
import '../theme/widgets.dart';

/// Product tokens, trusted media and controls; the SDK owns conversation and
/// routine rendering. Navigation, storage and credentials remain App concerns.
Widget withSmartfitCoachUi(BuildContext context, Widget child) =>
    CoachUiTheme.contains(context)
    ? child
    : CoachUiTheme(style: smartfitCoachUiStyle(), child: child);

CoachMediaPalette coachMediaPalette(SfPalette p) => CoachMediaPalette(
  mediaStage: p.mediaStage,
  onStage: p.onStage,
  onStageMuted: p.onStageMuted,
);

CoachUiStyle smartfitCoachUiStyle() {
  final p = SfColors.palette;
  return CoachUiStyle(
    colors: CoachUiColors(
      brightness: p.brightness,
      text: p.text,
      muted: p.muted,
      faint: p.faint,
      surface: p.surface,
      thumb: p.thumb,
      accent: p.accent,
      accentText: p.accentText,
      accentSoft: p.accentSoft,
      onAccent: p.onAccent,
      userBubble: p.userBubble,
      assistantBubble: p.assistantBubble,
      stage: coachMediaPalette(p),
      emphasis: p.emphasis,
      onEmphasis: p.onEmphasis,
      onMedia: Colors.white,
      mediaScrim: const Color(0x66000000),
      landingHighlight: Colors.white,
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
      pressable: (_, c) => SfPressable(
        onTap: c.onTap,
        semanticLabel: c.semanticLabel,
        tooltip: c.tooltip,
        scale: c.scale,
        expanded: c.expanded,
        haptic: SfHaptic.values[c.haptic.index],
        child: c.child,
      ),
      controlFace: (_, c) => SfControlFace(
        padding: c.padding,
        minHeight: c.minHeight,
        child: c.child,
      ),
      textAction: (_, c) => SfTextAction(
        label: c.label,
        onPressed: c.onPressed,
        icon: c.icon == null ? null : _glyph(c.icon!),
        iconFilled: c.iconFilled,
        color: c.color,
        boxed: c.boxed,
      ),
      surface: (_, c) => SfScrollCardSurface(
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
        child: SizedBox.square(
          dimension: 48,
          child: Builder(
            builder: (context) {
              final dark = SfColors.palette.mediaStage.computeLuminance() < .2;
              final palette = dark ? SfPalette.dark : SfPalette.light;
              return SfTactile(
                key: const ValueKey('start-disc'),
                style: SfTactileStyle.accent(
                  dark: dark,
                  color: palette.emphasis,
                ),
                pressed: SfPressedScope.of(context),
                radius: 24,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: SfIcon(
                      SfGlyph.play,
                      size: 18,
                      filled: true,
                      color: palette.onEmphasis,
                    ),
                  ),
                ),
              );
            },
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

CoachExercise toCoachExercise(Exercise e) => CoachExercise(
  id: e.id,
  name: e.name,
  poster: sfPoster(e),
  stage: coachMediaPalette(sfStageFor(e)),
  categoryLabel: e.category.zh,
  cues: e.cues,
  cutout: SfCutouts.has(e) ? SfCutouts.asset(e) : null,
  stillCutout: SfCutouts.has(e) ? SfCutouts.asset(e, still: true) : null,
);

CoachRoutine toCoachRoutine(TrainingPlan p, ExerciseLibrary library) {
  final moves = [
    for (final id in p.exerciseIds) library.tryGet(id),
  ].whereType<Exercise>();
  const extra = {Equipment.band, Equipment.dumbbell, Equipment.slider};
  final gear = {for (final e in moves) ...e.equipment.where(extra.contains)};
  final gearText = gear.isEmpty ? '徒手' : gear.map((e) => e.zh).join('、');
  final minutes = (SessionBuilder(library).planSeconds(p) / 60).round();
  final duration = minutes < 1 ? '不到 1 分钟' : '$minutes 分钟';
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
