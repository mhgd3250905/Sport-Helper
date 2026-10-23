// Copied from 3D-Body@a83a0f4 (branch feat/hiplab-flavor) `app/lib/data/local_state_storage.dart`.
// Refresh reads from the platform: the legacy plugin cache can contain values
// whose platform write failed, which must never become a durable device id.
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
  Future<String?> read(String key) async {
    final preferences = await _instance();
    await preferences.reload();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (!await (await _instance()).setString(key, value)) {
      throw StateError('Local settings write failed');
    }
  }
}
