import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart';
import 'package:smartfit/app/coach_chat_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/session.dart' show trainerPlan;
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support/chat_sdk_support.dart';
import 'support/coach_v2_fixtures.dart';

void main() {
  for (final template in ['core', 'office-relax']) {
    test(
      'unchanged stored SF $template template remains visible across SDK boots',
      () async {
        final fixture =
            jsonDecode(
                  File(
                    'test/fixtures/legacy-sf-3eb/$template.json',
                  ).readAsStringSync(),
                )
                as Map;
        final original = TrainingPlan.fromJson(
          Map<String, dynamic>.from(fixture['originalPlan'] as Map),
        );
        final legacy = Map<String, dynamic>.from(fixture['legacy'] as Map);
        final originalRow = Map<String, Object?>.from(
          (legacy['chat'] as List).single as Map,
        );
        final disk = MemoryStorage();
        disk.data[AppStore.key] = jsonEncode({
          'safetyAccepted': true,
          'safetyBlocked': false,
          'starfield': false,
          'savedPlans': [fixture['originalSavedPlan']],
          ...legacy,
        });
        final before = disk.data[AppStore.key]!;
        final store = AppStore(disk);
        await store.load();
        final catalog = CoachV2Fixtures.loadSync();
        final app = sdkChatServices(store, catalog);
        final plan = trainerPlan(original);
        final context = requestForPlan(plan);
        final profile = smartfitCoachAppProfile(app);
        final validation = coach.PlanValidator(
          catalog: app.coachCatalog!,
          profile: app.coachProfile!,
        ).validate(plan, context);
        final estimated = const coach.PlanDuration().estimateSeconds(
          plan,
          app.coachCatalog!,
        );
        final executable = profile.executionTiming(plan).totalSeconds;
        final sdk = RegExp(
          r'ref: ([a-f0-9]{40})',
        ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
        final client = coach.FakeLlmClient([], latency: Duration.zero);
        final chat = createSmartfitChat(
          app,
          gateway: CoachGatewayBinding.shared(client),
        );
        final restored = await chat.start();
        final firstMessages = [
          for (final message in chat.messages) message.toJson(),
        ];
        final afterStart = disk.data[AppStore.key]!;
        await chat.close();
        final afterClose = disk.data[AppStore.key]!;
        final nextStore = AppStore(disk);
        await nextStore.load();
        final nextClient = coach.FakeLlmClient([], latency: Duration.zero);
        final next = createSmartfitChat(
          sdkChatServices(nextStore, catalog),
          gateway: CoachGatewayBinding.shared(nextClient),
        );
        final nextStart = await next.start();
        final nextMessages = [
          for (final message in next.messages) message.toJson(),
        ];
        final afterNextStart = disk.data[AppStore.key]!;
        await next.close();
        nextStore.dispose();

        // Observe continuation on an independent copy. It must not alter the boot/close sample above.
        final continuationDisk = MemoryStorage()..data[AppStore.key] = before;
        final continuationStore = AppStore(continuationDisk);
        await continuationStore.load();
        final continuation = createSmartfitChat(
          sdkChatServices(continuationStore, catalog),
          gateway: CoachGatewayBinding.shared(
            coach.FakeLlmClient([], latency: Duration.zero),
          ),
        );
        await continuation.start();
        final focused = await continuation.sendPlanToConversation(
          SmartfitCoachPlanStore(
            continuationStore,
          ).snapshot(continuationStore.savedPlans.single),
        );
        final started = await continuation.started(plan);
        Object? saveError;
        try {
          await continuation.save(plan);
        } on Object catch (error) {
          saveError = error;
        }
        await continuation.close();
        continuationStore.dispose();
        final record = {
          'fixturePath': 'test/fixtures/legacy-sf-3eb/$template.json',
          'baselineSfSource': fixture['baselineSfSource'],
          'baselineSdk': fixture['baselineSdk'],
          'sdk': sdk,
          'templateId': template,
          'originalPlan': original.toJson(),
          'originalSavedPlan': fixture['originalSavedPlan'],
          'legacy': legacy,
          'catalogMode':
              'AppTestContent.build production 211; full 219 scope manifest',
          'targetSeconds': plan.targetMinutes * 60,
          'planDurationSeconds': estimated,
          'executionIncludingPreparationSeconds': executable,
          'validationIssues': validation.issues
              .map((issue) => issue.toJson())
              .toList(),
          'displayRestore': {
            'ok': restored.ok,
            'error': restored.error?.toString(),
            'issues': restored.issues.map((issue) => issue.toJson()).toList(),
            'messages': firstMessages,
          },
          'storageBeforeStart': before,
          'storageAfterFailedStart': afterStart,
          'storageAfterClose': afterClose,
          'storageAfterNextStart': afterNextStart,
          'nextBoot': {
            'ok': nextStart.ok,
            'messages': nextMessages,
            'originalCardVisible': nextMessages.any(
              (message) => message['id'] == originalRow['id'],
            ),
            'modelRequests': nextClient.requests.length,
          },
          'continuation': {
            'selectionOk': focused.ok,
            'selectionIssues': focused.errors
                .map((issue) => issue.toJson())
                .toList(),
            'started': started,
            'saveSucceeded': saveError == null,
            'saveError': saveError?.toString(),
            'saveResultError': saveError is CoachPlanStorageException
                ? saveError.result.error?.toString()
                : null,
          },
          'originalTargetAndDosesUnchanged':
              jsonEncode(original.toJson()) ==
              jsonEncode(fixture['originalPlan']),
          'modelRequests': client.requests.length,
        };
        final output = Platform.environment['SMARTFIT_LEGACY_EVIDENCE_DIR'];
        if (output != null) {
          final directory = Directory(output)..createSync(recursive: true);
          File('${directory.path}/$template-boot-sdk.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(record),
          );
        }
        // ignore: avoid_print
        print(jsonEncode(record));
        expect(store.chatLog.single, originalRow);
        expect(store.savedPlans.single.plan.toJson(), fixture['originalPlan']);
        expect(client.requests, isEmpty);
        expect(nextClient.requests, isEmpty);
        expect(
          restored.ok,
          isTrue,
          reason: '${restored.issues} ${restored.error}',
        );
        expect(
          firstMessages.singleWhere(
            (message) => message['id'] == originalRow['id'],
          )['plan'],
          fixture['originalPlan'],
        );
        expect(
          nextMessages.any((message) => message['id'] == originalRow['id']),
          isTrue,
          reason:
              'Closing a rejected legacy import must not shadow it with an empty new envelope',
        );
        // Display retention never authorizes bypassing current training admission.
        store.dispose();
      },
    );
  }
}
