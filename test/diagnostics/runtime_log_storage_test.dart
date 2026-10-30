import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/diagnostics/runtime_log.dart';
import 'package:smartfit/diagnostics/runtime_log_storage.dart';
import 'package:smartfit/diagnostics/runtime_log_storage_io.dart'
    show FileRuntimeLogStorage;
import 'package:smartfit/diagnostics/runtime_log_storage_stub.dart' as stub;

class _LegacyStorage implements LocalStateStorage {
  final values = <String, String>{};
  int reads = 0, writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }
}

void main() {
  late Directory root;
  late _LegacyStorage legacy;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'smartfit-runtime-log-storage-test-',
    );
    legacy = _LegacyStorage();
  });

  tearDown(() async {
    final parent = Directory.systemTemp.absolute.path;
    expect(
      root.absolute.path.startsWith('$parent${Platform.pathSeparator}'),
      isTrue,
    );
    expect(
      root.path.split(Platform.pathSeparator).last,
      startsWith('smartfit-runtime-log-storage-test-'),
    );
    await root.delete(recursive: true);
  });

  File recent() => File('${root.path}${Platform.pathSeparator}recent.json');

  test('native factory creates the file-backed diagnostics adapter lazily', () {
    expect(
      createRuntimeLogStorage(legacy: legacy),
      isA<FileRuntimeLogStorage>(),
    );
    expect(legacy.reads, 0);
    expect(legacy.writes, 0);
  });

  test(
    'legacy fallback migrates redacted events on flush without deleting preferences',
    () async {
      const secret = 'UNIT_MIGRATION_CREDENTIAL';
      final oldLog = RuntimeLog(enabled: true)
        ..recordDeveloper('chat.user', data: {'text': 'previous $secret'});
      final previous = oldLog.exportJson();
      legacy.values[RuntimeLog.storageKey] = previous;
      final storage = FileRuntimeLogStorage(legacy: legacy, directory: root);
      final log = RuntimeLog(
        enabled: true,
        storage: storage,
        secrets: [secret],
      );
      await log.initialize();
      expect(log.entryCount, 1);
      expect(await recent().exists(), isFalse);
      log.record('app.start');
      await log.flush();
      final migrated = await recent().readAsString();
      expect(jsonDecode(migrated)['schema'], 1);
      expect(jsonDecode(migrated)['events'], hasLength(2));
      expect(migrated, isNot(contains(secret)));
      expect(legacy.values[RuntimeLog.storageKey], previous);
      expect(legacy.reads, 1);
      expect(legacy.writes, 0);
      expect(await storage.read(RuntimeLog.storageKey), migrated);
      expect(legacy.reads, 1, reason: 'The new file takes precedence.');
    },
  );

  test(
    'atomic replacement leaves no partial files and preserves unrelated data',
    () async {
      final unrelated = File('${root.path}${Platform.pathSeparator}keep.txt');
      await unrelated.writeAsString('unrelated');
      final a = FileRuntimeLogStorage(legacy: legacy, directory: root);
      final b = FileRuntimeLogStorage(legacy: legacy, directory: root);
      await a.write(RuntimeLog.storageKey, '{"schema":1,"turn":0}');
      await Future.wait([
        for (var i = 1; i < 10; i++)
          (i.isEven ? a : b).write(
            RuntimeLog.storageKey,
            jsonEncode({'schema': 1, 'turn': i}),
          ),
      ]);
      await b.write(RuntimeLog.storageKey, '{"schema":1,"turn":10}');
      expect(jsonDecode(await recent().readAsString())['turn'], 10);
      expect(await unrelated.readAsString(), 'unrelated');
      expect(
        await root
            .list()
            .map((entry) => entry.path.split(Platform.pathSeparator).last)
            .toList(),
        unorderedEquals(['keep.txt', 'recent.json']),
      );
      expect(legacy.writes, 0);
    },
  );

  test(
    'unrecognized keys are rejected before filesystem or legacy I/O',
    () async {
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}unused',
      );
      final storage = FileRuntimeLogStorage(
        legacy: legacy,
        directory: directory,
      );
      await expectLater(storage.read('../user-settings'), throwsArgumentError);
      await expectLater(
        storage.write('other.key', 'private'),
        throwsArgumentError,
      );
      expect(await directory.exists(), isFalse);
      expect(legacy.reads, 0);
      expect(legacy.writes, 0);
    },
  );

  test(
    'failed atomic writes retain the previous document and permit retry',
    () async {
      final storage = FileRuntimeLogStorage(legacy: legacy, directory: root);
      await storage.write(RuntimeLog.storageKey, '{"schema":1,"turn":1}');
      final oversized = 'x' * (FileRuntimeLogStorage.maximumBytes + 1);
      await expectLater(
        storage.write(RuntimeLog.storageKey, oversized),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await recent().readAsString())['turn'], 1);
      await storage.write(RuntimeLog.storageKey, '{"schema":1,"turn":2}');
      expect(jsonDecode(await recent().readAsString())['turn'], 2);
      expect(await root.list().length, 1);
    },
  );

  test(
    'UTF-8 size rejection cleans temporary files without replacing the document',
    () async {
      final storage = FileRuntimeLogStorage(legacy: legacy, directory: root);
      await storage.write(RuntimeLog.storageKey, '{"schema":1,"turn":1}');
      final oversized =
          '\u4f60' * (FileRuntimeLogStorage.maximumBytes ~/ 3 + 1);
      await expectLater(
        storage.write(RuntimeLog.storageKey, oversized),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await recent().readAsString())['turn'], 1);
      expect(await root.list().length, 1);
    },
  );

  test('filesystem failure cannot poison a subsequent write', () async {
    final blocked = Directory(recent().path);
    await blocked.create();
    final storage = FileRuntimeLogStorage(legacy: legacy, directory: root);
    await expectLater(
      storage.write(RuntimeLog.storageKey, '{"schema":1}'),
      throwsA(isA<FileSystemException>()),
    );
    await blocked.delete();
    await storage.write(RuntimeLog.storageKey, '{"schema":1}');
    expect(await recent().readAsString(), '{"schema":1}');
  });

  test(
    'disabled production logging never creates or reads its backing document',
    () async {
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}unused',
      );
      final log = RuntimeLog(
        enabled: false,
        storage: FileRuntimeLogStorage(legacy: legacy, directory: directory),
        encode: (_) => throw StateError('Disabled encoder must not run'),
      );
      await log.initialize();
      log.record('app.start');
      log.recordDeveloper('chat.user', data: {'text': 'private'});
      log.protectSecret('UNIT_DISABLED_CREDENTIAL');
      await log.flush();
      expect(await directory.exists(), isFalse);
      expect(legacy.reads, 0);
      expect(legacy.writes, 0);
    },
  );

  test('non-IO fallback keeps the same fixed-key contract', () async {
    final storage = stub.createRuntimeLogStorage(legacy: legacy);
    await storage.write(RuntimeLog.storageKey, '{"schema":1}');
    expect(await storage.read(RuntimeLog.storageKey), '{"schema":1}');
    expect(() => storage.read('other.key'), throwsArgumentError);
    expect(() => storage.write('other.key', 'private'), throwsArgumentError);
  });
}
