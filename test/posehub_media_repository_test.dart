import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

class _Fixture {
  _Fixture({
    int actions = 2,
    int videoBytes = 4096,
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
            role == 'video' ? videoBytes : (role == 'cover' ? coverBytes : 24),
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
    int concurrent = 3,
    int redirects = 5,
    String? revision,
    String packVersion = 'r1-v3',
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
      final repo = await create(concurrent: 2);
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
