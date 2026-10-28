import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'session_snapshot_archive_contract.dart';

SessionSnapshotArchive createPlatformSessionSnapshotArchive() =>
    FileSessionSnapshotArchive();

/// Keeps complete SDK exports in the App's developer-log directory.
///
/// Only files bearing this service's exact filename format participate in
/// retention. Links, incomplete writes and unrelated files are untouched.
class FileSessionSnapshotArchive implements SessionSnapshotArchive {
  FileSessionSnapshotArchive({this.directory, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const retainedSnapshots = 5;
  static final _ownedName = RegExp(
    r'^SmartFit-session-\d{8}T\d{12}Z-\d{12}-[A-Za-z0-9_-]+\.json$',
  );
  static final _directoryWrites = <String, Future<void>>{};
  static int _sequence = 0;

  final Directory? directory;
  final DateTime Function() _clock;

  @override
  Future<String?> save(String contents) async {
    final directory =
        this.directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}diagnostics'
          '${Platform.pathSeparator}session-snapshots',
        );
    if (await FileSystemEntity.type(directory.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Snapshot archive directory cannot be a link');
    }
    await directory.create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    final key = Platform.isWindows ? canonical.toLowerCase() : canonical;
    final previous = _directoryWrites[key] ?? Future<void>.value();
    final write = previous.then((_) => _save(directory, contents));
    final settled = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _directoryWrites[key] = settled;
    try {
      return await write;
    } finally {
      if (identical(_directoryWrites[key], settled)) {
        _directoryWrites.remove(key);
      }
    }
  }

  Future<String> _save(Directory directory, String contents) async {
    final temporary = await directory.createTemp('.SmartFit-session-writing-');
    final nonce = temporary.path
        .split(Platform.pathSeparator)
        .last
        .substring('.SmartFit-session-writing-'.length);
    final sequence = (++_sequence).toString().padLeft(12, '0');
    final filename =
        'SmartFit-session-${_stamp(_clock())}-$sequence-$nonce.json';
    final finalFile = File(
      '${directory.path}${Platform.pathSeparator}$filename',
    );
    final partial = File(
      '${temporary.path}${Platform.pathSeparator}snapshot.tmp',
    );
    try {
      if (await finalFile.exists()) {
        throw FileSystemException('Snapshot filename already exists');
      }
      await partial.writeAsString(contents, flush: true);
      await partial.rename(finalFile.path);
      await _rotate(directory, newest: finalFile.path);
      return filename;
    } finally {
      // These are only this call's temporary file and newly-created directory.
      // Nonrecursive deletion cannot remove any unexpected sibling contents.
      if (await partial.exists()) await partial.delete();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _rotate(Directory directory, {required String newest}) async {
    final files = <({File file, DateTime modified, String name})>[];
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (!_ownedName.hasMatch(name)) continue;
      files.add((
        file: entry,
        modified: (await entry.stat()).modified,
        name: name,
      ));
    }
    files.sort((a, b) {
      final aIsNewest = a.file.path == newest;
      final bIsNewest = b.file.path == newest;
      if (aIsNewest != bIsNewest) return aIsNewest ? 1 : -1;
      final byTime = a.modified.compareTo(b.modified);
      return byTime == 0 ? a.name.compareTo(b.name) : byTime;
    });
    if (files.length > retainedSnapshots) {
      for (final old in files.take(files.length - retainedSnapshots)) {
        await old.file.delete();
      }
    }
  }

  static String _stamp(DateTime now) {
    final utc = now.toUtc();
    String pad(int n, int digits) => n.toString().padLeft(digits, '0');
    return '${pad(utc.year, 4)}${pad(utc.month, 2)}${pad(utc.day, 2)}T'
        '${pad(utc.hour, 2)}${pad(utc.minute, 2)}${pad(utc.second, 2)}'
        '${pad(utc.millisecond * 1000 + utc.microsecond, 6)}Z';
  }
}
