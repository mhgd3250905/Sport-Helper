import 'package:flutter/services.dart' show rootBundle;
import 'package:ugk_trainer/engine.dart';

import '../packs/drill_pack.dart';
import 'voice_asset_bundle.dart';

enum VoiceLanguage {
  app('app', '跟随 App'),
  zh('zh', '中文'),
  en('en', 'English');

  const VoiceLanguage(this.id, this.label);
  final String id;
  final String label;

  static VoiceLanguage byId(String? id) =>
      values.where((v) => v.id == id).firstOrNull ?? app;

  // SmartFit's interface currently uses Chinese.
  String get clipLanguage => this == en ? 'en' : 'zh';
}

/// Uses ugk_trainer's meanings and phrase construction, with optional bundled
/// speech paths and measured lengths for the selected encoding variant.
class VoiceLibrary extends VoiceSource {
  VoiceLibrary._(this.source, [this.bundle]);

  factory VoiceLibrary.fromPacks(PackSet packs, {VoiceAssetBundle? bundle}) {
    if (bundle != null) {
      final expected = <String>{};
      for (final pack in [packs.common, ...packs.exercises]) {
        for (final line in pack.lines) {
          for (final language in line.text.keys) {
            final key = pack.isCommon ? line.id : lineKey(pack.id, line.id);
            if (bundle.clip(key, language) == null) {
              throw FormatException('Missing bundled speech: $key/$language');
            }
            expected.add('$key/$language');
          }
        }
      }
      final actual = {
        for (final entry in bundle.clips.entries)
          for (final language in entry.value.keys) '${entry.key}/$language',
      };
      if (actual.length != expected.length || !actual.containsAll(expected)) {
        throw const FormatException('Speech bundle does not match drill packs');
      }
    }
    return VoiceLibrary._(
      DrillPackVoiceSource.fromPacks(
        common: packs.common.json,
        packs: {for (final p in packs.exercises) p.id: p.json},
        root: packs.common.folder.substring(
          0,
          packs.common.folder.lastIndexOf('/'),
        ),
      ),
      bundle,
    );
  }

  final DrillPackVoiceSource source;
  final VoiceAssetBundle? bundle;
  static final empty = VoiceLibrary._(DrillPackVoiceSource.empty);

  static String lineKey(String packId, String lineId) =>
      DrillPackVoiceSource.lineKey(packId, lineId);

  static Future<VoiceLibrary> load() async {
    try {
      return VoiceLibrary.fromPacks(
        await PackSet.load(rootBundle.loadString),
        bundle: await VoiceAssetBundle.load(rootBundle.loadString),
      );
    } on Object {
      return empty;
    }
  }

  @override
  Set<String> get languages => bundle?.languages ?? source.languages;
  @override
  bool has(String key, {String lang = 'zh'}) =>
      key.startsWith('chime.') || bundle == null
      ? source.has(key, lang: lang)
      : bundle!.clip(key, lang) != null;
  @override
  double seconds(String key, {String lang = 'zh'}) {
    final clip = bundle?.clip(key, lang);
    return clip != null
        ? clip.milliseconds / 1000
        : source.seconds(key, lang: lang);
  }

  @override
  double total(Iterable<String> keys, {String lang = 'zh'}) =>
      super.total(keys, lang: lang);
  @override
  String asset(String key, {String lang = 'zh'}) =>
      bundle?.clip(key, lang)?.asset ?? source.asset(key, lang: lang);
  @override
  String? line(String key, {String lang = 'zh'}) =>
      source.line(key, lang: lang);
  @override
  String? call(VoiceCall c) => source.call(c);
  @override
  String? drill(String exerciseId, DrillLine line) =>
      source.drill(exerciseId, line);
  @override
  List<String> number(int n) => source.number(n);
  @override
  List<String> secondsPhrase(int n) => source.secondsPhrase(n);
  @override
  List<String> minutesPhrase(int n) => source.minutesPhrase(n);
  @override
  List<String> setsPhrase(int n) => source.setsPhrase(n);
  @override
  List<String> repsPhrase(int n) => source.repsPhrase(n);
  @override
  List<String> ordinalSet(int n) => source.ordinalSet(n);
  @override
  List<String> ordinalRound(int n) => source.ordinalRound(n);
}
