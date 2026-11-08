import 'dart:async';

import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart' as sdk;

import '../diagnostics/runtime_log.dart';
import 'posehub_media_repository.dart';

/// Each SDK consumer owns a subscription, while the repository owns downloads.
/// Even 100% progress cannot substitute for ensureAction's verified completion.
class SmartFitPoseHubMediaPreparer implements sdk.PoseHubMediaPreparer {
  const SmartFitPoseHubMediaPreparer(
    this.repo, {
    this.videoOnly = false,
    this.entry,
  });
  final PoseHubMediaRepository? repo;
  final bool videoOnly;
  final String? entry;

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
    void Function()? removeVideoProgress;
    final log = RuntimeLog.instance;
    final operation = log.newOperation('posehub_prepare');
    final elapsed = Stopwatch();
    var downloadedVideo = false;
    var active = false;
    var terminal = false;
    final expectedTotal = videoOnly
        ? action.video.bytes
        : action.files.values.fold<int>(0, (sum, file) => sum + file.bytes);
    void retire() {
      active = false;
      removeProgress?.call();
      removeProgress = null;
      removeVideoProgress?.call();
      removeVideoProgress = null;
    }

    void finish(sdk.PoseHubMediaPreparationEvent event) {
      if (!active || terminal) return;
      terminal = true;
      elapsed.stop();
      log.record(
        event is sdk.PoseHubMediaReady
            ? 'posehub.prepare.ready'
            : 'posehub.prepare.failed',
        operation: operation,
        fields: {
          'actionId': action.id,
          'source': downloadedVideo
              ? 'network'
              : event is sdk.PoseHubMediaReady
              ? 'local_verified'
              : 'not_prepared',
          'verified': event is sdk.PoseHubMediaReady,
          'elapsedMs': elapsed.elapsedMilliseconds,
          'totalBytes': action.video.bytes,
        },
      );
      stream.add(event);
      retire();
      unawaited(stream.close());
    }

    stream = StreamController<sdk.PoseHubMediaPreparationEvent>(
      onListen: () {
        active = true;
        elapsed.start();
        try {
          final state = videoOnly
              ? repository.watchFile(action.video)
              : repository.watchAction(action.id);
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
          if (log.enabled) {
            final videoState = repository.watchFile(action.video);
            void videoProgress() {
              if (videoState.value.phase == PoseHubDownloadPhase.downloading) {
                downloadedVideo = true;
              }
            }

            videoState.addListener(videoProgress);
            removeVideoProgress = () =>
                videoState.removeListener(videoProgress);
            videoProgress();
            log.record(
              'posehub.prepare.requested',
              operation: operation,
              fields: {'actionId': action.id},
            );
          }
          progress();
          unawaited(
            Future<Uri>.sync(() {
              if (!videoOnly) return repository.ensureAction(action.id);
              final sourceEntry = entry;
              final video = switch (repository) {
                final PoseHubMediaEntryPreparation scoped
                    when sourceEntry != null =>
                  scoped.ensureVideoForEntry(
                    action.id,
                    entry: sourceEntry,
                    priority: true,
                  ),
                final PoseHubTrainingVideoPreparation current =>
                  current.ensureVideo(action.id, priority: true),
                _ => repository.ensureFile(action.video),
              };
              return video.then((_) => repository.mediaBaseUri);
            }).then<void>(
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
