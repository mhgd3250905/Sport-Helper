// Regressions for the PR #3 review (changes requested, 2026-10-20):
// P1 media packaging keeps verified stills with cache-only videos, P2 ring follows a paused
// skip/back, P2 switch/choice state semantics, P2 plan-detail "换一个" is
// its own accessible action.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_trainer/ugk_trainer.dart'
    show TrainerRingPainter, UgkPlayPauseButton;

import 'app_flow_test.dart' show services, tall;

const _two = TrainingPlan(
  id: 'two',
  source: 'template',
  title: '两个动作',
  summary: '',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 2,
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
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 20,
          perSide: false,
          restSeconds: 15,
        ),
        PlanItem(
          exerciseId: 'h-squat',
          mode: DoseMode.reps,
          sets: 1,
          reps: 8,
          perSide: false,
          restSeconds: 0,
        ),
      ],
    ),
  ],
);

const _swappable = TrainingPlan(
  id: 'swap',
  source: 'template',
  title: '可替换',
  summary: '',
  goal: 'relax',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 2,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-bridge-march',
          mode: DoseMode.time,
          sets: 1,
          workSeconds: 20,
          perSide: false,
          restSeconds: 15,
        ),
      ],
    ),
  ],
);

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Widget _host(Widget child) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('P1: cache-only videos retain verified metadata and all themed stills', () {
    final index = _json('assets/packs/index.json');
    final versions = {
      for (final e in index['packs'] as List) e['id']: e['version'],
    };
    // Pack metadata and its history remain intact while media lives in the
    // independent release manifest. Voice and chime consumers still use packs.
    for (final dir in Directory(
      'assets/packs',
    ).listSync().whereType<Directory>()) {
      final f = File('${dir.path}/pack.json');
      if (!f.existsSync()) continue;
      final pack = _json(f.path);
      expect(
        versions[pack['id']],
        pack['version'],
        reason: '${pack['id']} index version',
      );
    }
    const root = 'assets/training_media';
    const release = '$root/v0.3.0-app';
    final manifest = _json('$release/app-manifest.json');
    final packageFiles = Directory(
      '$release/packages',
    ).listSync().whereType<File>().toList();
    expect(packageFiles.map((file) => file.uri.pathSegments.last).toSet(), {
      'builtin.json',
      'realistic-dark.json',
      'realistic-light.json',
    });
    final packages = manifest['packages'] as Map<String, dynamic>;
    for (final id in ['builtin', 'realistic-dark', 'realistic-light']) {
      final descriptor = (packages[id] as Map)['manifest'] as Map;
      final file = File('$release/${descriptor['path']}');
      expect(file.lengthSync(), descriptor['bytes']);
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        descriptor['sha256'],
      );
    }
    final builtin = _json('$release/packages/builtin.json')['files'] as List;
    expect(builtin, hasLength(32));
    final indexedVideos = <String, Map>{};
    for (final descriptor in builtin.cast<Map>()) {
      expect(descriptor['path'], startsWith('../v0.3.0/realistic/dark/'));
      expect(descriptor['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(descriptor['bytes'], isPositive);
      expect(File('$release/${descriptor['path']}').existsSync(), isFalse);
      indexedVideos[descriptor['path'] as String] = descriptor;
    }
    final bundled = Directory(
      root,
    ).listSync(recursive: true).whereType<File>().toList();
    expect(bundled.where((file) => file.path.endsWith('.mp4')), isEmpty);
    expect(bundled, hasLength(941));
    expect(
      bundled.every(
        (file) => file.path.endsWith('.webp') || file.path.endsWith('.json'),
      ),
      isTrue,
    );
    final localIndex = _json('$release/assets-index.json')['actions'] as Map;
    expect(localIndex, hasLength(93));
    for (final entry in localIndex.entries) {
      for (final theme in ['dark', 'light']) {
        final media = (entry.value as Map)[theme] as Map;
        final video = media['video'] as Map;
        expect(
          video['asset'],
          '$root/v0.3.0/realistic/$theme/${entry.key}.mp4',
        );
        final source =
            [
              ...(_json('$release/packages/builtin.json')['files'] as List),
              ...(_json('$release/packages/realistic-$theme.json')['files']
                  as List),
            ].cast<Map>().firstWhere(
              (f) => f['path'] == '../v0.3.0/realistic/$theme/${entry.key}.mp4',
            );
        expect(video['sha256'], source['sha256']);
        expect(video['bytes'], source['bytes']);
        expect(File(video['asset'] as String).existsSync(), isFalse);
        indexedVideos[source['path'] as String] = source;
        for (final role in ['poster', 'thumbnail', 'playbackPoster']) {
          final descriptor = media[role] as Map;
          final file = File(descriptor['asset'] as String);
          expect(file.lengthSync(), descriptor['bytes']);
          expect(
            sha256.convert(file.readAsBytesSync()).toString(),
            descriptor['sha256'],
          );
        }
        final playback = media['playbackPoster'] as Map;
        expect(playback['sourceSha256'], video['sha256']);
        expect(playback['sourceFrame'], 0);
        expect(playback['sourceTimeSeconds'], 0);
      }
    }
    expect(indexedVideos, hasLength(191));
    final bytes = bundled.fold<int>(
      0,
      (total, file) => total + file.lengthSync(),
    );
    expect(bytes, 5_628_386);
    // The import verified source videos before deriving frame-zero stills.
    // This receipt rehashes the current static payload without re-decoding it.
    final report = _json('tools/media/builtin-assets-report.json');
    expect(report['videoDelivery'], 'cache-only');
    expect(report['videoCatalog'], {
      'files': indexedVideos.length,
      'bytes': indexedVideos.values.fold<int>(
        0,
        (sum, file) => sum + (file['bytes'] as int),
      ),
    });
    expect((report['groups'] as Map)['videos'], {'files': 0, 'bytes': 0});
    expect((report['bundle'] as Map)['bytes'], bytes);
    expect((report['bundle'] as Map)['files'], bundled.length);
    expect(report['validatedOutput'], isTrue);
    expect((report['sourceInputs'] as Map)['unchangedAfterBuild'], isTrue);
    expect(
      (report['sourceInputs'] as Map)['verificationScope'],
      'recorded-import-provenance',
    );
    expect(
      (report['outputVerification'] as Map)['sourceVideosReDecoded'],
      isFalse,
    );
    final inventory = [
      for (final file in bundled)
        '${file.path.replaceAll('\\', '/').substring(root.length + 1)}\u0000${file.lengthSync()}\u0000${sha256.convert(file.readAsBytesSync())}\n',
    ]..sort();
    expect(
      report['bundleInventorySha256'],
      sha256.convert(utf8.encode(inventory.join())).toString(),
    );
    expect(report['legacyPackMediaRemaining'], 0);
  });

  for (final back in [false, true]) {
    testWidgets(
      'P2: paused ${back ? 'back' : 'skip'} moves the ring to the new phase and stays paused',
      (tester) async {
        tall(tester);
        await tester.pumpWidget(
          AppScope(
            services: services(),
            child: MaterialApp(
              theme: buildTheme(),
              home: const PlayerPage(plan: _two),
            ),
          ),
        );
        await tester.pump();
        if (back) {
          // Into work first, so "back" has a phase to return to.
          await tester.tap(find.byKey(const ValueKey('skip')));
          await tester.pump();
        }
        // ugk_trainer uses clock.stopwatch: widget-test time is deterministic.
        await tester.pump(const Duration(milliseconds: 400));
        final ringPaint = find.byKey(const ValueKey('ring'));
        double ring() =>
            (tester.widget<CustomPaint>(ringPaint).painter!
                    as TrainerRingPainter)
                .progress
                .value;
        expect(ring(), greaterThan(0.01));
        await tester.tap(find.byKey(const ValueKey('pause')));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey(back ? 'prev' : 'skip')));
        await tester.pump();
        expect(
          ring(),
          lessThan(0.001),
          reason: 'new phase starts from an empty ring',
        );
        expect(find.byKey(const ValueKey('tag-paused')), findsNothing);
        final resume = tester.widget<UgkPlayPauseButton>(
          find.byKey(const ValueKey('pause')),
        );
        expect(resume.isPlaying, isFalse);
        expect(resume.strings.resume, '继续训练');
        expect(resume.theme.pausedColor, SfColors.accent);
        await tester.pump(const Duration(seconds: 1));
        expect(
          ring(),
          lessThan(0.001),
          reason: 'still paused: the ring does not move',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'P2: SfSwitchRow exposes toggled state; SfChoiceChip exposes selected state',
    (tester) async {
      final handle = tester.ensureSemantics();
      for (final v in [true, false]) {
        await tester.pumpWidget(
          _host(
            SfSwitchRow(
              title: '语音',
              subtitle: '播报口令',
              value: v,
              onChanged: (_) {},
            ),
          ),
        );
        expect(
          tester.getSemantics(find.byType(SfSwitchRow)),
          isSemantics(
            label: '语音',
            hint: '播报口令',
            hasToggledState: true,
            isToggled: v,
            hasTapAction: true,
          ),
        );
        await tester.pumpWidget(
          _host(SfChoiceChip(label: '哑铃', selected: v, onTap: () {})),
        );
        expect(
          tester.getSemantics(find.byType(SfChoiceChip)),
          isSemantics(
            label: '哑铃',
            hasSelectedState: true,
            isSelected: v,
            isButton: true,
            hasTapAction: true,
          ),
        );
      }
      handle.dispose();
    },
  );

  testWidgets('P2: plan detail keeps "换一个" as its own TalkBack action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tall(tester);
    await tester.pumpWidget(
      AppScope(
        services: services(),
        child: MaterialApp(
          theme: buildTheme(),
          home: const PlanPage(plan: _swappable),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = tester.getSemantics(
      find.byKey(const ValueKey('item-h-bridge-march')),
    );
    final swapFinder = find.descendant(
      of: find.byKey(const ValueKey('swap-h-bridge-march')),
      matching: find.bySemanticsLabel('换一个'),
    );
    expect(swapFinder, findsOneWidget);
    final swap = tester.getSemantics(swapFinder);
    expect(swap.id, isNot(row.id));
    expect(row, isSemantics(isButton: false, hasTapAction: false));
    expect(swap, isSemantics(label: '换一个', isButton: true, hasTapAction: true));
    swap.owner!.performAction(swap.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('item-h-bridge-march')),
      findsNothing,
      reason: 'the move was swapped',
    );
    handle.dispose();
  });
}
