import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../diagnostics/performance_fixture.dart';
import '../../domain/exercise.dart';
import '../../domain/plan.dart';
import '../theme.dart';
import '../theme/fixed_glass_policy.dart';
import '../theme/glass.dart';
import 'chat_widgets.dart';
import 'plan_card.dart';

/// Completion means that a bounded image was actually rasterized. It does not
/// assert that a shader compilation event occurred (that needs a Timeline).
@immutable
class PlanGlassPrewarmResult {
  const PlanGlassPrewarmResult(
    this.status,
    this.durationMs, {
    this.logicalWidth,
    this.logicalHeight,
    this.pixelRatio,
  });
  final String status;
  final double durationMs;
  final double? logicalWidth;
  final double? logicalHeight;
  final double? pixelRatio;
}

typedef PlanGlassPrewarmCallback =
    Future<PlanGlassPrewarmResult> Function({
      required BuildContext context,
      required PerformanceFixture fixture,
      required ExerciseLibrary library,
      required SfFixedGlassPolicy policy,
    });

/// Optional internal experiment, run before navigating to the measured page.
///
/// The normal, finite widget subtree paints underneath an opaque preparation
/// cover. Unlike Offstage / zero opacity / a widget outside the screen, the
/// boundary is laid out and painted. [RenderRepaintBoundary.toImage] explicitly
/// rasterizes its own layer subtree into an offscreen image even though the
/// cover hides it in the app's normal scene. No screenshot is encoded or saved.
/// Keeping this subtree in the existing view also gives the real input field
/// its Flutter View/IME/localization dependencies without registering a second
/// RenderView against the live phone view.
abstract final class PlanGlassPrewarmer {
  static const maxPixels = 2000000.0;
  static const settleDelay = Duration(milliseconds: 650);
  static const imageDecodeTimeout = Duration(seconds: 3);
  static const rasterTimeout = Duration(seconds: 3);

  static Future<PlanGlassPrewarmResult> prepare({
    required BuildContext context,
    required PerformanceFixture fixture,
    required ExerciseLibrary library,
    required SfFixedGlassPolicy policy,
  }) async {
    final elapsed = Stopwatch()..start();
    final overlay = Overlay.maybeOf(context);
    final media = MediaQuery.maybeOf(context);
    final plan = fixture.controller.messages
        .map((message) => message.plan)
        .whereType<TrainingPlan>()
        .firstOrNull;
    if (overlay == null ||
        media == null ||
        plan == null ||
        !context.mounted ||
        View.maybeOf(context) == null ||
        media.size.width < 280 ||
        media.size.height < 400) {
      return PlanGlassPrewarmResult(
        'unsupported',
        elapsed.elapsedMicroseconds / 1000,
      );
    }
    final size = Size(
      math.min(media.size.width, 480),
      math.min(media.size.height, 480),
    );
    final pixelRatio = math.min(
      media.devicePixelRatio,
      math.sqrt(maxPixels / (size.width * size.height)),
    );
    final key = GlobalKey();
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    final lifecycle = _PrewarmLifecycleObserver();
    WidgetsBinding.instance.addObserver(lifecycle);
    PlanGlassPrewarmResult result(String status) => PlanGlassPrewarmResult(
      status,
      elapsed.elapsedMicroseconds / 1000,
      logicalWidth: size.width,
      logicalHeight: size.height,
      pixelRatio: pixelRatio,
    );
    var active = true;
    ui.Image? image;
    final entry = OverlayEntry(
      builder: (context) => ExcludeSemantics(
        child: AbsorbPointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox.fromSize(
                    size: size,
                    child: themes.wrap(
                      MediaQuery(
                        data: media.copyWith(size: size),
                        child: SfFixedGlassScope(
                          isPlanContext: true,
                          policy: policy,
                          child: PlanGlassPrewarmScene(
                            library: library,
                            plan: plan,
                            suggestions: fixture.controller.suggestions,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // A regular opaque cover, not opacity applied to the target.
              ColoredBox(
                color: SfColors.background.withValues(alpha: 1),
                child: Center(
                  child: Text('正在离屏准备计划卡与固定玻璃…', style: SfType.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      overlay.insert(entry);
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted || lifecycle.interrupted) return result('failed');
      Object? decodeFailure;
      // Exactly the same bundled still assets PlanCard itself precaches. No
      // HTTP provider, player, network download or SDK is involved. Waiting
      // for decode avoids calling a placeholder-only raster a successful warmup.
      final assets = <String>{
        for (final item in plan.items)
          if (library.tryGet(item.exerciseId) case final exercise?) ...[
            sfPoster(exercise),
            if (SfCutouts.has(exercise)) SfCutouts.asset(exercise, still: true),
          ],
      };
      await Future.wait([
        for (final asset in assets)
          precacheImage(
            AssetImage(asset),
            context,
            onError: (error, _) => decodeFailure = error,
          ),
      ]).timeout(imageDecodeTimeout);
      if (decodeFailure != null || !context.mounted || lifecycle.interrupted) {
        return result('failed');
      }
      // SuggestionStrip uses its normal one-time entrance. Let that finish so
      // its glass is present in the captured subtree, rather than warming a
      // transparent first animation frame.
      await Future<void>.delayed(settleDelay);
      if (!context.mounted || !entry.mounted || lifecycle.interrupted) {
        return result('failed');
      }
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary || !boundary.hasSize) {
        return result('failed');
      }
      final pendingImage = boundary.toImage(pixelRatio: pixelRatio).then((
        value,
      ) {
        if (!active) value.dispose();
        return value;
      });
      image = await pendingImage.timeout(rasterTimeout);
      return result(lifecycle.interrupted ? 'failed' : 'succeeded');
    } on Object {
      return result('failed');
    } finally {
      active = false;
      image?.dispose();
      entry.remove();
      entry.dispose();
      WidgetsBinding.instance.removeObserver(lifecycle);
    }
  }
}

class _PrewarmLifecycleObserver with WidgetsBindingObserver {
  bool interrupted = false;
  @override
  void didChangeMetrics() => interrupted = true;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) interrupted = true;
  }
}

/// Actual app components, no controller, SDK, video, downloads or file writes.
/// The card uses the same deterministic plan as the scrolling benchmark.
class PlanGlassPrewarmScene extends StatelessWidget {
  const PlanGlassPrewarmScene({
    super.key,
    required this.library,
    required this.plan,
    required this.suggestions,
  });
  final ExerciseLibrary library;
  final TrainingPlan plan;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: LiquidGlassScope(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SfGlassField(),
          Column(
            children: [
              const SizedBox(height: SfSpace.x4),
              PlanCard(
                plan: plan,
                library: library,
                saved: false,
                onStart: (_) {},
                onSave: () {},
                onOpen: () {},
              ),
              const Spacer(),
              SuggestionStrip(items: suggestions, onTap: (_) {}),
              ChatInputBar(onSend: (_) {}, onPlans: () {}),
            ],
          ),
        ],
      ),
    ),
  );
}
