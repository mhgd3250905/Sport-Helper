// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/data/local_state_storage.dart`.
// Unchanged.
import 'package:shared_preferences/shared_preferences.dart';

/// Injectable local storage boundary. No account, network, or remote service.
abstract interface class LocalStateStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SharedPreferencesLocalStateStorage implements LocalStateStorage {
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await _instance()).setString(key, value)) {
      throw StateError('Local settings write failed');
    }
  }
}
