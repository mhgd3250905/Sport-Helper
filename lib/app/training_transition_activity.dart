import 'dart:async';

import 'package:flutter/foundation.dart';

/// A short paint-only window, never the lifetime of a training session.
/// Background cache work may wait here; durable result saving never waits.
class TrainingTransitionActivity extends ChangeNotifier {
  static final instance = TrainingTransitionActivity();
  var _holds = 0;
  Completer<void>? _idle;
  bool get active => _holds != 0;

  VoidCallback hold() {
    var released = false;
    if (_holds++ == 0) {
      _idle = Completer<void>();
      notifyListeners();
    }
    return () {
      if (released) return;
      released = true;
      if (--_holds == 0) {
        final idle = _idle;
        _idle = null;
        notifyListeners();
        idle?.complete();
      }
    };
  }

  Future<void> waitUntilIdle() async {
    while (active) {
      await _idle!.future;
    }
  }
}
