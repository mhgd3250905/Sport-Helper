import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'training_transition_timings_storage.dart';

TrainingTransitionTimingsStorage createTrainingTransitionTimingsStorage() =>
    FileTrainingTransitionTimingsStorage();

/// Application Support/diagnostics/training-transitions/recent.json.
/// All filesystem operations are asynchronous; owned files never follow links.
class FileTrainingTransitionTimingsStorage
    implements TrainingTransitionTimingsStorage {
  FileTrainingTransitionTimingsStorage({this.directory});
  static const maximumBytes = 2 * 1024 * 1024;
  final Directory? directory;

  Future<Directory> _directory() async {
    final value =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}diagnostics'
          '${Platform.pathSeparator}training-transitions',
        );
    if (await FileSystemEntity.type(value.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Transition diagnostics cannot use a link');
    }
    await value.create(recursive: true);
    return value;
  }

  Future<File> _file(String name) async {
    final root = await _directory();
    final file = File('${root.path}${Platform.pathSeparator}$name');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('Transition diagnostics target is not a file');
    }
    return file;
  }

  @override
  Future<String?> read() async {
    final file = await _file('recent.json');
    if (!await file.exists()) return null;
    if (await file.length() > maximumBytes) {
      throw FileSystemException('Transition diagnostics exceeds its limit');
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String json) async {
    // The recorder serializes writes and bounds the raw sample count. There
    // are no synchronous writes, stats, JSON encodes, or flushes on a frame.
    if (json.length > maximumBytes) {
      throw FileSystemException('Transition diagnostics exceeds its limit');
    }
    final file = await _file('recent.json');
    final temporary = await _file('recent.json.writing');
    await temporary.writeAsString(json, flush: true);
    await temporary.rename(file.path);
  }
}
