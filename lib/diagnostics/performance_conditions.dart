import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../ui/theme/adaptive_glass.dart';
import '../ui/theme/glass.dart';
import 'frame_recorder.dart';
import 'performance_lab.dart';
import 'performance_report.dart';

/// Updates labels only when a render condition changes, never per timing.
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
        final scope = SfAdaptiveGlassData.maybeOf(context);
        final service = PerformanceReportService.instance;
        final lab = PerformanceLab.instance;
        final view = View.of(context);
        final media = MediaQuery.of(context);
        final actualStars =
            lab.starfieldFor(store.starfield) && !media.disableAnimations;
        final rate = scope?.refreshRateHz ?? view.display.refreshRate;
        final recorder = FrameRecorder.instance;
        recorder.setRefreshRateHz(rate);
        recorder.setMetadata({
          'appearance': store.appearance,
          'theme': Theme.of(context).brightness.name,
          'refreshRateSource': 'flutter_display',
          'starfield': actualStars,
          'glassQuality': lab.glassEnabled
              ? scope?.effectiveQuality.name ?? 'unknown'
              : 'off',
        });
        recorder.setRenderConditions(
          glassEnabled: lab.glassEnabled,
          starfield: actualStars,
          glassQuality: lab.glassEnabled
              ? scope?.effectiveQuality.name ?? 'unknown'
              : 'off',
          glassPhase: scope?.phase ?? 'unknown',
          // SmartFit's clear material has no premium frost; report the actual
          // material rather than the adaptive adapter's permission flag.
          glassFrost:
              lab.glassEnabled &&
              SfGlass.materialFor(
                    scope?.effectiveQuality ?? SfGlass.control,
                  ).frost >
                  0,
          renderer: service.renderer,
          rendererBackend: service.rendererBackend,
          adaptiveTargetFrameMs: scope?.targetFrameMs ?? (1000 / rate),
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
