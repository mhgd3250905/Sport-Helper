import 'session_snapshot_archive_contract.dart';
import 'session_snapshot_archive_io.dart'
    if (dart.library.js_interop) 'session_snapshot_archive_web.dart'
    as platform;

export 'session_snapshot_archive_contract.dart';
export 'session_snapshot_archive_io.dart'
    if (dart.library.js_interop) 'session_snapshot_archive_web.dart';

SessionSnapshotArchive createSessionSnapshotArchive() =>
    platform.createPlatformSessionSnapshotArchive();
