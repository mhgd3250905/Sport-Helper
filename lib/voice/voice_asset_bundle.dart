import 'dart:convert';

/// Encoded speech assets and the lengths actually used by the trainer queue.
/// The original drill packs remain the source of text, meanings and chimes.
class VoiceAssetBundle {
  VoiceAssetBundle._(this.clips);

  static const manifestAsset = 'assets/voice_lc32/v1/manifest.json';
  final Map<String, Map<String, VoiceAssetClip>> clips;

  factory VoiceAssetBundle.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 ||
        json['version'] != 'v1' ||
        json['format'] != 'm4a' ||
        json['profile'] != 'LC' ||
        json['target_bit_rate_bps'] != 32000 ||
        json['sample_rate_hz'] != 22050 ||
        json['channels'] != 1) {
      throw const FormatException('Unsupported speech asset bundle');
    }
    final clips = <String, Map<String, VoiceAssetClip>>{};
    final safePack = RegExp(r'^[A-Za-z0-9_-]+$');
    final safeLine = RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*$');
    final sha256 = RegExp(r'^[0-9a-f]{64}$');
    for (final raw in json['clips'] as List) {
      final entry = Map<String, dynamic>.from(raw as Map);
      final pack = entry['pack'] as String;
      final line = entry['line'] as String;
      final lang = entry['lang'] as String;
      final asset = entry['asset'] as String;
      final ms = entry['decoded_ms'] as int;
      if (!safePack.hasMatch(pack) ||
          !safeLine.hasMatch(line) ||
          lang != 'zh' ||
          asset != 'assets/voice_lc32/v1/$pack/$lang/$line.m4a' ||
          ms <= 0 ||
          (entry['bytes'] as int) <= 0 ||
          !sha256.hasMatch(entry['sha256'] as String)) {
        throw FormatException('Invalid speech asset: $pack/$line/$lang');
      }
      final key = pack == '_common' ? line : '$pack/$line';
      final languages = clips.putIfAbsent(key, () => {});
      if (languages.containsKey(lang)) {
        throw FormatException('Duplicate speech asset: $key/$lang');
      }
      languages[lang] = VoiceAssetClip(asset: asset, milliseconds: ms);
    }
    return VoiceAssetBundle._(
      Map<String, Map<String, VoiceAssetClip>>.unmodifiable({
        for (final entry in clips.entries)
          entry.key: Map<String, VoiceAssetClip>.unmodifiable(entry.value),
      }),
    );
  }

  static Future<VoiceAssetBundle> load(
    Future<String> Function(String path) read,
  ) async => VoiceAssetBundle.fromJson(
    jsonDecode(await read(manifestAsset)) as Map<String, dynamic>,
  );

  VoiceAssetClip? clip(String key, String language) => clips[key]?[language];

  Set<String> get languages => {
    for (final entry in clips.values) ...entry.keys,
  };
}

class VoiceAssetClip {
  const VoiceAssetClip({required this.asset, required this.milliseconds});

  final String asset;
  final int milliseconds;
}
