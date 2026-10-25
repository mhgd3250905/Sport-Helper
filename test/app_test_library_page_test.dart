import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/diagnostics/action_issue.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/action_issue_form.dart';
import 'package:smartfit/ui/app_test_library_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:ugk_trainer/ugk_trainer.dart';

class _Storage implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

Future<AppTestCatalog> _catalog({bool media = false}) => AppTestCatalog.load(
  deliveryCatalogJson: jsonEncode({
    'format': 'pose-hub-app-test-catalog@1',
    'id': 'test-pack',
    'reviewed': false,
    'releaseEligible': false,
    'actions': [
      {
        'id': 'pending',
        'nameZh': '待补说明的长名称测试动作',
        'equipment': ['unknown-prop'],
        'revision': 'pending-r2',
        'availableForApp': media,
      },
      {
        'id': 'complete',
        'nameZh': '说明完整的动作',
        'equipment': <String>[],
        'revision': 'complete-r1',
        'category': 'mobility',
        'position': 'standing',
        'unilateral': false,
        'level': 1,
        'scenes': ['home'],
        'defaultDose': {
          'mode': 'time',
          'seconds': 30,
          'sets': 1,
          'restSeconds': 10,
        },
        'cues': {
          'zh': ['按说明缓慢活动'],
        },
      },
    ],
  }),
  bundledMedia: media
      ? const {
          'pending': AppTestAction(
            id: 'pending',
            revision: 'pending-r2',
            packedVideo: 'assets/test/packed.mp4',
            playbackPoster: 'assets/test/first.webp',
            cover: 'assets/test/cover.webp',
            thumbnail: 'assets/test/thumb.webp',
            loopSeconds: 8,
          ),
        }
      : const {},
);

AppServices _services() => AppServices(
  library: ExerciseLibrary([]),
  catalog: TemplateCatalog([]),
  store: AppStore(_Storage(), actionIssueEnabled: true)..starfield = false,
  voiceLibrary: VoiceLibrary.empty,
  voiceOutput: const MutedVoiceOutput(),
);

Future<void> _show(
  WidgetTester tester,
  AppTestCatalog catalog,
  AppServices services,
  SfPalette palette,
) async {
  tester.view.physicalSize = const Size(320, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: buildTheme(palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: SfPaletteScope(child: child!),
        ),
        home: AppTestLibraryPage(catalog: catalog),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => SfColors.palette = SfPalette.dark);

  for (final dark in [false, true]) {
    testWidgets(
      'pending catalog entries remain visible and markable, dark=$dark',
      (tester) async {
        final catalog = await _catalog();
        final services = _services();
        await _show(
          tester,
          catalog,
          services,
          dark ? SfPalette.dark : SfPalette.light,
        );
        expect(find.text('训练说明待补'), findsOneWidget);
        expect(find.text('unknown-prop'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('test-action-pending')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('test-action-pending')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('test-detail-play-pending')),
          findsNothing,
        );
        final mark = find.byKey(const ValueKey('test-detail-mark-pending'));
        await tester.ensureVisible(mark);
        await tester.pumpAndSettle();
        await tester.tap(mark);
        await tester.pumpAndSettle();
        final form = tester.widget<ActionIssueForm>(
          find.byType(ActionIssueForm),
        );
        expect(form.capture.actionId, 'pending');
        expect(form.capture.revision, 'pending-r2');
        expect(form.capture.videoSeconds, isNull);
        expect(
          form.capture.videoPositionUnavailableReason,
          ActionIssueVideoUnavailableReason.noVideo,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('category filtering does not delete pending entries from all', (
    tester,
  ) async {
    final catalog = await _catalog();
    expect(catalog.entries['complete']!.trainingEligible, isTrue);
    await _show(tester, catalog, _services(), SfPalette.light);
    final category = find.byKey(const ValueKey('test-cat-mobility'));
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-action-pending')), findsNothing);
    expect(find.byKey(const ValueKey('test-action-complete')), findsOneWidget);
    final all = find.byKey(const ValueKey('test-cat-all'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-action-pending')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'pending training can capture real video time and catalog revision',
    () async {
      final entry = (await _catalog(media: true)).entries['pending']!;
      expect(entry.trainingEligible, isFalse);
      final time = DateTime.utc(2026, 10, 25, 6);
      final result = await captureCatalogActionIssueContext(
        entry: entry,
        hasVideo: true,
        capturePlayback: () async => DrillMediaPlaybackSnapshot(
          mediaId: entry.id,
          videoSeconds: 2.25,
          ready: true,
          capturedAt: time,
        ),
      );
      expect(result.revision, 'pending-r2');
      expect(result.videoSeconds, 2.25);
      expect(result.capturedAt, time);
      expect(result.videoPositionUnavailableReason, isNull);
    },
  );

  testWidgets('pending training with bundled media starts only after a tap', (
    tester,
  ) async {
    final catalog = await _catalog(media: true);
    await _show(tester, catalog, _services(), SfPalette.light);
    await tester.tap(find.byKey(const ValueKey('test-action-pending')));
    await tester.pumpAndSettle();
    expect(find.byType(DrillMediaView), findsNothing);
    final play = find.byKey(const ValueKey('test-detail-play-pending'));
    await tester.ensureVisible(play);
    await tester.tap(play);
    await tester.pump();
    final video = tester.widget<DrillMediaView>(find.byType(DrillMediaView));
    expect(video.media.id, 'pending');
    expect(video.media.packedAlphaVideoAsset, 'assets/test/packed.mp4');
    expect(video.media.packedAlphaPosterAsset, 'assets/test/first.webp');
    expect(video.paused, isFalse);
    await tester.tap(play);
    await tester.pump();
    expect(
      tester.widget<DrillMediaView>(find.byType(DrillMediaView)).paused,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'another action position cannot contaminate this catalog issue',
    () async {
      final entry = (await _catalog(media: true)).entries['pending']!;
      final result = await captureCatalogActionIssueContext(
        entry: entry,
        hasVideo: true,
        capturePlayback: () async => DrillMediaPlaybackSnapshot(
          mediaId: 'complete',
          videoSeconds: 2.25,
          ready: true,
          capturedAt: DateTime.now().toUtc(),
        ),
      );
      expect(result.actionId, 'pending');
      expect(result.revision, 'pending-r2');
      expect(result.videoSeconds, isNull);
      expect(
        result.videoPositionUnavailableReason,
        ActionIssueVideoUnavailableReason.unavailable,
      );
    },
  );
}
