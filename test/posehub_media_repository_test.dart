import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/posehub_media_preparer.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/ui/training_media_settings.dart';
import 'package:smartfit/ui/training_media_progress.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart'
    show CatalogMediaTiming, CatalogMediaTimingCallback, PoseHubMediaReady;

class _CacheSettingsServices implements AppServices {
  _CacheSettingsServices(this.poseHubMedia);

  @override
  final PoseHubMediaRepository poseHubMedia;

  @override
  Null get media => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  _Fixture({
    int actions = 2,
    int videoBytes = 4096,
    List<int>? videoSizes,
    int coverBytes = 48,
    bool sharedVideos = false,
  }) {
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < actions; i++) {
      final id = 'action-$i';
      final files = <String, Object?>{};
      for (final role in ['video', 'cover', 'thumbnail']) {
        final path = 'media/$id/$role.${role == 'video' ? 'mp4' : 'webp'}';
        final bytes = Uint8List.fromList(
          List.generate(
            role == 'video'
                ? (videoSizes?[i] ?? videoBytes)
                : (role == 'cover' ? coverBytes : 24),
            (n) =>
                (n * 17 +
                    role.length +
                    (sharedVideos && role == 'video' ? 0 : i)) %
                251,
          ),
        );
        bodies[path] = bytes;
        files[role] = {
          'path': path,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        };
      }
      rows.add({
        'id': id,
        'nameZh': 'Fixture $id',
        ...flags,
        'availableForApp': true,
        'availableForTraining': false,
        'trainingDefinitionComplete': false,
        'trainingSemantics': {
          ...flags,
          'status': 'partial-fixture',
          'definitionComplete': false,
          'missingRequiredFields': ['defaultDose'],
          'unknownFields': [],
          'videoLoopIsTrainingDose': false,
        },
        'rhythm': {'videoLoopIsTrainingDose': false},
        'files': files,
      });
    }
    final raw = {
      'format': 'pose-hub-app-test-catalog@1',
      'id': 'fixture',
      ...flags,
      'totalCount': actions,
      'readyCount': actions,
      'pendingCount': 0,
      'actions': rows,
      'semanticCatalog': {
        'path': 'catalog/catalog.json',
        'bytes': 2,
        'sha256': sha256.convert(utf8.encode('{}')).toString(),
        'version': '0.0.0',
      },
      'trainingSemantics': {
        ...flags,
        'definitionCompleteCount': 0,
        'definitionCompleteIds': [],
        'incompleteActionIds': rows.map((r) => r['id']).toList(),
        'videoLoopIsTrainingDose': false,
      },
    };
    revision = sha256.convert(utf8.encode(jsonEncode(raw))).toString();
    catalog = coach.PoseHubAppTestCatalog.fromJson(raw);
  }

  static const flags = {
    'status': 'test-unreviewed',
    'reviewed': false,
    'releaseEligible': false,
  };
  final bodies = <String, Uint8List>{};
  late final coach.PoseHubAppTestCatalog catalog;
  late final String revision;
  coach.PoseHubPackAction get first => catalog.allActions.first;
}

Future<void> _until(bool Function() condition) async {
  final timer = Stopwatch()..start();
  while (!condition()) {
    if (timer.elapsed > const Duration(seconds: 5)) {
      throw StateError('Timed out waiting for test server.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory support;
  late _Fixture fixture;
  late HttpServer server;
  late Uri base;
  late Future<void> Function(HttpRequest) handler;
  late List<String> requested;
  final repositories = <PoseHubMediaRepository>[];

  setUp(() async {
    support = await Directory.systemTemp.createTemp('smartfit-media-test-');
    fixture = _Fixture();
    requested = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
    handler = (request) async {
      final bytes = fixture.bodies[request.uri.path.substring(1)];
      if (bytes == null) {
        request.response.statusCode = 404;
      } else {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
      }
      await request.response.close();
    };
    server.listen((request) async {
      requested.add(request.uri.path);
      try {
        await handler(request);
      } on IOException {
        // Several cases deliberately terminate a client or an incomplete body.
      }
    });
  });

  tearDown(() async {
    for (final repository in repositories) {
      repository.dispose();
    }
    repositories.clear();
    await server.close(force: true);
    await support.delete(recursive: true);
  });

  Future<PoseHubMediaRepository> create({
    PoseHubBundledFileLoader? bundled,
    List<Uri>? mediaBases,
    bool offline = false,
    Duration timeout = const Duration(seconds: 3),
    Duration progressInterval = const Duration(milliseconds: 25),
    int concurrent = 2,
    int redirects = 5,
    String? revision,
    String packVersion = 'r1-v3',
    int cacheBytes = poseHubVideoCacheLimitBytes,
    CatalogMediaTimingCallback? onTiming,
  }) async {
    final result = await PoseHubMediaRepository.forTesting(
      catalog: fixture.catalog,
      catalogRevision: revision ?? fixture.revision,
      mediaBaseUrls: offline ? [] : (mediaBases ?? [base]),
      packVersion: packVersion,
      rootDirectory: support.path,
      bundledFileLoader: bundled,
      allowInsecureLocalhost: true,
      timeout: timeout,
      progressInterval: progressInterval,
      maxConcurrent: concurrent,
      maxRedirects: redirects,
      maxVideoCacheBytes: cacheBytes,
      onTiming: onTiming,
    );
    repositories.add(result);
    return result;
  }

  Future<void> noParts(PoseHubMediaRepository repository) async {
    final files = await Directory.fromUri(
      repository.mediaBaseUri,
    ).list(recursive: true).toList();
    expect(
      files.whereType<File>().where((f) => f.path.endsWith('.part')),
      isEmpty,
    );
  }

  test(
    'training priority promotes a deduplicated queued video without cancelling active work',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      handler = (request) async {
        final path = request.uri.path.substring(1);
        if (path == actions[0].video.path) await release.future;
        final bytes = fixture.bodies[path]!;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      };
      final repo = await create(concurrent: 1);
      final training = repo as PoseHubTrainingVideoPreparation;
      final active = training.ensureVideo(actions[0].id);
      await _until(() => requested.isNotEmpty);
      final ordinary = training.ensureVideo(actions[1].id);
      await _until(
        () =>
            repo.watchFile(actions[1].video).value.phase ==
            PoseHubDownloadPhase.queued,
      );
      final queued = training.ensureVideo(actions[2].id);
      await _until(
        () =>
            repo.watchFile(actions[2].video).value.phase ==
            PoseHubDownloadPhase.queued,
      );
      final promoted = training.ensureVideo(actions[2].id, priority: true);
      expect(promoted, same(queued));
      expect(repo.ensureFile(actions[2].video), same(queued));
      expect(requested, ['/${actions[0].video.path}']);
      release.complete();
      await Future.wait([active, ordinary, promoted]);
      expect(requested, [
        '/${actions[0].video.path}',
        '/${actions[2].video.path}',
        '/${actions[1].video.path}',
      ]);
      expect(requested.toSet(), hasLength(3));
    },
  );

  test(
    'training retry starts a fresh video job and immediately advances failed bases',
    () async {
      var fail = true;
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog.instance = RuntimeLog(enabled: true);
      final timings = <CatalogMediaTiming>[];
      try {
        handler = (request) async {
          if (fail || request.uri.path.startsWith('/primary/')) {
            request.response.statusCode = 503;
          } else {
            final bytes = fixture.bodies[fixture.first.video.path]!;
            request.response.contentLength = bytes.length;
            request.response.add(bytes);
          }
          await request.response.close();
        };
        final repo = await create(
          mediaBases: [base.resolve('primary/'), base.resolve('backup/')],
          onTiming: timings.add,
        );
        final training = repo as PoseHubTrainingVideoPreparation;
        final failed = training.ensureVideo(fixture.first.id, priority: true);
        await expectLater(
          failed,
          throwsA(
            isA<PoseHubMediaException>().having((e) => e.code, 'code', 'http'),
          ),
        );
        fail = false;
        final retry = training.ensureVideo(fixture.first.id, priority: true);
        expect(retry, isNot(same(failed)));
        await retry;
        expect(requested, [
          '/primary/${fixture.first.video.path}',
          '/backup/${fixture.first.video.path}',
          '/primary/${fixture.first.video.path}',
          '/backup/${fixture.first.video.path}',
        ]);
        final events = (jsonDecode(log.exportJson()) as Map)['events'] as List;
        final attempts = [
          for (final e in events)
            if ((e as Map)['fields']['phase'] == 'attempt')
              e['fields']['baseIndex'],
        ];
        expect(attempts, [1, 2, 1, 2]);
        expect(timings, hasLength(2));
        expect(timings.first.result, 'failed');
        expect(timings.last.result, 'ready');
        expect(timings.last.source, 'network');
        expect(timings.last.baseIndex, 2);
        expect(timings.last.retries, 1);
        expect(timings.last.firstByteAt, isNotNull);
        expect(timings.last.toLogLine(), isNot(contains('http://')));
      } finally {
        RuntimeLog.instance = previousLog;
      }
    },
  );

  test(
    'Step1 training current then next uses the same slow-image fixture',
    () async {
      fixture = _Fixture(actions: 3);
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog.instance = RuntimeLog(enabled: true);
      try {
        handler = (request) async {
          final path = request.uri.path.substring(1);
          final bytes = fixture.bodies[path]!;
          await Future<void>.delayed(
            Duration(milliseconds: path.endsWith('.mp4') ? 10 : 200),
          );
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        };
        final repo = await create();
        (repo as PoseHubMediaTimingAnchor).markTrainingEntry();
        final training = repo as PoseHubTrainingVideoPreparation;
        final actions = fixture.catalog.allActions.toList();
        await training.ensureVideo(actions[0].id, priority: true);
        // The caller schedules only the next video after current becomes ready.
        await training.ensureVideo(actions[1].id);
        expect(requested, [
          '/${actions[0].video.path}',
          '/${actions[1].video.path}',
        ]);
        final exported = jsonDecode(log.exportJson()) as Map<String, dynamic>;
        final events = (exported['events'] as List)
            .cast<Map<String, dynamic>>()
            .where((e) => e['event'] == 'media.timing')
            .toList();
        final tasks = <String, Map<String, Object?>>{};
        for (final e in events) {
          final f = Map<String, dynamic>.from(e['fields'] as Map);
          if (f['taskId'] is! String) continue;
          final row = tasks.putIfAbsent(
            f['taskId'] as String,
            () => {
              'actionId': f['actionId'],
              'kind': f['kind'],
              'bytes': f['bytes'],
              'stagesMsFromEntry': <String, Object?>{},
              'visibleFirstFrameMs': null,
              'visibleFirstFrameEvidence': 'not_measured_repository_only',
            },
          );
          (row['stagesMsFromEntry'] as Map<String, Object?>)[f['phase']
                  as String] =
              f['sinceEntryMs'];
        }
        expect(tasks.values.every((t) => t['kind'] == 'video'), isTrue);
        final directory =
            Platform.environment['SMARTFIT_MEDIA_TIMING_REPORT_DIR'];
        if (directory != null) {
          final report = Directory(directory);
          await report.create(recursive: true);
          await File(
            '${report.path}/step1-repository-events.json',
          ).writeAsString(jsonEncode(exported));
          await File(
            '${report.path}/step1-repository-stage-table.json',
          ).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'format': 'sf-media-timing-controlled-after@1',
              'baselineSource': '2c534f562680c6b1604d05f321d8952caeae99e1',
              'behaviorChanged': true,
              'fixtureActions': 3,
              'maxConcurrent': 2,
              'callPattern': 'current_video_priority_then_only_next_video',
              'controlledVideoResponseDelayMs': 10,
              'controlledImageResponseDelayMs': 200,
              'mediaRequests': requested.length,
              'tasks': tasks.values.toList(),
              'actualDeviceSlowCauseEstablished': false,
              'firstFrameAndRevealMeasured': false,
            }),
          );
        }
      } finally {
        RuntimeLog.instance = previousLog;
      }
    },
  );

  test(
    'entry-aware joined consumers preserve producer terminal metadata',
    () async {
      final previousLog = RuntimeLog.instance;
      final log = RuntimeLog.instance = RuntimeLog(enabled: true);
      final terminals = <Map<String, Object?>>[];
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      try {
        handler = (request) async {
          await release.future;
          final bytes = fixture.bodies[request.uri.path.substring(1)]!;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        };
        final repo = await create(
          onTiming: (record) {
            final fields = {
              ...poseHubMediaTimingFields(record),
              'phase': 'terminal',
            };
            terminals.add(fields);
            log.record('media.timing', fields: fields);
          },
        );
        final entries = repo as PoseHubMediaEntryPreparation;
        entries.markMediaEntry('training');
        entries.markMediaEntry('guide_preview');
        final first = entries.ensureVideoForEntry(
          fixture.first.id,
          entry: 'guide_preview',
          priority: true,
        );
        await _until(() => requested.isNotEmpty);
        entries.markMediaEntry('action_library_preview');
        final bridge = TrainingMediaRepositoryBridge(
          catalog: fixture.catalog,
          host: repo,
          entry: 'action_library_preview',
        );
        final joined = bridge.ensureFile(fixture.first.video);
        expect(joined, same(first));
        release.complete();
        await first;
        bridge.dispose();
        expect(terminals, hasLength(1));
        expect(terminals.single['entry'], 'guide_preview');
        expect(terminals.single['entryId'], isA<String>());
        expect(terminals.single['sinceEntryMs'], isA<int>());
        final events = (jsonDecode(log.exportJson()) as Map)['events'] as List;
        final join = events.singleWhere(
          (e) =>
              e['event'] == 'media.timing' && e['fields']['phase'] == 'joined',
        );
        expect(join['fields']['entry'], 'action_library_preview');
        expect(join['fields']['taskId'], terminals.single['taskId']);
        expect(join['fields']['entryId'], isNot(terminals.single['entryId']));
        final fileEntries = [
          for (final e in events)
            if (e['fields']['kind'] == 'video') e['fields']['entry'],
        ];
        expect(fileEntries, isNot(contains('training')));
        expect(requested, hasLength(1));
      } finally {
        RuntimeLog.instance = previousLog;
      }
    },
  );

  for (final videoOnly in [false, true]) {
    for (final warmVideo in [false, true]) {
      final mode = warmVideo ? 'video-cached' : 'cold-cache';
      test(
        '${videoOnly ? 'Step1' : 'Step0'} preview production preparer $mode',
        () async {
          fixture = _Fixture(actions: 1);
          final previousLog = RuntimeLog.instance;
          final log = RuntimeLog.instance = RuntimeLog(enabled: true);
          try {
            handler = (request) async {
              final path = request.uri.path.substring(1);
              final bytes = fixture.bodies[path]!;
              await Future<void>.delayed(
                Duration(milliseconds: path.endsWith('.mp4') ? 10 : 200),
              );
              request.response.contentLength = bytes.length;
              request.response.add(bytes);
              await request.response.close();
            };
            final repo = await create();
            final action = fixture.first;
            if (warmVideo) await repo.ensureFile(action.video);
            requested.clear();
            final watch = Stopwatch()..start();
            if (videoOnly) {
              (repo as PoseHubMediaEntryPreparation).markMediaEntry(
                'action_library_preview',
              );
            } else {
              (repo as PoseHubMediaTimingAnchor).markTrainingEntry();
            }
            final videoState = repo.watchFile(action.video);
            int? videoReadyMs;
            int? allResourcesReadyMs;
            void videoChanged() {
              if (videoState.value.phase == PoseHubDownloadPhase.ready) {
                videoReadyMs ??= watch.elapsedMilliseconds;
              }
            }

            videoState.addListener(videoChanged);
            videoChanged();
            final prepared = <Object>[];
            try {
              await for (final event in SmartFitPoseHubMediaPreparer(
                repo,
                videoOnly: videoOnly,
                entry: videoOnly ? 'action_library_preview' : null,
              ).prepareAction(action)) {
                prepared.add(event);
                if (event is PoseHubMediaReady) {
                  allResourcesReadyMs = watch.elapsedMilliseconds;
                }
              }
            } finally {
              videoState.removeListener(videoChanged);
            }
            expect(prepared.whereType<PoseHubMediaReady>(), hasLength(1));
            expect(videoReadyMs, isNotNull);
            expect(allResourcesReadyMs, greaterThanOrEqualTo(videoReadyMs!));
            expect(
              requested,
              hasLength(videoOnly ? (warmVideo ? 0 : 1) : (warmVideo ? 2 : 3)),
            );
            if (warmVideo) {
              expect(requested, isNot(contains('/${action.video.path}')));
            }
            expect(
              (videoOnly ? videoState.value : repo.watchAction(action.id).value)
                  .phase,
              PoseHubDownloadPhase.ready,
            );
            final exported =
                jsonDecode(log.exportJson()) as Map<String, dynamic>;
            final events = (exported['events'] as List)
                .cast<Map<String, dynamic>>();
            final entry = events.lastWhere(
              (e) =>
                  e['event'] == 'media.timing' &&
                  (e['fields'] as Map)['phase'] == 'entry',
            );
            final entryStart = entry['sinceStartMs'] as int;
            final stages = <String, Map<String, Object?>>{};
            for (final e in events) {
              if (e['event'] != 'media.timing') continue;
              final f = e['fields'] as Map;
              if ((e['sinceStartMs'] as int) < entryStart ||
                  f['kind'] == 'repository') {
                continue;
              }
              (stages[f['kind'] as String] ??= {})[f['phase'] as String] =
                  f['sinceEntryMs'] ?? (e['sinceStartMs'] as int) - entryStart;
            }
            final directory =
                Platform.environment['SMARTFIT_PREVIEW_TIMING_REPORT_DIR'];
            if (directory != null) {
              final report = Directory(directory);
              await report.create(recursive: true);
              final prefix = videoOnly ? 'after-preview' : 'before-preview';
              await File(
                '${report.path}/$prefix-$mode-events.json',
              ).writeAsString(jsonEncode(exported));
              await File('${report.path}/$prefix-$mode.json').writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'format': videoOnly
                      ? 'sf-preview-preparer-controlled-after@1'
                      : 'sf-preview-preparer-controlled-before@1',
                  'baselineSource': '9fb21f485f51ad22c778655474d3dcb5bafd6dba',
                  'sdkRuntimeOnlyPublicExportChanged': true,
                  'entry': 'action_library_preview',
                  'entryFieldPresentInProduct': videoOnly,
                  'cacheState': mode,
                  'fixtureActions': 1,
                  'maxConcurrent': 2,
                  'videoResponseDelayMs': 10,
                  'imageResponseDelayMs': 200,
                  'behaviorChanged': videoOnly,
                  'preparedResourceScope': videoOnly
                      ? 'video_only'
                      : 'whole_action',
                  'realDeviceMeasured': false,
                  'entryMs': 0,
                  'videoReadyMs': videoReadyMs,
                  'allResourcesReadyMs': allResourcesReadyMs,
                  'visibleFirstFrameMs': null,
                  'visibleFirstFrameMeasured': false,
                  'requestCountAfterEntry': requested.length,
                  'fileStagesMs': stages,
                }),
              );
            }
          } finally {
            RuntimeLog.instance = previousLog;
          }
        },
      );
    }
  }

  test('Step0 timing observes unchanged two-worker full-action FIFO', () async {
    fixture = _Fixture(actions: 3);
    final previousLog = RuntimeLog.instance;
    final log = RuntimeLog.instance = RuntimeLog(enabled: true);
    try {
      handler = (request) async {
        final path = request.uri.path.substring(1);
        final bytes = fixture.bodies[path]!;
        // Controlled transport only: images are deliberately slower than
        // videos. Workers, FIFO and concurrency match production; existing
        // fixture-only transport timeouts remain unchanged.
        await Future<void>.delayed(
          Duration(milliseconds: path.endsWith('.mp4') ? 10 : 200),
        );
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      };
      final repo = await create();
      (repo as PoseHubMediaTimingAnchor).markTrainingEntry();
      final ordered = fixture.catalog.allActions.map((a) => a.id).toList();
      var next = 0;
      Future<void> worker() async {
        while (next < ordered.length) {
          await repo.ensureAction(ordered[next++]);
        }
      }

      // Same call pattern as AppServices._prefetchPoseHub: two workers, each
      // awaiting all three files of one action before taking another action.
      await Future.wait([worker(), worker()]);
      expect(requested, hasLength(9));
      expect(requested.toSet(), hasLength(9));
      final exported = jsonDecode(log.exportJson()) as Map<String, dynamic>;
      final events = (exported['events'] as List)
          .cast<Map<String, dynamic>>()
          .where((e) => e['event'] == 'media.timing')
          .toList();
      final fields = [
        for (final e in events) Map<String, dynamic>.from(e['fields'] as Map),
      ];
      expect(fields.where((f) => f['phase'] == 'complete'), hasLength(9));
      expect(fields.where((f) => f['phase'] == 'first_byte'), hasLength(9));
      expect(fields.any((f) => (f['queueDepth'] as int? ?? 0) > 0), isTrue);
      expect(fields.where((f) => f['phase'] == 'attempt_failed'), isEmpty);
      expect(
        fields
            .where((f) => f['phase'] == 'attempt')
            .every((f) => f['baseIndex'] == 1 && f['retry'] == 0),
        isTrue,
      );
      expect(log.exportJson(), isNot(contains('http://')));
      expect(log.exportJson(), isNot(contains('127.0.0.1')));
      final tasks = <String, Map<String, Object?>>{};
      for (final f in fields) {
        if (f['taskId'] is! String) continue;
        final row = tasks.putIfAbsent(
          f['taskId'] as String,
          () => {
            'actionId': f['actionId'],
            'kind': f['kind'],
            'bytes': f['bytes'],
            'stagesMsFromEntry': <String, Object?>{},
            'visibleFirstFrameMs': null,
            'visibleFirstFrameEvidence': 'not_measured_repository_only',
          },
        );
        (row['stagesMsFromEntry'] as Map<String, Object?>)[f['phase']
                as String] =
            f['sinceEntryMs'];
      }
      final directory =
          Platform.environment['SMARTFIT_MEDIA_TIMING_REPORT_DIR'];
      if (directory != null) {
        final report = Directory(directory);
        await report.create(recursive: true);
        await File(
          '${report.path}/step0-repository-events.json',
        ).writeAsString(jsonEncode(exported));
        await File(
          '${report.path}/step0-repository-stage-table.json',
        ).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'format': 'sf-media-timing-controlled-baseline@1',
            'source': '2c534f562680c6b1604d05f321d8952caeae99e1',
            'behaviorChanged': false,
            'callPattern':
                'two_workers_each_await_ensureAction_all_three_files',
            'maxConcurrent': 2,
            'controlledVideoResponseDelayMs': 10,
            'controlledImageResponseDelayMs': 200,
            'mediaRequests': requested.length,
            'runtimeTimingEvents': events.length,
            'tasks': tasks.values.toList(),
            'actualDeviceSlowCauseEstablished': false,
            'firstFrameAndRevealMeasured': false,
          }),
        );
      }
    } finally {
      RuntimeLog.instance = previousLog;
    }
  });

  test(
    'create makes an empty versioned root immediately and requests no media',
    () async {
      final repo = await create();
      expect(repo.mediaBaseUri.scheme, 'file');
      expect(
        repo.mediaBaseUri.path.endsWith('/r1-v3/${fixture.revision}/'),
        isTrue,
      );
      expect(await Directory.fromUri(repo.mediaBaseUri).exists(), isTrue);
      expect(await Directory.fromUri(repo.mediaBaseUri).list().isEmpty, isTrue);
      expect(requested, isEmpty);
    },
  );

  test(
    'ensureAction prepares only its three files and merges repeated calls',
    () async {
      final repo = await create();
      final first = repo.ensureAction(fixture.first.id);
      expect(repo.ensureAction(fixture.first.id), same(first));
      expect(await first, repo.mediaBaseUri);
      expect(
        requested.toSet(),
        fixture.first.files.values.map((f) => '/${f.path}').toSet(),
      );
      expect(requested.length, 3);
      for (final file in fixture.first.files.values) {
        expect(
          await File.fromUri(file.resolve(repo.mediaBaseUri)).readAsBytes(),
          fixture.bodies[file.path],
        );
      }
      expect(
        repo.watchAction(fixture.first.id).value.phase,
        PoseHubDownloadPhase.ready,
      );
      await noParts(repo);
    },
  );

  test(
    'same file Future and same SHA across distinct paths share one HTTP job',
    () async {
      fixture = _Fixture(sharedVideos: true);
      final repo = await create();
      final a = fixture.catalog.allActions[0].video;
      final b = fixture.catalog.allActions[1].video;
      final first = repo.ensureFile(a);
      expect(repo.ensureFile(a), same(first));
      final uris = await Future.wait([first, repo.ensureFile(b)]);
      expect(requested.length, 1);
      expect(uris, [
        a.resolve(repo.mediaBaseUri),
        b.resolve(repo.mediaBaseUri),
      ]);
      expect(await File.fromUri(uris[1]).readAsBytes(), fixture.bodies[b.path]);
    },
  );

  test(
    'valid cache survives repository restart and works without a source URL',
    () async {
      final first = await create();
      final file = fixture.first.video;
      final uri = await first.ensureFile(file);
      first.dispose();
      final second = await create(offline: true);
      expect(await second.ensureFile(file), uri);
      expect(requested.length, 1);
      expect(second.watchFile(file).value.phase, PoseHubDownloadPhase.ready);
    },
  );

  test(
    'same-size corrupted cache is verified and replaced only by valid bytes',
    () async {
      final repo = await create();
      final file = fixture.first.video;
      final uri = await repo.ensureFile(file);
      await File.fromUri(uri).writeAsBytes(Uint8List(file.bytes));
      expect(await repo.ensureFile(file), uri);
      expect(requested.length, 2);
      expect(await File.fromUri(uri).readAsBytes(), fixture.bodies[file.path]);
    },
  );

  test(
    'v2 native and previous cache roots are never reused even for identical SHA',
    () async {
      final file = fixture.first.video;
      final previousRoots = [
        Directory('${support.path}/posehub/app-test-pack-r1-v2'),
        Directory('${support.path}/posehub-media/${fixture.revision}'),
        Directory('${support.path}/posehub-media/r1-v2/${fixture.revision}'),
      ];
      final oldFiles = <File>[];
      for (final root in previousRoots) {
        final old = File.fromUri(root.uri.resolve(file.path));
        await old.parent.create(recursive: true);
        await old.writeAsBytes(fixture.bodies[file.path]!);
        oldFiles.add(old);
      }
      final userData = File('${support.path}/keep-user-data')
        ..writeAsStringSync('preserved');
      final repo = await create(offline: true);
      await expectLater(
        repo.ensureFile(file),
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
      expect(
        await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
        isFalse,
      );
      for (final old in oldFiles) {
        expect(await old.readAsBytes(), fixture.bodies[file.path]);
      }
      expect(await userData.readAsString(), 'preserved');
      expect(requested, isEmpty);
      final online = await create();
      await online.ensureFile(file);
      expect(requested, ['/${file.path}']);
    },
  );

  test(
    'bundled small images are verified, remain unchanged and never fetch videos',
    () async {
      final loaded = <String>[];
      final repo = await create(
        bundled: (file) async {
          expect(file.path.endsWith('.webp'), isTrue);
          loaded.add(file.path);
          return fixture.bodies[file.path];
        },
      );
      final coverBefore = Uint8List.fromList(
        fixture.bodies[fixture.first.cover.path]!,
      );
      await repo.ensureAction(fixture.first.id);
      expect(loaded.toSet(), {
        fixture.first.cover.path,
        fixture.first.thumbnail.path,
      });
      expect(requested, ['/${fixture.first.video.path}']);
      expect(fixture.bodies[fixture.first.cover.path], coverBefore);
    },
  );

  test(
    'bad bundled SHA fails without falling through to HTTP and can retry',
    () async {
      var bad = true;
      final repo = await create(
        bundled: (file) async =>
            bad ? Uint8List(file.bytes) : fixture.bodies[file.path],
      );
      await expectLater(
        repo.ensureFile(fixture.first.cover),
        throwsA(
          isA<PoseHubMediaException>().having((e) => e.code, 'code', 'sha256'),
        ),
      );
      expect(requested, isEmpty);
      await noParts(repo);
      bad = false;
      await repo.ensureFile(fixture.first.cover);
      expect(
        repo.watchFile(fixture.first.cover).value.phase,
        PoseHubDownloadPhase.ready,
      );
    },
  );

  test(
    '302 across hosts follows a relative public transport with no private headers',
    () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => other.close(force: true));
      final got = Completer<HttpHeaders>();
      other.listen((request) async {
        got.complete(request.headers);
        final bytes = fixture.bodies[fixture.first.video.path]!;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      handler = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          'http://localhost:${other.port}/asset?signed=DO_NOT_LOG',
        );
        request.response.cookies.add(Cookie('private', 'DO_NOT_FORWARD'));
        await request.response.close();
      };
      final repo = await create();
      await repo.ensureFile(fixture.first.video);
      final headers = await got.future;
      expect(headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(headers.value(HttpHeaders.cookieHeader), isNull);
      expect(requested.length, 1);
    },
  );

  test(
    'redirect loops are bounded and expose no signed URI in error/state',
    () async {
      handler = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/loop?signed=DO_NOT_LOG',
        );
        await request.response.close();
      };
      final repo = await create(redirects: 2);
      final file = fixture.first.video;
      await expectLater(
        repo.ensureFile(file),
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'redirect',
          ),
        ),
      );
      expect(requested.length, 3);
      expect(
        repo.watchFile(file).value.error.toString(),
        isNot(contains('DO_NOT_LOG')),
      );
      expect(
        repo.watchFile(file).value.error.toString(),
        isNot(contains('http')),
      );
      await noParts(repo);
    },
  );

  test('unsafe redirect target is rejected before contacting it', () async {
    handler = (request) async {
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://example.invalid/secret?key=DO_NOT_LOG',
      );
      await request.response.close();
    };
    final repo = await create();
    await expectLater(
      repo.ensureFile(fixture.first.video),
      throwsA(
        isA<PoseHubMediaException>().having(
          (e) => e.code,
          'code',
          'invalid_url',
        ),
      ),
    );
    expect(requested.length, 1);
  });

  test(
    'truncated real HTTP body fails, cleans temporary files and retries',
    () async {
      var truncate = true;
      handler = (request) async {
        final bytes = fixture.bodies[fixture.first.video.path]!;
        request.response.contentLength = bytes.length;
        if (truncate) {
          final socket = await request.response.detachSocket();
          socket.add(bytes.sublist(0, bytes.length ~/ 2));
          await socket.flush();
          socket.destroy();
        } else {
          request.response.add(bytes);
          await request.response.close();
        }
      };
      final repo = await create();
      await expectLater(
        repo.ensureFile(fixture.first.video),
        throwsA(isA<PoseHubMediaException>()),
      );
      await noParts(repo);
      expect(
        await File.fromUri(
          fixture.first.video.resolve(repo.mediaBaseUri),
        ).exists(),
        isFalse,
      );
      truncate = false;
      await repo.ensureFile(fixture.first.video);
      expect(requested.length, 2);
    },
  );

  for (final mode in ['header', 'overflow', 'sha']) {
    test(
      '$mode mismatch is not published and leaves no temporary file',
      () async {
        handler = (request) async {
          final original = fixture.bodies[fixture.first.video.path]!;
          if (mode == 'header') {
            request.response.contentLength = 0;
          } else if (mode == 'overflow') {
            request.response.add([...original, 1]);
          } else {
            request.response.contentLength = original.length;
            request.response.add(Uint8List(original.length));
          }
          await request.response.close();
        };
        final repo = await create();
        await expectLater(
          repo.ensureFile(fixture.first.video),
          throwsA(isA<PoseHubMediaException>()),
        );
        await noParts(repo);
        expect(
          await File.fromUri(
            fixture.first.video.resolve(repo.mediaBaseUri),
          ).exists(),
          isFalse,
        );
        expect(
          repo.watchAction(fixture.first.id).value.phase,
          PoseHubDownloadPhase.failed,
        );
      },
    );
  }

  test(
    'HTTP errors remain observable and a manual retry starts a new request',
    () async {
      var fail = true;
      handler = (request) async {
        if (fail) {
          request.response.statusCode = 503;
        } else {
          final bytes = fixture.bodies[fixture.first.video.path]!;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close();
      };
      final repo = await create();
      await expectLater(
        repo.ensureFile(fixture.first.video),
        throwsA(isA<PoseHubMediaException>()),
      );
      expect(
        repo.watchFile(fixture.first.video).value.phase,
        PoseHubDownloadPhase.failed,
      );
      fail = false;
      await repo.ensureFile(fixture.first.video);
      expect(repo.watchFile(fixture.first.video).value.error, isNull);
      expect(requested.length, 2);
    },
  );

  test(
    'bounded concurrency queues files and never starts unrelated action work',
    () async {
      fixture = _Fixture(actions: 4);
      final gate = Completer<void>();
      var active = 0;
      var highest = 0;
      handler = (request) async {
        active++;
        if (active > highest) highest = active;
        await gate.future;
        final bytes = fixture.bodies[request.uri.path.substring(1)]!;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
        active--;
      };
      final repo = await PoseHubMediaRepository.forTesting(
        catalog: fixture.catalog,
        catalogRevision: fixture.revision,
        mediaBaseUrls: [base],
        rootDirectory: support.path,
        allowInsecureLocalhost: true,
      );
      repositories.add(repo);
      final work = Future.wait(
        fixture.catalog.allActions.take(3).map((a) => repo.ensureFile(a.video)),
      );
      await _until(() => requested.length == 2);
      expect(
        fixture.catalog.allActions
            .take(3)
            .where(
              (action) =>
                  repo.watchFile(action.video).value.phase ==
                  PoseHubDownloadPhase.queued,
            )
            .length,
        1,
      );
      gate.complete();
      await work;
      expect(highest, 2);
      expect(requested, [
        for (final action in fixture.catalog.allActions.take(3))
          '/${action.video.path}',
      ]);
      expect(requested.length, 3);
      expect(requested.any((path) => path.contains('action-3')), isFalse);
    },
  );

  test(
    'file and action progress are throttled while a lone cover is downloading',
    () async {
      fixture = _Fixture(coverBytes: 16384);
      final cover = fixture.first.cover;
      handler = (request) async {
        final bytes = fixture.bodies[cover.path]!;
        request.response.bufferOutput = false;
        request.response.contentLength = bytes.length;
        for (var i = 0; i < bytes.length; i += 256) {
          request.response.add(bytes.sublist(i, i + 256));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 3));
        }
        await request.response.close();
      };
      final repo = await create(
        progressInterval: const Duration(milliseconds: 25),
      );
      final fileStates = <PoseHubDownloadState>[];
      final actionStates = <PoseHubDownloadState>[];
      final fileWatch = repo.watchFile(cover);
      final actionWatch = repo.watchAction(fixture.first.id);
      fileWatch.addListener(() => fileStates.add(fileWatch.value));
      actionWatch.addListener(() => actionStates.add(actionWatch.value));
      await repo.ensureFile(cover);
      expect(fileStates.last.phase, PoseHubDownloadPhase.ready);
      expect(fileStates.last.receivedBytes, cover.bytes);
      final downloading = fileStates
          .where((s) => s.phase == PoseHubDownloadPhase.downloading)
          .toList();
      expect(
        downloading.any(
          (s) => s.receivedBytes > 0 && s.receivedBytes < cover.bytes,
        ),
        isTrue,
      );
      expect(downloading.length, lessThan(20));
      expect(
        actionStates.any((s) => s.phase == PoseHubDownloadPhase.downloading),
        isTrue,
      );
      expect(requested, ['/${cover.path}']);
    },
  );

  test(
    'base URL resolves the original nested catalog path without flat mapping',
    () async {
      final file = fixture.first.video;
      handler = (request) async {
        expect(request.uri.path, '/pack/r1-v3/${file.path}');
        final bytes = fixture.bodies[file.path]!;
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      };
      final repo = await create(mediaBases: [base.resolve('pack/r1-v3/')]);
      await repo.ensureFile(file);
      expect(requested, ['/pack/r1-v3/${file.path}']);
    },
  );

  test(
    'separate catalog hashes isolate files and unknown descriptors are rejected',
    () async {
      final first = await create();
      final second = await create(revision: 'a' * 64);
      expect(first.mediaBaseUri, isNot(second.mediaBaseUri));
      final unknown = coach.PoseHubPackFile.fromJson({
        'path': 'media/unknown/video.mp4',
        'bytes': 1,
        'sha256': '0' * 64,
      });
      await expectLater(first.ensureFile(unknown), throwsFormatException);
      expect(requested, isEmpty);
    },
  );

  test(
    'production creation never accepts HTTP or credential/query base URLs',
    () async {
      for (final url in [
        base,
        Uri.parse('https://user:secret@example.invalid/'),
        Uri.parse('https://example.invalid/?key=secret'),
      ]) {
        await expectLater(
          PoseHubMediaRepository.create(
            catalog: fixture.catalog,
            catalogRevision: fixture.revision,
            mediaBaseUrls: [url],
            rootDirectory: support.path,
          ),
          throwsA(anything),
        );
      }
      expect(requested, isEmpty);
    },
  );

  test(
    'partial bytes remain unpublished until complete verification',
    () async {
      fixture = _Fixture(videoBytes: 32768);
      final gate = Completer<void>();
      handler = (request) async {
        final bytes = fixture.bodies[fixture.first.video.path]!;
        request.response.bufferOutput = false;
        request.response.contentLength = bytes.length;
        request.response.add(bytes.sublist(0, bytes.length ~/ 2));
        await request.response.flush();
        await gate.future;
        request.response.add(bytes.sublist(bytes.length ~/ 2));
        await request.response.close();
      };
      final repo = await create(progressInterval: Duration.zero);
      final file = fixture.first.video;
      final work = repo.ensureFile(file);
      try {
        await _until(() => repo.watchFile(file).value.receivedBytes > 0);
        expect(
          await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
          isFalse,
        );
      } finally {
        gate.complete();
      }
      final uri = await work;
      expect(await File.fromUri(uri).readAsBytes(), fixture.bodies[file.path]);
      await noParts(repo);
    },
  );

  test(
    'idle response timeout cleans temporary output and exposes a safe error',
    () async {
      final gate = Completer<void>();
      handler = (request) async {
        request.response.bufferOutput = false;
        request.response.contentLength = fixture.first.video.bytes;
        request.response.add([fixture.bodies[fixture.first.video.path]!.first]);
        await request.response.flush();
        await gate.future;
        await request.response.close();
      };
      final repo = await create(timeout: const Duration(milliseconds: 100));
      try {
        await expectLater(
          repo.ensureFile(fixture.first.video),
          throwsA(
            isA<PoseHubMediaException>().having(
              (e) => e.code,
              'code',
              'timeout',
            ),
          ),
        );
        await noParts(repo);
      } finally {
        gate.complete();
      }
    },
  );

  test(
    'disposed repository refuses further work without deleting cached files',
    () async {
      final repo = await create();
      final uri = await repo.ensureFile(fixture.first.video);
      repo.dispose();
      await expectLater(
        repo.ensureFile(fixture.first.video),
        throwsA(isA<PoseHubMediaException>()),
      );
      expect(await File.fromUri(uri).exists(), isTrue);
    },
  );

  test(
    'empty media bases fail closed without any guessed download URL',
    () async {
      final repo = await create(mediaBases: []);
      await expectLater(
        repo.ensureFile(fixture.first.video),
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
      expect(requested, isEmpty);
      await noParts(repo);
    },
  );

  for (final failure in ['http', 'bytes', 'sha256', 'truncated', 'timeout']) {
    test(
      'ordered mirror fallback after $failure cleans partial output',
      () async {
        final file = fixture.first.video;
        final bytes = fixture.bodies[file.path]!;
        final release = Completer<void>();
        late PoseHubMediaRepository repo;
        handler = (request) async {
          if (request.uri.path.startsWith('/primary/')) {
            expect(request.uri.path, '/primary/${file.path}');
            if (failure == 'http') {
              request.response.statusCode = 503;
            } else if (failure == 'bytes') {
              request.response.contentLength = 0;
            } else if (failure == 'sha256') {
              request.response.contentLength = bytes.length;
              request.response.add(Uint8List(bytes.length));
            } else if (failure == 'truncated') {
              request.response.contentLength = bytes.length;
              final socket = await request.response.detachSocket();
              socket.add(bytes.sublist(0, bytes.length ~/ 2));
              await socket.flush();
              socket.destroy();
              return;
            } else {
              request.response.bufferOutput = false;
              request.response.contentLength = bytes.length;
              request.response.add(bytes.sublist(0, 1));
              await request.response.flush();
              await release.future;
            }
            await request.response.close();
            return;
          }
          expect(request.uri.path, '/backup/${file.path}');
          await noParts(repo);
          expect(
            await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
            isFalse,
          );
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        };
        repo = await create(
          mediaBases: [base.resolve('primary/'), base.resolve('backup/')],
          timeout: const Duration(milliseconds: 150),
        );
        try {
          final uri = await repo.ensureFile(file);
          expect(await File.fromUri(uri).readAsBytes(), bytes);
          expect(requested, ['/primary/${file.path}', '/backup/${file.path}']);
          expect(repo.watchFile(file).value.phase, PoseHubDownloadPhase.ready);
          expect(repo.watchFile(file).value.error, isNull);
          await noParts(repo);
        } finally {
          release.complete();
        }
      },
    );
  }

  test(
    'a failed primary connection automatically tries the next base',
    () async {
      final unavailable = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final deadBase = Uri.parse('http://127.0.0.1:${unavailable.port}/');
      await unavailable.close(force: true);
      final repo = await create(mediaBases: [deadBase, base]);
      final file = fixture.first.video;
      final uri = await repo.ensureFile(file);
      expect(await File.fromUri(uri).readAsBytes(), fixture.bodies[file.path]);
      expect(requested, ['/${file.path}']);
      await noParts(repo);
    },
  );

  test('all failed mirrors leave no published file or partial data', () async {
    handler = (request) async {
      request.response.contentLength = fixture.first.video.bytes;
      request.response.add(Uint8List(fixture.first.video.bytes));
      await request.response.close();
    };
    final repo = await create(
      mediaBases: [base.resolve('first/'), base.resolve('second/')],
    );
    final file = fixture.first.video;
    await expectLater(
      repo.ensureFile(file),
      throwsA(
        isA<PoseHubMediaException>().having((e) => e.code, 'code', 'sha256'),
      ),
    );
    expect(requested, ['/first/${file.path}', '/second/${file.path}']);
    expect(
      await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
      isFalse,
    );
    expect(repo.watchFile(file).value.phase, PoseHubDownloadPhase.failed);
    await noParts(repo);
  });

  test(
    'pack versions isolate the same catalog SHA and never share cache files',
    () async {
      final older = await create(packVersion: 'r1-v2');
      final file = fixture.first.video;
      await older.ensureFile(file);
      final current = await create(offline: true);
      expect(current.mediaBaseUri, isNot(older.mediaBaseUri));
      expect(
        current.mediaBaseUri.path.endsWith('/r1-v3/${fixture.revision}/'),
        isTrue,
      );
      await expectLater(
        current.ensureFile(file),
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
      expect(
        await File.fromUri(file.resolve(older.mediaBaseUri)).readAsBytes(),
        fixture.bodies[file.path],
      );
      expect(requested.length, 1);
    },
  );

  test(
    'global video usage and clear preserve images, data and unknown versions',
    () async {
      final repo = await create(
        bundled: (file) async => fixture.bodies[file.path],
      );
      expect(repo, isA<PoseHubVideoCache>());
      final cache = repo as PoseHubVideoCache;
      await repo.ensureAction(fixture.first.id);
      await repo.ensureFile(fixture.catalog.allActions.last.video);
      final video = fixture.first.video;
      final target = File.fromUri(video.resolve(repo.mediaBaseUri));
      expect(
        await cache.videoCacheBytes(),
        fixture.catalog.allActions.fold<int>(
          0,
          (n, action) => n + action.video.bytes,
        ),
      );
      // Usage counts actual published video bytes, rather than image/metadata sizes.
      await target.writeAsBytes([1, 2, 3]);
      final stale = File('${target.path}.123_456_789.part');
      await stale.writeAsBytes([4, 5]);
      final preserved = <File, List<int>>{};
      for (final directory in [
        '${support.path}/training-data',
        '${support.path}/posehub/app-test-pack-r1-v2',
        '${support.path}/posehub-media/r1-v2/${fixture.revision}',
        '${support.path}/posehub-media/r1-v3/${'b' * 64}',
      ]) {
        final isTrainingData = directory.endsWith('/training-data');
        final keep = isTrainingData
            ? File('$directory/history.json')
            : File.fromUri(Directory(directory).uri.resolve(video.path));
        final bytes = isTrainingData
            ? utf8.encode('keep-user-data')
            : utf8.encode('unrecognized-old-video');
        await keep.parent.create(recursive: true);
        await keep.writeAsBytes(bytes);
        preserved[keep] = bytes;
      }
      final unknownBytes = preserved.entries
          .where((entry) => entry.key.path.contains('posehub-media'))
          .fold<int>(0, (n, entry) => n + entry.value.length);
      expect(
        await cache.videoCacheBytes(),
        3 + fixture.catalog.allActions.last.video.bytes + unknownBytes,
      );
      await cache.clearVideoCache();
      expect(await cache.videoCacheBytes(), unknownBytes);
      expect(await stale.exists(), isFalse);
      for (final action in fixture.catalog.allActions) {
        expect(
          await File.fromUri(action.video.resolve(repo.mediaBaseUri)).exists(),
          isFalse,
        );
      }
      for (final image in [fixture.first.cover, fixture.first.thumbnail]) {
        expect(
          await File.fromUri(image.resolve(repo.mediaBaseUri)).readAsBytes(),
          fixture.bodies[image.path],
        );
      }
      for (final keep in preserved.entries) {
        expect(await keep.key.readAsBytes(), keep.value);
      }
      await noParts(repo);
    },
  );

  test(
    'clear cancels in-flight video and prevents late publish before redownload',
    () async {
      fixture = _Fixture(videoBytes: 32768);
      final release = Completer<void>();
      final oldServerDone = Completer<void>();
      var firstRequest = true;
      handler = (request) async {
        final bytes = fixture.bodies[fixture.first.video.path]!;
        if (!firstRequest) {
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
          return;
        }
        firstRequest = false;
        try {
          request.response.bufferOutput = false;
          request.response.contentLength = bytes.length;
          request.response.add(bytes.sublist(0, bytes.length ~/ 2));
          await request.response.flush();
          await release.future;
          request.response.add(bytes.sublist(bytes.length ~/ 2));
          await request.response.close();
        } catch (_) {
          // The client intentionally closes this socket during cache retirement.
        } finally {
          oldServerDone.complete();
        }
      };
      final repo = await create(progressInterval: Duration.zero);
      final cache = repo as PoseHubVideoCache;
      final file = fixture.first.video;
      final old = repo.ensureFile(file);
      final cancelled = expectLater(
        old,
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'cache_cleared',
          ),
        ),
      );
      try {
        await _until(() => repo.watchFile(file).value.receivedBytes > 0);
        final clearing = cache.clearVideoCache();
        expect(cache.clearVideoCache(), same(clearing));
        await clearing.timeout(const Duration(seconds: 2));
        await cancelled;
        expect(await cache.videoCacheBytes(), 0);
        expect(
          await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
          isFalse,
        );
        await noParts(repo);
        release.complete();
        await oldServerDone.future;
        expect(
          await File.fromUri(file.resolve(repo.mediaBaseUri)).exists(),
          isFalse,
        );
        await noParts(repo);
        final uri = await repo.ensureFile(file);
        expect(
          await File.fromUri(uri).readAsBytes(),
          fixture.bodies[file.path],
        );
        expect(await cache.videoCacheBytes(), file.bytes);
        expect(requested.length, 2);
      } finally {
        if (!release.isCompleted) release.complete();
      }
    },
  );

  test(
    'queued old videos settle and new requests wait for the clear barrier',
    () async {
      fixture = _Fixture(videoBytes: 32768);
      final release = Completer<void>();
      var firstRequest = true;
      var cleared = false;
      handler = (request) async {
        final bytes = fixture.bodies[request.uri.path.substring(1)]!;
        if (firstRequest) {
          firstRequest = false;
          try {
            request.response.bufferOutput = false;
            request.response.contentLength = bytes.length;
            request.response.add(bytes.sublist(0, bytes.length ~/ 2));
            await request.response.flush();
            await release.future;
            request.response.add(bytes.sublist(bytes.length ~/ 2));
            await request.response.close();
          } catch (_) {}
        } else {
          expect(
            cleared,
            isTrue,
            reason: 'No new transport can start before clear completes.',
          );
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        }
      };
      final repo = await create(
        concurrent: 1,
        progressInterval: Duration.zero,
        bundled: (file) async => fixture.bodies[file.path],
      );
      final cache = repo as PoseHubVideoCache;
      final first = fixture.first.video;
      final second = fixture.catalog.allActions.last.video;
      final old = repo.ensureFile(first);
      final oldCancelled = expectLater(
        old,
        throwsA(isA<PoseHubMediaException>()),
      );
      await _until(() => repo.watchFile(first).value.receivedBytes > 0);
      final queued = repo.ensureFile(second);
      final queuedCancelled = expectLater(
        queued,
        throwsA(isA<PoseHubMediaException>()),
      );
      await _until(
        () => repo.watchFile(second).value.phase == PoseHubDownloadPhase.queued,
      );
      final clearing = cache.clearVideoCache();
      clearing.then<void>((_) {
        cleared = true;
      });
      final next = repo.ensureFile(second);
      expect(repo.ensureFile(second), same(next));
      final nextAction = repo.ensureAction(fixture.catalog.allActions.last.id);
      expect(
        repo.ensureAction(fixture.catalog.allActions.last.id),
        same(nextAction),
      );
      try {
        await clearing.timeout(const Duration(seconds: 2));
        await Future.wait([oldCancelled, queuedCancelled]);
        expect(await next, second.resolve(repo.mediaBaseUri));
        expect(await nextAction, repo.mediaBaseUri);
        expect(requested, ['/${first.path}', '/${second.path}']);
        expect(await cache.videoCacheBytes(), second.bytes);
        await noParts(repo);
      } finally {
        release.complete();
      }
    },
  );

  test(
    'clearing videos preserves a healthy in-flight image download',
    () async {
      fixture = _Fixture(videoBytes: 49152, coverBytes: 32768);
      final imageGate = Completer<void>();
      final videoGate = Completer<void>();
      handler = (request) async {
        final bytes = fixture.bodies[request.uri.path.substring(1)]!;
        final isVideo = request.uri.path.endsWith('.mp4');
        try {
          request.response.bufferOutput = false;
          request.response.contentLength = bytes.length;
          request.response.add(bytes.sublist(0, bytes.length ~/ 2));
          await request.response.flush();
          await (isVideo ? videoGate.future : imageGate.future);
          request.response.add(bytes.sublist(bytes.length ~/ 2));
          await request.response.close();
        } catch (_) {}
      };
      final repo = await create(progressInterval: Duration.zero);
      final cache = repo as PoseHubVideoCache;
      final image = fixture.first.cover;
      final video = fixture.first.video;
      final imageWork = repo.ensureFile(image);
      final videoWork = repo.ensureFile(video);
      final cancelled = expectLater(
        videoWork,
        throwsA(isA<PoseHubMediaException>()),
      );
      try {
        await _until(
          () =>
              repo.watchFile(image).value.receivedBytes > 0 &&
              repo.watchFile(video).value.receivedBytes > 0,
        );
        await cache.clearVideoCache().timeout(const Duration(seconds: 2));
        await cancelled;
        expect(await cache.videoCacheBytes(), 0);
        imageGate.complete();
        final uri = await imageWork;
        expect(
          await File.fromUri(uri).readAsBytes(),
          fixture.bodies[image.path],
        );
        expect(repo.watchFile(image).value.phase, PoseHubDownloadPhase.ready);
        videoGate.complete();
        await noParts(repo);
      } finally {
        if (!imageGate.isCompleted) imageGate.complete();
        if (!videoGate.isCompleted) videoGate.complete();
      }
    },
  );

  test(
    'cache-only lookup validates, touches and never requests a miss',
    () async {
      final repo = await create();
      final access = repo as PoseHubVideoCacheAccess;
      final action = fixture.first;
      expect(await access.cachedVideo(action.id), isNull);
      expect(requested, isEmpty);
      final uri = await repo.ensureFile(action.video);
      final file = File.fromUri(uri);
      final old = DateTime.utc(2020);
      await file.setLastModified(old);
      expect(await access.cachedVideo(action.id), uri);
      expect((await file.lastModified()).isAfter(old), isTrue);
      expect(requested, ['/${action.video.path}']);
      await file.writeAsBytes(Uint8List(action.video.bytes));
      expect(await access.cachedVideo(action.id), isNull);
      expect(requested, ['/${action.video.path}']);
      expect(
        repo.watchFile(action.video).value.phase,
        PoseHubDownloadPhase.idle,
      );
    },
  );

  test(
    'cache hits persist their LRU order across repository restart',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final first = await create(cacheBytes: 8192);
      await first.ensureFile(actions[0].video);
      await first.ensureFile(actions[1].video);
      final a = File.fromUri(actions[0].video.resolve(first.mediaBaseUri));
      final b = File.fromUri(actions[1].video.resolve(first.mediaBaseUri));
      await a.setLastModified(DateTime.utc(2020));
      await b.setLastModified(DateTime.utc(2021));
      await (first as PoseHubVideoCacheAccess).cachedVideo(actions[0].id);
      final lastUse = await a.lastModified();
      expect(lastUse.isAfter(await b.lastModified()), isTrue);
      first.dispose();
      final reopened = await create(cacheBytes: 8192);
      expect(await a.lastModified(), lastUse);
      await reopened.ensureFile(actions[2].video);
      expect(await a.exists(), isTrue);
      expect(await b.exists(), isFalse);
      expect(await (reopened as PoseHubVideoCache).videoCacheBytes(), 8192);
      expect(requested, [
        for (final action in actions) '/${action.video.path}',
      ]);
      await noParts(reopened);
    },
  );

  test(
    'reopening enforces the cap on older unbounded published videos',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final first = await create();
      for (var index = 0; index < actions.length; index++) {
        final uri = await first.ensureFile(actions[index].video);
        await File.fromUri(uri).setLastModified(DateTime.utc(2020 + index));
      }
      first.dispose();
      final current = await create(cacheBytes: 8192, offline: true);
      expect(await (current as PoseHubVideoCache).videoCacheBytes(), 8192);
      expect(
        await File.fromUri(
          actions[0].video.resolve(current.mediaBaseUri),
        ).exists(),
        isFalse,
      );
      for (final action in actions.skip(1)) {
        expect(
          await File.fromUri(
            action.video.resolve(current.mediaBaseUri),
          ).exists(),
          isTrue,
        );
      }
      expect(requested, hasLength(3));
    },
  );

  test(
    'reference-counted playing pins reject additions and release idempotently',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final repo = await create(cacheBytes: 4096);
      final access = repo as PoseHubVideoCacheAccess;
      final firstUri = await repo.ensureFile(actions[0].video);
      final releaseOne = access.retainVideo(actions[0].id);
      final releaseTwo = access.retainVideo(actions[0].id);
      final full = isA<PoseHubMediaException>().having(
        (e) => e.code,
        'code',
        'cache_full',
      );
      await expectLater(repo.ensureFile(actions[1].video), throwsA(full));
      expect(
        await File.fromUri(firstUri).readAsBytes(),
        fixture.bodies[actions[0].video.path],
      );
      releaseOne();
      releaseOne();
      await expectLater(repo.ensureFile(actions[2].video), throwsA(full));
      expect(await (repo as PoseHubVideoCache).videoCacheBytes(), 4096);
      await noParts(repo);
      releaseTwo();
      releaseTwo();
      await repo.ensureFile(actions[1].video);
      expect(await File.fromUri(firstUri).exists(), isFalse);
      expect(await access.cachedVideo(actions[1].id), isNotNull);
      await noParts(repo);
    },
  );

  test(
    'insufficient unpinned room preserves every old file before rejecting',
    () async {
      fixture = _Fixture(actions: 3, videoSizes: [4096, 4096, 8192]);
      final actions = fixture.catalog.allActions.toList();
      final repo = await create(cacheBytes: 8192);
      await repo.ensureFile(actions[0].video);
      await repo.ensureFile(actions[1].video);
      final release = (repo as PoseHubVideoCacheAccess).retainVideo(
        actions[1].id,
      );
      try {
        await expectLater(
          repo.ensureFile(actions[2].video),
          throwsA(
            isA<PoseHubMediaException>().having(
              (e) => e.code,
              'code',
              'cache_full',
            ),
          ),
        );
        for (final action in actions.take(2)) {
          expect(
            await File.fromUri(
              action.video.resolve(repo.mediaBaseUri),
            ).readAsBytes(),
            fixture.bodies[action.video.path],
          );
        }
        expect(await (repo as PoseHubVideoCache).videoCacheBytes(), 8192);
        await noParts(repo);
      } finally {
        release();
      }
    },
  );

  test(
    'same-root handles serialize concurrent publication under one cap',
    () async {
      fixture = _Fixture(actions: 4);
      final actions = fixture.catalog.allActions.toList();
      final first = await create(cacheBytes: 8192);
      await first.ensureFile(actions[0].video);
      await first.ensureFile(actions[1].video);
      final second = await create(cacheBytes: 8192);
      final snapshots = <Future<int>>[];
      for (final (repo, action) in [
        (first, actions[2]),
        (second, actions[3]),
      ]) {
        final state = repo.watchFile(action.video);
        state.addListener(() {
          if (state.value.phase == PoseHubDownloadPhase.ready) {
            snapshots.add((repo as PoseHubVideoCache).videoCacheBytes());
          }
        });
      }
      await Future.wait([
        first.ensureFile(actions[2].video),
        second.ensureFile(actions[3].video),
      ]);
      expect(await (first as PoseHubVideoCache).videoCacheBytes(), 8192);
      expect(
        await Future.wait(snapshots),
        everyElement(lessThanOrEqualTo(8192)),
      );
      for (final action in actions.take(2)) {
        expect(
          await File.fromUri(action.video.resolve(first.mediaBaseUri)).exists(),
          isFalse,
        );
      }
      for (final action in actions.skip(2)) {
        expect(
          await File.fromUri(action.video.resolve(first.mediaBaseUri)).exists(),
          isTrue,
        );
      }
      await noParts(first);
    },
  );

  test(
    'LRU budgets unknown version videos while preserving images and parts',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final repo = await create(
        cacheBytes: 8192,
        bundled: (file) async => fixture.bodies[file.path],
      );
      await repo.ensureAction(actions[0].id);
      await repo.ensureFile(actions[1].video);
      final oldest = File.fromUri(actions[0].video.resolve(repo.mediaBaseUri));
      await oldest.setLastModified(DateTime.utc(2020));
      final preserved = <File>[
        File('${oldest.path}.123_456_789.part'),
        File('${oldest.parent.path}/unknown.mp4'),
        File(
          '${support.path}/posehub-media/r1-v2/${fixture.revision}/media/other/video.mp4',
        ),
        File(
          '${support.path}/posehub-media/r1-v3/${'b' * 64}/media/other/video.mp4',
        ),
        File('${support.path}/posehub-media/${'d' * 64}/media/other/video.mp4'),
      ];
      for (final file in preserved) {
        await file.parent.create(recursive: true);
        await file.writeAsString('preserved');
      }
      await repo.ensureFile(actions[2].video);
      expect(await oldest.exists(), isFalse);
      for (final file in preserved) {
        expect(await file.readAsString(), 'preserved');
      }
      for (final image in [actions[0].cover, actions[0].thumbnail]) {
        expect(
          await File.fromUri(image.resolve(repo.mediaBaseUri)).readAsBytes(),
          fixture.bodies[image.path],
        );
      }
      expect(
        await (repo as PoseHubVideoCache).videoCacheBytes(),
        actions[2].video.bytes + 4 * utf8.encode('preserved').length,
      );
    },
  );

  test('bad incoming hash cannot evict a healthy old cached video', () async {
    final repo = await create(cacheBytes: 4096);
    final first = fixture.first.video;
    final second = fixture.catalog.allActions.last.video;
    final original = await repo.ensureFile(first);
    handler = (request) async {
      request.response.contentLength = second.bytes;
      request.response.add(Uint8List(second.bytes));
      await request.response.close();
    };
    await expectLater(
      repo.ensureFile(second),
      throwsA(
        isA<PoseHubMediaException>().having((e) => e.code, 'code', 'sha256'),
      ),
    );
    expect(
      await File.fromUri(original).readAsBytes(),
      fixture.bodies[first.path],
    );
    expect(await (repo as PoseHubVideoCache).videoCacheBytes(), 4096);
    await noParts(repo);
  });

  test('clear and a second handle preserve a retained playing video', () async {
    final first = await create(cacheBytes: 4096);
    final uri = await first.ensureFile(fixture.first.video);
    final access = first as PoseHubVideoCacheAccess;
    final release = access.retainVideo(fixture.first.id);
    final second = await create(cacheBytes: 4096);
    await (second as PoseHubVideoCache).clearVideoCache();
    expect(await File.fromUri(uri).exists(), isTrue);
    await expectLater(
      second.ensureFile(fixture.catalog.allActions.last.video),
      throwsA(
        isA<PoseHubMediaException>().having(
          (e) => e.code,
          'code',
          'cache_full',
        ),
      ),
    );
    release();
    await (second as PoseHubVideoCache).clearVideoCache();
    expect(await File.fromUri(uri).exists(), isFalse);
  });

  test('an unsafe publish destination cannot evict any old video', () async {
    fixture = _Fixture(actions: 3);
    final actions = fixture.catalog.allActions.toList();
    final repo = await create(cacheBytes: 8192);
    await repo.ensureFile(actions[0].video);
    await repo.ensureFile(actions[1].video);
    final invalid = Directory.fromUri(
      actions[2].video.resolve(repo.mediaBaseUri),
    );
    await invalid.create(recursive: true);
    await expectLater(
      repo.ensureFile(actions[2].video),
      throwsA(
        isA<PoseHubMediaException>().having(
          (e) => e.code,
          'code',
          'unsafe_cache',
        ),
      ),
    );
    for (final action in actions.take(2)) {
      expect(
        await File.fromUri(
          action.video.resolve(repo.mediaBaseUri),
        ).readAsBytes(),
        fixture.bodies[action.video.path],
      );
    }
    expect(await invalid.exists(), isTrue);
    expect(await (repo as PoseHubVideoCache).videoCacheBytes(), 8192);
    await noParts(repo);
  });

  test('video cap cannot be disabled or increased beyond 300MB', () async {
    expect(poseHubVideoCacheLimitBytes, 300000000);
    for (final cap in [0, -1, 300000001]) {
      await expectLater(create(cacheBytes: cap), throwsFormatException);
    }
    expect(requested, isEmpty);
  });

  test(
    'unsafe ownership cannot delete files or leak a failed small cap',
    () async {
      final first = await create(cacheBytes: 8192);
      final uri = await first.ensureFile(fixture.first.video);
      first.dispose();
      final index = File(
        '${support.path}/posehub-media/video-cache-owners-v1.json',
      );
      final original = await index.readAsBytes();
      final outside = File('${support.path}/outside-cache.mp4');
      await outside.writeAsString('preserve-outside-cache');
      await index.writeAsString(
        jsonEncode({
          'format': 'smartfit-video-cache-owners@1',
          'videos': [
            {
              'relative':
                  'r1-v3/${fixture.revision}/media/../../../outside-cache.mp4',
              'bytes': fixture.first.video.bytes,
              'sha256': fixture.first.video.sha256,
            },
          ],
        }),
      );
      await expectLater(
        create(cacheBytes: 1),
        throwsA(
          isA<PoseHubMediaException>().having(
            (e) => e.code,
            'code',
            'unsafe_cache',
          ),
        ),
      );
      expect(
        await File.fromUri(uri).readAsBytes(),
        fixture.bodies[fixture.first.video.path],
      );
      expect(await outside.readAsString(), 'preserve-outside-cache');
      await index.writeAsBytes(original);
      final healthy = await create(cacheBytes: 8192);
      await healthy.ensureFile(fixture.catalog.allActions.last.video);
      expect(await (healthy as PoseHubVideoCache).videoCacheBytes(), 8192);
    },
  );

  test(
    'over-budget initialization releases its limit token on dispose',
    () async {
      final unknown = File(
        '${support.path}/posehub-media/r1-v2/${'c' * 64}/media/unknown/video.mp4',
      );
      await unknown.parent.create(recursive: true);
      await unknown.writeAsBytes(Uint8List(6000));
      final bounded = await create(cacheBytes: 4096);
      expect(await (bounded as PoseHubVideoCache).videoCacheBytes(), 6000);
      expect(requested, isEmpty);
      bounded.dispose();

      final healthy = await create(cacheBytes: 12288);
      await healthy.ensureFile(fixture.first.video);
      expect(await (healthy as PoseHubVideoCache).videoCacheBytes(), 10096);
      expect(await unknown.length(), 6000);
      expect(requested, ['/${fixture.first.video.path}']);
    },
  );

  test(
    'unknown bytes above cap preserve cached reads settings and atomic rejection',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final original = await create();
      final firstUri = await original.ensureFile(actions[0].video);
      final secondUri = await original.ensureFile(actions[1].video);
      original.dispose();

      final unknown = File(
        '${support.path}/posehub-media/r1-v2/${'c' * 64}/media/unknown/video.mp4',
      );
      final unknownBytes = Uint8List(10000);
      await unknown.parent.create(recursive: true);
      await unknown.writeAsBytes(unknownBytes);
      requested.clear();

      final current = await create(cacheBytes: 8192);
      final cache = current as PoseHubVideoCache;
      final access = current as PoseHubVideoCacheAccess;
      final services = _CacheSettingsServices(current);
      expect(await access.cachedVideo(actions[0].id), firstUri);
      expect(await access.cachedVideo(actions[1].id), secondUri);
      expect(requested, isEmpty);
      expect(await cache.videoCacheBytes(), 18192);
      expect(await trainingVideoCacheBytes(services), 18192);

      await expectLater(
        current.ensureFile(actions[2].video),
        throwsA(
          isA<PoseHubMediaException>().having(
            (error) => error.code,
            'code',
            'cache_full',
          ),
        ),
      );
      for (final (uri, action) in [
        (firstUri, actions[0]),
        (secondUri, actions[1]),
      ]) {
        expect(
          await File.fromUri(uri).readAsBytes(),
          fixture.bodies[action.video.path],
        );
      }
      expect(await unknown.readAsBytes(), unknownBytes);
      expect(requested, ['/${actions[2].video.path}']);
      expect(await cache.videoCacheBytes(), 18192);
      await noParts(current);

      final release = access.retainVideo(actions[0].id);
      try {
        await clearTrainingVideoCache(services);
        expect(await access.cachedVideo(actions[0].id), firstUri);
        expect(await File.fromUri(secondUri).exists(), isFalse);
        expect(await unknown.readAsBytes(), unknownBytes);
        expect(await trainingVideoCacheBytes(services), 14096);
      } finally {
        release();
      }
      await clearTrainingVideoCache(services);
      expect(await File.fromUri(firstUri).exists(), isFalse);
      expect(await trainingVideoCacheBytes(services), 10000);
      expect(await unknown.readAsBytes(), unknownBytes);
    },
  );

  test(
    'initialization preserves peer pins when they alone exceed its cap',
    () async {
      fixture = _Fixture(actions: 3);
      final actions = fixture.catalog.allActions.toList();
      final first = await create(cacheBytes: 8192);
      final uris = [
        await first.ensureFile(actions[0].video),
        await first.ensureFile(actions[1].video),
      ];
      final access = first as PoseHubVideoCacheAccess;
      final releases = [
        access.retainVideo(actions[0].id),
        access.retainVideo(actions[1].id),
      ];
      requested.clear();
      try {
        final current = await create(cacheBytes: 4096);
        final cache = current as PoseHubVideoCache;
        final currentAccess = current as PoseHubVideoCacheAccess;
        for (var index = 0; index < uris.length; index++) {
          expect(
            await currentAccess.cachedVideo(actions[index].id),
            uris[index],
          );
        }
        expect(requested, isEmpty);
        expect(await cache.videoCacheBytes(), 8192);
        await expectLater(
          current.ensureFile(actions[2].video),
          throwsA(
            isA<PoseHubMediaException>().having(
              (error) => error.code,
              'code',
              'cache_full',
            ),
          ),
        );
        await cache.clearVideoCache();
        for (var index = 0; index < uris.length; index++) {
          expect(
            await File.fromUri(uris[index]).readAsBytes(),
            fixture.bodies[actions[index].video.path],
          );
        }
        expect(await cache.videoCacheBytes(), 8192);
        await noParts(current);
      } finally {
        for (final release in releases) {
          release();
        }
      }
    },
  );

  test(
    'action failure returns immediately and retry shares healthy pending files',
    () async {
      final cover = fixture.first.cover;
      final pendingImage = Completer<Uint8List?>();
      final loaded = <String>[];
      var failVideo = true;
      handler = (request) async {
        if (failVideo) {
          request.response.statusCode = 503;
        } else {
          final bytes = fixture.bodies[fixture.first.video.path]!;
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
        }
        await request.response.close();
      };
      final repo = await create(
        bundled: (file) async {
          loaded.add(file.path);
          return file.path == cover.path
              ? pendingImage.future
              : fixture.bodies[file.path];
        },
      );
      final first = repo.ensureAction(fixture.first.id);
      final healthy = repo.ensureFile(cover);
      try {
        await expectLater(
          first.timeout(const Duration(seconds: 2)),
          throwsA(
            isA<PoseHubMediaException>().having((e) => e.code, 'code', 'http'),
          ),
        );
        expect(pendingImage.isCompleted, isFalse);
        failVideo = false;
        final retry = repo.ensureAction(fixture.first.id);
        expect(retry, isNot(same(first)));
        expect(repo.ensureFile(cover), same(healthy));
        await _until(() => requested.length == 2);
        expect(loaded.where((path) => path == cover.path).length, 1);
        pendingImage.complete(fixture.bodies[cover.path]);
        expect(await retry, repo.mediaBaseUri);
        expect(await healthy, cover.resolve(repo.mediaBaseUri));
        expect(
          repo.watchAction(fixture.first.id).value.phase,
          PoseHubDownloadPhase.ready,
        );
        expect(requested, [
          '/${fixture.first.video.path}',
          '/${fixture.first.video.path}',
        ]);
      } finally {
        if (!pendingImage.isCompleted) {
          pendingImage.complete(fixture.bodies[cover.path]);
        }
      }
    },
  );
}
