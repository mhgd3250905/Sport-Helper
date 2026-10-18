// Copied from HipLab@main lib/hip/voice/voice_queue.dart (mhgd3250905/HipLab, 2026-10-18). SmartFit: import paths only.
import 'voice_cue.dart';
import 'voice_library.dart';

/// Where sound goes. The app uses the just_audio implementation; tests use
/// a recording fake.
abstract class VoiceOutput {
  /// Session started: configure ducking / background audio.
  Future<void> begin();

  /// Session over: release audio focus, stop keep-alive.
  Future<void> end();

  /// Play these voice clip assets back to back, replacing whatever plays.
  Future<void> speak(List<String> assets);

  /// Cut the current line.
  Future<void> stopSpeech();

  Future<void> chime(String asset);

  set volume(double v);
}

/// What the OS did to the app's audio mid-session.
enum AudioInterruption {
  /// A phone/FaceTime call, Siri, an alarm or another app took the audio
  /// session: the session should pause (a follow-along can't continue
  /// while the user is on the phone).
  began,

  /// The interruption is over and the audio session is active again.
  /// The session stays paused until the user taps 继续.
  ended,

  /// Headphones / Bluetooth audio went away ("becoming noisy"): pause so
  /// the coach doesn't suddenly talk out of the speaker.
  unplugged,
}

/// Optional extra of a [VoiceOutput]: OS audio interruptions and a way to
/// take the audio session back when the user resumes.
abstract class InterruptibleVoiceOutput {
  Stream<AudioInterruption> get interruptions;

  /// Re-activate the audio session (and the iOS background keep-alive)
  /// after a pause; safe to call when nothing was interrupted.
  Future<void> reactivate();
}

/// Silent output (voice and chimes off, or widget tests).
class MutedVoiceOutput implements VoiceOutput {
  const MutedVoiceOutput();
  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
  @override
  Future<void> speak(List<String> assets) async {}
  @override
  Future<void> stopSpeech() async {}
  @override
  Future<void> chime(String asset) async {}
  @override
  set volume(double v) {}
}

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

/// One line that actually started (for tests and the demo export).
class SpokenLine {
  SpokenLine(this.start, this.clips, this.priority, this.length);
  final double start;
  final List<String> clips;
  final CuePriority priority;
  final double length;
  double? cutAt;
  double get end => cutAt ?? start + length;
  @override
  String toString() =>
      '${start.toStringAsFixed(2)}–${end.toStringAsFixed(2)} ${clips.join('+')}'
      '${cutAt != null ? ' (cut)' : ''}';
}

class _Pending {
  _Pending(this.cue, this.deadline);
  final VoiceCue cue;
  final double deadline;
}

/// Puts cues on the air one at a time (#13): never two voices at once, a
/// count is never cut and cuts anything but another count, lower lines wait
/// briefly and are dropped when their moment has passed. Chimes are layered
/// on their own channel and never wait.
///
/// Times are seconds on any monotonic clock the caller uses consistently
/// (the player passes active session time; the assessment wall time).
class VoiceQueue {
  VoiceQueue({required this.output, required this.lib, required this.settings});

  final VoiceOutput output;
  final VoiceLibrary lib;
  VoiceSettings settings;
  final List<SpokenLine> log = [];
  final List<(double, String)> chimeLog = [];
  SpokenLine? _current;
  final List<_Pending> _pending = [];

  String get lang => settings.language.clipLanguage;

  static double _wait(CuePriority p) => switch (p) {
    CuePriority.count => 0.25,
    CuePriority.call => 2.0,
    CuePriority.info => 4.0,
    CuePriority.coach => 1.5,
  };

  bool _busy(double now) => _current != null && now < _current!.end - .02;

  void submit(VoiceCue cue, double now) {
    if (settings.chimes) {
      for (final c in cue.chimes) {
        if (lib.has(c)) {
          chimeLog.add((now, c));
          output.chime(lib.asset(c));
        }
      }
    }
    if (!settings.voice) return;
    final clips = cue.voiceClips.where((c) => lib.has(c, lang: lang)).toList();
    if (clips.isEmpty) return;
    final trimmed = VoiceCue(cue.at, clips, cue.priority);
    if (!_busy(now)) {
      _start(trimmed, now);
      return;
    }
    final cur = _current!;
    if (trimmed.priority == CuePriority.count &&
        cur.priority != CuePriority.count) {
      _cut(now);
      _start(trimmed, now);
      return;
    }
    if (trimmed.priority.index > cur.priority.index &&
        cur.priority.index <= CuePriority.info.index) {
      _cut(now);
      _start(trimmed, now);
      return;
    }
    _pending.add(_Pending(trimmed, now + _wait(trimmed.priority)));
  }

  /// Call often (every timer tick): starts a waiting line when the air is free.
  void tick(double now) {
    _pending.removeWhere((p) => p.deadline < now);
    if (_pending.isEmpty || _busy(now)) return;
    _pending.sort(
      (a, b) => b.cue.priority.index.compareTo(a.cue.priority.index),
    );
    final next = _pending.removeAt(0);
    _start(next.cue, now);
  }

  void _start(VoiceCue cue, double now) {
    final line = SpokenLine(
      now,
      cue.clips,
      cue.priority,
      lib.total(cue.clips, lang: lang),
    );
    _current = line;
    log.add(line);
    output.speak([for (final c in cue.clips) lib.asset(c, lang: lang)]);
  }

  void _cut(double now) {
    final cur = _current;
    if (cur != null && now < cur.end) cur.cutAt = now;
    _current = null;
    output.stopSpeech();
  }

  /// Pause / skip / close: silence now and forget anything waiting.
  void cancelAll(double now) {
    _pending.clear();
    if (_busy(now)) _cut(now);
    _current = null;
  }
}
