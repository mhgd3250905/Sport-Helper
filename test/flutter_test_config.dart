import 'dart:async';

import 'package:smartfit/ui/theme/media_theme.dart';

/// Keep animated media still during deterministic component tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SfCutouts.animate = false;
  await testMain();
}
