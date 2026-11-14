import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import '../app/posehub_media_repository.dart';

CatalogMediaDownloadState trainingDownloadState(PoseHubDownloadState state) =>
    CatalogMediaDownloadState(
      phase: switch (state.phase) {
        PoseHubDownloadPhase.idle => CatalogMediaDownloadPhase.idle,
        PoseHubDownloadPhase.queued => CatalogMediaDownloadPhase.queued,
        PoseHubDownloadPhase.checking => CatalogMediaDownloadPhase.checking,
        PoseHubDownloadPhase.downloading =>
          CatalogMediaDownloadPhase.downloading,
        PoseHubDownloadPhase.verifying => CatalogMediaDownloadPhase.verifying,
        PoseHubDownloadPhase.ready => CatalogMediaDownloadPhase.ready,
        PoseHubDownloadPhase.failed => CatalogMediaDownloadPhase.failed,
      },
      receivedBytes: state.receivedBytes,
      totalBytes: state.totalBytes,
      error: state.error,
    );

class _DownloadState extends ChangeNotifier
    implements ValueListenable<CatalogMediaDownloadState> {
  _DownloadState(this.source) {
    source.addListener(notifyListeners);
  }
  final ValueListenable<PoseHubDownloadState> source;
  @override
  CatalogMediaDownloadState get value => trainingDownloadState(source.value);
  @override
  void dispose() {
    source.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Delegates every byte, cache pin and budget operation to the App repository.
/// The SDK policy/HUD can observe it without creating another downloader.
class TrainingMediaRepositoryBridge
    implements CatalogMediaRepository, CatalogMediaPriorityRepository {
  TrainingMediaRepositoryBridge({
    required this.catalog,
    required this.host,
    this.entry = 'training',
  }) {
    for (final action in catalog.allActions) {
      _videos[action.video.path] = action.id;
    }
  }
  @override
  final coach.PoseHubAppTestCatalog catalog;
  final PoseHubMediaRepository host;
  final String entry;
  final _videos = <String, String>{};
  final _files = <String, _DownloadState>{};
  final _actions = <String, _DownloadState>{};
  @override
  Uri get mediaBaseUri => host.mediaBaseUri;

  @override
  Future<Uri> ensureFile(coach.PoseHubPackFile file) =>
      ensureFileWithPriority(file, priority: CatalogMediaPriority.current);

  @override
  Future<Uri> ensureFileWithPriority(
    coach.PoseHubPackFile file, {
    required CatalogMediaPriority priority,
  }) {
    final id = _videos[file.path];
    if (id != null) {
      if (host case final PoseHubMediaEntryPreparation media) {
        return media.ensureVideoForEntry(
          id,
          entry: entry,
          priority: priority == CatalogMediaPriority.current,
        );
      }
      if (host case final PoseHubTrainingVideoPreparation training) {
        return training.ensureVideo(
          id,
          priority: priority == CatalogMediaPriority.current,
        );
      }
    }
    return host.ensureFile(file);
  }

  @override
  Future<Uri> ensureAction(String actionId) => host.ensureAction(actionId);

  @override
  ValueListenable<CatalogMediaDownloadState> watchFile(
    coach.PoseHubPackFile file,
  ) =>
      _files.putIfAbsent(file.path, () => _DownloadState(host.watchFile(file)));

  @override
  ValueListenable<CatalogMediaDownloadState> watchAction(String actionId) =>
      _actions.putIfAbsent(
        actionId,
        () => _DownloadState(host.watchAction(actionId)),
      );

  @override
  Future<Uri?> cachedVideo(String actionId) => switch (host) {
    final PoseHubVideoCacheAccess cache => cache.cachedVideo(actionId),
    _ => Future.value(null),
  };
  @override
  VoidCallback retainVideo(String actionId) => switch (host) {
    final PoseHubVideoCacheAccess cache => cache.retainVideo(actionId),
    _ => () {},
  };
  @override
  Future<int> videoCacheBytes() => switch (host) {
    final PoseHubVideoCache cache => cache.videoCacheBytes(),
    _ => Future.value(0),
  };
  @override
  Future<void> clearVideoCache() => switch (host) {
    final PoseHubVideoCache cache => cache.clearVideoCache(),
    _ => Future.value(),
  };
  @override
  void dispose() {
    for (final state in [..._files.values, ..._actions.values]) {
      state.dispose();
    }
    _files.clear();
    _actions.clear();
  }
}

/// Selected synchronously by mediaBuilder before the SDK builds its keyed HUD.
/// File notifications stay live; selecting a new action never carries old ready.
class CurrentTrainingDownload extends ChangeNotifier
    implements ValueListenable<CatalogMediaDownloadState> {
  CurrentTrainingDownload(this.repository);
  final TrainingMediaRepositoryBridge repository;
  String? actionId;
  ValueListenable<CatalogMediaDownloadState>? _source;
  void select(coach.PoseHubPackAction action) {
    if (actionId == action.id) return;
    _source?.removeListener(notifyListeners);
    actionId = action.id;
    _source = repository.watchFile(action.video)..addListener(notifyListeners);
  }

  @override
  CatalogMediaDownloadState get value =>
      _source?.value ??
      const CatalogMediaDownloadState(phase: CatalogMediaDownloadPhase.idle);
  @override
  void dispose() {
    _source?.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The SDK's current-ready/next-only queue owns lookahead. This adapter only
/// requests a video and exposes the host's actual per-file state.
class TrainingVideoPreparer implements PoseHubMediaPreparer {
  TrainingVideoPreparer(this.repository, this.current);
  final TrainingMediaRepositoryBridge repository;
  final CurrentTrainingDownload current;
  @override
  Stream<PoseHubMediaPreparationEvent> prepareAction(
    coach.PoseHubPackAction action,
  ) {
    late StreamController<PoseHubMediaPreparationEvent> output;
    final state = repository.watchFile(action.video);
    var active = false;
    void progress() {
      if (!active) return;
      final value = state.value;
      output.add(
        PoseHubMediaProgress(
          fraction: value.progress,
          receivedBytes: value.receivedBytes,
          totalBytes: value.totalBytes > 0 ? value.totalBytes : null,
        ),
      );
    }

    void detach() {
      active = false;
      state.removeListener(progress);
    }

    output = StreamController(
      onListen: () {
        active = true;
        state.addListener(progress);
        progress();
        unawaited(
          repository
              .ensureFileWithPriority(
                action.video,
                priority: current.actionId == action.id
                    ? CatalogMediaPriority.current
                    : CatalogMediaPriority.prefetch,
              )
              .then<void>(
                (_) {
                  if (!active) return;
                  output.add(
                    PoseHubMediaReady(mediaBaseUri: repository.mediaBaseUri),
                  );
                  detach();
                  unawaited(output.close());
                },
                onError: (Object _, StackTrace _) {
                  if (!active) return;
                  output.add(const PoseHubMediaFailed(reason: '示范视频准备失败，请重试。'));
                  detach();
                  unawaited(output.close());
                },
              ),
        );
      },
      onCancel: detach,
    );
    return output.stream;
  }
}
