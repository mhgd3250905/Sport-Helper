import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_config.dart';
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
  final manifest = <String, Object?>{
    'format': 'smartfit-posehub-file-delivery@3',
    'ready': true,
    'mediaBaseUrls': [
      'https://domestic.example.test/pack/{pack}/',
      'https://media.uuugk.win/pack/{pack}/',
    ],
  };

  Future<PoseHubMediaDelivery> load({
    String packVersion = 'r2-v1',
    String mediaBaseUrls = '',
  }) => PoseHubMediaDelivery.load(
    packVersion: packVersion,
    mediaBaseUrls: mediaBaseUrls,
    bundle: _ManifestBundle(manifest),
  );
}

void main() {
  test('pending delivery cannot be enabled by a mirror override', () async {
    final fixture = _Fixture();
    fixture.manifest['ready'] = false;
    final delivery = await fixture.load(
      mediaBaseUrls: '["https://override.example.test/pack/{pack}/"]',
    );
    expect(delivery.mediaBaseUrls, isEmpty);
    expect(delivery.packVersion, 'r2-v1');
    expect(PoseHubMediaDelivery.unavailable('r2-v1').mediaBaseUrls, isEmpty);
  });

  test(
    'ordered immutable mirrors preserve original nested case-sensitive paths',
    () async {
      final delivery = await _Fixture().load();
      expect(delivery.packVersion, 'r2-v1');
      expect(delivery.mediaBaseUrls.map((base) => base.host), [
        'domestic.example.test',
        'media.uuugk.win',
      ]);
      const path = 'media/abs-A/abs-A-r2-alpha-r2/abs-A.rgb-alpha.mp4';
      expect(
        delivery.mediaBaseUrls.last.resolve(path).toString(),
        'https://media.uuugk.win/pack/r2-v1/$path',
      );
      expect(() => delivery.mediaBaseUrls.clear(), throwsUnsupportedError);
    },
  );

  test('the pack follows the catalogue in use, not the asset', () async {
    final delivery = await _Fixture().load(packVersion: 'r2-v2');
    expect(
      delivery.mediaBaseUrls.last.toString(),
      'https://media.uuugk.win/pack/r2-v2/',
    );
  });

  test(
    'JSON build override replaces the full list and preserves its order',
    () async {
      final delivery = await _Fixture().load(
        mediaBaseUrls: jsonEncode([
          'https://first.example.test/{pack}/',
          'https://backup.example.test/{pack}/',
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
    'wrong format or pack identities reject before selecting a source',
    () async {
      for (final pack in ['', 'R2-V1', '../r2-v1', 'r2_v1']) {
        await expectLater(
          _Fixture().load(packVersion: pack),
          throwsFormatException,
        );
      }
      for (final mutate in <void Function(_Fixture)>[
        (f) => f.manifest['format'] = 'smartfit-posehub-file-delivery@2',
        (f) => f.manifest['mediaBaseUrls'] = ['https://media.uuugk.win/v3/'],
        (f) => f.manifest['mediaBaseUrls'] = [
          'https://media.uuugk.win/{pack}/{pack}/',
        ],
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
      ['http://cdn.example.test/{pack}/'],
      ['https://user:password@cdn.example.test/{pack}/'],
      ['https://cdn.example.test/{pack}/?token=fixture'],
      ['https://cdn.example.test/{pack}/#fragment'],
      ['https://cdn.example.test/{pack}'],
      ['https:///{pack}/'],
      ['file:///tmp/media/'],
      ['//cdn.example.test/{pack}/'],
      ['https://cdn.example.test/a/../{pack}/'],
      ['https://cdn.example.test/{pack}/', 'https://cdn.example.test/{pack}/'],
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

  test('release mirrors reuse only their /pack/<version>/ directory', () {
    expect(
      PoseHubMediaConfig.fromMirrors(
        'https://media.uuugk.win/pack/r1-v3/',
        'https://cn.example.test/mirror/pack/r1-v3/',
      ),
      jsonEncode([
        'https://media.uuugk.win/pack/{pack}/',
        'https://cn.example.test/mirror/pack/{pack}/',
      ]),
    );
    expect(PoseHubMediaConfig.fromMirrors('https://cdn.test/v0.3.0-app/', ''), '');
  });
}
