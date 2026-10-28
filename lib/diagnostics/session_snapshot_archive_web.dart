import 'session_snapshot_archive_contract.dart';

SessionSnapshotArchive createPlatformSessionSnapshotArchive() =>
    MemorySessionSnapshotArchive();

/// Browser diagnostics stay in memory; saving never opens a download or UI.
class MemorySessionSnapshotArchive implements SessionSnapshotArchive {
  static const retainedSnapshots = 5;
  final _snapshots = <({String filename, String contents})>[];
  int _sequence = 0;

  List<({String filename, String contents})> get snapshots =>
      List.unmodifiable(_snapshots);

  @override
  Future<String?> save(String contents) async {
    final filename = 'SmartFit-session-${++_sequence}.json';
    _snapshots.add((filename: filename, contents: contents));
    if (_snapshots.length > retainedSnapshots) _snapshots.removeAt(0);
    return filename;
  }
}
