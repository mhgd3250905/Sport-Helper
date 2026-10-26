import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

class _Bundle extends CachingAssetBundle {
  final files = <String, List<int>>{};
  final reads = <String>[];

  @override
  Future<ByteData> load(String key) async {
    reads.add(key);
    final data = files[key];
    if (data == null) throw FlutterError('Missing optional asset: $key');
    // The view verifies that the loader honors ByteData offsets and length.
    final padded = Uint8List.fromList([99, ...data, 88]);
    return ByteData.view(padded.buffer, 1, data.length);
  }
}

class _Fixture {
  _Fixture() {
    sha = coach.sha256Hex(payload);
    asset = '${PoseHubBundledImages.assetPrefix}$sha.webp';
    index = {
      'format': 'smartfit-posehub-bundled-images@1',
      'catalogSha256': revision,
      'uniqueFiles': 1,
      'uniqueBytes': payload.length,
      'referencedBytes': payload.length * 2,
      'files': {
        for (final path in [cover, thumbnail])
          path: {'asset': asset, 'bytes': payload.length, 'sha256': sha},
      },
    };
    bundle.files[asset] = payload;
  }
  static final revision = 'a' * 64;
  static const cover = 'media/fixture/fixture.cover.webp';
  static const thumbnail = 'media/fixture/fixture.thumbnail.webp';
  final payload = [1, 2, 3, 4];
  final bundle = _Bundle();
  late final String sha;
  late final String asset;
  late final Map<String, Object?> index;

  coach.PoseHubPackFile file({String? path, int? bytes, String? hash}) =>
      coach.PoseHubPackFile.fromJson({
        'path': path ?? cover,
        'bytes': bytes ?? payload.length,
        'sha256': hash ?? sha,
      });

  Future<PoseHubBundledImages> load({String? revision}) {
    bundle.files[PoseHubBundledImages.indexAsset] = utf8.encode(
      jsonEncode(index),
    );
    return PoseHubBundledImages.load(
      catalogRevision: revision ?? _Fixture.revision,
      bundle: bundle,
    );
  }
}

void main() {
  test(
    'exact catalog/file descriptors load shared, content-addressed bytes',
    () async {
      final fixture = _Fixture();
      final images = await fixture.load();
      expect(await images.loadFile(fixture.file()), fixture.payload);
      expect(
        await images.loadFile(fixture.file(path: _Fixture.thumbnail)),
        fixture.payload,
      );
      expect(fixture.bundle.reads, [
        PoseHubBundledImages.indexAsset,
        fixture.asset,
        fixture.asset,
      ]);
    },
  );

  test(
    'path, SHA, size and non-image misses do not read any payload',
    () async {
      final fixture = _Fixture();
      final images = await fixture.load();
      for (final file in [
        fixture.file(path: 'media/other.webp'),
        fixture.file(hash: '0' * 64),
        fixture.file(bytes: fixture.payload.length + 1),
        fixture.file(path: 'media/fixture/video.mp4'),
      ]) {
        expect(await images.loadFile(file), isNull);
      }
      expect(fixture.bundle.reads, [PoseHubBundledImages.indexAsset]);
    },
  );

  test(
    'catalog mismatch, unsafe assets/paths and inconsistent totals reject',
    () async {
      final mismatched = _Fixture();
      await expectLater(
        mismatched.load(revision: 'b' * 64),
        throwsFormatException,
      );
      for (final mutate in <void Function(_Fixture)>[
        (f) => ((f.index['files']! as Map)[_Fixture.cover] as Map)['asset'] =
            '${PoseHubBundledImages.assetPrefix}../${f.sha}.webp',
        (f) {
          final files = f.index['files']! as Map;
          files['../outside.webp'] = files.remove(_Fixture.cover);
        },
        (f) => f.index['uniqueBytes'] = 1,
      ]) {
        final fixture = _Fixture();
        mutate(fixture);
        await expectLater(fixture.load(), throwsFormatException);
        expect(fixture.bundle.reads, [PoseHubBundledImages.indexAsset]);
      }
    },
  );

  test(
    'catalog-version image directories resolve within the image root',
    () async {
      final fixture = _Fixture();
      final asset =
          '${PoseHubBundledImages.assetPrefix}'
          '${_Fixture.revision}/${fixture.sha}.webp';
      for (final spec in (fixture.index['files']! as Map).values) {
        (spec as Map)['asset'] = asset;
      }
      fixture.bundle.files[asset] = fixture.payload;
      final images = await fixture.load();
      expect(await images.loadFile(fixture.file()), fixture.payload);
      expect(fixture.bundle.reads, [PoseHubBundledImages.indexAsset, asset]);
    },
  );

  test(
    'missing or corrupted optional payload becomes a downloader cache miss',
    () async {
      for (final payload in <List<int>?>[
        null,
        [9, 9, 9, 9],
        [1, 2],
      ]) {
        final fixture = _Fixture();
        final images = await fixture.load();
        if (payload == null) {
          fixture.bundle.files.remove(fixture.asset);
        } else {
          fixture.bundle.files[fixture.asset] = payload;
        }
        expect(await images.loadFile(fixture.file()), isNull);
      }
    },
  );
}
