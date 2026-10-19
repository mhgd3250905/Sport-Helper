// Copied from HipLab@6020d8e lib/hip/voice/voice_line_controller.dart (mhgd3250905/HipLab, 2026-10-18; identical to HipLab main after the 10-18 voice fixes). SmartFit: import paths only.
import 'dart:async';

/// What [VoiceLineController] needs from the platform: the voice player,
/// the chime player's state, and the audio session. The app implements it
/// with just_audio + audio_session (just_audio_output.dart); tests use a
/// fake that records what happened when.
abstract class VoicePlatform {
  /// iOS only lifts other apps' duck when the session deactivates.
  bool get isIOS;

  Future<void> configureSession({required bool duck});

  /// Deactivating also notifies other apps so their music comes back up.
  Future<void> setSessionActive(bool active);

  /// iOS keep-alive loop (silent clip): paused around a deactivation
  /// (deactivating with running I/O fails), resumed right after.
  Future<void> keepAlivePause();
  Future<void> keepAliveResume();

  Future<void> setVoiceVolume(double v);

  /// Load these clips (played back to back) without starting them.
  Future<void> loadVoice(List<String> assets);

  /// Start the loaded clips and complete when they have *finished* playing
  /// or were stopped – not when playback merely started.
  Future<void> playVoiceToEnd();

  Future<void> stopVoice();

  /// The voice / chime player is producing sound right now.
  bool get voiceAudible;
  bool get chimeAudible;
}

/// Owns the life of one spoken line (#13 voice audit, 2026-10-18).
///
/// The bug this replaces: `AudioPlayer.play()` completes *immediately* when
/// the player is already in the playing state – and just_audio stays
/// "playing" after a clip completes. So from the second line of a session
/// on, `speak()` thought the line was over as soon as it started, and
/// ~0.7 s later released the duck, which on iOS deactivates the audio
/// session – cutting the line that was still playing. That is the
/// "前面有声音、后面突然没了 / 长词只听到一两个字" from the iPhone test.
///
/// Rules here:
/// * a line is over when its clips have played to the end (or were cut);
/// * releasing the duck (and on iOS deactivating the session) happens only
///   [releaseDelay] after the last line ended, never while a voice or chime
///   is audible, and never when a newer line has been asked for since;
/// * all audio-session calls run one at a time, so a release that is in
///   progress can not interleave with the activation for the next line;
/// * a new line does not clip the tail of one still playing (the queue's
///   clock runs from when a line was asked for, playback starts a little
///   later) unless the queue cut it on purpose with [stopSpeech] – then it
///   waits up to [maxTailWait] for the real end.
class VoiceLineController {
  VoiceLineController(
    this.p, {
    this.releaseDelay = const Duration(milliseconds: 700),
    this.maxTailWait = const Duration(milliseconds: 1200),
    this.isActive = _always,
  });

  final VoicePlatform p;
  final Duration releaseDelay;
  final Duration maxTailWait;

  /// False after the session ended: a release then must not resume the
  /// keep-alive.
  final bool Function() isActive;
  static bool _always() => true;

  double volume = 1;
  int _generation = 0;
  bool _ducking = false;
  bool _cut = false;
  Timer? _release;
  Future<void>? _line;
  Future<void> _ops = Future.value();

  bool get ducking => _ducking;

  bool _current(int gen) => gen == _generation && isActive();

  /// Runs [op] after every audio-session operation queued before it.
  Future<void> serial(Future<void> Function() op) {
    final f = _ops.then((_) => op());
    _ops = f.then((_) {}, onError: (Object _) {});
    return f;
  }

  static Future<void> _step(Future<void> Function() call) async {
    try {
      await call();
    } on Object {
      /* best effort: one failing platform call must not skip the rest */
    }
  }

  Future<void> speak(List<String> assets) async {
    if (!isActive()) return;
    _release?.cancel();
    final gen = ++_generation;
    final cut = _cut;
    _cut = false;
    final prev = _line;
    if (prev != null && !cut && p.voiceAudible) {
      // Let the line on the air finish instead of clipping its tail.
      await prev.timeout(maxTailWait, onTimeout: () {});
      if (!_current(gen)) return;
    }
    final line = _play(gen, assets);
    _line = line;
    await line;
  }

  Future<void> _play(int gen, List<String> assets) async {
    Future<void>? playback;
    try {
      // Serialize preparation as well as focus: an old delayed load must
      // finish before a newer request reuses the same player.
      await serial(() async {
        if (!_current(gen)) return;
        await _duck(true, current: () => _current(gen));
        if (!_current(gen)) return;
        await p.setVoiceVolume(volume);
        if (!_current(gen)) return;
        await p.loadVoice(assets);
        if (!_current(gen)) return;
        // Do not hold the operation queue during playback: stopSpeech and
        // interruptions must be able to stop a line before it finishes.
        // Attach error handling immediately, before the serial callback
        // yields: an immediately failing player must not become unhandled.
        playback = _step(p.playVoiceToEnd);
      });
      await playback;
    } on Object {
      /* a missing clip must never stop the training */
    }
    if (!_current(gen)) return;
    _scheduleRelease(gen);
  }

  void _scheduleRelease(int gen) {
    _release?.cancel();
    _release = Timer(releaseDelay, () {
      unawaited(
        serial(() async {
          if (!_current(gen)) return; // another line or session took over
          if (p.voiceAudible || p.chimeAudible) {
            _scheduleRelease(gen); // still sounding: try again later
            return;
          }
          await _duck(false, current: () => _current(gen));
        }),
      );
    });
  }

  /// The queue cut the line on purpose (a count or a call takes over).
  Future<void> stopSpeech() async {
    _cut = true;
    final gen = ++_generation;
    _release?.cancel();
    await serial(() => _step(p.stopVoice));
    if (_current(gen)) _scheduleRelease(gen);
  }

  /// Interruption / unplug / session end: forget the current line.
  void abandon() {
    _release?.cancel();
    _generation++;
    _cut = false;
  }

  /// Mark the duck as gone without touching the session (an interruption
  /// already took it, or [end] reconfigures it).
  void forgetDuck() => _ducking = false;

  /// Used after unplugging: abandon invalidated the pending release timer,
  /// but the stopped session must still give other apps their volume back.
  Future<void> releaseDuck() => serial(() => _duck(false));

  Future<void> _duck(bool on, {bool Function()? current}) async {
    final valid = current ?? isActive;
    if (!valid() || on == _ducking) return;
    if (on) {
      // Adding duckOthers and (re-)activating lowers other apps' audio.
      await _step(() => p.configureSession(duck: true));
      if (!valid()) return;
      await _step(() => p.setSessionActive(true));
      // A cancelled configure has not acquired focus. Only remember a
      // duck after activation, so the next line still requests its focus.
      _ducking = true;
      return;
    }
    _ducking = false;
    await _step(() => p.configureSession(duck: false));
    if (p.isIOS) {
      // iOS only lifts the duck when the session deactivates: pause the
      // keep-alive, deactivate (notifying others), take it straight back.
      await _step(p.keepAlivePause);
      await _step(() => p.setSessionActive(false));
      if (valid()) {
        await _step(() => p.setSessionActive(true));
        await _step(p.keepAliveResume);
      }
    } else {
      await _step(() => p.setSessionActive(false));
    }
  }
}
