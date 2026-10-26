import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/exercise.dart';
import 'alpha_bounds.dart';
import 'theme/solid_surface.dart';
import 'theme/tokens.dart';

/// The second UI rollout is separate from packed-video playback.
abstract final class SfAlphaCards {
  static const enabled = bool.fromEnvironment('SMARTFIT_ALPHA_CARDS');
  static const rise = 14.0;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SfAlphaCardsScope>()
          ?.enabled ??
      enabled;

  static bool hasCover(Exercise? exercise, {bool enabled = enabled}) =>
      enabled && exercise?.media.alphaCover?.isNotEmpty == true;
}

/// Also permits isolated component tests without changing the App build flag.
class SfAlphaCardsScope extends InheritedWidget {
  const SfAlphaCardsScope({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;

  @override
  bool updateShouldNotify(SfAlphaCardsScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Only a card with an alpha hero lowers its painted face. SDK layout,
/// hitboxes and the coordinates used by the existing flying images stay put.
class SfAlphaCardScope extends InheritedWidget {
  const SfAlphaCardScope({
    super.key,
    required this.active,
    required super.child,
  });
  final bool active;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SfAlphaCardScope>()?.active ??
      false;

  @override
  bool updateShouldNotify(SfAlphaCardScope oldWidget) =>
      active != oldWidget.active;
}

class SfAlphaCardSurface extends StatelessWidget {
  const SfAlphaCardSurface({
    super.key,
    required this.child,
    required this.radius,
    this.padding,
    this.width,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: SfAlphaCards.rise,
          child: SfSolidSurface(
            key: const ValueKey('alpha-card-face'),
            radius: radius,
            child: const SizedBox.expand(),
          ),
        ),
        Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ],
    ),
  );
}

/// Static, theme-independent alpha artwork; never a video loading poster.
/// A square layout preserves the previous grid's extent while its face starts
/// 14dp below the artwork. Nothing relies on painting outside a scroll clip.
class SfAlphaArtwork extends StatelessWidget {
  const SfAlphaArtwork({
    super.key,
    required this.exercise,
    this.thumbnail = false,
    this.radius = SfRadius.lg,
  });
  final Exercise exercise;
  final bool thumbnail;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final media = exercise.media;
    final alpha = thumbnail
        ? media.alphaThumbnail ?? media.alphaCover
        : media.alphaCover;
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = light ? SfPalette.light : SfPalette.dark;
    Widget fallback() => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: palette.mediaStage,
        child: Image.asset(
          light ? media.lightPoster ?? '' : media.poster,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              top: SfAlphaCards.rise,
              child: SfSolidSurface(
                key: ValueKey('alpha-artwork-face-${exercise.id}'),
                radius: radius,
                child: const SizedBox.expand(),
              ),
            ),
            if (alpha?.isNotEmpty == true)
              SfAlphaAsset(
                asset: alpha!,
                key: ValueKey('alpha-artwork-image-${exercise.id}'),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback(),
              )
            else
              fallback(),
          ],
        ),
      ),
    );
  }
}

/// Static alpha media, usable by catalog entries without training semantics.
/// Source bytes stay unchanged; cropping is a drawImageRect using import-time
/// bounds. Missing/stale metadata falls back to the original image framing.
class SfAlphaAsset extends StatelessWidget {
  const SfAlphaAsset({
    super.key,
    required this.asset,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.topCenter,
    this.semanticLabel,
    this.errorBuilder,
  });
  final String asset;
  final BoxFit fit;
  final Alignment alignment;
  final String? semanticLabel;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) => FutureBuilder<SfAlphaBounds>(
    future: SfAlphaBounds.load(DefaultAssetBundle.of(context)),
    builder: (context, snapshot) => Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: Image.asset(
        asset,
        fit: fit,
        alignment: alignment,
        excludeFromSemantics: true,
        gaplessPlayback: true,
        errorBuilder: errorBuilder ?? (_, _, _) => const SizedBox.shrink(),
        frameBuilder: (context, child, frame, synchronous) {
          // Wait for the cached bounds before the first visible frame, so the
          // figure never jumps from uncropped to cropped after loading.
          if (!snapshot.hasData) return const SizedBox.expand();
          final source = snapshot.data!.entries[asset];
          if (source == null || child is! RawImage || child.image == null) {
            return child;
          }
          return CustomPaint(
            painter: _AlphaPainter(child.image!, source, fit, alignment),
            child: const SizedBox.expand(),
          );
        },
      ),
    ),
  );
}

class _AlphaPainter extends CustomPainter {
  _AlphaPainter(this.image, this.bounds, this.fit, this.alignment);
  final ui.Image image;
  final Rect bounds;
  final BoxFit fit;
  final Alignment alignment;

  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTRB(
      bounds.left * image.width,
      bounds.top * image.height,
      bounds.right * image.width,
      bounds.bottom * image.height,
    );
    final sizes = applyBoxFit(fit, source.size, size);
    final input = alignment.inscribe(sizes.source, source);
    final output = alignment.inscribe(sizes.destination, Offset.zero & size);
    canvas.drawImageRect(
      image,
      input,
      output,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_AlphaPainter oldDelegate) =>
      image != oldDelegate.image ||
      bounds != oldDelegate.bounds ||
      fit != oldDelegate.fit ||
      alignment != oldDelegate.alignment;
}
