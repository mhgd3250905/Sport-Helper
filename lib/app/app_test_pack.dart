import 'dart:convert';

import '../domain/exercise.dart';
import '../packs/drill_pack.dart';

abstract final class AppTestPackConfig {
  static const enabled =
      String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'internal' &&
      bool.fromEnvironment('SMARTFIT_APP_TEST_PACK');
  static const indexAsset = 'assets/app_test_pack/app-test-pack-r1/index.json';
  static const fullCatalog =
      enabled && bool.fromEnvironment('SMARTFIT_FULL_TEST_CATALOG');
}

/// Build-validated, locally bundled test media. This is never a release gate
/// override for production and does not infer readiness from catalog presence.
class AppTestPack {
  AppTestPack._(this.id, this.actions, this.catalog);

  final String id;
  final Map<String, AppTestAction> actions;
  final Map<String, Map<String, dynamic>> catalog;

  static Future<AppTestPack?> load(
    PackTextLoader read, {
    bool enabled = AppTestPackConfig.enabled,
  }) async {
    if (!enabled) return null;
    final index =
        jsonDecode(await read(AppTestPackConfig.indexAsset))
            as Map<String, dynamic>;
    if (index['format'] != 'smartfit-app-test-pack-index@1' ||
        index['status'] != 'test-unreviewed' ||
        index['reviewed'] != false ||
        index['releaseEligible'] != false ||
        index['internalOnly'] != true) {
      throw const FormatException('Invalid internal app-test pack identity');
    }
    final rawCatalog =
        jsonDecode(await read(_asset(index['catalogAsset'])))
            as Map<String, dynamic>;
    if (rawCatalog['format'] != 'pose-hub-app-test-catalog@1' ||
        rawCatalog['id'] != index['id'] ||
        rawCatalog['reviewed'] != false ||
        rawCatalog['releaseEligible'] != false) {
      throw const FormatException('Invalid app-test catalog identity');
    }
    final catalog = <String, Map<String, dynamic>>{};
    for (final value in rawCatalog['actions'] as List) {
      final entry = Map<String, dynamic>.from(value as Map);
      final id = entry['id'] as String;
      if (catalog.containsKey(id)) {
        throw const FormatException('Duplicate app-test catalog id');
      }
      catalog[id] = entry;
    }
    final actions = <String, AppTestAction>{};
    for (final entry in (index['actions'] as Map).entries) {
      final id = entry.key as String;
      if (!catalog.containsKey(id)) {
        throw const FormatException('Test media absent from catalog');
      }
      if (catalog[id]!['state'] != 'ready-test-unreviewed' ||
          catalog[id]!['availableForApp'] != true) {
        throw const FormatException('Test media not ready in catalog');
      }
      actions[id] = AppTestAction.fromJson(
        id,
        Map<String, dynamic>.from(entry.value as Map),
        catalog[id]!,
      );
    }
    return AppTestPack._(
      index['id'] as String,
      Map.unmodifiable(actions),
      Map.unmodifiable(catalog),
    );
  }

  static String _asset(Object? raw) {
    if (raw is! String ||
        !raw.startsWith('assets/app_test_pack/') ||
        raw.contains('\\') ||
        raw.split('/').any((part) => part == '..' || part == '.') ||
        Uri.parse(raw).hasQuery ||
        Uri.parse(raw).hasFragment) {
      throw const FormatException('Invalid app-test asset path');
    }
    return raw;
  }
}

class AppTestAction {
  const AppTestAction({
    required this.id,
    required this.revision,
    required this.packedVideo,
    required this.playbackPoster,
    required this.cover,
    required this.thumbnail,
    required this.loopSeconds,
  });
  final String id;
  final String? revision;
  final String packedVideo, playbackPoster, cover, thumbnail;
  final double loopSeconds;

  factory AppTestAction.fromJson(
    String id,
    Map<String, dynamic> media,
    Map<String, dynamic> metadata,
  ) {
    String asset(String role) {
      final descriptor = Map<String, dynamic>.from(media[role] as Map);
      if (descriptor['bytes'] is! int ||
          (descriptor['bytes'] as int) <= 0 ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch(descriptor['sha256'] as String? ?? '')) {
        throw const FormatException(
          'Invalid app-test media integrity descriptor',
        );
      }
      return AppTestPack._asset(descriptor['asset']);
    }

    final video = Map<String, dynamic>.from(media['packedVideo'] as Map);
    final poster = Map<String, dynamic>.from(
      media['alphaPlaybackPoster'] as Map,
    );
    final seconds = (video['durationSeconds'] as num).toDouble();
    if (video['width'] != 720 ||
        video['height'] != 1440 ||
        video['codec'] != 'h264' ||
        !seconds.isFinite ||
        seconds <= 0 ||
        poster['sourceFrame'] != 0 ||
        poster['sourceTimeSeconds'] != 0 ||
        poster['sourceSha256'] != video['sha256']) {
      throw const FormatException('Invalid packed alpha/first-frame pair');
    }
    return AppTestAction(
      id: id,
      revision: metadata['revision'] as String?,
      packedVideo: asset('packedVideo'),
      playbackPoster: asset('alphaPlaybackPoster'),
      cover: asset('alphaCover'),
      thumbnail: asset('alphaThumbnail'),
      loopSeconds: seconds,
    );
  }

  ExerciseMedia applyTo(ExerciseMedia fallback) => ExerciseMedia(
    id: fallback.id,
    video: fallback.video,
    poster: fallback.poster,
    loopSeconds: loopSeconds,
    posterSeconds: fallback.posterSeconds,
    source: fallback.source,
    videoAvailable: fallback.videoAvailable,
    lightVideo: fallback.lightVideo,
    lightPoster: fallback.lightPoster,
    lightVideoAvailable: fallback.lightVideoAvailable,
    playbackPoster: fallback.playbackPoster,
    lightPlaybackPoster: fallback.lightPlaybackPoster,
    packedAlphaVideo: packedVideo,
    alphaPlaybackPoster: playbackPoster,
    alphaCover: cover,
    alphaThumbnail: thumbnail,
    revision: revision,
    appTestOnly: true,
  );
}
