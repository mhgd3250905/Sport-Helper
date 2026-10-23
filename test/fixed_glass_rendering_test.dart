// The optional images render real Flutter conversation widgets. They are
// appearance review candidates, not device screenshots or performance data.
// Run serially with SF_FIXED_GLASS_SCREENSHOTS=1 and --update-goldens in an
// internal build. The normal tests do not write files or start an emulator.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/fixed_glass_policy.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

const _plan = TrainingPlan(
  id: 'fixed-glass-review-plan',
  source: 'template',
  title: '居家轻力量',
  summary: '徒手完成，保持动作平稳。',
  goal: 'strength',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 15,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.reps,
          sets: 2,
          reps: 10,
          perSide: false,
          restSeconds: 30,
        ),
        PlanItem(
          exerciseId: 'h-calf-raise',
          mode: DoseMode.reps,
          sets: 2,
          reps: 12,
          perSide: false,
          restSeconds: 30,
        ),
        PlanItem(
          exerciseId: 'w-dead-bug',
          mode: DoseMode.reps,
          sets: 2,
          reps: 8,
          perSide: true,
          restSeconds: 30,
        ),
      ],
    ),
  ],
);

const _candidates = <String, SfFixedGlassPolicy>{
  'baseline': SfFixedGlassPolicy.baseline,
  'no-saturation': SfFixedGlassPolicy(saturationEnabled: false),
  'half-blur': SfFixedGlassPolicy(blurScale: .5),
  'all-static': SfFixedGlassPolicy(
    topBar: false,
    bottomBar: false,
    input: false,
    suggestions: false,
  ),
};

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = File(path).readAsBytesSync();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  await load('NotoSansSC', 'assets/fonts/NotoSansSC.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'E:/flutter';
  await load(
    'MaterialIcons',
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

Future<AppServices> _reviewServices(String theme) async {
  final store = AppStore(MemoryStorage())..starfield = false;
  await store.setAppearance(theme);
  await store.acceptSafety(blocked: false);
  final services = AppServices(
    library: loadLibrary(),
    catalog: loadCatalog(),
    store: store,
    voiceLibrary: VoiceLibrary.empty,
    voiceOutput: const MutedVoiceOutput(),
    chatReplyDelay: Duration.zero,
  );
  final chat = services.chat..start();
  final today = DateTime.now();
  final at = DateTime(today.year, today.month, today.day, 9, 41);
  chat.messages
    ..clear()
    ..addAll([
      ChatMessage(
        id: 'fixed-glass-review-user',
        role: ChatRole.user,
        at: at,
        text: '今天在家练 15 分钟，想活动全身。',
      ),
      ChatMessage(
        id: 'fixed-glass-review-answer',
        role: ChatRole.assistant,
        at: at,
        text: '安排一组徒手轻力量。按自己的节奏来，动作不舒服就停下。',
      ),
      ChatMessage(
        id: 'fixed-glass-review-plan-message',
        role: ChatRole.assistant,
        at: at,
        plan: _plan,
      ),
    ]);
  chat.suggestions = const ['再短一点', '难一点', '换掉第 2 个', '换一套'];
  return services;
}

Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in tester.allElements.toList()) {
      final widget = element.widget;
      if (widget is Image) await precacheImage(widget.image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _surface({
  required SfFixedGlassPolicy policy,
  bool isPlanContext = true,
  SfFixedGlassRole role = SfFixedGlassRole.input,
}) => MaterialApp(
  home: SfFixedGlassScope(
    policy: policy,
    isPlanContext: isPlanContext,
    child: Center(
      child: SfFixedGlassSurface(
        role: role,
        radius: 26,
        width: 240,
        height: 72,
        padding: const EdgeInsets.all(12),
        child: const Text('固定玻璃'),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = GlassQuality.minimal;
  });
  tearDown(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = null;
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets('fixed material and bounds follow ${palette.brightness}', (
      tester,
    ) async {
      final previous = SfColors.palette;
      SfColors.palette = palette;
      addTearDown(() => SfColors.palette = previous);
      await tester.pumpWidget(_surface(policy: SfFixedGlassPolicy.baseline));
      final glass = find.byType(GlassContainer);
      expect(glass, findsOneWidget);
      expect(tester.getSize(glass), const Size(240, 72));
      final settings = tester.widget<GlassContainer>(glass).settings!;
      expect(settings.blur, palette.brightness == Brightness.dark ? 1.2 : 1.5);
      expect(
        settings.saturation,
        palette.brightness == Brightness.dark ? 1.15 : 1.1,
      );
      final boundary = find.byKey(
        const ValueKey('sf-fixed-glass-boundary-input'),
      );
      final clip = find.byKey(const ValueKey('sf-fixed-glass-clip-input'));
      expect(tester.widget(boundary), isA<RepaintBoundary>());
      expect(tester.widget(clip), isA<ClipPath>());
      expect(tester.getRect(boundary), tester.getRect(glass));
      expect(tester.getRect(clip), tester.getRect(glass));
      expect(tester.widget<ClipPath>(clip).clipBehavior, Clip.antiAlias);
      final shape =
          tester.widget<ClipPath>(clip).clipper! as ShapeBorderClipper;
      expect(shape.shape, isA<RoundedSuperellipseBorder>());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'plan filters change without moving ${palette.brightness} controls',
      (tester) async {
        final previous = SfColors.palette;
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = previous);
        await tester.pumpWidget(_surface(policy: SfFixedGlassPolicy.baseline));
        final surface = find.byType(SfFixedGlassSurface);
        final originalRect = tester.getRect(surface);
        final blur = palette.brightness == Brightness.dark ? 1.2 : 1.5;
        for (final candidate in _candidates.entries) {
          await tester.pumpWidget(_surface(policy: candidate.value));
          await tester.pumpAndSettle();
          expect(tester.getRect(surface), originalRect);
          if (candidate.key == 'all-static') {
            expect(find.byType(BackdropFilter), findsNothing);
            expect(find.byType(GlassContainer), findsNothing);
            expect(find.byType(GlassBackgroundSource), findsNothing);
          } else {
            final material = tester
                .widget<GlassContainer>(find.byType(GlassContainer))
                .settings!;
            expect(material.blur, blur * candidate.value.blurScale);
            expect(
              material.saturation,
              candidate.value.saturationEnabled
                  ? SfGlass.standardMaterial.saturation
                  : 1,
            );
            expect(
              find.byType(BackdropFilter),
              findsNWidgets(candidate.value.saturationEnabled ? 2 : 1),
              reason:
                  'Minimal must remove the saturation pass, not only change '
                  'the reported configuration.',
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !PerformanceLab.buildEnabled,
    );
  }

  testWidgets('plan-only static override preserves ordinary chat glass', (
    tester,
  ) async {
    const policy = SfFixedGlassPolicy(
      input: false,
      suggestions: false,
      saturationEnabled: false,
      blurScale: .5,
    );
    for (final role in [SfFixedGlassRole.input, SfFixedGlassRole.suggestions]) {
      await tester.pumpWidget(
        _surface(policy: policy, role: role, isPlanContext: false),
      );
      expect(find.byType(GlassContainer), findsOneWidget);
      final material = tester
          .widget<GlassContainer>(find.byType(GlassContainer))
          .settings!;
      expect(material.blur, SfGlass.standardMaterial.blur);
      expect(material.saturation, SfGlass.standardMaterial.saturation);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final theme in ['light', 'dark']) {
    testWidgets(
      'measured default $theme plan screenshot',
      (tester) async {
        await _loadFonts();
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final services = await _reviewServices(theme);

        // Exercise the normal App entry. There is no injected fixed-glass
        // scope or experiment policy: this must render the shipping default.
        await tester.pumpWidget(
          SmartFitApp(services: services, fontFamily: 'NotoSansSC'),
        );
        await tester.pumpAndSettle();
        await _precache(tester);

        final card = find.byType(PlanCard);
        final suggestions = find.byType(SuggestionStrip);
        final input = find.byType(ChatInputBar);
        expect(card, findsOneWidget);
        expect(suggestions, findsOneWidget);
        expect(input, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(
          find.descendant(of: card, matching: find.byType(GlassContainer)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: suggestions,
            matching: find.byType(SfFixedGlassSurface),
          ),
          findsNWidgets(4),
        );
        expect(
          find.descendant(
            of: suggestions,
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: suggestions,
            matching: find.byType(GlassContainer),
          ),
          findsNothing,
        );
        final inputGlass = find.descendant(
          of: input,
          matching: find.byType(GlassContainer),
        );
        expect(inputGlass, findsOneWidget);
        expect(
          find.descendant(of: input, matching: find.byType(BackdropFilter)),
          findsNWidgets(2),
        );
        final material = tester.widget<GlassContainer>(inputGlass).settings!;
        expect(material.blur, theme == 'dark' ? 1.2 : 1.5);
        expect(material.saturation, theme == 'dark' ? 1.15 : 1.1);
        expect(find.byType(GlassBackgroundSource), findsNothing);
        expect(tester.takeException(), isNull);

        final out =
            Platform.environment['SF_MEASURED_GLASS_SCREENSHOT_DIR'] ??
            '${Directory.current.path}/docs/screenshots/'
                'measured-plan-glass-default';
        Directory(out).createSync(recursive: true);
        Map<String, double> bounds(Finder finder) {
          final rect = tester.getRect(finder);
          return {
            'left': rect.left,
            'top': rect.top,
            'width': rect.width,
            'height': rect.height,
          };
        }

        File('$out/plan-$theme-layout.json').writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({'theme': theme, 'planCardLogicalBounds': bounds(card), 'suggestionStripLogicalBounds': bounds(suggestions), 'inputBarLogicalBounds': bounds(input), 'suggestionBackdropFilters': 0, 'inputBackdropFilters': 2, 'inputBlur': material.blur, 'inputSaturation': material.saturation})}\n',
        );
        await expectLater(
          find.byType(MaterialApp).first,
          matchesGoldenFile(Uri.file('$out/plan-$theme-default.png')),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      skip: Platform.environment['SF_MEASURED_GLASS_SCREENSHOTS'] != '1',
    );

    testWidgets(
      'fixed glass $theme plan candidate screenshots',
      (tester) async {
        await _loadFonts();
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final lab = PerformanceLab.instance;
        final services = await _reviewServices(theme);
        final out =
            Platform.environment['SF_SCREENSHOT_DIR'] ??
            '${Directory.current.path}/docs/screenshots/fixed-glass-experiment';
        Directory(out).createSync(recursive: true);
        Rect? cardRect;
        Rect? inputRect;
        Rect? suggestionRect;
        for (final candidate in _candidates.entries) {
          lab.setFixedGlassPolicy(candidate.value);
          await tester.pumpWidget(
            SfFixedGlassScope(
              isPlanContext: true,
              policy: candidate.value,
              child: SmartFitApp(services: services, fontFamily: 'NotoSansSC'),
            ),
          );
          await tester.pumpAndSettle();
          await _precache(tester);
          final card = find.byType(PlanCard);
          expect(card, findsOneWidget);
          cardRect ??= tester.getRect(card);
          inputRect ??= tester.getRect(find.byType(ChatInputBar));
          suggestionRect ??= tester.getRect(find.byType(SuggestionStrip));
          expect(tester.getRect(card), cardRect);
          expect(tester.getRect(find.byType(ChatInputBar)), inputRect);
          expect(tester.getRect(find.byType(SuggestionStrip)), suggestionRect);
          expect(
            find.descendant(of: card, matching: find.byType(BackdropFilter)),
            findsNothing,
            reason:
                'Scrolling cards remain static in every fixed-bar candidate.',
          );
          expect(find.byType(GlassBackgroundSource), findsNothing);
          if (candidate.key == 'all-static') {
            expect(find.byType(BackdropFilter), findsNothing);
          } else {
            expect(find.byType(GlassContainer), findsWidgets);
            for (final element in find.byType(GlassContainer).evaluate()) {
              final material = (element.widget as GlassContainer).settings!;
              expect(
                material.blur,
                (theme == 'dark' ? 1.2 : 1.5) * candidate.value.blurScale,
              );
              expect(
                material.saturation,
                candidate.value.saturationEnabled
                    ? (theme == 'dark' ? 1.15 : 1.1)
                    : 1,
              );
            }
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp).first,
            matchesGoldenFile(
              Uri.file('$out/plan-$theme-${candidate.key}.png'),
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      skip:
          !PerformanceLab.buildEnabled ||
          Platform.environment['SF_FIXED_GLASS_SCREENSHOTS'] != '1',
    );
  }
}
