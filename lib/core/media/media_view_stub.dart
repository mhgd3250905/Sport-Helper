// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/platform/drill_media/media_view_stub.dart`.
// Only the import path changed; HipLab 2026-10-17 (#3): fit/align/variant
// parameters mirrored from media_view_native.dart.
import 'package:flutter/widgets.dart';
import 'drill_media.dart';
import 'media_controller.dart';

class DrillMediaPlatformView extends StatefulWidget {
  const DrillMediaPlatformView({
    super.key,
    required this.media,
    required this.controller,
    required this.labels,
    this.fit = 'contain',
    this.align = Alignment.center,
    this.variant,
  });
  final DrillMedia media;
  final DrillMediaController controller;
  final Map<String, String> labels;

  /// CSS object-fit of the clip ('contain' | 'cover'); matches the poster's
  /// BoxFit so the poster → video hand-over does not jump.
  final String fit;
  final Alignment align;

  /// 'light' → play `light/<id>.mp4` (theme-matched render), else default.
  final String? variant;
  @override
  State<DrillMediaPlatformView> createState() => _UnsupportedState();
}

class _UnsupportedState extends State<DrillMediaPlatformView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.reportError();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
