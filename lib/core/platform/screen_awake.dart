import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while a timed session (training player, hip check)
/// is open, so the device's auto-lock never sends the app to the background
/// mid-session.
///
/// Why: on Android a backgrounded Flutter activity without a foreground
/// service can be throttled or frozen by the system (cached-app freezer,
/// Doze), which would stall the 100 ms session ticker and the voice cues.
/// Keeping the screen on is the lowest-risk guard (no permission, no
/// manifest service, no Play Console declaration). A manual lock with the
/// power button is still not covered – see docs/development-roadmap.md D-10.
///
/// Reference-counted so nested sessions don't release each other's hold.
/// Platform errors are swallowed: in widget tests (no plugin) and on
/// unsupported platforms this is a no-op.
class ScreenAwake {
  ScreenAwake._();

  static int _holds = 0;

  static void acquire() {
    if (_holds++ == 0) _set(true);
  }

  static void release() {
    if (_holds == 0) return;
    if (--_holds == 0) _set(false);
  }

  static void _set(bool on) {
    try {
      unawaited(WakelockPlus.toggle(enable: on).catchError((Object _) {}));
    } catch (_) {
      // Plugin missing (tests / web stub): nothing to keep awake.
    }
  }
}
