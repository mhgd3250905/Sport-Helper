import 'package:flutter/foundation.dart';

import 'frame_recorder.dart';

/// Ephemeral internal controls. No preference or conversation is persisted.
class PerformanceLab extends ChangeNotifier {
  PerformanceLab({this.enabled = buildEnabled});
  static const buildEnabled = FrameRecorder.buildEnabled;
  static final instance = PerformanceLab();
  final bool enabled;
  bool _glassEnabled = true;
  bool? _starfield;
  bool _freezeAdaptation = false;

  bool get glassEnabled => !enabled || _glassEnabled;
  // An unset override preserves the original static sky when the user's
  // animation preference is off. Explicit off removes the entire dust layer.
  bool get starsVisible => !enabled || _starfield != false;
  bool get freezeAdaptation => enabled && _freezeAdaptation;
  bool starfieldFor(bool persisted) =>
      enabled ? _starfield ?? persisted : persisted;
  String variantFor(bool persisted) =>
      'glass_${glassEnabled ? 'on' : 'off'}_stars_${starfieldFor(persisted) ? 'on' : 'off'}';

  void setVariant(String id) {
    if (!enabled) return;
    if (!const {
      'glass_on_stars_on',
      'glass_on_stars_off',
      'glass_off_stars_on',
      'glass_off_stars_off',
    }.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown performance variant');
    }
    _glassEnabled = id.startsWith('glass_on_');
    _starfield = id.endsWith('_stars_on');
    notifyListeners();
  }

  void setGlassEnabled(bool value) {
    if (!enabled || value == _glassEnabled) return;
    _glassEnabled = value;
    notifyListeners();
  }

  void setStarfieldOverride(bool? value) {
    if (!enabled || value == _starfield) return;
    _starfield = value;
    notifyListeners();
  }

  void setFreezeAdaptation(bool value) {
    if (!enabled || value == _freezeAdaptation) return;
    _freezeAdaptation = value;
    notifyListeners();
  }

  PerformanceLabOverrides snapshotOverrides() =>
      PerformanceLabOverrides(_glassEnabled, _starfield);

  void restoreOverrides(PerformanceLabOverrides value) {
    if (!enabled) return;
    _glassEnabled = value.glassEnabled;
    _starfield = value.starfield;
    notifyListeners();
  }

  void resetOverrides() =>
      restoreOverrides(const PerformanceLabOverrides(true, null));
}

@immutable
class PerformanceLabOverrides {
  const PerformanceLabOverrides(this.glassEnabled, this.starfield);
  final bool glassEnabled;
  final bool? starfield;
}
