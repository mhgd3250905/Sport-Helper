import 'dart:math';

import '../core/storage/local_state_storage.dart';

/// An installation identifier generated locally, without hardware identifiers.
class DeviceIdentity {
  DeviceIdentity(this._storage);

  static const key = 'smartfit.device-id.v1';
  static final _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final LocalStateStorage _storage;
  String? _id;
  Future<String>? _loading;

  /// The returned id is persisted. Failed writes propagate and may be retried.
  Future<String> loadOrCreate() {
    final existing = _id;
    if (existing != null) return Future.value(existing);
    return _loading ??= Future<void>.value().then((_) => _load());
  }

  Future<String> _load() async {
    try {
      final existing = await _storage.read(key);
      if (existing != null && existing.length == 36 && _uuidV4.hasMatch(existing)) {
        return _id = existing;
      }
      final random = Random.secure();
      final bytes = List.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final id =
          '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
      await _storage.write(key, id);
      return _id = id;
    } finally {
      _loading = null;
    }
  }
}
