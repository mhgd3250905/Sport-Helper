import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../domain/exercise.dart';
import '../alpha_artwork.dart';
import '../theme.dart' show levelZh;
import '../theme/media_theme.dart';
import '../theme/polish_card.dart';
import '../theme/tokens.dart';
import '../theme/ui_polish_tokens.dart';

/// Only sourced SDK facts drive this presentation; node stamps stay internal.
class CoachTaskBubble extends StatefulWidget {
  const CoachTaskBubble({
    super.key,
    this.task,
    this.sessionState,
    this.library,
    this.waiting = false,
    this.onCancel,
  });

  final coach.CoachTaskState? task;
  final coach.CoachSessionState? sessionState;
  final ExerciseLibrary? library;
  final bool waiting;
  final VoidCallback? onCancel;

  @override
  State<CoachTaskBubble> createState() => _CoachTaskBubbleState();
}

class _CoachTaskBubbleState extends State<CoachTaskBubble>
    with TickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.rotation,
  );
  late final _shine = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.shimmer,
  );
  late final _progress = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.progressTransition,
  );
  late final _images = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.imageHold + SfGenerationTokens.imageTransition,
  )..addListener(_advanceImage);
  bool? _reduced;
  int _imageIndex = 0;
  double _lastImageValue = 0;

  coach.CoachTaskState? get _task => widget.task ?? widget.sessionState?.task;
  List<String> get _picks => widget.sessionState?.picks ?? const [];
  List<Exercise> get _selected => [
    for (final id in _picks) ?widget.library?.tryGet(id),
  ];
  bool get _complete =>
      _task?.nodes.any((node) => node.id == 'output' && _done(node)) ?? false;

  static bool _done(coach.CoachNodeState node) =>
      node.status == 'done' || node.status == 'updated';

  static int _phase(coach.CoachTaskState? task) {
    final nodes = task?.nodes ?? const <coach.CoachNodeState>[];
    final node =
        nodes.where((node) => node.status == 'current').firstOrNull ??
        nodes.where(_done).lastOrNull;
    return switch (node?.id) {
      'actions' => 1,
      'planning' => 2,
      'review' => 3,
      'output' => SfGenerationTokens.progressSegments,
      _ => 0,
    };
  }

  String get _status => switch (_phase(_task)) {
    1 when _picks.isNotEmpty => '挑好了 ${_picks.length} 个动作',
    2 => '安排顺序和时长',
    3 => '最后检查一遍',
    4 => '马上就好',
    _ => '读懂你的需求',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = SfMotion.reduced(context);
    if (_reduced != reduced) {
      _reduced = reduced;
      _syncMotion(restartProgress: true);
    }
  }

  @override
  void didUpdateWidget(CoachTaskBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPicks = oldWidget.sessionState?.picks ?? const <String>[];
    if (!listEquals(oldPicks, _picks)) {
      _imageIndex = 0;
      _lastImageValue = 0;
      _images.value = 0;
    }
    _syncMotion(
      restartProgress:
          _phase(oldWidget.task ?? oldWidget.sessionState?.task) !=
          _phase(_task),
    );
  }

  void _syncMotion({bool restartProgress = false}) {
    final animate = _reduced == false && widget.waiting && !_complete;
    for (final controller in [_rotation, _shine]) {
      if (animate) {
        if (!controller.isAnimating) controller.repeat();
      } else {
        controller.stop();
      }
    }
    if (animate && _selected.length > 1) {
      if (!_images.isAnimating) _images.repeat();
    } else {
      _images.stop();
    }
    if (_reduced == true || _complete) {
      _progress.value = 1;
    } else if (restartProgress) {
      _progress.forward(from: 0);
    }
  }

  void _advanceImage() {
    final count = _selected.length;
    if (count > 1 && _images.value < _lastImageValue && mounted) {
      setState(() => _imageIndex = (_imageIndex + 1) % count);
    }
    _lastImageValue = _images.value;
  }

  @override
  void dispose() {
    _rotation.dispose();
    _shine.dispose();
    _progress.dispose();
    _images.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = _parameterLabels(widget.sessionState?.params ?? const {});
    final scene = chips.where((chip) => chip.field == 'scene').firstOrNull;
    final goal = chips.where((chip) => chip.field == 'goal').firstOrNull;
    final title = scene != null && goal != null
        ? '正在为你准备 · ${scene.label}${goal.label}'
        : '正在想怎么练…';
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: SfGenerationTokens.maxWidth,
        ),
        child: AnimatedSize(
          key: const ValueKey('generation-completion-size'),
          duration: SfGenerationTokens.completionTransition,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _complete && !widget.waiting
              ? const SizedBox.shrink()
              : SfPolishCard(
                  padding: SfGenerationTokens.padding,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: SfGenerationTokens.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.waiting && widget.onCancel != null)
                            SizedBox.square(
                              key: const ValueKey('generation-cancel-target'),
                              dimension: SfGenerationTokens.cancelTouchSize,
                              child: TextButton(
                                onPressed: widget.onCancel,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: SfColors.muted,
                                  backgroundColor: SfGenerationTokens.chipFill(
                                    false,
                                  ),
                                ),
                                child: Text(
                                  '取消',
                                  style: SfGenerationTokens.cancel,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: SfSpace.x2),
                      Row(
                        children: [
                          _animation(),
                          const SizedBox(width: SfSpace.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _StatusSentence(
                                  text: _status,
                                  shimmer: _shine,
                                  reduced: _reduced == true,
                                ),
                                const SizedBox(height: SfSpace.x2),
                                _progressBar(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: SfSpace.x3),
                        Wrap(
                          spacing: SfSpace.x2,
                          runSpacing: SfSpace.x2,
                          children: [
                            for (var index = 0; index < chips.length; index++)
                              _ParameterChip(
                                key: ValueKey(
                                  'generation-chip-${chips[index].field}-'
                                  '${chips[index].label}-${chips[index].user}',
                                ),
                                data: chips[index],
                                index: index,
                                reduced: _reduced == true,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _animation() => SizedBox.square(
    key: const ValueKey('generation-animation'),
    dimension: SfGenerationTokens.animationSize,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: RotationTransition(
            key: const ValueKey('generation-rotation'),
            turns: _rotation,
            child: CustomPaint(painter: _ArcPainter(SfColors.accent)),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([_rotation, _images]),
          builder: (context, _) {
            final selected = _selected;
            if (selected.isEmpty) {
              return Row(
                key: const ValueKey('generation-dots'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (
                    var index = 0;
                    index < SfGenerationTokens.dotCount;
                    index++
                  )
                    Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? 0 : SfGenerationTokens.dotGap,
                      ),
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          _reduced == true
                              ? 0
                              : -math.sin(
                                      (_rotation.value -
                                              index *
                                                  SfGenerationTokens
                                                      .dotDelay
                                                      .inMilliseconds /
                                                  SfGenerationTokens
                                                      .rotation
                                                      .inMilliseconds) *
                                          math.pi *
                                          2,
                                    ) *
                                    SfGenerationTokens.dotLift,
                        ),
                        child: Container(
                          key: ValueKey('generation-dot-$index'),
                          width: SfGenerationTokens.dotSize,
                          height: SfGenerationTokens.dotSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SfColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }
            final current = _imageIndex % selected.length;
            final next = (current + 1) % selected.length;
            final cycle =
                SfGenerationTokens.imageHold +
                SfGenerationTokens.imageTransition;
            final elapsed = _images.value * cycle.inMilliseconds;
            final blend = _reduced == true || selected.length == 1
                ? 0.0
                : ((elapsed - SfGenerationTokens.imageHold.inMilliseconds) /
                          SfGenerationTokens.imageTransition.inMilliseconds)
                      .clamp(0.0, 1.0);
            return Padding(
              key: const ValueKey('generation-thumbnails'),
              padding: const EdgeInsets.all(SfGenerationTokens.thumbnailInset),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: 1 - blend,
                      child: _thumbnail(selected[current]),
                    ),
                    if (blend > 0)
                      Opacity(
                        opacity: blend,
                        child: _thumbnail(selected[next]),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    ),
  );

  Widget _thumbnail(Exercise exercise) {
    final asset =
        exercise.media.alphaThumbnail ??
        exercise.media.alphaCover ??
        sfPoster(exercise);
    return SfAlphaAsset(
      key: ValueKey('generation-thumbnail-${exercise.id}'),
      asset: asset,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      semanticLabel: exercise.name,
    );
  }

  Widget _progressBar() => AnimatedBuilder(
    animation: _progress,
    builder: (context, _) {
      final phase = _phase(_task);
      return Row(
        children: [
          for (
            var index = 0;
            index < SfGenerationTokens.progressSegments;
            index++
          ) ...[
            if (index > 0)
              const SizedBox(width: SfGenerationTokens.progressGap),
            Expanded(
              child: SizedBox(
                height: SfGenerationTokens.progressHeight,
                child: ClipRRect(
                  key: ValueKey('generation-progress-$index'),
                  borderRadius: BorderRadius.circular(
                    SfGenerationTokens.progressRadius,
                  ),
                  child: ColoredBox(
                    color: SfCardTokens.edge,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: ValueKey('generation-progress-fill-$index'),
                        heightFactor: 1,
                        widthFactor: index < phase
                            ? 1
                            : index == phase
                            ? Curves.easeOutCubic.transform(_progress.value)
                            : 0,
                        child: ColoredBox(color: SfColors.accent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

typedef _ChipData = ({String field, String label, bool user});

List<_ChipData> _parameterLabels(Map<String, coach.CoachParamValue> params) {
  final result = <_ChipData>[];
  for (final field in ['scene', 'goal', 'equipment', 'level', 'limits']) {
    final param = params[field];
    if (param == null) continue;
    final value = param.value;
    final label = switch (field) {
      'scene' => const {
        'home': '居家',
        'office': '办公室',
        'gym': '健身房',
        'outdoor': '户外',
      }[value],
      'goal' =>
        value is List
            ? [
                for (final code in value)
                  for (final category in ExerciseCategory.values)
                    if (code == 'purpose.${category.name}') category.zh,
              ].firstOrNull
            : null,
      'equipment' => _equipmentLabel(value),
      'level' => value is int ? levelZh(value) : null,
      'limits' => _limitsLabel(value),
      _ => null,
    };
    if (label != null && label.isNotEmpty) {
      result.add((field: field, label: label, user: param.source == 'user'));
    }
  }
  return result;
}

String? _equipmentLabel(Object? value) {
  if (value is! List) return null;
  if (value.isEmpty || value.every((code) => code == 'none')) return '徒手';
  final code = value.whereType<String>().firstOrNull;
  if (code == null) return null;
  final id = code.startsWith('equip.')
      ? code.substring('equip.'.length).replaceAll('_', '-')
      : code;
  final translated = equipmentLabel(id).split(RegExp('[（(]')).first.trim();
  return translated == id && RegExp(r'[A-Za-z]').hasMatch(translated)
      ? null
      : translated;
}

String? _limitsLabel(Object? value) {
  if (value is! List) return null;
  if (value.isEmpty) return '无伤痛';
  const labels = {
    'limit.knee': '膝',
    'limit.waist': '腰',
    'limit.shoulder': '肩',
    'limit.wrist': '手腕',
    'limit.neck': '颈',
    'limit.hip': '髋',
    'limit.inner_thigh': '大腿内侧',
  };
  final known = [for (final code in value) ?labels[code]];
  return known.length == value.length ? known.join('、') : '身体限制';
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawArc(
    (Offset.zero & size).deflate(SfGenerationTokens.arcWidth / 2),
    -math.pi / 2,
    SfGenerationTokens.arcSweep * math.pi / 180,
    false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = SfGenerationTokens.arcWidth
      ..color = color,
  );

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}

class _StatusSentence extends StatefulWidget {
  const _StatusSentence({
    required this.text,
    required this.shimmer,
    required this.reduced,
  });
  final String text;
  final Animation<double> shimmer;
  final bool reduced;

  @override
  State<_StatusSentence> createState() => _StatusSentenceState();
}

class _StatusSentenceState extends State<_StatusSentence>
    with SingleTickerProviderStateMixin {
  late final _transition = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.statusTransition,
    value: 1,
  );
  String? _previous;

  @override
  void didUpdateWidget(_StatusSentence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _previous = oldWidget.text;
      if (widget.reduced) {
        _transition.value = 1;
      } else {
        _transition.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = SfGenerationTokens.status;
    final height =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!;
    return Semantics(
      label: widget.text,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox(
          key: const ValueKey('generation-status'),
          height: height,
          child: AnimatedBuilder(
            animation: Listenable.merge([_transition, widget.shimmer]),
            builder: (context, _) {
              Widget text(String value) => ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    SfColors.text,
                    widget.reduced
                        ? SfColors.text
                        : SfGenerationTokens.highlight,
                    SfColors.text,
                  ],
                  stops: SfGenerationTokens.shimmerStops,
                  transform: _ShimmerSlide(widget.shimmer.value),
                ).createShader(bounds),
                blendMode: BlendMode.srcIn,
                child: Text(value, style: style, maxLines: 1),
              );
              final value = _transition.value;
              return ClipRect(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (value < 1 && _previous != null)
                      Opacity(
                        opacity: 1 - value,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            -SfGenerationTokens.statusOffset * value,
                          ),
                          child: text(_previous!),
                        ),
                      ),
                    Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          SfGenerationTokens.statusOffset * (1 - value),
                        ),
                        child: text(widget.text),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ShimmerSlide extends GradientTransform {
  const _ShimmerSlide(this.value);
  final double value;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (2 * value - 1), 0, 0);
}

class _ParameterChip extends StatefulWidget {
  const _ParameterChip({
    super.key,
    required this.data,
    required this.index,
    required this.reduced,
  });
  final _ChipData data;
  final int index;
  final bool reduced;

  @override
  State<_ParameterChip> createState() => _ParameterChipState();
}

class _ParameterChipState extends State<_ParameterChip>
    with SingleTickerProviderStateMixin {
  late final _appearance = AnimationController(
    vsync: this,
    duration: SfGenerationTokens.chipTransition,
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _delay?.cancel();
    if (widget.reduced) {
      _appearance.value = 1;
    } else if (widget.index == 0) {
      _appearance.forward();
    } else {
      _delay = Timer(SfGenerationTokens.chipDelay * widget.index, () {
        if (mounted) _appearance.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_ParameterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduced != widget.reduced) _start();
  }

  @override
  void dispose() {
    _delay?.cancel();
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _appearance,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: SfGenerationTokens.chipInitialScale,
        end: 1,
      ).animate(_appearance),
      child: Container(
        key: ValueKey('generation-chip-face-${widget.data.field}'),
        height: SfGenerationTokens.chipHeight,
        padding: SfGenerationTokens.chipPadding,
        decoration: BoxDecoration(
          color: SfGenerationTokens.chipFill(widget.data.user),
          borderRadius: BorderRadius.circular(SfGenerationTokens.chipRadius),
          border: widget.data.user
              ? null
              : Border.all(
                  color: SfCardTokens.edge,
                  width: SfCardTokens.edgeWidth,
                ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            widget.data.label,
            style: SfGenerationTokens.chipText(widget.data.user),
          ),
        ),
      ),
    ),
  );
}
