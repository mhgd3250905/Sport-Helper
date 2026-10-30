import 'training_transition_timings_storage.dart';

TrainingTransitionTimingsStorage createTrainingTransitionTimingsStorage() =>
    _MemoryStorage();

class _MemoryStorage implements TrainingTransitionTimingsStorage {
  String? _json;
  @override
  Future<String?> read() async => _json;
  @override
  Future<void> write(String json) async => _json = json;
}
