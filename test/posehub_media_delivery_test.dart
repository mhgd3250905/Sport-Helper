import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_delivery.dart';

class _ManifestBundle extends CachingAssetBundle {
  _ManifestBundle(this.manifest);
  final Object? manifest;

  @override
  Future<ByteData> load(String key) async {
    expect(key, PoseHubMediaDelivery.asset);
    return ByteData.sublistView(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
    );
  }
}

class _Fixture {
  static final revision = 'a' * 64;
  final manifest = <String, Object?>{
    'format': 'smartfit-posehub-file-delivery@2',
    'ready': true,
    'packVersion': 'r1-v3',
    'catalogSha256': revision,
    'releaseTag': 'posehub-app-test-pack-r1-v3',
    'mediaBaseUrls': [
      'https://domestic.example.test/pack/r1-v3/',
      'https://media.uuugk.win/pack/r1-v3/',
    ],
  };

  Future<PoseHubMediaDelivery> load({
    String? catalogRevision,
    String mediaBaseUrls = '',
  }) => PoseHubMediaDelivery.load(
    catalogRevision: catalogRevision ?? revision,
    mediaBaseUrls: mediaBaseUrls,
    bundle: _ManifestBundle(manifest),
  );
}

void main() {
  test('pending delivery cannot be enabled by a mirror override', () async {
    final fixture = _Fixture();
    fixture.manifest['ready'] = false;
    final delivery = await fixture.load(
      mediaBaseUrls: '["https://override.example.test/pack/r1-v3/"]',
    );
    expect(delivery.mediaBaseUrls, isEmpty);
    expect(PoseHubMediaDelivery.unavailable().mediaBaseUrls, isEmpty);
  });

  test(
    'ordered immutable mirrors preserve original nested case-sensitive paths',
    () async {
      final delivery = await _Fixture().load();
      expect(delivery.packVersion, 'r1-v3');
      expect(delivery.mediaBaseUrls.map((base) => base.host), [
        'domestic.example.test',
        'media.uuugk.win',
      ]);
      const path = 'media/abs-A/abs-A-r2-alpha-r2/abs-A.rgb-alpha.mp4';
      expect(
        delivery.mediaBaseUrls.last.resolve(path).toString(),
        'https://media.uuugk.win/pack/r1-v3/$path',
      );
      expect(() => delivery.mediaBaseUrls.clear(), throwsUnsupportedError);
    },
  );

  test(
    'JSON build override replaces the full list and preserves its order',
    () async {
      final delivery = await _Fixture().load(
        mediaBaseUrls: jsonEncode([
          'https://first.example.test/v3/',
          'https://backup.example.test/v3/',
        ]),
      );
      expect(delivery.mediaBaseUrls.map((base) => base.host), [
        'first.example.test',
        'backup.example.test',
      ]);
      for (final raw in [
        '',
        '[]',
        '{}',
        '"https://not-a-list.test/"',
        'broken',
      ]) {
        if (raw.isEmpty) continue;
        await expectLater(
          _Fixture().load(mediaBaseUrls: raw),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'wrong catalog or pack identities reject before selecting a source',
    () async {
      await expectLater(
        _Fixture().load(catalogRevision: 'b' * 64),
        throwsFormatException,
      );
      for (final mutate in <void Function(_Fixture)>[
        (f) => f.manifest['format'] = 'smartfit-posehub-file-delivery@1',
        (f) => f.manifest['packVersion'] = 'r1-v2',
        (f) => f.manifest['catalogSha256'] = 'bad-sha',
      ]) {
        final fixture = _Fixture();
        mutate(fixture);
        await expectLater(fixture.load(), throwsFormatException);
      }
    },
  );

  test('unsafe or empty mirror lists reject in assets and overrides', () async {
    for (final invalid in <Object?>[
      null,
      [],
      'https://not-a-list.test/',
      [1],
      ['http://cdn.example.test/v3/'],
      ['https://user:password@cdn.example.test/v3/'],
      ['https://cdn.example.test/v3/?token=fixture'],
      ['https://cdn.example.test/v3/#fragment'],
      ['https://cdn.example.test/v3'],
      ['https:///'],
      ['file:///tmp/media/'],
      ['//cdn.example.test/v3/'],
      ['https://cdn.example.test/a/../v3/'],
      ['https://cdn.example.test/v3/', 'https://cdn.example.test/v3/'],
    ]) {
      final fixture = _Fixture();
      fixture.manifest['mediaBaseUrls'] = invalid;
      await expectLater(
        fixture.load(),
        throwsFormatException,
        reason: 'asset invalid mirror list',
      );
      await expectLater(
        _Fixture().load(mediaBaseUrls: jsonEncode(invalid)),
        throwsFormatException,
        reason: 'override invalid mirror list',
      );
    }
  });
}
