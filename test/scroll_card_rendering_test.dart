import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/ui/theme/tokens.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'scroll face has no background filter (${palette.brightness})',
      (tester) async {
        final previous = SfColors.palette;
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = previous);
        PerformanceLab.instance.resetOverrides();
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(
              child: SfScrollCardSurface(
                width: 240,
                height: 130,
                padding: EdgeInsets.all(12),
                child: Text('计划卡'),
              ),
            ),
          ),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(GlassContainer), findsNothing);
        expect(find.byType(GlassBackgroundSource), findsNothing);
        expect(
          tester.getSize(find.byType(SfScrollCardSurface)),
          const Size(240, 130),
        );
        final face = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('sf-static-scroll-card')),
        );
        final decoration = face.decoration as ShapeDecoration;
        expect(decoration.shadows, hasLength(1));
        expect(
          decoration.gradient!.colors.every((c) => c.a > 0 && c.a < 1),
          isTrue,
        );
      },
    );
  }

  testWidgets('chat plans are isolated and static; fixed input keeps glass', (
    tester,
  ) async {
    tall(tester);
    PerformanceLab.instance.resetOverrides();
    final s = services();
    await s.store.acceptSafety(blocked: false);
    s.chat.start();
    await s.chat.send('在家 15 分钟练核心，徒手');
    await tester.pumpWidget(SmartFitApp(services: s));
    await tester.pumpAndSettle();

    final card = find.byType(PlanCard);
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(GlassContainer)),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.byType(SfScrollCardSurface)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('plan-card-paint-boundary')),
      ),
      findsOneWidget,
    );
    expect(find.byType(GlassBackgroundSource), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ChatInputBar),
        matching: find.byType(GlassContainer),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
