import 'package:flutter/foundation.dart';

import '../ui/theme/fixed_glass_policy.dart';
import 'frame_recorder.dart';

/// Ephemeral internal controls. No preference or conversation is persisted.
class PerformanceLab extends ChangeNotifier {
  PerformanceLab({this.enabled = buildEnabled});
  static const buildEnabled = FrameRecorder.buildEnabled;
  static final instance = PerformanceLab();
  final bool enabled;
  bool _glassEnabled = true;
  bool _scrollingGlassEnabled = false;
  bool? _starfield;
  bool _freezeAdaptation = false;
  SfFixedGlassPolicy _fixedGlassPolicy = SfFixedGlassPolicy.baseline;
  bool _fixedGlassPlanContext = false;
  Set<SfFixedGlassRole> _fixedGlassPresentRoles = const {};
  String _fixedGlassConfigurationId = 'baseline';
  bool _prewarmEnabled = false;
  String _prewarmStatus = 'disabled';
  double? _prewarmDurationMs;
  double? _prewarmLogicalWidth;
  double? _prewarmLogicalHeight;
  double? _prewarmPixelRatio;

  SfFixedGlassPolicy get fixedGlassPolicy =>
      enabled ? _fixedGlassPolicy : SfFixedGlassPolicy.baseline;
  bool get fixedGlassPlanContext => enabled && _fixedGlassPlanContext;
  Set<SfFixedGlassRole> get fixedGlassPresentRoles => _fixedGlassPresentRoles;
  String get fixedGlassConfigurationId => _fixedGlassConfigurationId;
  bool get prewarmEnabled => enabled && _prewarmEnabled;
  String get prewarmStatus => enabled ? _prewarmStatus : 'disabled';
  double? get prewarmDurationMs => enabled ? _prewarmDurationMs : null;
  double? get prewarmLogicalWidth => enabled ? _prewarmLogicalWidth : null;
  double? get prewarmLogicalHeight => enabled ? _prewarmLogicalHeight : null;
  double? get prewarmPixelRatio => enabled ? _prewarmPixelRatio : null;

  bool get glassEnabled => !enabled || _glassEnabled;

  /// Production and a fresh internal session always use static scroll cards.
  /// The global glass switch must also be on for the comparison override.
  bool get scrollingGlassEnabled =>
      enabled && _scrollingGlassEnabled && glassEnabled;
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

  void setScrollingGlassEnabled(bool value) {
    if (!enabled || value == _scrollingGlassEnabled) return;
    _scrollingGlassEnabled = value;
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

  void setFixedGlassPolicy(SfFixedGlassPolicy value) {
    if (!enabled || value == _fixedGlassPolicy) return;
    _fixedGlassPolicy = value;
    _fixedGlassConfigurationId = _fixedGlassPlanContext
        ? 'custom_plan'
        : 'custom_chat';
    notifyListeners();
  }

  /// Restores the persisted starfield preference instead of changing it as an
  /// accidental second variable in a fixed-glass experiment.
  void applyFixedGlassConfiguration(String id) {
    if (!enabled) return;
    if (!SfFixedGlassPolicy.experimentIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unknown fixed-glass configuration');
    }
    _glassEnabled = true;
    _scrollingGlassEnabled = false;
    _starfield = null;
    _fixedGlassConfigurationId = id;
    _fixedGlassPolicy =
        SfFixedGlassPolicy.forConfiguration(id) ?? _fixedGlassPolicy;
    _prewarmEnabled = id == 'baseline_prewarmed';
    _prewarmStatus = _prewarmEnabled ? 'pending' : 'disabled';
    _prewarmDurationMs = null;
    _prewarmLogicalWidth = _prewarmLogicalHeight = _prewarmPixelRatio = null;
    notifyListeners();
  }

  void setFixedGlassContext({
    required bool isPlanContext,
    required Set<SfFixedGlassRole> presentRoles,
  }) {
    if (!enabled) return;
    final roles = Set<SfFixedGlassRole>.unmodifiable(presentRoles);
    if (_fixedGlassPlanContext == isPlanContext &&
        setEquals(_fixedGlassPresentRoles, roles)) {
      return;
    }
    _fixedGlassPlanContext = isPlanContext;
    _fixedGlassPresentRoles = roles;
    notifyListeners();
  }

  void setPrewarmEnabled(bool value) {
    if (!enabled || value == _prewarmEnabled) return;
    _prewarmEnabled = value;
    _prewarmStatus = value ? 'pending' : 'disabled';
    _prewarmDurationMs = null;
    _prewarmLogicalWidth = _prewarmLogicalHeight = _prewarmPixelRatio = null;
    notifyListeners();
  }

  void setPrewarmStatus(
    String status, {
    double? durationMs,
    double? logicalWidth,
    double? logicalHeight,
    double? pixelRatio,
  }) {
    if (!enabled) return;
    if (!const {
      'disabled',
      'pending',
      'succeeded',
      'unsupported',
      'failed',
    }.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    if ((!_prewarmEnabled && status != 'disabled') ||
        (_prewarmEnabled && status == 'disabled') ||
        (durationMs != null &&
            (!durationMs.isFinite || durationMs < 0 || durationMs > 60000))) {
      throw ArgumentError('Prewarm status does not match the actual attempt');
    }
    for (final value in [logicalWidth, logicalHeight, pixelRatio]) {
      if (value != null && (!value.isFinite || value <= 0 || value > 100000)) {
        throw ArgumentError('Invalid prewarm geometry');
      }
    }
    _prewarmStatus = status;
    _prewarmDurationMs = durationMs;
    _prewarmLogicalWidth = logicalWidth;
    _prewarmLogicalHeight = logicalHeight;
    _prewarmPixelRatio = pixelRatio;
    notifyListeners();
  }

  PerformanceLabOverrides snapshotOverrides() => PerformanceLabOverrides(
    _glassEnabled,
    _starfield,
    scrollingGlassEnabled: _scrollingGlassEnabled,
    fixedGlassPolicy: _fixedGlassPolicy,
    fixedGlassPlanContext: _fixedGlassPlanContext,
    fixedGlassPresentRoles: _fixedGlassPresentRoles,
    fixedGlassConfigurationId: _fixedGlassConfigurationId,
    prewarmEnabled: _prewarmEnabled,
    prewarmStatus: _prewarmStatus,
    prewarmDurationMs: _prewarmDurationMs,
    prewarmLogicalWidth: _prewarmLogicalWidth,
    prewarmLogicalHeight: _prewarmLogicalHeight,
    prewarmPixelRatio: _prewarmPixelRatio,
  );

  void restoreOverrides(PerformanceLabOverrides value) {
    if (!enabled) return;
    _glassEnabled = value.glassEnabled;
    _scrollingGlassEnabled = value.scrollingGlassEnabled;
    _starfield = value.starfield;
    _fixedGlassPolicy = value.fixedGlassPolicy;
    _fixedGlassPlanContext = value.fixedGlassPlanContext;
    _fixedGlassPresentRoles = value.fixedGlassPresentRoles;
    _fixedGlassConfigurationId = value.fixedGlassConfigurationId;
    _prewarmEnabled = value.prewarmEnabled;
    _prewarmStatus = value.prewarmStatus;
    _prewarmDurationMs = value.prewarmDurationMs;
    _prewarmLogicalWidth = value.prewarmLogicalWidth;
    _prewarmLogicalHeight = value.prewarmLogicalHeight;
    _prewarmPixelRatio = value.prewarmPixelRatio;
    notifyListeners();
  }

  void resetOverrides() =>
      restoreOverrides(const PerformanceLabOverrides(true, null));
}

@immutable
class PerformanceLabOverrides {
  const PerformanceLabOverrides(
    this.glassEnabled,
    this.starfield, {
    this.scrollingGlassEnabled = false,
    this.fixedGlassPolicy = SfFixedGlassPolicy.baseline,
    this.fixedGlassPlanContext = false,
    this.fixedGlassPresentRoles = const {},
    this.fixedGlassConfigurationId = 'baseline',
    this.prewarmEnabled = false,
    this.prewarmStatus = 'disabled',
    this.prewarmDurationMs,
    this.prewarmLogicalWidth,
    this.prewarmLogicalHeight,
    this.prewarmPixelRatio,
  });
  final bool glassEnabled;
  final bool scrollingGlassEnabled;
  final bool? starfield;
  final SfFixedGlassPolicy fixedGlassPolicy;
  final bool fixedGlassPlanContext;
  final Set<SfFixedGlassRole> fixedGlassPresentRoles;
  final String fixedGlassConfigurationId;
  final bool prewarmEnabled;
  final String prewarmStatus;
  final double? prewarmDurationMs;
  final double? prewarmLogicalWidth;
  final double? prewarmLogicalHeight;
  final double? prewarmPixelRatio;
}
