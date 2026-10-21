import 'package:ugk_trainer/engine.dart' as trainer;

import 'voice_library.dart';

export 'package:ugk_trainer/engine.dart'
    show
        AudioInterruption,
        InterruptibleVoiceOutput,
        MutedVoiceOutput,
        SpokenLine,
        VoiceOutput,
        VoiceQueue;

/// App preferences retain their saved JSON and "follow App" choice. The
/// trainer receives a resolved clip language at the integration boundary.
class VoiceSettings {
  const VoiceSettings({
    this.voice = true,
    this.chimes = true,
    this.language = VoiceLanguage.app,
    this.volume = 1.0,
  });

  final bool voice;
  final bool chimes;
  final VoiceLanguage language;
  final double volume;

  trainer.VoiceSettings toTrainerSettings() => trainer.VoiceSettings(
    voice: voice,
    chimes: chimes,
    language: language.clipLanguage,
    volume: volume,
  );

  VoiceSettings copyWith({
    bool? voice,
    bool? chimes,
    VoiceLanguage? language,
    double? volume,
  }) => VoiceSettings(
    voice: voice ?? this.voice,
    chimes: chimes ?? this.chimes,
    language: language ?? this.language,
    volume: volume ?? this.volume,
  );

  Map<String, Object?> toJson() => {
    'voice': voice,
    'chimes': chimes,
    'language': language.id,
    'volume': volume,
  };

  factory VoiceSettings.fromJson(Map<String, dynamic> j) => VoiceSettings(
    voice: j['voice'] != false,
    chimes: j['chimes'] != false,
    language: VoiceLanguage.byId(j['language'] as String?),
    volume: ((j['volume'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0),
  );
}
