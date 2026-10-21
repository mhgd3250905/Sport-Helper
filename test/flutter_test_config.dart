import 'dart:async';

import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/ui/theme/media_theme.dart';

/// The test renderer cannot run the liquid-glass fragment shaders, so every
/// SmartFit glass surface draws its shader-free tier here (BackdropFilter
/// blur + the iOS 27 tint). On a device the adaptive scope picks premium /
/// standard; see docs/liquid-glass-plan.md §6.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SfGlass.qualityOverride = GlassQuality.minimal;
  SfCutouts.animate = false;
  await testMain();
}
