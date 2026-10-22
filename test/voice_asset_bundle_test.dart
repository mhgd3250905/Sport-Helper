import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/voice/voice_asset_bundle.dart';
import 'package:smartfit/voice/voice_library.dart';

import 'support.dart';

Map<String, dynamic> _manifest() =>
    jsonDecode(File(VoiceAssetBundle.manifestAsset).readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('App source uses all 695 encoded assets and measured lengths', () async {
    final (_, _, voices, _) = await AppServices.loadContent();
    final manifest = _manifest();
    final clips = manifest['clips'] as List;
    expect(clips, hasLength(695));
    expect(voices.languages, {'zh'});
    final assets = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundled = assets.listAssets().toSet();
    final target = <String>{};
    for (final raw in clips) {
      final clip = raw as Map;
      final key = clip['pack'] == '_common'
          ? clip['line'] as String
          : '${clip['pack']}/${clip['line']}';
      final asset = clip['asset'] as String;
      target.add(asset);
      expect(voices.has(key), isTrue, reason: key);
      expect(voices.asset(key), asset, reason: key);
      expect(
        voices.seconds(key),
        (clip['decoded_ms'] as int) / 1000,
        reason: key,
      );
      expect(bundled, contains(asset), reason: key);
      expect(voices.line(key), isNotEmpty, reason: key);
    }
    expect(
      bundled
          .where(
            (p) => p.startsWith('assets/voice_lc32/') && p.endsWith('.m4a'),
          )
          .toSet(),
      target,
    );
    expect(
      bundled.where(
        (p) => p.startsWith('assets/packs/') && p.contains('/voice/'),
      ),
      isEmpty,
    );
    for (final chime in ['tick', 'start', 'end', 'finish', 'silence']) {
      expect(voices.has('chime.$chime'), isTrue);
      expect(
        voices.asset('chime.$chime'),
        'assets/packs/_common/chime/$chime.m4a',
      );
      expect(bundled, contains(voices.asset('chime.$chime')));
      expect(voices.seconds('chime.$chime'), 0);
    }
    expect(voices.has('n.1', lang: 'en'), isFalse);
  });

  test(
    'phrase duration sums the new decoded lengths rather than old pack ms',
    () {
      final voices = loadVoices();
      final clips = (_manifest()['clips'] as List).cast<Map>();
      int ms(String key) =>
          clips.firstWhere(
                (c) => c['pack'] == '_common' && c['line'] == key,
              )['decoded_ms']
              as int;
      expect(
        voices.total(['n.1', 'n.2']),
        (ms('n.1') + ms('n.2')) / 1000 + .06,
      );
      expect(voices.total(['chime.tick', 'n.1']), ms('n.1') / 1000);
      expect(voices.number(10), ['n.10']);
      expect(voices.secondsPhrase(10), ['n.10', 'u.sec']);
    },
  );

  test(
    'an incomplete bundle cannot silently fall back to unpackaged originals',
    () {
      final manifest = _manifest();
      (manifest['clips'] as List).removeLast();
      expect(
        () => VoiceLibrary.fromPacks(
          loadPacksSync(),
          bundle: VoiceAssetBundle.fromJson(manifest),
        ),
        throwsFormatException,
      );
    },
  );

  test('invalid encoding, duplicate clips and escaping paths are rejected', () {
    for (final field in ['profile', 'channels', 'sample_rate_hz']) {
      final manifest = _manifest()..[field] = field == 'profile' ? 'HE-AAC' : 2;
      expect(() => VoiceAssetBundle.fromJson(manifest), throwsFormatException);
    }
    final duplicate = _manifest();
    final clips = duplicate['clips'] as List;
    clips.add(clips.first);
    expect(() => VoiceAssetBundle.fromJson(duplicate), throwsFormatException);
    final escaping = _manifest();
    ((escaping['clips'] as List).first as Map)['asset'] =
        'assets/../outside.m4a';
    expect(() => VoiceAssetBundle.fromJson(escaping), throwsFormatException);
  });
}
