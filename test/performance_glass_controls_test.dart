import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/ui/theme/glass.dart';

void main() {
  test('overrides default to existing settings and never persist', () {
    final lab = PerformanceLab(enabled: true);
    expect(lab.glassEnabled, isTrue);
    expect(lab.starfieldFor(false), isFalse);
    expect(lab.starfieldFor(true), isTrue);
    lab.setStarfieldOverride(false);
    final previous = lab.snapshotOverrides();
    lab.setVariant('glass_off_stars_on');
    expect(lab.glassEnabled, isFalse);
    expect(lab.starfieldFor(false), isTrue);
    lab.restoreOverrides(previous);
    expect(lab.glassEnabled, isTrue);
    expect(lab.starfieldFor(true), isFalse);
    lab.resetOverrides();
    expect(lab.starfieldFor(true), isTrue);
    expect(() => lab.setVariant('invalid'), throwsArgumentError);
    lab.dispose();
  });

  test('production controller cannot activate internal overrides', () {
    final lab = PerformanceLab(enabled: false);
    lab.setVariant('glass_off_stars_on');
    lab.setGlassEnabled(false);
    lab.setStarfieldOverride(true);
    lab.setFreezeAdaptation(true);
    expect(lab.glassEnabled, isTrue);
    expect(lab.starfieldFor(false), isFalse);
    expect(lab.freezeAdaptation, isFalse);
    lab.dispose();
  });

  testWidgets(
    'glass off removes filters and capture but keeps layout',
    (tester) async {
      SfGlass.qualityOverride = GlassQuality.minimal;
      final lab = PerformanceLab.instance;
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
