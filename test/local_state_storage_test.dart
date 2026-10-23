import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:smartfit/app/device_identity.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';

/// Replaces only the native boundary. Tests still execute the real legacy
/// SharedPreferences cache and the App's actual storage/identity adapters.
class _PlatformStorage extends SharedPreferencesStorePlatform {
  final persisted = <String, Object>{};
  final attemptedValues = <Object>[];
  Object? readError;
  Object? writeError;
  bool rejectWrite = false;
  int reads = 0;
  int clears = 0;
  int removes = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    final error = readError;
    readError = null;
    if (error != null) throw error;
    return {
      for (final entry in persisted.entries)
        if (entry.key.startsWith('flutter.')) entry.key: entry.value,
    };
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    attemptedValues.add(value);
    final error = writeError;
    writeError = null;
    if (error != null) throw error;
    if (rejectWrite) {
      rejectWrite = false;
      return false;
    }
    persisted[key] = value;
    return true;
  }

  @override
  Future<bool> clear() async {
    clears++;
    throw StateError('The storage adapter must never clear existing data');
  }

  @override
  Future<bool> remove(String key) async {
    removes++;
    throw StateError('The storage adapter must never remove existing data');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const persistedId = 'ea2c6891-654f-431b-a1f4-11a9a3e03bea';
  const idKey = 'flutter.${DeviceIdentity.key}';
  const stateKey = 'flutter.smartfit.state.v1';
  late _PlatformStorage platform;
  late SharedPreferencesStorePlatform previousPlatform;

  setUp(() {
    previousPlatform = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    platform = _PlatformStorage();
    SharedPreferencesStorePlatform.instance = platform;
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousPlatform;
    expect(platform.clears, 0);
    expect(platform.removes, 0);
  });

  for (final warmCache in [false, true]) {
    test(
      'platform read failure with ${warmCache ? 'warm' : 'cold'} cache preserves identity and other saved data',
      () async {
        final before = <String, Object>{
          idKey: persistedId,
          stateKey: '{"safetyAccepted":true,"history":[{"title":"existing"}]}',
          'flutter.smartfit.ai-memory.v1': 'existing-memory',
          'unrelated-native-preference': 'keep',
        };
        platform.persisted.addAll(before);
        final storage = SharedPreferencesLocalStateStorage();
        if (warmCache) {
          expect(await storage.read(DeviceIdentity.key), persistedId);
        }
        final failure = PlatformException(
          code: 'read_failed',
          message: 'private-details',
        );
        platform.readError = failure;
        final identity = DeviceIdentity(storage);
        await expectLater(identity.loadOrCreate(), throwsA(same(failure)));
        expect(platform.attemptedValues, isEmpty);
        expect(platform.persisted, before);

        expect(await identity.loadOrCreate(), persistedId);
        expect(
          await DeviceIdentity(
            SharedPreferencesLocalStateStorage(),
          ).loadOrCreate(),
          persistedId,
        );
        expect(platform.attemptedValues, isEmpty);
        expect(platform.persisted, before);
      },
    );
  }

  for (final returnsFalse in [false, true]) {
    test(
      'failed native write ${returnsFalse ? 'false' : 'PlatformException'} cannot become a memory-only device identity',
      () async {
        const savedState = '{"history":[{"title":"existing"}]}';
        platform.persisted[stateKey] = savedState;
        final failure = PlatformException(
          code: 'write_failed',
          message: 'private-details',
        );
        if (returnsFalse) {
          platform.rejectWrite = true;
        } else {
          platform.writeError = failure;
        }
        final identity = DeviceIdentity(SharedPreferencesLocalStateStorage());
        await expectLater(
          identity.loadOrCreate(),
          returnsFalse ? throwsStateError : throwsA(same(failure)),
        );
        expect(platform.persisted, {stateKey: savedState});
        expect(platform.attemptedValues, hasLength(1));

        // This new App adapter still sees the plugin's global singleton cache.
        // A platform refresh must discard the attempted but unpersisted UUID.
        final newStorage = SharedPreferencesLocalStateStorage();
        expect(await newStorage.read(DeviceIdentity.key), isNull);
        final persisted = await identity.loadOrCreate();
        expect(platform.attemptedValues, hasLength(2));
        expect(platform.persisted[idKey], persisted);
        expect(platform.persisted[stateKey], savedState);
        expect(await DeviceIdentity(newStorage).loadOrCreate(), persisted);

        // Simulate a new Dart process after the successful retry.
        SharedPreferences.resetStatic();
        expect(
          await DeviceIdentity(
            SharedPreferencesLocalStateStorage(),
          ).loadOrCreate(),
          persisted,
        );
        expect(platform.attemptedValues, hasLength(2));
      },
    );
  }

  test(
    'refresh failure propagates instead of returning a poisoned cached value',
    () async {
      final storage = SharedPreferencesLocalStateStorage();
      platform.persisted[stateKey] = 'original';
      expect(await storage.read('smartfit.state.v1'), 'original');
      final writeFailure = PlatformException(code: 'write_failed');
      platform.writeError = writeFailure;
      await expectLater(
        storage.write('smartfit.state.v1', 'unpersisted'),
        throwsA(same(writeFailure)),
      );
      final readFailure = PlatformException(code: 'reload_failed');
      platform.readError = readFailure;
      await expectLater(
        SharedPreferencesLocalStateStorage().read('smartfit.state.v1'),
        throwsA(same(readFailure)),
      );
      expect(await storage.read('smartfit.state.v1'), 'original');
      expect(platform.persisted[stateKey], 'original');
    },
  );

  test(
    'updates retain the legacy flutter prefix and existing keys without migration',
    () async {
      platform.persisted.addAll({
        idKey: persistedId,
        stateKey: 'old',
        'native-key': true,
      });
      final storage = SharedPreferencesLocalStateStorage();
      await storage.write('smartfit.state.v1', 'updated');
      expect(
        await SharedPreferencesLocalStateStorage().read('smartfit.state.v1'),
        'updated',
      );
      expect(platform.persisted, {
        idKey: persistedId,
        stateKey: 'updated',
        'native-key': true,
      });
      expect(await DeviceIdentity(storage).loadOrCreate(), persistedId);
    },
  );
}
