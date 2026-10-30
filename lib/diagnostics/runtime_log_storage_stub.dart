import '../core/storage/local_state_storage.dart';
import 'runtime_log_storage.dart' show runtimeLogStorageKey;

LocalStateStorage createRuntimeLogStorage({
  required LocalStateStorage legacy,
}) => _LegacyRuntimeLogStorage(legacy);

class _LegacyRuntimeLogStorage implements LocalStateStorage {
  _LegacyRuntimeLogStorage(this.legacy);

  final LocalStateStorage legacy;

  void _checkKey(String key) {
    if (key != runtimeLogStorageKey) {
      throw ArgumentError.value(key, 'key', 'Unsupported diagnostics key');
    }
  }

  @override
  Future<String?> read(String key) {
    _checkKey(key);
    return legacy.read(runtimeLogStorageKey);
  }

  @override
  Future<void> write(String key, String value) {
    _checkKey(key);
    return legacy.write(runtimeLogStorageKey, value);
  }
}
