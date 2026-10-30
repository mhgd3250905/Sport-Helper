import '../core/storage/local_state_storage.dart';
import 'runtime_log_storage_stub.dart'
    if (dart.library.io) 'runtime_log_storage_io.dart'
    as platform;

const runtimeLogStorageKey = 'smartfit.runtime-log.v1';

/// Diagnostics use their own document; the old preferences remain readable.
LocalStateStorage createRuntimeLogStorage({
  required LocalStateStorage legacy,
}) => platform.createRuntimeLogStorage(legacy: legacy);
