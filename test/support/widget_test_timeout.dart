import 'package:flutter_test/flutter_test.dart';

/// Configure only files that already register widget tests. Importing this
/// helper never initializes a binding or changes pure IO/HTTP unit tests.
void configureWidgetTestTimeout() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = const Timeout(Duration(seconds: 60));
  }
}
