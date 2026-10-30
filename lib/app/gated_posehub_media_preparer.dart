import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'training_transition_activity.dart';

/// Public SDK adapter: initState may request prefetch, but its native/file work
/// starts only after the still-image entrance is complete. Cancellation never
/// completes startGate and never starts a canceled session's request.
class GatedPoseHubMediaPreparer implements PoseHubMediaPreparer {
  const GatedPoseHubMediaPreparer(this.delegate, this.gate);
  final PoseHubMediaPreparer delegate;
  final Future<void> gate;

  @override
  Stream<PoseHubMediaPreparationEvent> prepareAction(
    coach.PoseHubPackAction action,
  ) {
    late StreamController<PoseHubMediaPreparationEvent> stream;
    StreamSubscription<PoseHubMediaPreparationEvent>? subscription;
    var canceled = false;
    stream = StreamController<PoseHubMediaPreparationEvent>(
      onListen: () {
        unawaited(() async {
          await gate;
          await TrainingTransitionActivity.instance.waitUntilIdle();
          if (canceled) return;
          subscription = delegate
              .prepareAction(action)
              .listen(
                stream.add,
                onError: stream.addError,
                onDone: () => unawaited(stream.close()),
              );
        }());
      },
      onCancel: () async {
        canceled = true;
        await subscription?.cancel();
      },
    );
    return stream.stream;
  }
}
