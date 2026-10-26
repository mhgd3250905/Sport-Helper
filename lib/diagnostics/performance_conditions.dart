import 'package:flutter/material.dart';

import '../data/app_store.dart';
import 'frame_recorder.dart';
import 'performance_lab.dart';
import 'performance_report.dart';

/// Changes immutable frame labels only when live render conditions change.
class PerformanceConditions extends StatelessWidget {
  const PerformanceConditions({
    super.key,
    required this.store,
    required this.child,
  });
  final AppStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!FrameRecorder.buildEnabled) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([
        PerformanceLab.instance,
        PerformanceReportService.instance,
      ]),
      child: child,
      builder: (context, child) {
        final service = PerformanceReportService.instance;
        final media = MediaQuery.of(context);
        final rate = View.of(context).display.refreshRate;
        final stars =
            PerformanceLab.instance.starfieldFor(store.starfield) &&
            !media.disableAnimations;
        final recorder = FrameRecorder.instance;
        recorder.setRefreshRateHz(rate);
        recorder.setMetadata({
          'appearance': store.appearance,
          'theme': Theme.of(context).brightness.name,
          'refreshRateSource': 'flutter_display',
          'starfield': stars,
          'material': PerformanceLab.material,
        });
        recorder.setRenderConditions(
          starfield: stars,
          renderer: service.renderer,
          rendererBackend: service.rendererBackend,
          rendererVerified: service.rendererVerified,
          theme: Theme.of(context).brightness.name,
          viewportWidth: media.size.width,
          viewportHeight: media.size.height,
          devicePixelRatio: media.devicePixelRatio,
          textScale: media.textScaler.scale(1),
        );
        return child!;
      },
    );
  }
}
