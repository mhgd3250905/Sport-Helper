import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'frame_recorder.dart';

/// Local VM-service access for profile/DevTools capture. The release phone
/// package uses the Settings share path and includes no VM-service extension.
void installPerformanceServiceExtension() {
  if (!FrameRecorder.buildEnabled || !kProfileMode) return;
  registerExtension('ext.smartfit.performance', (_, arguments) async {
    final recorder = FrameRecorder.instance;
    switch (arguments['action'] ?? 'snapshot') {
      case 'snapshot':
        break;
      case 'reset':
        recorder.endScenario();
        recorder.reset();
        recorder.start();
      case 'scenario':
        final name = arguments['scenario'];
        final scenario = FrameScenario.values.where(
          (value) => value.name == name,
        );
        if (scenario.isEmpty) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.invalidParams,
            'Unknown fixed scenario',
          );
        }
        recorder.beginScenario(scenario.first);
      case 'endScenario':
        recorder.endScenario();
      default:
        return ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          'Unknown recorder action',
        );
    }
    return ServiceExtensionResponse.result(jsonEncode(recorder.snapshot()));
  });
}
