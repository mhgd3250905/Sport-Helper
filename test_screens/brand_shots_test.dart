// Real Flutter widget renders for the icon / brand-colour review. Run outside
// the normal unit suite, after applying the brand tokens:
//   flutter test --no-pub test_screens/brand_shots_test.dart --update-goldens
// SF_SCREENSHOT_DIR selects the output folder. No emulator or user storage.
// These are component colour/layout images, not device performance evidence.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/main.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import '../test/app_flow_test.dart' show MemoryStorage;
import '../test/support.dart';

const _plan = TrainingPlan(
  id: 'brand-review-core',
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

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) throw StateError('Missing screenshot font: $path');
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }

  await load('NotoSansSC', 'assets/fonts/NotoSansSC.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'E:/flutter';
  await load(
    'MaterialIcons',
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

Future<AppServices> _services(
  String theme, {
  required bool conversation,
}) async {
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

  // Start once, then replace only this in-memory controller's fixture data.
  // No request goes to AI, and no real conversation is read or overwritten.
  final chat = services.chat..start();
  final now = DateTime.now();
  final at = DateTime(now.year, now.month, now.day, 9, 41);
  chat.messages.clear();
  if (conversation) {
    chat.messages.addAll([
      ChatMessage(
        id: 'brand-review-user',
        role: ChatRole.user,
        at: at,
        text: '今天在家练 15 分钟，想活动全身。',
      ),
      ChatMessage(
        id: 'brand-review-reply',
        role: ChatRole.assistant,
        at: at,
        text: '好，安排一组徒手轻力量。按自己的节奏来，动作不舒服就停下。',
      ),
      ChatMessage(
        id: 'brand-review-plan',
        role: ChatRole.assistant,
        at: at,
        plan: _plan,
      ),
    ]);
    chat.suggestions = const ['再短一点', '难一点', '换掉第 2 个', '换一套'];
  } else {
    chat.messages.add(
      ChatMessage(
        id: 'brand-review-greeting',
        role: ChatRole.assistant,
        at: at,
        text: '早上好\n说说今天想怎么练？',
        greeting: true,
      ),
    );
  }
  return services;
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    for (final element in tester.allElements.toList()) {
      final widget = element.widget;
      if (widget is Image) await precacheImage(widget.image, element);
    }
  });
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
  final out =
      Platform.environment['SF_SCREENSHOT_DIR'] ??
      '${Directory.current.path}/.buildlog/brand-review/screenshots';
  Directory(out).createSync(recursive: true);
  await expectLater(
    find.byType(MaterialApp).first,
    matchesGoldenFile(Uri.file('$out/$name.png')),
  );
}

void main() {
  for (final theme in ['light', 'dark']) {
    for (final conversation in [false, true]) {
      final screen = conversation ? 'chat' : 'home';
      testWidgets('brand $screen $theme', (tester) async {
        await _loadFonts();
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final services = await _services(theme, conversation: conversation);
        await tester.pumpWidget(
          SmartFitApp(services: services, fontFamily: 'NotoSansSC'),
        );
        await tester.pumpAndSettle();
        if (conversation) {
          expect(find.byType(PlanCard), findsOneWidget);
          expect(find.text('今天在家练 15 分钟，想活动全身。'), findsOneWidget);
        } else {
          expect(find.text('早上好'), findsOneWidget);
          expect(find.text('说说今天想怎么练？'), findsOneWidget);
        }
        await _capture(tester, '$screen-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
