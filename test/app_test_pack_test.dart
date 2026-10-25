import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_pack.dart';
import 'package:smartfit/domain/exercise.dart';

/// Use the actual importer output and its immutable catalog snapshot. Mutations
/// below affect decoded in-memory fixtures only, never delivered asset files.
class _Fixture {
  _Fixture(this.index, this.catalog);

  factory _Fixture.bundled() {
    final index =
        jsonDecode(File(AppTestPackConfig.indexAsset).readAsStringSync())
            as Map<String, dynamic>;
    final catalog =
        jsonDecode(File(index['catalogAsset'] as String).readAsStringSync())
            as Map<String, dynamic>;
    return _Fixture(index, catalog);
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
      'actual index maps verified media and retains the complete catalog',
      () async {
        final fixture = _Fixture.bundled();
        final pack = await fixture.load();

        expect(pack.id, 'app-test-pack-r1');
        expect(pack.catalog, hasLength(fixture.entries.length));
        expect(pack.catalog.length, greaterThan(93));
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
        final fixture = _Fixture.bundled();
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
        final fixture = _Fixture.bundled();
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
          final fixture = _Fixture.bundled();
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
        final fixture = _Fixture.bundled();
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
    'applying real alpha media preserves both opaque theme fallbacks',
    () async {
      final fixture = _Fixture.bundled();
      final pack = await fixture.load();
      final legacy =
          (jsonDecode(
                    File(
                      'assets/training_media/v0.3.0-app/assets-index.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['actions']
              as Map<String, dynamic>;
      final id = pack.actions.keys.firstWhere(legacy.containsKey);
      final themes = legacy[id] as Map<String, dynamic>;
      String path(String theme, String role) =>
          ((themes[theme] as Map)[role] as Map)['asset'] as String;
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
