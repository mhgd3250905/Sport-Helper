import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../domain/exercise.dart';
import '../alpha_artwork.dart';
import '../theme.dart' show levelZh;
import '../theme/media_theme.dart';
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
    this.visualComplete = false,
    this.onCancel,
  });

  final coach.CoachTaskState? task;
  final coach.CoachSessionState? sessionState;
  final ExerciseLibrary? library;
  final bool waiting;

  /// Completes the orb visually while the delivery wrapper retains this card.
  /// It does not change the sourced SDK task, phase, or status sentence.
  final bool visualComplete;
  final VoidCallback? onCancel;

  @override
  State<CoachTaskBubble> createState() => _CoachTaskBubbleState();
}

class _CoachTaskBubbleState extends State<CoachTaskBubble>
    with TickerProviderStateMixin {
  late final AnimationController _rotation;
  late final AnimationController _shine;
  late final AnimationController _progress;
  late final AnimationController _images;
  late final AnimationController _breath;
  late final AnimationController _coreCollapse;
  late final AnimationController _completion;
  late final AnimationController _band;
  bool? _reduced;
  bool _tickersEnabled = true;
  bool _showingComplete = false;
  int _imageIndex = 0;
  double _lastImageValue = 0;
  int _progressPhase = 0;
  List<double> _progressFrom = List.filled(
    SfGenerationTokens.progressSegments,
    0,
  );

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.rotation,
    );
    _shine = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.shimmer,
    );
    _progress = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.progressTransition,
      value: 1,
    );
    _images = AnimationController(
      vsync: this,
      duration:
          SfGenerationTokens.silhouetteHold + SfGenerationTokens.silhouetteFade,
    )..addListener(_advanceImage);
    _breath = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.breath,
    );
    _coreCollapse = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.coreCollapse,
    );
    _completion = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.completionVisual,
    )..addListener(_completionFrame);
    _band = AnimationController(
      vsync: this,
      duration: SfGenerationTokens.progressBand,
    );
  }

  coach.CoachTaskState? get _task => widget.task ?? widget.sessionState?.task;
  List<String> get _picks => widget.sessionState?.picks ?? const [];
  List<Exercise> get _selected => [
    for (final id in _picks) ?widget.library?.tryGet(id),
  ];
  bool get _complete =>
      _task?.nodes.any((node) => node.id == 'output' && _done(node)) ?? false;
  // SDK output may finish before the reply is admitted. While waiting, only
  // the delivery wrapper's successful-reply marker may show the success check.
  bool get _visualComplete =>
      widget.visualComplete || (_complete && !widget.waiting);
  bool get _motionOff => _reduced == true || !_tickersEnabled;

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
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    if (_reduced != reduced || _tickersEnabled != tickersEnabled) {
      _reduced = reduced;
      _tickersEnabled = tickersEnabled;
      _syncMotion(restartProgress: true);
    }
  }

  @override
  void didUpdateWidget(CoachTaskBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPicks = oldWidget.sessionState?.picks ?? const <String>[];
    if (!listEquals(oldPicks, _picks)) {
      _images.stop();
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
    final complete = _visualComplete;
    final animate = !_motionOff && widget.waiting && !complete;
    if (_motionOff) {
      _completion.stop();
      _completion.value = complete ? 1 : 0;
    } else if (complete) {
      if (!_showingComplete) _completion.forward(from: 0);
    } else {
      _completion.stop();
      _completion.value = 0;
    }
    _showingComplete = complete;

    // The ring keeps rotating during its 240 ms closing sweep only.
    if (animate || (!_motionOff && complete && _completion.value < 1)) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      if (_reduced == true) _rotation.value = 0;
    }
    for (final controller in [_shine, _band]) {
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
      if (_reduced == true) {
        _imageIndex = 0;
        _lastImageValue = 0;
        _images.value = 0;
      }
    }
    if (animate && _selected.isEmpty) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      if (_motionOff) _breath.value = 1;
    }
    if (_selected.isEmpty) {
      _coreCollapse.stop();
      _coreCollapse.value = 0;
    } else if (animate) {
      if (!_coreCollapse.isAnimating && !_coreCollapse.isCompleted) {
        _coreCollapse.forward();
      }
    } else {
      _coreCollapse.stop();
      _coreCollapse.value = 1;
    }
    _syncProgress(restart: restartProgress);
  }

  void _completionFrame() {
    if (_visualComplete && _completion.value >= 1) {
      _rotation.stop();
      // Flutter's interpolation reports its completed status after the exact
      // endpoint frame. Settle at value 1 so a long next frame cannot rotate
      // the already closed ring or keep the completion ticker alive.
      if (_completion.isAnimating) _completion.value = 1;
    }
  }

  double _segmentFill(int index) {
    final target = index < _progressPhase ? 1.0 : 0.0;
    final eased = Curves.easeOutCubic.transform(_progress.value);
    return _progressFrom[index] + (target - _progressFrom[index]) * eased;
  }

  void _syncProgress({required bool restart}) {
    final phase = _phase(_task);
    final target = [
      for (var index = 0; index < SfGenerationTokens.progressSegments; index++)
        index < phase ? 1.0 : 0.0,
    ];
    if (_motionOff || !widget.waiting) {
      _progress.stop();
      _progressPhase = phase;
      _progressFrom = target;
      _progress.value = 1;
    } else if (restart) {
      final from = [
        for (
          var index = 0;
          index < SfGenerationTokens.progressSegments;
          index++
        )
          _segmentFill(index),
      ];
      _progress.stop();
      _progressPhase = phase;
      _progressFrom = from;
      if (listEquals(from, target)) {
        _progress.value = 1;
      } else {
        _progress.forward(from: 0);
      }
    }
  }

  void _advanceImage() {
    final count = _selected.length;
    if (_images.isAnimating &&
        count > 1 &&
        _images.value < _lastImageValue &&
        mounted) {
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
    _breath.dispose();
    _coreCollapse.dispose();
    _completion.dispose();
    _band.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chips = _parameterLabels(widget.sessionState?.params ?? const {});
    final scene = chips.where((chip) => chip.field == 'scene').firstOrNull;
    final goal = chips.where((chip) => chip.field == 'goal').firstOrNull;
    final title = scene != null && goal != null
        ? '为你准备 · ${scene.label}${goal.label}'
        : '正在想怎么练';
    final staticDetails = _motionOff || _visualComplete || !widget.waiting;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: SfGenerationTokens.maxWidth,
        ),
        child: SizedBox(
          key: const ValueKey('generation-completion-size'),
          child: Container(
            key: const ValueKey('generation-card'),
            padding: SfGenerationTokens.cardPadding,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: SfColors.surface,
              borderRadius: BorderRadius.circular(
                SfGenerationTokens.cardRadius,
              ),
              boxShadow: SfGenerationTokens.cardShadow,
            ),
            // A foreground outline does not add half a pixel to the padding.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(
                SfGenerationTokens.cardRadius,
              ),
              border: Border.all(
                color: SfGenerationTokens.cardEdge,
                width: SfGenerationTokens.cardEdgeWidth,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _animation(),
                    const SizedBox(width: SfGenerationTokens.animationGap),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: SfGenerationTokens.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: SfGenerationTokens.statusGap),
                          _StatusSentence(
                            text: _status,
                            shimmer: _shine,
                            reduced: staticDetails,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SfGenerationTokens.animationGap),
                    SizedBox.square(
                      key: const ValueKey('generation-cancel-target'),
                      dimension: SfGenerationTokens.cancelTouchSize,
                      child:
                          widget.waiting &&
                              !_visualComplete &&
                              widget.onCancel != null
                          ? _CancelButton(onCancel: widget.onCancel!)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: SfGenerationTokens.progressTopGap),
                _progressBar(),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: SfGenerationTokens.chipsTopGap),
                  Wrap(
                    spacing: SfGenerationTokens.chipGap,
                    runSpacing: SfGenerationTokens.chipGap,
                    children: [
                      for (var index = 0; index < chips.length; index++)
                        _ParameterChip(
                          key: ValueKey(
                            'generation-chip-${chips[index].field}-'
                            '${chips[index].label}-${chips[index].user}',
                          ),
                          data: chips[index],
                          index: index,
                          reduced: staticDetails,
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
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left:
              SfGenerationTokens.animationSize / 2 -
              SfGenerationTokens.glowRadius,
          top:
              SfGenerationTokens.animationSize / 2 -
              SfGenerationTokens.glowRadius,
          width: SfGenerationTokens.glowRadius * 2,
          height: SfGenerationTokens.glowRadius * 2,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('generation-glow'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    SfGenerationTokens.glow,
                    SfColors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SfGenerationTokens.orbFill,
            ),
          ),
        ),
        Positioned.fill(
          child: RotationTransition(
            key: const ValueKey('generation-rotation'),
            turns: _rotation,
            child: AnimatedBuilder(
              animation: _completion,
              builder: (context, _) {
                final closing = Curves.easeOutCubic.transform(
                  _completion.value,
                );
                return CustomPaint(
                  painter: _ArcPainter(
                    color: SfColors.accent,
                    sweep: _reduced == true
                        ? 360
                        : SfGenerationTokens.arcSweep +
                              (360 - SfGenerationTokens.arcSweep) * closing,
                    tailAlpha: _visualComplete
                        ? closing
                        : _reduced == true
                        ? .25
                        : 0,
                    headAlpha: _reduced == true ? 0 : 1 - _completionDetail,
                  ),
                );
              },
            ),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([
            _breath,
            _coreCollapse,
            _images,
            _completion,
          ]),
          builder: (context, _) {
            final selected = _selected;
            final breath = _motionOff
                ? 1.0
                : Curves.easeInOutSine.transform(_breath.value);
            final collapse = Curves.easeInCubic.transform(_coreCollapse.value);
            final coreScale =
                (SfGenerationTokens.breathInitialScale +
                    (1 - SfGenerationTokens.breathInitialScale) * breath) *
                (1 - collapse);
            final coreOpacity =
                (SfGenerationTokens.breathInitialOpacity +
                    (1 - SfGenerationTokens.breathInitialOpacity) * breath) *
                (1 - collapse) *
                (1 - _completionDetail);
            return Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                if (selected.isEmpty || collapse < 1)
                  Center(
                    child: Opacity(
                      opacity: coreOpacity,
                      child: Transform.scale(
                        scale: coreScale,
                        child: SizedBox.square(
                          dimension: SfGenerationTokens.haloSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                key: const ValueKey('generation-halo'),
                                width: SfGenerationTokens.haloSize,
                                height: SfGenerationTokens.haloSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SfColors.accent.withValues(alpha: .15),
                                ),
                              ),
                              Container(
                                key: const ValueKey('generation-core'),
                                width: SfGenerationTokens.coreSize,
                                height: SfGenerationTokens.coreSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SfColors.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (selected.isNotEmpty) _thumbnails(selected),
                if (_visualComplete)
                  Center(
                    child: Opacity(
                      opacity: _completionDetail,
                      child: Transform.scale(
                        scale:
                            SfGenerationTokens.checkInitialScale +
                            (1 - SfGenerationTokens.checkInitialScale) *
                                Curves.easeOutBack.transform(_completion.value),
                        child: Icon(
                          Icons.check_rounded,
                          key: const ValueKey('generation-check'),
                          size: SfGenerationTokens.checkSize,
                          color: SfColors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );

  double get _completionDetail =>
      (_completion.value *
              SfGenerationTokens.completionVisual.inMicroseconds /
              SfGenerationTokens.completionDetail.inMicroseconds)
          .clamp(0.0, 1.0);

  Widget _thumbnails(List<Exercise> selected) {
    final current = _reduced == true ? 0 : _imageIndex % selected.length;
    final next = (current + 1) % selected.length;
    final cycle =
        SfGenerationTokens.silhouetteHold + SfGenerationTokens.silhouetteFade;
    final elapsed = _images.value * cycle.inMicroseconds;
    final blend = _reduced == true || selected.length == 1
        ? 0.0
        : ((elapsed - SfGenerationTokens.silhouetteHold.inMicroseconds) /
                  SfGenerationTokens.silhouetteFade.inMicroseconds)
              .clamp(0.0, 1.0);
    return Padding(
      key: const ValueKey('generation-thumbnails'),
      padding: const EdgeInsets.all(SfGenerationTokens.thumbnailInset),
      child: Opacity(
        opacity: 1 - _completionDetail,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: 1 - blend, child: _thumbnail(selected[current])),
              if (blend > 0)
                Opacity(
                  opacity: blend,
                  child: Transform.scale(
                    scale:
                        SfGenerationTokens.imageInitialScale +
                        (1 - SfGenerationTokens.imageInitialScale) *
                            Curves.easeOutCubic.transform(blend),
                    child: _thumbnail(selected[next]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

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
    animation: Listenable.merge([_progress, _band]),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: index == phase
                              ? SfColors.accent.withValues(alpha: .30)
                              : SfGenerationTokens.progressTrack,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: ValueKey('generation-progress-fill-$index'),
                            heightFactor: 1,
                            widthFactor: _segmentFill(index),
                            child: ColoredBox(color: SfColors.accent),
                          ),
                        ),
                        if (index == phase &&
                            !_motionOff &&
                            !_visualComplete &&
                            widget.waiting)
                          Positioned(
                            left:
                                constraints.maxWidth *
                                (-SfGenerationTokens.progressBandFraction +
                                    (1 +
                                            SfGenerationTokens
                                                .progressBandFraction) *
                                        Curves.easeInOutSine.transform(
                                          _band.value,
                                        )),
                            top: 0,
                            bottom: 0,
                            width:
                                constraints.maxWidth *
                                SfGenerationTokens.progressBandFraction,
                            child: DecoratedBox(
                              key: ValueKey('generation-progress-band-$index'),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    SfColors.accent.withValues(alpha: 0),
                                    SfColors.accent,
                                    SfColors.accent.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
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
  const _ArcPainter({
    required this.color,
    required this.sweep,
    required this.tailAlpha,
    required this.headAlpha,
  });
  final Color color;
  final double sweep;
  final double tailAlpha;
  final double headAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(
      SfGenerationTokens.arcStroke / 2,
    );
    final radians = sweep * math.pi / 180;
    const start = -math.pi / 2;
    canvas.drawArc(
      bounds,
      start,
      radians,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SfGenerationTokens.arcStroke
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: radians,
          transform: const GradientRotation(start),
          colors: [
            color.withValues(alpha: tailAlpha),
            color,
          ],
        ).createShader(bounds),
    );
    if (headAlpha > 0) {
      final angle = start + radians;
      canvas.drawCircle(
        bounds.center +
            Offset(
              bounds.width / 2 * math.cos(angle),
              bounds.height / 2 * math.sin(angle),
            ),
        SfGenerationTokens.arcHeadSize / 2,
        Paint()..color = color.withValues(alpha: headAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.sweep != sweep ||
      oldDelegate.tailAlpha != tailAlpha ||
      oldDelegate.headAlpha != headAlpha;
}

class _CancelButton extends StatefulWidget {
  const _CancelButton({required this.onCancel});
  final VoidCallback onCancel;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _press(true),
    onPointerUp: (_) => _press(false),
    onPointerCancel: (_) => _press(false),
    child: Opacity(
      opacity: _pressed ? .5 : 1,
      child: TextButton(
        onPressed: widget.onCancel,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(SfGenerationTokens.cancelTouchSize),
          foregroundColor: SfColors.muted,
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          overlayColor: Colors.transparent,
        ),
        child: Text('取消', style: SfGenerationTokens.cancel),
      ),
    ),
  );
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
  late final AnimationController _transition;
  String? _previous;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration:
          SfGenerationTokens.statusDelay + SfGenerationTokens.statusTransition,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(_StatusSentence oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduced) {
      _transition.stop();
      _transition.value = 1;
      _previous = null;
    } else if (oldWidget.text != widget.text) {
      _previous = oldWidget.text;
      _transition.forward(from: 0);
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
              Widget text(String value) {
                final sentence = Text(
                  value,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                );
                if (widget.reduced) return sentence;
                return ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      SfColors.muted,
                      SfColors.muted,
                      SfGenerationTokens.highlight,
                      SfColors.muted,
                      SfColors.muted,
                    ],
                    stops: SfGenerationTokens.shimmerStops,
                    transform: _ShimmerSlide(widget.shimmer.value),
                  ).createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: sentence,
                );
              }

              if (widget.reduced) return text(widget.text);
              final elapsed =
                  _transition.value *
                  (SfGenerationTokens.statusDelay +
                          SfGenerationTokens.statusTransition)
                      .inMicroseconds;
              final outgoing = Curves.easeInCubic.transform(
                (elapsed / SfGenerationTokens.statusExit.inMicroseconds).clamp(
                  0.0,
                  1.0,
                ),
              );
              final incoming = Curves.easeOutCubic.transform(
                ((elapsed - SfGenerationTokens.statusDelay.inMicroseconds) /
                        SfGenerationTokens.statusTransition.inMicroseconds)
                    .clamp(0.0, 1.0),
              );
              return ClipRect(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (outgoing < 1 && _previous != null)
                      Opacity(
                        opacity: 1 - outgoing,
                        child: Transform.translate(
                          offset: Offset(
                            0,
                            -SfGenerationTokens.statusOffset * outgoing,
                          ),
                          child: text(_previous!),
                        ),
                      ),
                    Opacity(
                      opacity: incoming,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          SfGenerationTokens.statusOffset * (1 - incoming),
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
      Matrix4.translationValues(bounds.width * (1 - 2 * value), 0, 0);
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
  late final AnimationController _appearance;
  late final Animation<double> _entry;

  @override
  void initState() {
    super.initState();
    final delay = SfGenerationTokens.chipDelay * widget.index;
    final duration = delay + SfGenerationTokens.chipTransition;
    _appearance = AnimationController(
      vsync: this,
      duration: duration,
      value: widget.reduced ? 1 : 0,
    );
    _entry = _appearance.drive(
      CurveTween(
        curve: Interval(
          delay.inMicroseconds / duration.inMicroseconds,
          1,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
    if (!widget.reduced) _appearance.forward();
  }

  @override
  void didUpdateWidget(_ParameterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduced) {
      _appearance.stop();
      _appearance.value = 1;
    }
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _entry,
    child: ScaleTransition(
      scale: Tween<double>(
        begin: SfGenerationTokens.chipInitialScale,
        end: 1,
      ).animate(_entry),
      child: Container(
        key: ValueKey('generation-chip-face-${widget.data.field}'),
        height: SfGenerationTokens.chipHeight,
        padding: SfGenerationTokens.chipPadding,
        decoration: BoxDecoration(
          color: SfGenerationTokens.chipFill(widget.data.user),
          borderRadius: BorderRadius.circular(SfGenerationTokens.chipRadius),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SfGenerationTokens.chipRadius),
          border: widget.data.user
              ? null
              : Border.all(color: SfGenerationTokens.chipEdge, width: 1),
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
