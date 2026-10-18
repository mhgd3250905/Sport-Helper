// Copied from HipLab@main lib/hip/voice/voice_library.dart (mhgd3250905/HipLab, 2026-10-18). SmartFit: import paths only.
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

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

/// Read-only view of `assets/voice/manifest.json` (written by
/// tools/voice/build_voice.py): which clips exist, how long each one is,
/// and which clip speaks a given content string (doses, tips).
class VoiceLibrary {
  VoiceLibrary(this._clips, this._chimes, this._texts, this._lines);

  factory VoiceLibrary.fromJson(Map<String, dynamic> j) {
    Map<String, int> ints(Object? m) => {
      for (final e in Map<String, dynamic>.from(m as Map? ?? const {}).entries)
        e.key: (e.value as num).toInt(),
    };
    return VoiceLibrary(
      {
        for (final e in Map<String, dynamic>.from(j['clips'] as Map).entries)
          e.key: ints(e.value),
      },
      ints(j['chimes']),
      {
        for (final e in Map<String, dynamic>.from(j['texts'] as Map).entries)
          e.key: Map<String, String>.from(e.value as Map),
      },
      {
        for (final e in Map<String, dynamic>.from(
          j['lines'] as Map? ?? const {},
        ).entries)
          e.key: Map<String, String>.from(e.value as Map),
      },
    );
  }

  /// A library with no clips: every lookup misses, durations fall back to
  /// estimates. Used when the manifest is unavailable.
  static final empty = VoiceLibrary(const {}, const {}, const {}, const {});

  static const manifestAsset = 'assets/voice/manifest.json';

  static Future<VoiceLibrary> load() async {
    try {
      return VoiceLibrary.fromJson(
        jsonDecode(await rootBundle.loadString(manifestAsset))
            as Map<String, dynamic>,
      );
    } on Object {
      return empty;
    }
  }

  final Map<String, Map<String, int>> _clips;
  final Map<String, int> _chimes;
  final Map<String, Map<String, String>> _texts;
  final Map<String, Map<String, String>> _lines;

  bool has(String key, {String lang = 'zh'}) => key.startsWith('chime.')
      ? _chimes.containsKey(key.substring(6))
      : _clips[lang]?.containsKey(key) ?? false;

  /// Clip length in seconds (an estimate when the clip is unknown).
  double seconds(String key, {String lang = 'zh'}) {
    if (key.startsWith('chime.')) return 0; // chimes play on their own channel
    final ms = _clips[lang]?[key];
    if (ms != null) return ms / 1000;
    if (key.startsWith('n.')) return .4;
    return 1.2;
  }

  double total(Iterable<String> keys, {String lang = 'zh'}) =>
      keys.fold(0.0, (s, k) => s + seconds(k, lang: lang)) +
      // tiny gap between concatenated clips
      .06 *
          (keys.where((k) => !k.startsWith('chime.')).length - 1).clamp(0, 99);

  /// Clip key for a content string, e.g. a dose ("每侧 30 秒") or a tip.
  String? textKey(String kind, String text) => _texts[kind]?[text];

  /// The written line for a clip (for the on-screen subtitle).
  String? line(String key, {String lang = 'zh'}) => _lines[key]?[lang];

  String asset(String key, {String lang = 'zh'}) => key.startsWith('chime.')
      ? 'assets/voice/chime/${key.substring(6)}.m4a'
      : 'assets/voice/$lang/$key.m4a';
}
