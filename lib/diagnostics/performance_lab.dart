import 'package:flutter/foundation.dart';

import 'frame_recorder.dart';

/// Internal, in-memory diagnostics. The user's starfield preference is intact.
class PerformanceLab extends ChangeNotifier {
  PerformanceLab({this.enabled = buildEnabled});
  static const buildEnabled = FrameRecorder.buildEnabled;
  static const material = 'solid';
  static final instance = PerformanceLab();
  final bool enabled;
  bool? _starfield;

  bool get starsVisible => !enabled || _starfield != false;
  bool starfieldFor(bool persisted) =>
      enabled ? _starfield ?? persisted : persisted;

  void setStarfieldOverride(bool? value) {
    if (!enabled || value == _starfield) return;
    _starfield = value;
    notifyListeners();
  }

  PerformanceLabOverrides snapshotOverrides() =>
      PerformanceLabOverrides(_starfield);

  void restoreOverrides(PerformanceLabOverrides value) {
    if (!enabled || _starfield == value.starfield) return;
    _starfield = value.starfield;
    notifyListeners();
  }

  void resetOverrides() =>
      restoreOverrides(const PerformanceLabOverrides(null));
}

@immutable
class PerformanceLabOverrides {
  const PerformanceLabOverrides(this.starfield);
  final bool? starfield;
}
