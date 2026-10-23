// Explicit visual-review harness. It uses the real App conversation and card
// widgets, with in-memory fixtures only. It never starts an emulator or records
// device-performance numbers. Run serially with SF_SCROLL_CARD_SCREENSHOTS=1:
// flutter test --no-pub --concurrency=1 --flavor internal
//   test/scroll_card_visual_review_test.dart --update-goldens
// The shader-free minimal quality matches the +17 phone comparison tier.
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
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

const _plan = TrainingPlan(
  id: 'scroll-card-review-plan',
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

const _exercise = TrainingPlan(
  id: 'scroll-card-review-exercise',
  source: 'template',
  title: '俄罗斯转体',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'single',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-russian-twist',
          mode: DoseMode.reps,
          sets: 2,
          reps: 12,
          perSide: false,
          restSeconds: 20,
        ),
      ],
    ),
  ],
);

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) throw StateError('Missing review font: $path');
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
        .load();
  }

  await load('NotoSansSC', 'assets/fonts/NotoSansSC.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'E:/flutter';
  await load(
    'MaterialIcons',
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

Future<AppServices> _services(String theme) async {
  // Persisted animation preference off leaves the existing static star field.
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
        id: 'scroll-card-review-user',
        role: ChatRole.user,
        at: at,
        text: '今天在家练 15 分钟，想活动全身。',
      ),
      ChatMessage(
        id: 'scroll-card-review-answer',
        role: ChatRole.assistant,
        at: at,
        text: '安排一组徒手轻力量。按自己的节奏来，动作不舒服就停下。',
      ),
      ChatMessage(
        id: 'scroll-card-review-plan-message',
        role: ChatRole.assistant,
        at: at,
        plan: _plan,
      ),
      ChatMessage(
        id: 'scroll-card-review-exercise-message',
        role: ChatRole.assistant,
        at: at,
        plan: _exercise,
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

void main() {
  for (final theme in ['light', 'dark']) {
    testWidgets(
      'scroll card $theme before and after visual review',
      (tester) async {
        await _loadFonts();
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final lab = PerformanceLab.instance;
        final priorQuality = SfGlass.qualityOverride;
        lab.resetOverrides();
        SfGlass.qualityOverride = GlassQuality.minimal;
        addTearDown(() {
          lab.resetOverrides();
          SfGlass.qualityOverride = priorQuality;
        });
        final services = await _services(theme);
        // One mounted App, one scroll position, same media and background.
        lab.setScrollingGlassEnabled(true);
        await tester.pumpWidget(
          SmartFitApp(services: services, fontFamily: 'NotoSansSC'),
        );
        await tester.pumpAndSettle();
        await _precache(tester);
        final cards = find.byType(PlanCard);
        expect(cards, findsNWidgets(2));
        final beforeRects = [
          tester.getRect(cards.at(0)),
          tester.getRect(cards.at(1)),
        ];
        expect(
          find.descendant(of: cards, matching: find.byType(BackdropFilter)),
          findsWidgets,
          reason: 'Before renders the original +17 minimal glass path.',
        );
        expect(find.byType(GlassBackgroundSource), findsOneWidget);
        expect(tester.takeException(), isNull);
        final out =
            Platform.environment['SF_SCREENSHOT_DIR'] ??
            '${Directory.current.path}/docs/screenshots/performance-scroll-cards';
        Directory(out).createSync(recursive: true);
        await expectLater(
          find.byType(MaterialApp).first,
          matchesGoldenFile(Uri.file('$out/plan-$theme-before.png')),
        );

        lab.setScrollingGlassEnabled(false);
        await tester.pumpAndSettle();
        await _precache(tester);
        expect(find.byType(GlassBackgroundSource), findsNothing);
        expect(
          find.descendant(of: cards, matching: find.byType(BackdropFilter)),
          findsNothing,
          reason: 'The new scroll card has neither blur nor saturation filter.',
        );
        expect(tester.getRect(cards.at(0)), beforeRects[0]);
        expect(tester.getRect(cards.at(1)), beforeRects[1]);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp).first,
          matchesGoldenFile(Uri.file('$out/plan-$theme-after.png')),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
      skip:
          !PerformanceLab.buildEnabled ||
          Platform.environment['SF_SCROLL_CARD_SCREENSHOTS'] != '1',
    );
  }
}
