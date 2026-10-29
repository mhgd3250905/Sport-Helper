import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_legacy_video_catalog.dart';
import 'package:smartfit/app/training_media_config.dart';

class _Assets extends CachingAssetBundle {
  final files = <String, Uint8List>{};
  final requested = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requested.add(key);
    final bytes = files[key] ?? await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

_Assets _fixture({String? invalidPath}) {
  final assets = _Assets();
  final packages = <String, Object>{};
  for (final (i, name) in [
    'builtin',
    'realistic-dark',
    'realistic-light',
  ].indexed) {
    final content = Uint8List.fromList([i + 1, 2, 3]);
    final files = [
      {
        'path':
            invalidPath ??
            '../v0.3.0/realistic/${name == 'realistic-light' ? 'light' : 'dark'}/action-$i.mp4',
        'bytes': content.length,
        'sha256': sha256.convert(content).toString(),
      },
    ];
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'files': files})));
    assets.files['${TrainingMediaConfig.assetRoot}/packages/$name.json'] =
        bytes;
    packages[name] = {
      'fileCount': 1,
      'totalBytes': content.length,
      'manifest': {
        'path': 'packages/$name.json',
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
    };
  }
  assets.files[TrainingMediaConfig.manifestAsset] = Uint8List.fromList(
    utf8.encode(jsonEncode({'version': '0.3.0', 'packages': packages})),
  );
  return assets;
}

void main() {
  test(
    'retained shipped manifests describe every legacy video without MP4 reads',
    () async {
      final assets = _Assets();
      final videos = await loadPoseHubLegacyVideoCatalog(bundle: assets);
      expect(videos, hasLength(378));
      expect(videos.fold<int>(0, (n, video) => n + video.bytes), 146490225);
      expect(videos.map((video) => video.sha256).toSet(), hasLength(378));
      expect(videos.every((video) => video.version == '0.3.0'), isTrue);
      expect(assets.requested, [
        TrainingMediaConfig.manifestAsset,
        for (final name in ['builtin', 'realistic-dark', 'realistic-light'])
          '${TrainingMediaConfig.assetRoot}/packages/$name.json',
      ]);
    },
  );

  test(
    'trusted descriptors retain SHA and sizes from verified submanifests',
    () async {
      final assets = _fixture();
      final files = await loadPoseHubLegacyVideoCatalog(bundle: assets);
      expect(files, hasLength(3));
      expect(files.map((file) => file.bytes), everyElement(3));
      expect(files.first.sha256, sha256.convert([1, 2, 3]).toString());
    },
  );

  test(
    'corrupt metadata fails before a legacy descriptor is trusted',
    () async {
      final assets = _fixture();
      final key = '${TrainingMediaConfig.assetRoot}/packages/builtin.json';
      assets.files[key]![0] ^= 1;
      await expectLater(
        loadPoseHubLegacyVideoCatalog(bundle: assets),
        throwsFormatException,
      );
    },
  );

  test(
    'correctly hashed metadata still cannot introduce a traversing path',
    () async {
      await expectLater(
        loadPoseHubLegacyVideoCatalog(
          bundle: _fixture(invalidPath: '../../outside.mp4'),
        ),
        throwsFormatException,
      );
    },
  );
}
