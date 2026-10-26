import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as sdk;

import 'posehub_media_repository.dart';

/// Each SDK consumer owns a subscription, while the repository owns downloads.
/// Even 100% progress cannot substitute for ensureAction's verified completion.
class SmartFitPoseHubMediaPreparer implements sdk.PoseHubMediaPreparer {
  const SmartFitPoseHubMediaPreparer(this.repo);
  final PoseHubMediaRepository? repo;

  @override
  Stream<sdk.PoseHubMediaPreparationEvent> prepareAction(
    coach.PoseHubPackAction action,
  ) {
    final repository = repo;
    if (repository == null) {
      return Stream.value(
        const sdk.PoseHubMediaFailed(reason: '本机动作缓存暂不可用，请重试。'),
      );
    }
    late StreamController<sdk.PoseHubMediaPreparationEvent> stream;
    void Function()? removeProgress;
    var active = false;
    var terminal = false;
    final expectedTotal = action.files.values.fold<int>(
      0,
      (sum, file) => sum + file.bytes,
    );
    void retire() {
      active = false;
      removeProgress?.call();
      removeProgress = null;
    }

    void finish(sdk.PoseHubMediaPreparationEvent event) {
      if (!active || terminal) return;
      terminal = true;
      stream.add(event);
      retire();
      unawaited(stream.close());
    }

    stream = StreamController<sdk.PoseHubMediaPreparationEvent>(
      onListen: () {
        active = true;
        try {
          final state = repository.watchAction(action.id);
          void progress() {
            if (!active || terminal) return;
            final value = state.value;
            final total = expectedTotal;
            final received = total > 0
                ? value.receivedBytes.clamp(0, total)
                : value.receivedBytes.clamp(0, 0x1fffffffffffff);
            stream.add(
              sdk.PoseHubMediaProgress(
                fraction: total > 0 ? received / total : null,
                receivedBytes: received,
                totalBytes: total > 0 ? total : null,
              ),
            );
          }

          state.addListener(progress);
          removeProgress = () => state.removeListener(progress);
          progress();
          unawaited(
            Future<Uri>.sync(
              () => repository.ensureAction(action.id),
            ).then<void>(
              (base) => finish(sdk.PoseHubMediaReady(mediaBaseUri: base)),
              onError: (Object _, StackTrace _) =>
                  finish(const sdk.PoseHubMediaFailed(reason: '动作资源准备失败，请重试。')),
            ),
          );
        } catch (_) {
          finish(const sdk.PoseHubMediaFailed(reason: '动作资源准备失败，请重试。'));
        }
      },
      onCancel: () {
        retire();
        if (!stream.isClosed) unawaited(stream.close());
      },
    );
    return stream.stream;
  }
}
