import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'frame_recorder.dart';

/// Local automation exists only in an internal profile build. Release uses the
/// ordinary Settings export; no key, endpoint or App content is exposed here.
void installPerformanceServiceExtension() {
  if (!FrameRecorder.buildEnabled || !kProfileMode) return;
  registerExtension('ext.smartfit.performance', (_, arguments) async {
    final recorder = FrameRecorder.instance;
    ServiceExtensionResponse error(String text) =>
        ServiceExtensionResponse.error(
          ServiceExtensionResponse.invalidParams,
          text,
        );
    final action = arguments['action'] ?? 'snapshot';
    if (action == 'status') {
      return ServiceExtensionResponse.result(jsonEncode(recorder.status()));
    }
    if (action == 'case') {
      final value = recorder.caseReport(arguments['caseId'] ?? '');
      return value == null
          ? error('Unknown fixed case ID.')
          : ServiceExtensionResponse.result(jsonEncode(value));
    }
    switch (action) {
      case 'snapshot':
        break;
      case 'reset':
        if (recorder.currentCaseId != null) {
          return error('End the active case before resetting.');
        }
        recorder.cancelArmedCase();
        recorder.endScenario();
        recorder.reset();
        recorder.start();
      case 'armCase':
        final theme = arguments['theme'];
        final matches = FrameRecorder.acceptanceScenarios.where(
          (v) => v.name == arguments['scenario'],
        );
        if (theme != recorder.status()['currentTheme'] || matches.isEmpty) {
          return error('Expected actual theme and a supported scene.');
        }
        if (!recorder.armCase(theme: theme!, scenario: matches.first)) {
          return error('Could not arm a real-page case.');
        }
        return ServiceExtensionResponse.result(jsonEncode(recorder.status()));
      case 'endCase':
        recorder.endCase();
        recorder.cancelArmedCase();
        return ServiceExtensionResponse.result(jsonEncode(recorder.status()));
      case 'cancelCase':
        recorder.endCase(completed: false);
        recorder.cancelArmedCase();
        return ServiceExtensionResponse.result(jsonEncode(recorder.status()));
      case 'scenario':
        final values = FrameScenario.values.where(
          (v) => v.name == arguments['scenario'],
        );
        if (values.isEmpty) return error('Unknown fixed scenario.');
        recorder.beginScenario(values.first);
      case 'endScenario':
        recorder.endScenario();
      default:
        return error('Unknown recorder action.');
    }
    return ServiceExtensionResponse.result(jsonEncode(recorder.snapshot()));
  });
}
