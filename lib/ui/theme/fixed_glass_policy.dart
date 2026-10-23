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
    this.inputBlur,
  }) : assert(blurScale == 1 || blurScale == .5),
       assert(inputBlur == null || inputBlur == 1.2);

  static const baseline = SfFixedGlassPolicy();

  /// Every chat suggestion strip uses the approved static face. The input
  /// keeps its original material; the phone comparison needs no warm-up.
  static const chat = SfFixedGlassPolicy(suggestions: false);

  /// Compatibility name for the original plan-card-only rollout.
  static const planCards = chat;
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
    'chat_suggestions_static',
    'chat_suggestions_static_input_blur_1_2',
    'custom_plan',
    'custom_chat',
  };

  static SfFixedGlassPolicy? forConfiguration(String id) => switch (id) {
    'baseline' || 'baseline_prewarmed' || 'chat_baseline' => baseline,
    'input_static' => baseline.copyWith(input: false),
    'suggestions_static' => planCards,
    'chat_suggestions_static' => chat,
    'chat_suggestions_static_input_blur_1_2' => chat.copyWith(inputBlur: 1.2),
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

  static bool isChatConfiguration(String id) => switch (id) {
    'chat_baseline' ||
    'chat_suggestions_static' ||
    'chat_suggestions_static_input_blur_1_2' ||
    'custom_chat' => true,
    _ => false,
  };
  final bool topBar;
  final bool bottomBar;
  final bool input;
  final bool suggestions;
  final bool saturationEnabled;
  final double blurScale;

  /// An absolute sigma for the internal input-only follow-up comparison.
  /// The production/default policy leaves this null and ignores overrides.
  final double? inputBlur;

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
    double? inputBlur,
  }) => SfFixedGlassPolicy(
    topBar: topBar ?? this.topBar,
    bottomBar: bottomBar ?? this.bottomBar,
    input: input ?? this.input,
    suggestions: suggestions ?? this.suggestions,
    saturationEnabled: saturationEnabled ?? this.saturationEnabled,
    blurScale: blurScale ?? this.blurScale,
    inputBlur: inputBlur ?? this.inputBlur,
  );

  String get key =>
      '${topBar ? 1 : 0}${bottomBar ? 1 : 0}${input ? 1 : 0}'
      '${suggestions ? 1 : 0}|${saturationEnabled ? 1 : 0}|$blurScale'
      '${inputBlur == null ? '' : '|inputBlur=$inputBlur'}';

  Map<String, Object> toJson() => {
    'topBar': topBar,
    'bottomBar': bottomBar,
    'input': input,
    'suggestions': suggestions,
    'saturationEnabled': saturationEnabled,
    'blurScale': blurScale,
    'inputBlur': ?inputBlur,
  };

  @override
  bool operator ==(Object other) =>
      other is SfFixedGlassPolicy && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

/// A page-local material policy. Every normal chat uses [SfFixedGlassPolicy.chat].
/// [isPlanContext] describes the content, independently of the chosen material.
/// Internal comparisons can supply an explicit ancestor policy.
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
