import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/session_snapshot_archive.dart';
import 'package:smartfit/diagnostics/session_snapshot_archive_web.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'smartfit-snapshot-archive-test-',
    );
  });
  tearDown(() async {
    // The test owns the createTemp child, never its system-temp parent.
    final parent = Directory.systemTemp.absolute.path;
    expect(root.absolute.path.startsWith(parent), isTrue);
    expect(
      root.path.split(Platform.pathSeparator).last,
      startsWith('smartfit-snapshot-archive-test-'),
    );
    await root.delete(recursive: true);
  });

  Future<List<File>> snapshots() async => [
    await for (final entry in root.list(followLinks: false))
      if (entry is File &&
          entry.path.endsWith('.json') &&
          entry.path
              .split(Platform.pathSeparator)
              .last
              .startsWith('SmartFit-session-'))
        entry,
  ];

  test(
    'writes exact complete JSON before returning, with no partial artifacts',
    () async {
      final archive = FileSessionSnapshotArchive(directory: root);
      const contents = '{\n  "sessionState": {"quote": "拉伸一下臀部\\n保留原话"}\n}\n';
      final filename = await archive.save(contents);
      expect(filename, startsWith('SmartFit-session-'));
      final files = await snapshots();
      expect(files, hasLength(1));
      expect(await files.single.readAsBytes(), utf8.encode(contents));
      expect(root.listSync().whereType<Directory>(), isEmpty);
      expect(root.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    },
  );

  test(
    'successive saves and a new archive instance retain the five newest',
    () async {
      final fixed = DateTime.utc(2026, 10, 28, 12, 57);
      final first = FileSessionSnapshotArchive(
        directory: root,
        clock: () => fixed,
      );
      for (var i = 0; i < 4; i++) {
        await first.save(jsonEncode({'turn': i}));
      }
      final next = FileSessionSnapshotArchive(
        directory: root,
        clock: () => fixed,
      );
      for (var i = 4; i < 9; i++) {
        await next.save(jsonEncode({'turn': i}));
      }
      final files = await snapshots();
      expect(files, hasLength(5));
      expect([
        for (final file in files)
          (jsonDecode(await file.readAsString()) as Map)['turn'],
      ], unorderedEquals([4, 5, 6, 7, 8]));
    },
  );

  test(
    'concurrent archive instances serialize retention and never overwrite',
    () async {
      final fixed = DateTime.utc(2026, 10, 28);
      final a = FileSessionSnapshotArchive(directory: root, clock: () => fixed);
      final b = FileSessionSnapshotArchive(directory: root, clock: () => fixed);
      final names = await Future.wait([
        for (var i = 0; i < 12; i++)
          (i.isEven ? a : b).save(jsonEncode({'turn': i})),
      ]);
      expect(names.toSet(), hasLength(12));
      final files = await snapshots();
      expect(files, hasLength(5));
      final turns = [
        for (final file in files)
          (jsonDecode(await file.readAsString()) as Map)['turn'],
      ];
      expect(turns.toSet(), hasLength(5));
      expect(
        turns.every((turn) => turn is int && turn >= 0 && turn < 12),
        isTrue,
      );
      await a.save('{"turn":99}');
      expect([
        for (final file in await snapshots())
          (jsonDecode(await file.readAsString()) as Map)['turn'],
      ], contains(99));
      expect(root.listSync().whereType<Directory>(), isEmpty);
    },
  );

  test(
    'rotation does not touch unrelated files or incomplete-write directories',
    () async {
      final unrelated = File('${root.path}${Platform.pathSeparator}notes.json');
      await unrelated.writeAsString('keep unrelated log');
      final similar = File(
        '${root.path}${Platform.pathSeparator}SmartFit-session-user.json',
      );
      await similar.writeAsString('keep non-service file');
      final partial = Directory(
        '${root.path}${Platform.pathSeparator}.SmartFit-session-writing-old',
      );
      await partial.create();
      await File(
        '${partial.path}${Platform.pathSeparator}snapshot.tmp',
      ).writeAsString('old unfinished write');
      final archive = FileSessionSnapshotArchive(directory: root);
      for (var i = 0; i < 8; i++) {
        await archive.save(jsonEncode({'turn': i}));
      }
      expect(await unrelated.readAsString(), 'keep unrelated log');
      expect(await similar.readAsString(), 'keep non-service file');
      expect(
        await File(
          '${partial.path}${Platform.pathSeparator}snapshot.tmp',
        ).readAsString(),
        'old unfinished write',
      );
      final saved = await snapshots();
      expect(saved.where((f) => f.path != similar.path), hasLength(5));
    },
  );

  test(
    'I/O failure reaches the caller and cannot poison later saves',
    () async {
      final blocked = File('${root.path}${Platform.pathSeparator}blocked');
      await blocked.writeAsString('not a directory');
      final archive = FileSessionSnapshotArchive(
        directory: Directory(blocked.path),
      );
      await expectLater(
        archive.save('{"turn":1}'),
        throwsA(isA<FileSystemException>()),
      );
      await blocked.delete();
      await archive.save('{"turn":2}');
      final files = await Directory(
        blocked.path,
      ).list().where((f) => f is File).toList();
      expect(files, hasLength(1));
      expect(await File(files.single.path).readAsString(), '{"turn":2}');
    },
  );

  test(
    'a backward supplied clock still keeps the just-saved snapshot',
    () async {
      var now = DateTime.utc(2030, 1, 1);
      final archive = FileSessionSnapshotArchive(
        directory: root,
        clock: () => now,
      );
      for (var i = 0; i < 5; i++) {
        await archive.save(jsonEncode({'turn': i}));
      }
      now = DateTime.utc(2020, 1, 1);
      await archive.save('{"turn":99}');
      final files = await snapshots();
      expect(files, hasLength(5));
      expect([
        for (final file in files)
          (jsonDecode(await file.readAsString()) as Map)['turn'],
      ], contains(99));
    },
  );

  test(
    'browser archive retains at most five snapshots without downloads',
    () async {
      final archive = MemorySessionSnapshotArchive();
      for (var i = 0; i < 8; i++) {
        await archive.save(jsonEncode({'turn': i}));
      }
      expect(archive.snapshots, hasLength(5));
      expect(archive.snapshots.map((s) => jsonDecode(s.contents)['turn']), [
        3,
        4,
        5,
        6,
        7,
      ]);
      expect(() => archive.snapshots.clear(), throwsUnsupportedError);
    },
  );
}
