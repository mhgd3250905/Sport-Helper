import 'package:flutter/widgets.dart';

/// Semantic fixed surfaces. Absent roles must be reported as not applicable,
/// rather than measured by toggling a widget which does not exist.
enum SfFixedGlassRole { topBar, bottomBar, input, suggestions }

@immutable
class SfFixedGlassPolicy {
  const SfFixedGlassPolicy({
    this.topBar = true,
    this.bottomBar = true,
    this.input = true,
    this.suggestions = true,
    this.saturationEnabled = true,
    this.blurScale = 1,
  }) : assert(blurScale == 1 || blurScale == .5);

  static const baseline = SfFixedGlassPolicy();

  /// The phone comparison isolated the plan conversation's suggestion strip.
  /// Keep the input's full material and leave ordinary chat on [baseline].
  static const planCards = SfFixedGlassPolicy(suggestions: false);
  static const experimentIds = {
    'baseline',
    'input_static',
    'suggestions_static',
    'no_saturation',
    'half_blur',
    'no_saturation_half_blur',
    'all_static',
    'baseline_prewarmed',
    'chat_baseline',
    'custom_plan',
    'custom_chat',
  };

  static SfFixedGlassPolicy? forConfiguration(String id) => switch (id) {
    'baseline' || 'baseline_prewarmed' || 'chat_baseline' => baseline,
    'input_static' => baseline.copyWith(input: false),
    'suggestions_static' => planCards,
    'no_saturation' => baseline.copyWith(saturationEnabled: false),
    'half_blur' => baseline.copyWith(blurScale: .5),
    'no_saturation_half_blur' => baseline.copyWith(
      saturationEnabled: false,
      blurScale: .5,
    ),
    'all_static' => baseline.copyWith(
      topBar: false,
      bottomBar: false,
      input: false,
      suggestions: false,
    ),
    _ => null,
  };
  final bool topBar;
  final bool bottomBar;
  final bool input;
  final bool suggestions;
  final bool saturationEnabled;
  final double blurScale;

  bool enabledFor(SfFixedGlassRole role) => switch (role) {
    SfFixedGlassRole.topBar => topBar,
    SfFixedGlassRole.bottomBar => bottomBar,
    SfFixedGlassRole.input => input,
    SfFixedGlassRole.suggestions => suggestions,
  };

  SfFixedGlassPolicy copyWith({
    bool? topBar,
    bool? bottomBar,
    bool? input,
    bool? suggestions,
    bool? saturationEnabled,
    double? blurScale,
  }) => SfFixedGlassPolicy(
    topBar: topBar ?? this.topBar,
    bottomBar: bottomBar ?? this.bottomBar,
    input: input ?? this.input,
    suggestions: suggestions ?? this.suggestions,
    saturationEnabled: saturationEnabled ?? this.saturationEnabled,
    blurScale: blurScale ?? this.blurScale,
  );

  String get key =>
      '${topBar ? 1 : 0}${bottomBar ? 1 : 0}${input ? 1 : 0}'
      '${suggestions ? 1 : 0}|${saturationEnabled ? 1 : 0}|$blurScale';

  Map<String, Object> toJson() => {
    'topBar': topBar,
    'bottomBar': bottomBar,
    'input': input,
    'suggestions': suggestions,
    'saturationEnabled': saturationEnabled,
    'blurScale': blurScale,
  };

  @override
  bool operator ==(Object other) =>
      other is SfFixedGlassPolicy && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

/// A page-local policy. Normal plan conversations use [SfFixedGlassPolicy.planCards]
/// while ordinary chat keeps its baseline. Internal experiments can provide an
/// explicit ancestor scope without changing the production default.
class SfFixedGlassScope extends InheritedWidget {
  const SfFixedGlassScope({
    super.key,
    required this.isPlanContext,
    required this.policy,
    required super.child,
  });
  final bool isPlanContext;
  final SfFixedGlassPolicy policy;

  static SfFixedGlassScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SfFixedGlassScope>();

  @override
  bool updateShouldNotify(SfFixedGlassScope oldWidget) =>
      isPlanContext != oldWidget.isPlanContext || policy != oldWidget.policy;
}
