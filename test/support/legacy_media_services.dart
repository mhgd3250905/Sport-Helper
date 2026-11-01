import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import '../support.dart';
import 'coach_v2_fixtures.dart';

/// Existing 93-pack media/assets with the SDK's real 211-action chat protocol.
/// No PoseHub catalogue/repository is attached to its legacy rendering paths.
AppServices legacyMediaServices({
  VoiceOutput output = const MutedVoiceOutput(),
}) => _LegacyMediaServices(output);

class LegacyMediaStorage implements LocalStateStorage {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

List<Object> _legacyMediaScript() {
  final script = CoachV2Fixtures.loadSync().planTurn(
    prefix: 'legacy-media',
    equipmentQuote: '瑜伽垫',
    fields: {
      'equipment': CoachV2Fixtures.sourced(['equip.mat'], '瑜伽垫'),
    },
  );
  final deliver = script[1] as coach.FakeStep;
  script[1] = (coach.LlmRequest request) {
    try {
      return deliver(request);
    } catch (error) {
      final receipts = request.messages
          .where((message) => message.toolCallId != null)
          .map((message) => '${message.toolCallId}: ${message.content}')
          .join('\n');
      throw StateError('$error\n$receipts');
    }
  };
  return script;
}

class _LegacyMediaServices extends AppServices {
  _LegacyMediaServices(VoiceOutput output)
    : this._(output, CoachV2Fixtures.loadSync());

  _LegacyMediaServices._(VoiceOutput output, CoachV2Fixtures fixture)
    : super(
        library: loadLibrary(),
        catalog: loadCatalog(),
        store: AppStore(LegacyMediaStorage())..starfield = false,
        coachCatalog: fixture.catalog,
        coachProfile: fixture.profile,
        voiceLibrary: VoiceLibrary.empty,
        voiceOutput: output,
        chatReplyDelay: Duration.zero,
      );

  CoachChatController? _fixtureChat;

  // Theme switching still mounts the real App and SDK conversation. Only its
  // transport is synthetic; profile, scope, timing and storage remain real.
  @override
  CoachChatController get chat => _fixtureChat ??= createSmartfitChat(
    this,
    gateway: CoachGatewayBinding.shared(
      coach.FakeLlmClient(_legacyMediaScript(), latency: Duration.zero),
    ),
  );

  @override
  Future<void> dispose() async {
    final controller = _fixtureChat;
    if (controller != null) {
      await controller.close();
      controller.dispose();
    }
    await super.dispose();
  }
}

void legacyMediaTall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

/// Drive memory/controller work in FakeAsync; real yields are for asset decode.
Future<T> _complete<T>(
  WidgetTester tester,
  Future<T> operation,
  String label,
) async {
  var completed = false;
  T? value;
  Object? error;
  StackTrace? stack;
  unawaited(
    operation.then<void>(
      (result) {
        value = result;
        completed = true;
      },
      onError: (Object failure, StackTrace trace) {
        error = failure;
        stack = trace;
        completed = true;
      },
    ),
  );
  for (var attempt = 0; !completed && attempt < 250; attempt++) {
    await tester.pump();
    if (!completed) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }
  expect(completed, isTrue, reason: '$label did not complete');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

Future<void> showLegacyMediaChatCard(
  AppServices services, {
  required WidgetTester tester,
}) async {
  expect((await services.chat.start()).ok, isTrue);
  final result = await _complete(
    tester,
    services.chat.send('在家用瑜伽垫10分钟拉伸'),
    'Admitted legacy-media chat plan',
  );
  expect(
    result?.status,
    coach.TurnStatus.ok,
    reason: '${result?.error}; issues=${result?.issues}',
  );
  expect(services.chat.currentPlan, isNotNull);
}

Future<void> warmLegacyTrainingPoster(
  WidgetTester tester,
  AppServices services,
  TrainingPlan plan, {
  BuildContext? sourceContext,
}) async {
  if (plan.items.isEmpty) return;
  final context = sourceContext ?? tester.element(find.byType(Scaffold).first);
  await _complete(
    tester,
    TrainingPosterImages.precache(
      context,
      services.library[plan.items.first.exerciseId],
    ),
    'Legacy training poster decode',
  );
}

/// Call in the test body after unmounting; keep SDK close on the pumped clock.
Future<void> closeLegacyMediaServices(
  WidgetTester tester,
  AppServices services,
) => _complete(tester, services.dispose(), 'Legacy media services close');
