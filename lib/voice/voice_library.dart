import 'package:flutter/services.dart' show rootBundle;
import 'package:ugk_trainer/engine.dart';

import '../packs/drill_pack.dart';

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

/// Compatibility view for existing content fixtures. All clip lookup,
/// phrase construction and duration rules belong to ugk_trainer.
class VoiceLibrary extends VoiceSource {
  VoiceLibrary._(this.source);

  factory VoiceLibrary.fromPacks(PackSet packs) => VoiceLibrary._(
    DrillPackVoiceSource.fromPacks(
      common: packs.common.json,
      packs: {for (final p in packs.exercises) p.id: p.json},
      root: packs.common.folder.substring(
        0,
        packs.common.folder.lastIndexOf('/'),
      ),
    ),
  );

  final DrillPackVoiceSource source;
  static final empty = VoiceLibrary._(DrillPackVoiceSource.empty);

  static String lineKey(String packId, String lineId) =>
      DrillPackVoiceSource.lineKey(packId, lineId);

  static Future<VoiceLibrary> load() async {
    try {
      return VoiceLibrary._(
        await DrillPackVoiceSource.load(rootBundle.loadString),
      );
    } on Object {
      return empty;
    }
  }

  @override
  Set<String> get languages => source.languages;
  @override
  bool has(String key, {String lang = 'zh'}) => source.has(key, lang: lang);
  @override
  double seconds(String key, {String lang = 'zh'}) =>
      source.seconds(key, lang: lang);
  @override
  double total(Iterable<String> keys, {String lang = 'zh'}) =>
      source.total(keys, lang: lang);
  @override
  String asset(String key, {String lang = 'zh'}) =>
      source.asset(key, lang: lang);
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
