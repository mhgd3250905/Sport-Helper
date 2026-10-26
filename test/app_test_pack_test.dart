import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/domain/exercise.dart';

/// A small isolated legacy-import fixture. The retired delivery is deliberately
/// not a source for either these generic admission checks or current App media.
class _Fixture {
  _Fixture(this.index, this.catalog);

  factory _Fixture.memory() {
    final videoHash = 'a' * 64;
    Map<String, dynamic> file(String name) => {
      'asset': 'assets/app_test_pack/fixture/$name',
      'bytes': 128,
      'sha256': 'b' * 64,
    };
    return _Fixture(
      {
        'format': 'smartfit-app-test-pack-index@1',
        'id': 'memory-fixture',
        'catalogAsset': 'assets/app_test_pack/fixture/catalog.json',
        'status': 'test-unreviewed',
        'reviewed': false,
        'releaseEligible': false,
        'internalOnly': true,
        'pendingIds': ['pending-action'],
        'actions': {
          'ready-action': {
            'packedVideo': {
              ...file('ready.rgb-alpha.mp4'),
              'sha256': videoHash,
              'width': 720,
              'height': 1440,
              'codec': 'h264',
              'durationSeconds': 6,
            },
            'alphaPlaybackPoster': {
              ...file('ready.first.webp'),
              'sourceSha256': videoHash,
              'sourceFrame': 0,
              'sourceTimeSeconds': 0,
            },
            'alphaCover': file('ready.cover.webp'),
            'alphaThumbnail': file('ready.thumb.webp'),
          },
        },
      },
      {
        'format': 'pose-hub-app-test-catalog@1',
        'id': 'memory-fixture',
        'reviewed': false,
        'releaseEligible': false,
        'actions': [
          for (final ready in [true, false])
            {
              'id': ready ? 'ready-action' : 'pending-action',
              'nameZh': ready ? '已备素材' : '待备素材',
              'revision': 'fixture-r1',
              'state': ready ? 'ready-test-unreviewed' : 'pending',
              'availableForApp': ready,
              'rhythm': {
                'durationSeconds': 6,
                'videoLoopIsTrainingDose': false,
              },
            },
        ],
      },
    );
  }

  final Map<String, dynamic> index;
  final Map<String, dynamic> catalog;
  final reads = <String>[];

  Map<String, dynamic> get media => index['actions'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get entries =>
      (catalog['actions'] as List).cast<Map<String, dynamic>>();
  String get readyId => media.keys.first;
  String get pendingId =>
      entries.firstWhere((entry) => !media.containsKey(entry['id']))['id']
          as String;

  Map<String, dynamic> descriptor(String id, String role) =>
      (media[id] as Map<String, dynamic>)[role] as Map<String, dynamic>;

  Future<String> read(String path) async {
    reads.add(path);
    if (path == AppTestPackConfig.indexAsset) return jsonEncode(index);
    if (path == index['catalogAsset']) return jsonEncode(catalog);
    throw StateError('Unexpected asset read: $path');
  }

  Future<AppTestPack> load() async =>
      (await AppTestPack.load(read, enabled: true))!;
}

void main() {
  group('App-test pack admission', () {
    test('disabled gate returns before reading any test asset', () async {
      var reads = 0;
      final result = await AppTestPack.load((path) async {
        reads++;
        throw StateError('Disabled test pack must not read $path');
      }, enabled: false);

      expect(result, isNull);
      expect(reads, 0);
    });

    test(
      'isolated index maps verified media and retains pending catalog rows',
      () async {
        final fixture = _Fixture.memory();
        final pack = await fixture.load();

        expect(pack.id, fixture.index['id']);
        expect(pack.catalog, hasLength(fixture.entries.length));
        expect(
          pack.catalog.keys,
          unorderedEquals(['ready-action', 'pending-action']),
        );
        expect(pack.actions.keys, unorderedEquals(fixture.media.keys));
        expect(fixture.reads, [
          AppTestPackConfig.indexAsset,
          fixture.index['catalogAsset'],
        ]);
        for (final action in pack.actions.values) {
          expect(
            action.packedVideo,
            fixture.descriptor(action.id, 'packedVideo')['asset'],
          );
          expect(
            action.playbackPoster,
            fixture.descriptor(action.id, 'alphaPlaybackPoster')['asset'],
          );
          expect(
            action.cover,
            fixture.descriptor(action.id, 'alphaCover')['asset'],
          );
          expect(
            action.thumbnail,
            fixture.descriptor(action.id, 'alphaThumbnail')['asset'],
          );
          expect(
            action.loopSeconds,
            fixture.descriptor(action.id, 'packedVideo')['durationSeconds'],
          );
          expect(action.revision, pack.catalog[action.id]!['revision']);
        }
      },
    );

    test(
      'pending catalog metadata stays visible without media admission',
      () async {
        final fixture = _Fixture.memory();
        final pending = fixture.entries.firstWhere(
          (entry) => entry['id'] == fixture.pendingId,
        );
        // A producer-side descriptor appearing in catalog alone is insufficient.
        pending['files'] = fixture.media[fixture.readyId];
        final pack = await fixture.load();

        expect(pack.catalog[fixture.pendingId]!['nameZh'], isNotEmpty);
        expect(pack.catalog[fixture.pendingId]!['rhythm'], isA<Map>());
        expect(pack.actions.containsKey(fixture.pendingId), isFalse);
        expect(
          pack.catalog.keys.toSet().difference(pack.actions.keys.toSet()),
          unorderedEquals(fixture.index['pendingIds'] as List),
        );
      },
    );

    test(
      'app-test index cannot be admitted as reviewed production media',
      () async {
        final fixture = _Fixture.memory();
        fixture.index['releaseEligible'] = true;
        await expectLater(fixture.load(), throwsA(isA<FormatException>()));
      },
    );

    for (final mismatch in <(String, Object)>[
      ('sourceSha256', List.filled(64, '0').join()),
      ('sourceFrame', 1),
      ('sourceTimeSeconds', 1),
    ]) {
      test(
        'rejects frame-zero poster with mismatched ${mismatch.$1}',
        () async {
          final fixture = _Fixture.memory();
          fixture.descriptor(
            fixture.readyId,
            'alphaPlaybackPoster',
          )[mismatch.$1] = mismatch.$2;
          await expectLater(fixture.load(), throwsA(isA<FormatException>()));
        },
      );
    }

    test(
      'index media cannot override a pending catalog readiness state',
      () async {
        final fixture = _Fixture.memory();
        final metadata = fixture.entries.firstWhere(
          (entry) => entry['id'] == fixture.readyId,
        );
        metadata['state'] = 'existing-full-layers-ready-to-encode';
        metadata['availableForApp'] = false;

        await expectLater(fixture.load(), throwsA(isA<FormatException>()));
      },
    );
  });

  test(
    'applying verified alpha media preserves both opaque theme fallbacks',
    () async {
      final fixture = _Fixture.memory();
      final pack = await fixture.load();
      final id = fixture.readyId;
      String path(String theme, String role) => 'assets/fixture/$theme/$role';
      final fallback = ExerciseMedia(
        id: id,
        video: path('dark', 'video'),
        poster: path('dark', 'poster'),
        loopSeconds: 8,
        posterSeconds: 0,
        source: 'Pose-Hub 0.3.0',
        lightVideo: path('light', 'video'),
        lightPoster: path('light', 'poster'),
        lightVideoAvailable: true,
        playbackPoster: path('dark', 'playbackPoster'),
        lightPlaybackPoster: path('light', 'playbackPoster'),
      );
      final action = pack.actions[id]!;
      final mapped = action.applyTo(fallback);

      expect(mapped.id, fallback.id);
      expect(mapped.source, fallback.source);
      expect(mapped.video, fallback.video);
      expect(mapped.poster, fallback.poster);
      expect(mapped.lightVideo, fallback.lightVideo);
      expect(mapped.lightPoster, fallback.lightPoster);
      expect(mapped.playbackPoster, fallback.playbackPoster);
      expect(mapped.lightPlaybackPoster, fallback.lightPlaybackPoster);
      expect(mapped.posterSeconds, fallback.posterSeconds);
      expect(mapped.videoAvailable, fallback.videoAvailable);
      expect(mapped.lightVideoAvailable, fallback.lightVideoAvailable);
      expect(mapped.packedAlphaVideo, action.packedVideo);
      expect(mapped.alphaPlaybackPoster, action.playbackPoster);
      expect(mapped.alphaCover, action.cover);
      expect(mapped.alphaThumbnail, action.thumbnail);
      expect(mapped.revision, action.revision);
      expect(mapped.loopSeconds, action.loopSeconds);
      expect(mapped.appTestOnly, isTrue);
      expect(mapped.hasPackedAlpha, isTrue);
      for (final light in [false, true]) {
        expect(mapped.videoAvailableFor(light: light), isTrue);
        expect(
          mapped.playbackPosterFor(light: light),
          fallback.playbackPosterFor(light: light),
        );
      }
      expect(fallback.hasPackedAlpha, isFalse);
      expect(fallback.appTestOnly, isFalse);
    },
  );
}
