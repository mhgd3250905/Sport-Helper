import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme/media_theme.dart';

/// Keep animated media still during deterministic component tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 60));
  }
  SfCutouts.animate = false;
  await testMain();
}
