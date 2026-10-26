import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_delivery.dart';
import 'package:ugk_coach/ugk_coach.dart';

class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.manifest);
  final Object? manifest;

  @override
  Future<ByteData> load(String key) async {
    if (key != PoseHubMediaDelivery.asset) {
      throw StateError('Unexpected delivery asset read: $key');
    }
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
  }
}

class _Fixture {
  static final revision = 'a' * 64;
  static final sha = 'b' * 64;
  static const path = 'media/fixture/fixture.rgb-alpha.mp4';
  static const assetName = '动作 #?:%&=@[]+.mp4';
  static const base =
      'https://github.com/example/sdk/releases/download/fixture-v3/';

  final manifest = <String, Object?>{
    'format': 'smartfit-posehub-file-delivery@1',
    'ready': true,
    'catalogSha256': revision,
    'releaseTag': 'fixture-v3',
    'mediaBaseUrl': base,
    'files': <String, Object?>{
      path: <String, Object?>{
        'assetName': assetName,
        'bytes': 12,
        'sha256': sha,
      },
    },
  };

  Map<String, Object?> get record =>
      (manifest['files']! as Map)[path] as Map<String, Object?>;

  PoseHubPackFile file({String? sourcePath, int bytes = 12, String? hash}) =>
      PoseHubPackFile.fromJson({
        'path': sourcePath ?? path,
        'bytes': bytes,
        'sha256': hash ?? sha,
      });

  Future<PoseHubMediaDelivery> load({
    String? catalogRevision,
    String mediaBaseUrl = '',
  }) => PoseHubMediaDelivery.load(
    catalogRevision: catalogRevision ?? revision,
    mediaBaseUrl: mediaBaseUrl,
    bundle: _ManifestBundle(manifest),
  );
}

void main() {
  test(
    'pending inventory never invents URLs, even with a public base override',
    () async {
      final fixture = _Fixture();
      fixture.manifest['ready'] = false;
      fixture.manifest['mediaBaseUrl'] = null;
      final pending = await fixture.load(
        mediaBaseUrl: 'https://cdn.example.test/media/',
      );
      expect(pending.mediaBaseUrl, isNull);
      expect(pending.urlFor(fixture.file()), isNull);
      expect(PoseHubMediaDelivery.unavailable().urlFor(fixture.file()), isNull);
    },
  );

  test(
    'exact catalog path maps a reserved-character asset name as one segment',
    () async {
      final fixture = _Fixture();
      final delivery = await fixture.load();
      final url = delivery.urlFor(fixture.file())!;
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(url.pathSegments, [
        'example',
        'sdk',
        'releases',
        'download',
        'fixture-v3',
        _Fixture.assetName,
      ]);
      expect(url.hasQuery, isFalse);
      expect(url.hasFragment, isFalse);
      expect(url.userInfo, isEmpty);
      expect(url.toString(), contains('%23%3F%3A%25'));

      final overridden = await fixture.load(
        mediaBaseUrl: 'https://cdn.example.test/current/',
      );
      final overriddenUrl = overridden.urlFor(fixture.file())!;
      expect(overriddenUrl.host, 'cdn.example.test');
      expect(overriddenUrl.pathSegments, ['current', _Fixture.assetName]);
      expect(overriddenUrl.hasQuery, isFalse);
      expect(overriddenUrl.hasFragment, isFalse);
      expect(delivery.mediaBaseUrl.toString(), _Fixture.base);
    },
  );

  test(
    'unknown paths and mismatched file size or SHA have no download URL',
    () async {
      final fixture = _Fixture();
      final delivery = await fixture.load();
      for (final file in [
        fixture.file(sourcePath: 'media/other/other.mp4'),
        fixture.file(bytes: 13),
        fixture.file(hash: '0' * 64),
      ]) {
        expect(delivery.urlFor(file), isNull);
      }
    },
  );

  test(
    'invalid revision, manifest and immutable asset records reject',
    () async {
      await expectLater(
        _Fixture().load(catalogRevision: 'c' * 64),
        throwsFormatException,
      );
      final malformedRevision = _Fixture();
      malformedRevision.manifest['catalogSha256'] = 'not-a-sha';
      await expectLater(
        malformedRevision.load(catalogRevision: 'not-a-sha'),
        throwsFormatException,
      );
      for (final mutate in <void Function(_Fixture)>[
        (f) => f.manifest['format'] = 'unrelated@1',
        (f) => f.manifest['files'] = [],
        (f) => (f.manifest['files']! as Map)[_Fixture.path] = [],
        (f) => f.record['bytes'] = 0,
        (f) => f.record['bytes'] = 1.5,
        (f) => f.record['sha256'] = 'bad-hash',
        (f) => f.record['sha256'] = 'B' * 64,
      ]) {
        final fixture = _Fixture();
        mutate(fixture);
        await expectLater(fixture.load(), throwsFormatException);
      }
      for (final name in [
        '',
        '.',
        '..',
        '/absolute.mp4',
        'nested/video.mp4',
        r'nested\video.mp4',
        'video\u0000.mp4',
        'video\u007f.mp4',
      ]) {
        final fixture = _Fixture();
        fixture.record['assetName'] = name;
        await expectLater(fixture.load(), throwsFormatException, reason: name);
      }
    },
  );

  test(
    'HTTP, credentials, queries, fragments and invalid bases reject',
    () async {
      for (final base in [
        'http://cdn.example.test/media/',
        'https://user:password@cdn.example.test/media/',
        'https://user@cdn.example.test/media/',
        'https://cdn.example.test/media/?token=fixture',
        'https://cdn.example.test/media/?',
        'https://cdn.example.test/media/#fragment',
        'https://cdn.example.test/media',
        'https:///',
        'file:///tmp/media/',
        '//cdn.example.test/media/',
      ]) {
        final fixture = _Fixture();
        fixture.manifest['mediaBaseUrl'] = base;
        await expectLater(fixture.load(), throwsFormatException, reason: base);
        await expectLater(
          _Fixture().load(mediaBaseUrl: base),
          throwsFormatException,
          reason: 'override $base',
        );
      }
    },
  );
}
