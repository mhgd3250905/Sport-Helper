import 'training_transition_timings_storage_stub.dart'
    if (dart.library.io) 'training_transition_timings_storage_io.dart'
    as platform;

/// One bounded diagnostics document, separate from user/session persistence.
abstract interface class TrainingTransitionTimingsStorage {
  Future<String?> read();
  Future<void> write(String json);
}

TrainingTransitionTimingsStorage createTrainingTransitionTimingsStorage() =>
    platform.createTrainingTransitionTimingsStorage();
