import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/ui/theme/fixed_glass_policy.dart';

void main() {
  test(
    'fixed-glass presets preserve star preference and restore ephemeral state',
    () {
      final lab = PerformanceLab(enabled: true);
      lab.setFixedGlassContext(
        isPlanContext: true,
        presentRoles: const {
          SfFixedGlassRole.input,
          SfFixedGlassRole.suggestions,
        },
      );
      lab.applyFixedGlassConfiguration('no_saturation_half_blur');
      expect(lab.fixedGlassPolicy.saturationEnabled, isFalse);
      expect(lab.fixedGlassPolicy.blurScale, .5);
      expect(lab.starfieldFor(false), isFalse);
      expect(lab.starfieldFor(true), isTrue);
      expect(lab.scrollingGlassEnabled, isFalse);
      final previous = lab.snapshotOverrides();
      lab.applyFixedGlassConfiguration('baseline_prewarmed');
      expect(lab.prewarmStatus, 'pending');
      lab.setPrewarmStatus(
        'succeeded',
        durationMs: 12,
        logicalWidth: 390,
        logicalHeight: 480,
        pixelRatio: 3.25,
      );
      expect(lab.prewarmPixelRatio, 3.25);
      lab.restoreOverrides(previous);
      expect(lab.fixedGlassConfigurationId, 'no_saturation_half_blur');
      expect(lab.fixedGlassPolicy.blurScale, .5);
      expect(lab.prewarmStatus, 'disabled');
      expect(lab.prewarmPixelRatio, isNull);
      expect(lab.fixedGlassPresentRoles, hasLength(2));
      lab.resetOverrides();
      expect(lab.fixedGlassPolicy, SfFixedGlassPolicy.baseline);
      expect(lab.fixedGlassPresentRoles, isEmpty);
      expect(
        () => lab.applyFixedGlassConfiguration('top_bar_static'),
        throwsArgumentError,
      );
      lab.dispose();
    },
  );

  test('production cannot enable fixed-glass experiments or prewarming', () {
    final lab = PerformanceLab(enabled: false);
    lab.applyFixedGlassConfiguration('all_static');
    lab.setFixedGlassPolicy(SfFixedGlassPolicy.baseline.copyWith(input: false));
    lab.setFixedGlassContext(
      isPlanContext: true,
      presentRoles: const {SfFixedGlassRole.input},
    );
    lab.setPrewarmEnabled(true);
    lab.setPrewarmStatus(
      'succeeded',
      durationMs: 1,
      logicalWidth: 100,
      logicalHeight: 100,
      pixelRatio: 1,
    );
    expect(lab.fixedGlassPolicy, SfFixedGlassPolicy.baseline);
    expect(lab.fixedGlassPlanContext, isFalse);
    expect(lab.fixedGlassPresentRoles, isEmpty);
    expect(lab.prewarmEnabled, isFalse);
    expect(lab.prewarmStatus, 'disabled');
    expect(lab.prewarmDurationMs, isNull);
    lab.dispose();
  });
  test('overrides default to existing settings and never persist', () {
    final lab = PerformanceLab(enabled: true);
    expect(lab.glassEnabled, isTrue);
    expect(lab.scrollingGlassEnabled, isFalse);
    expect(lab.starfieldFor(false), isFalse);
    expect(lab.starfieldFor(true), isTrue);
    lab.setStarfieldOverride(false);
    lab.setScrollingGlassEnabled(true);
    final previous = lab.snapshotOverrides();
    lab.setVariant('glass_off_stars_on');
    expect(lab.glassEnabled, isFalse);
    expect(lab.scrollingGlassEnabled, isFalse);
    expect(lab.starfieldFor(false), isTrue);
    lab.restoreOverrides(previous);
    expect(lab.glassEnabled, isTrue);
    expect(lab.scrollingGlassEnabled, isTrue);
    expect(lab.starfieldFor(true), isFalse);
    lab.resetOverrides();
    expect(lab.scrollingGlassEnabled, isFalse);
    expect(lab.starfieldFor(true), isTrue);
    expect(() => lab.setVariant('invalid'), throwsArgumentError);
    lab.dispose();
  });

  test('production controller cannot activate internal overrides', () {
    final lab = PerformanceLab(enabled: false);
    lab.setVariant('glass_off_stars_on');
    lab.setGlassEnabled(false);
    lab.setScrollingGlassEnabled(true);
    lab.setStarfieldOverride(true);
    lab.setFreezeAdaptation(true);
    expect(lab.glassEnabled, isTrue);
    expect(lab.scrollingGlassEnabled, isFalse);
    expect(lab.starfieldFor(false), isFalse);
    expect(lab.freezeAdaptation, isFalse);
    lab.dispose();
  });

  test(
    'scroll-card override is gated by global glass and survives restore',
    () {
      final lab = PerformanceLab(enabled: true);
      lab.setScrollingGlassEnabled(true);
      lab.setGlassEnabled(false);
      final previous = lab.snapshotOverrides();
      expect(lab.scrollingGlassEnabled, isFalse);
      lab.resetOverrides();
      lab.restoreOverrides(previous);
      expect(lab.scrollingGlassEnabled, isFalse);
      lab.setGlassEnabled(true);
      expect(lab.scrollingGlassEnabled, isTrue);
      lab.setScrollingGlassEnabled(false);
      expect(lab.scrollingGlassEnabled, isFalse);
      lab.dispose();
    },
  );

  testWidgets('default scroll card has no backdrop filters or capture', (
    tester,
  ) async {
    final lab = PerformanceLab.instance;
    lab.resetOverrides();
    addTearDown(lab.resetOverrides);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SfGlassBackgroundSource(
            child: SfScrollCardSurface(
              width: 180,
              height: 70,
              padding: EdgeInsets.all(12),
              child: Text('静态计划卡'),
            ),
          ),
        ),
      ),
    );
    expect(lab.scrollingGlassEnabled, isFalse);
    expect(find.byType(GlassContainer), findsNothing);
    expect(find.byType(GlassBackgroundSource), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const ValueKey('sf-static-scroll-card')), findsOneWidget);
  });

  testWidgets(
    'glass off removes filters and capture but keeps layout',
    (tester) async {
      SfGlass.qualityOverride = GlassQuality.minimal;
      final lab = PerformanceLab.instance;
      lab.resetOverrides();
      lab.setScrollingGlassEnabled(true);
      addTearDown(() {
        lab.resetOverrides();
        SfGlass.qualityOverride = null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SfGlassBackgroundSource(
              child: SfGlassSurface(
                width: 180,
                height: 70,
                radius: 18,
                padding: const EdgeInsets.all(12),
                child: const Text('固定卡片'),
              ),
            ),
          ),
        ),
      );
      final original = tester.getSize(find.byType(SfGlassSurface));
      expect(find.byType(GlassContainer), findsOneWidget);
      expect(find.byType(GlassBackgroundSource), findsOneWidget);
      lab.setGlassEnabled(false);
      await tester.pump();
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(GlassBackgroundSource), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(tester.getSize(find.byType(SfGlassSurface)), original);
      final opaque = tester.widget<Container>(
        find.byKey(const ValueKey('performance-opaque-glass')),
      );
      expect((opaque.decoration as ShapeDecoration).color!.a, 1);
      lab.setGlassEnabled(true);
      await tester.pump();
      expect(find.byType(GlassContainer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
    skip: !PerformanceLab.buildEnabled,
  );
}
