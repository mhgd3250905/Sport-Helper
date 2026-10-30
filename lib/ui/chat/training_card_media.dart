import 'package:flutter/material.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

import '../training_route.dart';

/// Media registered by this App card's public SDK image builder. The SDK keeps
/// its card geometry; a workout reads the actual image box instead of copying
/// its private layout calculations or locating private Elements.
class TrainingCardMediaRegistry {
  TrainingCardMediaRegistry(this.exerciseId);

  final String exerciseId;
  final _images = <_TrainingImageBinding>[];
  bool expanded = false;

  TrainingTransitionSource? capture() {
    // A folded hero is no longer the displayed picture after expanding the
    // SDK card. Use the specified no-origin transition rather than animate an
    // invisible, retained hero. Its expanded thumbnails remain SDK-owned.
    if (expanded) return null;
    _TrainingImageBinding? selected;
    Rect? selectedRect;
    for (final image in _images) {
      final rect = image.visibleRect();
      if (rect == null) continue;
      if (selectedRect == null ||
          rect.width * rect.height > selectedRect.width * selectedRect.height) {
        selected = image;
        selectedRect = rect;
      }
    }
    if (selected == null || selectedRect == null) return null;
    final image = selected;
    return TrainingTransitionSource(
      initialRect: selectedRect,
      rect: () => expanded ? null : image.visibleRect(),
      opacity: image.opacity,
      repaintKey: image.repaint,
    );
  }

  void dispose() {
    for (final image in _images) {
      image.opacity.dispose();
    }
    _images.clear();
  }
}

/// Only the selected card receives this local theme. All public builder
/// callbacks are delegated unchanged except for measuring its own images and
/// remembering the SDK's public expand/collapse control value.
class TrainingCardMedia extends StatelessWidget {
  const TrainingCardMedia({
    super.key,
    required this.registry,
    required this.child,
  });

  final TrainingCardMediaRegistry registry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = CoachUiTheme.of(context);
    final builders = base.builders;
    return CoachUiTheme(
      style: CoachUiStyle(
        colors: base.colors,
        typography: base.typography,
        strings: base.strings,
        builders: CoachUiBuilders(
          pressable: (context, request) {
            if (request.expanded case final expanded?) {
              registry.expanded = expanded;
            }
            return builders.pressable?.call(context, request) ??
                TextButton(onPressed: request.onTap, child: request.child);
          },
          controlFace: builders.controlFace,
          textAction: builders.textAction,
          surface: builders.surface,
          icon: builders.icon,
          startButton: builders.startButton,
          media: (context, request) {
            final image =
                builders.media?.call(context, request) ??
                Image.asset(
                  request.asset,
                  fit: request.fit,
                  alignment: request.alignment,
                  gaplessPlayback: request.cutout,
                  semanticLabel: request.semanticLabel,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
            if (request.exercise.id != registry.exerciseId) return image;
            return _TrainingCardImage(registry: registry, child: image);
          },
        ),
      ),
      child: child,
    );
  }
}

class _TrainingImageBinding {
  final repaint = GlobalKey();
  final opacity = _MediaOpacity();
  bool attached = true;

  Rect? visibleRect() {
    final context = repaint.currentContext;
    if (!attached || context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    if (rect.isEmpty || !rect.overlaps(screen)) return null;
    return rect;
  }
}

/// A source may disappear while the independent return overlay is retiring.
/// Its last visibility write must not notify an already disposed card owner.
class _MediaOpacity extends ValueNotifier<double> {
  _MediaOpacity() : super(1);
  bool _disposed = false;

  @override
  set value(double next) {
    if (!_disposed) super.value = next;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

class _TrainingCardImage extends StatefulWidget {
  const _TrainingCardImage({required this.registry, required this.child});
  final TrainingCardMediaRegistry registry;
  final Widget child;

  @override
  State<_TrainingCardImage> createState() => _TrainingCardImageState();
}

class _TrainingCardImageState extends State<_TrainingCardImage> {
  late final _binding = _TrainingImageBinding();

  @override
  void initState() {
    super.initState();
    widget.registry._images.add(_binding);
  }

  @override
  void dispose() {
    _binding.attached = false;
    widget.registry._images.remove(_binding);
    _binding.opacity.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TrainingCardImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registry == widget.registry) return;
    oldWidget.registry._images.remove(_binding);
    widget.registry._images.add(_binding);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: _binding.opacity,
    child: RepaintBoundary(key: _binding.repaint, child: widget.child),
    builder: (_, opacity, child) => Opacity(opacity: opacity, child: child),
  );
}
