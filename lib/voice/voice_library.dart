// API copied from HipLab@6020d8e lib/hip/voice/voice_library.dart (mhgd3250905/HipLab,
// 2026-10-18): has / seconds / total / line / asset, as used by VoiceQueue and
// SessionScript. SmartFit 2026-10-19: the data comes from the drill packs
// (docs/drill-pack-spec.md) instead of one assets/voice/manifest.json.
//
// Clip keys:
//   `n.3`, `p.go`, `u.sets` …   a line of the shared `_common` pack
//   `h-squat/cue1` …            line `cue1` of the `h-squat` pack
//   `chime.tick` …              a chime of the `_common` pack (own channel)
import 'package:flutter/services.dart' show rootBundle;

import '../packs/drill_pack.dart';

/// 跟随 App / 中文 / English.
enum VoiceLanguage {
  app('app', '跟随 App'),
  zh('zh', '中文'),
  en('en', 'English');

  const VoiceLanguage(this.id, this.label);
  final String id;
  final String label;
  static VoiceLanguage byId(String? id) =>
      values.where((v) => v.id == id).firstOrNull ?? app;

  /// The clip folder to use. The app UI is Chinese only for now, so
  /// "follow the app" resolves to zh.
  String get clipLanguage => this == en ? 'en' : 'zh';
}

class _Clip {
  const _Clip(this.asset, this.text, this.ms);
  final Map<String, String> asset;
  final Map<String, String> text;
  final Map<String, int> ms;
}

/// Read-only view of every voice line in the loaded drill packs: which clips
/// exist, how long each one really is (decoded length), its written text.
class VoiceLibrary {
  VoiceLibrary._(this._clips, this._chimes);

  factory VoiceLibrary.fromPacks(PackSet packs) {
    final clips = <String, _Clip>{};
    void add(DrillPack p, String Function(String id) key) {
      for (final l in p.lines) {
        clips[key(l.id)] = _Clip(
          {for (final lang in l.ms.keys) lang: p.voiceAsset(l.id, lang)},
          l.text,
          l.ms,
        );
      }
    }

    add(packs.common, (id) => id);
    for (final p in packs.exercises) {
      add(p, (id) => lineKey(p.id, id));
    }
    return VoiceLibrary._(clips, {
      for (final e in packs.common.chimes.entries)
        e.key: packs.common.asset(e.value),
    });
  }

  /// A library with no clips: every lookup misses, durations fall back to
  /// estimates. Used when the packs are unavailable.
  static final empty = VoiceLibrary._(const {}, const {});

  /// Key of a pack's own line (`h-squat/cue1`).
  static String lineKey(String packId, String lineId) => '$packId/$lineId';

  static Future<VoiceLibrary> load() async {
    try {
      return VoiceLibrary.fromPacks(await PackSet.load(rootBundle.loadString));
    } on Object {
      return empty;
    }
  }

  final Map<String, _Clip> _clips;
  final Map<String, String> _chimes;

  bool has(String key, {String lang = 'zh'}) => key.startsWith('chime.')
      ? _chimes.containsKey(key.substring(6))
      : _clips[key]?.ms.containsKey(lang) ?? false;

  /// Clip length in seconds (an estimate when the clip is unknown).
  double seconds(String key, {String lang = 'zh'}) {
    if (key.startsWith('chime.')) return 0; // chimes play on their own channel
    final ms = _clips[key]?.ms[lang];
    if (ms != null) return ms / 1000;
    if (key.startsWith('n.')) return .4;
    return 1.2;
  }

  double total(Iterable<String> keys, {String lang = 'zh'}) =>
      keys.fold(0.0, (s, k) => s + seconds(k, lang: lang)) +
      // tiny gap between concatenated clips
      .06 *
          (keys.where((k) => !k.startsWith('chime.')).length - 1).clamp(0, 99);

  /// The written line for a clip (for the on-screen subtitle).
  String? line(String key, {String lang = 'zh'}) => _clips[key]?.text[lang];

  String asset(String key, {String lang = 'zh'}) {
    if (key.startsWith('chime.')) {
      return _chimes[key.substring(6)] ??
          '${PackSet.defaultRoot}/$commonPackId/chime/${key.substring(6)}.m4a';
    }
    final a = _clips[key]?.asset[lang];
    if (a != null) return a;
    final slash = key.indexOf('/');
    return slash < 0
        ? '${PackSet.defaultRoot}/$commonPackId/voice/$lang/$key.m4a'
        : '${PackSet.defaultRoot}/${key.substring(0, slash)}/voice/$lang/'
              '${key.substring(slash + 1)}.m4a';
  }
}
