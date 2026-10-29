import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/diagnostics/training_log.dart';
import 'package:smartfit/diagnostics/training_media_log.dart';
import 'package:smartfit/app/training_media_config.dart';
import 'package:smartfit/domain/plan.dart' as app;
import 'package:smartfit/domain/exercise.dart' as app_exercise;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app_flow_test.dart' as fixture;

List<Map<String, dynamic>> events(RuntimeLog log) =>
    (jsonDecode(log.exportJson())['events'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shared player pause/resume and actual result reach the internal log',
    (tester) async {
      final previous = RuntimeLog.instance;
      final log = RuntimeLog(enabled: true);
      RuntimeLog.instance = log;
      addTearDown(() => RuntimeLog.instance = previous);
      final services = fixture.services();
      const plan = app.TrainingPlan(
        id: 'log-test',
        source: 'template',
        title: 'private-title',
        summary: '',
        goal: 'relax',
        scene: 'home',
        equipment: [],
        level: 1,
        targetMinutes: 1,
        blocks: [
          app.PlanBlock(
            id: 'main',
            name: 'private-name',
            type: app.BlockType.main,
            rounds: 1,
            restBetweenRoundsSeconds: 0,
            items: [
              app.PlanItem(
                exerciseId: 'h-squat',
                mode: app_exercise.DoseMode.time,
                sets: 1,
                workSeconds: 5,
                perSide: false,
                restSeconds: 0,
              ),
            ],
          ),
        ],
      );
      await fixture.showPlayer(tester, services, plan: plan);
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pump();
      final records = events(log);
      expect(
        records.where((event) => event['event'] == 'training.started'),
        hasLength(1),
      );
      expect(
        records.where((event) => event['event'] == 'training.paused'),
        hasLength(1),
      );
      expect(
        records.where((event) => event['event'] == 'training.resumed'),
        hasLength(1),
      );
      final finished = records.singleWhere(
        (event) => event['event'] == 'training.finished',
      );
      expect(
        finished['fields']['durationMs'],
        (services.store.sessionResults.single.activeSeconds * 1000).round(),
      );
      expect(
        records.any((event) => event['event'] == 'training.result.saved'),
        true,
      );
      expect(
        records.any((event) => event['event'] == 'video.surface.requested'),
        true,
      );
      expect(log.exportJson(), isNot(contains('private-title')));
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'shipping cache misses log offline outcomes and detach cleanly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'smartfit-media-log-',
      );
      final repository = await TrainingMediaRepository.create(
        manifestAsset: TrainingMediaConfig.manifestAsset,
        baseUrls: const [],
        allowPending: true,
        cacheDirectory: directory.path,
        networkProbe: () async => TrainingMediaNetwork.offline,
      );
      final log = RuntimeLog(enabled: true);
      final observer = TrainingMediaLog(repository, log: log)..start();
      try {
        expect(await repository.availableActionIds(), isEmpty);
        expect(await repository.availableVideo('h-squat'), isNull);
        expect(await repository.cacheBytes(), 0);
        // Builtin is a retained source package name, not proof that a video
        // payload ships. Both metadata-backed and catalog-only misses use the
        // real offline path with the current asset manifest and empty cache.
        expect(
          File(
            'assets/training_media/v0.3.0/realistic/dark/h-squat.mp4',
          ).existsSync(),
          isFalse,
        );
        await expectLater(
          repository.ensureVideo('h-squat'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repository.ensureVideo('abs-A'),
          throwsA(isA<StateError>()),
        );
        final resources = events(
          log,
        ).where((event) => event['event'] == 'media.resource.state').toList();
        for (final id in ['h-squat', 'abs-A']) {
          final miss = resources.singleWhere(
            (event) =>
                event['fields']['actionId'] == id &&
                event['fields']['phase'] == 'offline',
          );
          expect(miss['fields']['reason'], 'offline');
          expect(miss['fields'].containsKey('verified'), false);
          expect(miss['fields'].containsKey('source'), false);
        }
        expect(
          resources.where((event) => event['fields']['phase'] == 'ready'),
          isEmpty,
        );
        expect(await repository.availableActionIds(), isEmpty);
        expect(await repository.cacheBytes(), 0);
        observer.dispose();
        final count = log.entryCount;
        await repository.clearCache();
        expect(log.entryCount, count);
      } finally {
        observer.dispose();
        repository.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'training observations deduplicate builds and stop heartbeats at finish',
    (tester) async {
      final log = RuntimeLog(enabled: true);
      final training = TrainingLog(log: log);
      training.start(actionCount: 2, voice: true, chimes: true);
      training.visibleAction('h-squat', paused: false);
      training.visibleAction('h-squat', paused: false);
      training.visibleAction('h-squat', paused: true);
      training.visibleAction('h-squat', paused: true);
      training.visibleAction('h-squat', paused: false);
      await tester.pump(const Duration(seconds: 31));
      final at = DateTime.utc(2026, 10, 23);
      final result = SessionResult(
        sessionId: 'private-session-id',
        planId: 'private-plan-id',
        planTitle: 'private-plan-title',
        startedAt: at,
        endedAt: at.add(const Duration(seconds: 31)),
        activeSeconds: 12.345,
        endedEarly: true,
        completedExercises: 1,
        totalExercises: 2,
        items: const [],
      );
      training.finished(result);
      training.finished(result);
      await tester.pump(const Duration(minutes: 1));
      training.saving();
      training.saveFailed(StateError('secret payload'));
      training.dispose();

      final records = events(log);
      expect(
        records.where((e) => e['event'] == 'training.action.visible'),
        hasLength(1),
      );
      expect(
        records.where((e) => e['event'] == 'training.paused'),
        hasLength(1),
      );
      expect(
        records.where((e) => e['event'] == 'training.resumed'),
        hasLength(1),
      );
      expect(
        records.where((e) => e['event'] == 'training.heartbeat.wall'),
        hasLength(1),
      );
      final finished = records.singleWhere(
        (e) => e['event'] == 'training.finished',
      );
      expect(finished['fields']['durationMs'], 12345);
      expect(finished['fields']['status'], 'ended_early');
      expect(finished['fields']['success'], false);
      expect(records.map((e) => e['operation']).toSet(), hasLength(1));
      final exported = log.exportJson();
      expect(exported, isNot(contains('private-')));
      expect(exported, isNot(contains('secret payload')));

      // Replay audio begins before the first media build: it must receive
      // the new training operation, including its first spoken cue.
      final replay = TrainingLog(log: log);
      replay.start(actionCount: 2, voice: true, chimes: true);
      replay.finished(result);
      final previousOperation = replay.operation;
      replay.audioBeginning();
      final nextOperation = replay.operation;
      expect(nextOperation, isNot(previousOperation));
      replay.visibleAction('h-squat', paused: false);
      expect(replay.operation, nextOperation);
      expect(events(log).last['operation'], nextOperation);
      replay.dispose();
    },
  );

  test('media error classifications never export exception paths or URLs', () {
    const cases = {
      'FormatException: Media SHA-256 verification failed /private/path':
          'checksum_failed',
      'TimeoutException: https://example.test/private': 'timeout',
      'StateError: No network connection': 'offline',
      'StateError: Waiting for Wi-Fi': 'wifi_required',
      'HttpException: Media response size/status mismatch':
          'http_status_or_size',
      'FormatException: Media exceeds declared size': 'size_mismatch',
      'Exception: https://host.test/private?token=secret':
          'download_or_validation_failed',
    };
    for (final entry in cases.entries) {
      expect(TrainingMediaLog.failureReason(entry.key), entry.value);
    }
  });
}
