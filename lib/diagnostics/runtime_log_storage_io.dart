import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/storage/local_state_storage.dart';
import 'runtime_log_storage.dart' show runtimeLogStorageKey;

LocalStateStorage createRuntimeLogStorage({
  required LocalStateStorage legacy,
}) => FileRuntimeLogStorage(legacy: legacy);

/// Application Support/diagnostics/runtime-log/recent.json. All I/O is async;
/// only this fixed document is owned, and the legacy value is never removed.
class FileRuntimeLogStorage implements LocalStateStorage {
  FileRuntimeLogStorage({required this.legacy, this.directory});

  static const maximumBytes = 2 * 1024 * 1024;
  static final _directoryWrites = <String, Future<void>>{};
  final LocalStateStorage legacy;
  final Directory? directory;

  void _checkKey(String key) {
    if (key != runtimeLogStorageKey) {
      throw ArgumentError.value(key, 'key', 'Unsupported diagnostics key');
    }
  }

  Future<Directory> _directory() async {
    final value =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}diagnostics'
          '${Platform.pathSeparator}runtime-log',
        );
    if (await FileSystemEntity.type(value.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Runtime diagnostics cannot use a link');
    }
    await value.create(recursive: true);
    return value;
  }

  Future<File> _target(Directory directory) async {
    final file = File('${directory.path}${Platform.pathSeparator}recent.json');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Runtime diagnostics target is not a file');
    }
    return file;
  }

  @override
  Future<String?> read(String key) async {
    _checkKey(key);
    final file = await _target(await _directory());
    if (!await file.exists()) return legacy.read(runtimeLogStorageKey);
    if (await file.length() > maximumBytes) {
      throw FileSystemException('Runtime diagnostics exceeds its limit');
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String key, String value) async {
    _checkKey(key);
    if (value.length > maximumBytes) {
      throw FileSystemException('Runtime diagnostics exceeds its limit');
    }
    final root = await _directory();
    final canonical = await root.resolveSymbolicLinks();
    final identity = Platform.isWindows ? canonical.toLowerCase() : canonical;
    final previous = _directoryWrites[identity] ?? Future<void>.value();
    final writing = previous.then((_) => _write(root, value));
    final settled = writing.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _directoryWrites[identity] = settled;
    try {
      await writing;
    } finally {
      if (identical(_directoryWrites[identity], settled)) {
        _directoryWrites.remove(identity);
      }
    }
  }

  Future<void> _write(Directory root, String value) async {
    final file = await _target(root);
    final temporary = await root.createTemp('.runtime-log-writing-');
    final partial = File(
      '${temporary.path}${Platform.pathSeparator}recent.tmp',
    );
    try {
      await partial.writeAsString(value, flush: true);
      if (await partial.length() > maximumBytes) {
        throw FileSystemException('Runtime diagnostics exceeds its limit');
      }
      await _target(root);
      await partial.rename(file.path);
    } finally {
      if (await partial.exists()) await partial.delete();
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
