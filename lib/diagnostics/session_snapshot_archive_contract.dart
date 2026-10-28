/// A developer-only archive. Callers supply the already-redacted JSON text.
abstract interface class SessionSnapshotArchive {
  /// Returns the saved filename after durable writing and retention complete.
  Future<String?> save(String contents);
}
