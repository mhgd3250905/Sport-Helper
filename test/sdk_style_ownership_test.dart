import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/polish_card.dart';
import 'package:ugk_coach_ui/ugk_coach_ui.dart';

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'recommendations keep SDK surfaces, controls and typography in ${palette.brightness.name}',
      (tester) async {
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = SfPalette.dark);
        late CoachUiStyle actual;
        late CoachUiStyle defaults;
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(palette),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  defaults = CoachUiStyle.fromTheme(Theme.of(context));
                  // A recommendation must reset the surrounding conversation's
                  // custom plan-card builders, rather than inheriting them.
                  return withSmartfitCoachUi(
                    context,
                    Builder(
                      builder: (context) => withSmartfitRecommendUi(
                        context,
                        Builder(
                          builder: (context) {
                            actual = CoachUiTheme.of(context);
                            return CoachRecommendCard(
                              actionIds: const ['sample'],
                              note: '',
                              library: CoachExerciseLibrary(const [
                                CoachExercise(
                                  id: 'sample',
                                  name: '示例动作',
                                  poster: '',
                                  stage: CoachMediaPalette(
                                    mediaStage: Colors.transparent,
                                    onStage: Colors.black,
                                    onStageMuted: Colors.grey,
                                  ),
                                  levelLabel: '进阶',
                                  equipmentLabel: '徒手',
                                ),
                              ]),
                              onOpenAction: (id) => opened = id,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        expect(actual.colors.cardSurface, defaults.colors.cardSurface);
        expect(actual.colors.cardBorder, defaults.colors.cardBorder);
        expect(
          actual.colors.primaryForeground,
          defaults.colors.primaryForeground,
        );
        expect(actual.colors.text, defaults.colors.text);
        expect(actual.colors.muted, defaults.colors.muted);
        expect(actual.typography.body, defaults.typography.body);
        expect(actual.typography.callout, defaults.typography.callout);
        expect(actual.typography.caption, defaults.typography.caption);
        expect(actual.builders.surface, isNull);
        expect(actual.builders.pressable, isNull);
        expect(actual.builders.controlFace, isNull);
        expect(actual.builders.media, isNull);
        expect(actual.builders.startButton, isNull);
        expect(actual.builders.icon, isNull);
        expect(actual.builders.textAction, isNull);
        expect(actual.strings.planFromActions, '排成计划');
        expect(find.byType(SfPolishCard), findsNothing);
        expect(find.byType(SfPressable), findsNothing);
        final title = tester.widget<Text>(find.text('示例动作'));
        expect(title.style!.fontSize, 15);
        expect(title.style!.fontWeight, FontWeight.w600);
        expect(title.style!.height, 1.35);
        final surface = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('recommend-surface-sample')),
        );
        expect(
          (surface.decoration as BoxDecoration).color,
          defaults.colors.cardSurface,
        );
        await tester.tap(find.byKey(const ValueKey('recommend-action-sample')));
        expect(opened, 'sample');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
