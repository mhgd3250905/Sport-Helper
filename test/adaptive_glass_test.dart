import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/ui/theme/adaptive_glass.dart';

void main() {
  late SfAdaptiveGlassController controller;
  late DateTime now;

  void frames(int count, int rasterUs, {int buildUs = 1000}) {
    for (var i = 0; i < count; i++) {
      controller.addSample(buildUs: buildUs, rasterUs: rasterUs);
    }
  }

  SfAdaptiveGlassController create({
    GlassQuality? initialQuality,
    double hz = 120,
    bool isWeb = false,
    bool shaders = true,
  }) => SfAdaptiveGlassController(
    initialQuality: initialQuality,
    refreshRateHz: hz,
    isWeb: isWeb,
    shaderFiltersSupported: shaders,
    clock: () => now,
  );

  setUp(() {
    now = DateTime.utc(2026, 10, 23);
    controller = create();
  });

  tearDown(() => controller.dispose());

  test(
    'display budget is exact and invalid rates preserve the prior value',
    () {
      expect(controller.targetFrameMs, 1000 / 120);
      controller.setRefreshRateHz(90);
      expect(controller.targetFrameMs, 1000 / 90);
      controller.setRefreshRateHz(double.nan);
      controller.setRefreshRateHz(0);
      controller.setRefreshRateHz(2000);
      expect(controller.refreshRateHz, 90);
    },
  );

  test('skip 90 then collect 180 raster frames before choosing at 120 Hz', () {
    var notifications = 0;
    controller.addListener(() => notifications++);
    frames(89, 900000);
    expect(controller.phase, 'skipping');
    expect(controller.retainedSampleCount, 0);
    expect(notifications, 0);
    frames(1, 900000);
    expect(controller.phase, 'warmup');
    frames(179, 12000, buildUs: 200000);
    expect(controller.effectiveQuality, GlassQuality.premium);
    frames(1, 12000, buildUs: 200000);
    expect(controller.effectiveQuality, GlassQuality.standard);
    expect(controller.phase, 'runtime');
    expect(controller.retainedSampleCount, 0);
    expect(notifications, 2);
  });

  test(
    'warmup thresholds scale at 60 Hz and preserve inclusive standard edge',
    () {
      controller.dispose();
      controller = create(hz: 60);
      frames(90, 500000);
      frames(180, 12000);
      expect(controller.effectiveQuality, GlassQuality.premium);
      controller.resetOnResume();
      frames(90, 500000);
      frames(180, 29166);
      expect(controller.effectiveQuality, GlassQuality.standard);
      controller.resetOnResume();
      frames(90, 500000);
      frames(180, 29167);
      expect(controller.effectiveQuality, GlassQuality.minimal);
    },
  );

  test(
    'runtime needs two consecutive P95 slow windows and eight second cooldown',
    () {
      controller.dispose();
      controller = create(initialQuality: GlassQuality.premium);
      expect(controller.phase, 'runtime');
      frames(120, 13000);
      expect(controller.effectiveQuality, GlassQuality.premium);
      frames(120, 8000); // Neutral window breaks the slow-window streak.
      frames(120, 13000);
      expect(controller.effectiveQuality, GlassQuality.premium);
      frames(120, 13000);
      expect(controller.effectiveQuality, GlassQuality.standard);
      frames(240, 13000);
      expect(controller.effectiveQuality, GlassQuality.standard);
      now = now.add(const Duration(seconds: 7));
      frames(120, 13000);
      expect(controller.effectiveQuality, GlassQuality.standard);
      now = now.add(const Duration(seconds: 1));
      frames(120, 13000);
      expect(controller.effectiveQuality, GlassQuality.minimal);
    },
  );

  test('recovery needs ten consecutive windows strictly below 0.6 budget', () {
    controller.dispose();
    controller = create(initialQuality: GlassQuality.minimal);
    frames(9 * 120, 4000);
    expect(controller.effectiveQuality, GlassQuality.minimal);
    frames(120, 5000); // Exactly 0.6 budget does not count as recovery.
    frames(9 * 120, 4000);
    expect(controller.effectiveQuality, GlassQuality.minimal);
    frames(120, 4000);
    expect(controller.effectiveQuality, GlassQuality.standard);
  });

  test(
    'quality ceiling uses explicit tier order, not enum declaration order',
    () {
      controller.dispose();
      controller = create(initialQuality: GlassQuality.standard);
      expect(controller.cap(GlassQuality.premium), GlassQuality.standard);
      expect(controller.cap(GlassQuality.standard), GlassQuality.standard);
      expect(controller.cap(GlassQuality.minimal), GlassQuality.minimal);
    },
  );

  test(
    'matrix freeze holds quality and phase across light and heavy cells',
    () {
      controller.dispose();
      controller = create(initialQuality: GlassQuality.standard);
      controller.setFrozen(true);
      expect(controller.phase, 'comparison_locked');
      frames(20000, 1000);
      frames(20000, 80000);
      expect(controller.effectiveQuality, GlassQuality.standard);
      expect(controller.retainedSampleCount, 0);
      controller.resetOnResume();
      expect(controller.phase, 'comparison_locked');
      expect(controller.effectiveQuality, GlassQuality.standard);
      controller.setFrozen(false);
      expect(controller.phase, 'skipping');
      expect(controller.effectiveQuality, GlassQuality.standard);
    },
  );

  test('refresh change and lifecycle resume clear old statistical windows', () {
    controller.dispose();
    controller = create(initialQuality: GlassQuality.premium);
    frames(119, 80000);
    controller.setRefreshRateHz(60);
    expect(controller.retainedSampleCount, 0);
    frames(121, 80000);
    expect(controller.effectiveQuality, GlassQuality.premium);
    controller.resetOnResume();
    expect(controller.phase, 'skipping');
    expect(controller.retainedSampleCount, 0);
  });

  test('web stays standard and unsupported native stays minimal', () {
    controller.dispose();
    controller = create(isWeb: true, shaders: false);
    frames(10000, 80000);
    expect(controller.effectiveQuality, GlassQuality.standard);
    expect(controller.phase, 'web_standard');
    controller.dispose();
    controller = create(shaders: false);
    frames(10000, 1000);
    expect(controller.effectiveQuality, GlassQuality.minimal);
    expect(controller.phase, 'unsupported');
    expect(controller.retainedSampleCount, 0);
  });

  test(
    'long sessions retain a fixed buffer with no per-frame notifications',
    () {
      controller.dispose();
      controller = create(initialQuality: GlassQuality.premium);
      var notifications = 0;
      controller.addListener(() => notifications++);
      frames(100000, 8000);
      expect(controller.sampleCapacity, 180);
      expect(controller.retainedSampleCount, lessThan(120));
      expect(notifications, 0);
      final oldCount = controller.retainedSampleCount;
      controller.addSample(buildUs: -1, rasterUs: 1000);
      controller.addSample(buildUs: 1, rasterUs: -1);
      expect(controller.retainedSampleCount, oldCount);
    },
  );

  testWidgets('scope propagates actual state and does not rebuild per frame', (
    tester,
  ) async {
    controller.dispose();
    controller = create(initialQuality: GlassQuality.standard);
    final freeze = ValueNotifier(false);
    var builds = 0;
    SfAdaptiveGlassData? latest;
    await tester.pumpWidget(
      SfAdaptiveGlass(
        controller: controller,
        initialQuality: GlassQuality.standard,
        onQualityChanged: (_, to) {},
        freezeListenable: freeze,
        freezeAdaptation: () => freeze.value,
        child: Builder(
          builder: (context) {
            builds++;
            latest = SfAdaptiveGlassData.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(latest!.effectiveQuality, GlassQuality.standard);
    expect(latest!.targetFrameMs, 1000 / latest!.refreshRateHz);
    final originalBuilds = builds;
    frames(10, 1000);
    await tester.pump();
    expect(builds, originalBuilds);
    freeze.value = true;
    await tester.pump();
    expect(latest!.phase, 'comparison_locked');
    await tester.pumpWidget(const SizedBox());
    freeze.dispose();
  });

  testWidgets('freeze change during descendant build is deferred safely', (
    tester,
  ) async {
    controller.dispose();
    controller = create(initialQuality: GlassQuality.standard);
    final freeze = ValueNotifier(false);
    await tester.pumpWidget(
      SfAdaptiveGlass(
        controller: controller,
        initialQuality: GlassQuality.standard,
        onQualityChanged: (_, to) {},
        freezeListenable: freeze,
        freezeAdaptation: () => freeze.value,
        child: Builder(
          builder: (_) {
            if (!freeze.value) freeze.value = true;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.phase, 'comparison_locked');
    await tester.pumpWidget(const SizedBox());
    freeze.dispose();
  });
}
