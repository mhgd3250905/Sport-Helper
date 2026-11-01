// SF migration capture. Reuses the frozen SDK scenario and original frame data,
// but the profile, visuals, host actions and thin page are real SF production.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/coach_chat.dart' as sf_chat;
import 'package:smartfit/app/services.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/media_theme.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/ui/training_route.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_chat/ugk_coach_chat.dart' as chat;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachTaskBubble;
import 'package:ugk_trainer/ugk_trainer.dart'
    show PoseHubActionLibrary, TrainerSlideRoute;

import 'support.dart';
import 'support/coach_v2_fixtures.dart';

class _MemoryStorage implements LocalStateStorage {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

class _Plans extends chat.CoachPlanStorageAdapter {
  _Plans(this.values);
  final List<chat.CoachSavedPlanSnapshot> values;
  @override
  Future<List<chat.CoachSavedPlanSnapshot>> load() async => values;
  @override
  Future<chat.CoachPlanWriteResult> save(
    chat.CoachPlanWriteRequest request,
  ) async => const chat.CoachPlanWriteResult.failure(
    chat.CoachPlanWriteStatus.readOnly,
  );
}

class _History extends chat.CoachChatHistoryStore {
  _History(this.value);
  final chat.CoachChatSnapshot? value;
  @override
  Future<chat.CoachChatSnapshot?> load(String namespace) async => value;
  @override
  Future<void> write(String namespace, chat.CoachChatSnapshot snapshot) async {}
}

class _Preferences extends chat.CoachChatPreferenceStore {
  @override
  Future<chat.CoachChatPreferences> load() async =>
      const chat.CoachChatPreferences(
        safetyAccepted: true,
        starfield: false,
        enableUserMemory: false,
      );
  @override
  Future<void> update(chat.CoachChatPreferences value) async {}
}

// A normal view-model test double: hydrate actual plans through snapshot
// admission; provide only the source live frame's displayed suggestion list.
class _FixtureController extends chat.CoachChatController {
  _FixtureController({
    required super.profile,
    required super.catalog,
    required super.bindings,
    super.context,
    required this.displaySuggestions,
  }) : super(
         replyDelay: Duration.zero,
         clock: () => DateTime(2026, 10, 30, 12),
       );
  List<String> displaySuggestions;
  @override
  List<String> get suggestions => displaySuggestions;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The original test/flutter_test_config.dart applies this same setting.
  // This tool is outside test/, so preserve that source environment explicitly.
  SfCutouts.animate = false;
  final output = Directory(Platform.environment['CHAT_CAPTURE_OUTPUT']!);
  final baseline = Directory(Platform.environment['CHAT_CAPTURE_BASELINE']!);
  final inputs = Directory(Platform.environment['CHAT_CAPTURE_INPUTS']!);
  final selected = (Platform.environment['CHAT_CAPTURE_FRAMES'] ?? '')
      .split(',')
      .where((value) => value.isNotEmpty)
      .toSet();
  late CoachV2Fixtures fixture;
  late coach.PoseHubAppTestCatalog sdk;
  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
    sdk = await PoseHubActionLibrary.load();
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'))).load();
  });
  for (final dark in [false, true]) {
    testWidgets('SDK candidate source frames ${dark ? 'dark' : 'light'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      final mode = dark ? 'dark' : 'light';
      final palette = dark ? SfPalette.dark : SfPalette.light;
      SfColors.palette = palette;
      final failures = <String>[];
      final comparisons = <Map<String, Object?>>[];
      _FixtureController? activeController;
      final themeStartedAt = tester.binding.clock.now();
      bool wanted(String name) => selected.isEmpty || selected.contains(name);
      Map<String, Object?> source(String name) => Map<String, Object?>.from(
        jsonDecode(File('${inputs.path}/$mode-$name.json').readAsStringSync())
            as Map,
      );
      final store = AppStore(_MemoryStorage())..starfield = false;
      await store.acceptSafety(blocked: false);
      late PoseHubMediaRepository media;
      late PoseHubAssetBundle bundle;
      await tester.runAsync(() async {
        final images = await PoseHubBundledImages.load(
          catalogRevision: PoseHubActionLibrary.catalogSha256,
        );
        media = await PoseHubMediaRepository.create(
          catalog: sdk,
          catalogRevision: PoseHubActionLibrary.catalogSha256,
          mediaBaseUrls: const [],
          rootDirectory: '${output.path}/media-cache-$mode',
          bundledFileLoader: images.loadFile,
        );
        bundle = PoseHubAssetBundle(catalog: sdk, installation: media);
      });
      final services = AppServices(
        library: fixture.library,
        catalog: loadCatalog(),
        store: store,
        voiceLibrary: VoiceLibrary.empty,
        voiceOutput: const MutedVoiceOutput(),
        coachCatalog: fixture.catalog,
        coachProfile: fixture.profile,
        chatReplyDelay: Duration.zero,
        poseHubCatalog: sdk,
      );
      // Do not rebuild the SDK candidate's hand-written SF profile or training
      // callback. This is the actual App factory and its production host ports.
      // The factory is not started, so its configured gateway is never created.
      final production = sf_chat.createSmartfitChat(services);
      final profile = production.profile;
      final hostActions = production.bindings.actions;

      Future<void> settleArtwork() async {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      Future<void> compare(GlobalKey rootKey, String name) async {
        if (!wanted(name)) return;
        expect(tester.takeException(), isNull);
        expect(find.byType(ChatHomePage, skipOffstage: false), findsOneWidget);
        expect(
          find.byType(chat.CoachChatPage, skipOffstage: false),
          findsOneWidget,
        );
        int? bubbleBoundaries;
        if (name == 'waiting-250ms') {
          final bubble = find.byType(CoachTaskBubble);
          expect(bubble, findsOneWidget);
          bubbleBoundaries = find
              .descendant(of: bubble, matching: find.byType(RepaintBoundary))
              .evaluate()
              .length;
          expect(
            bubbleBoundaries,
            4,
            reason:
                'Actual bubble subtree excludes page/list/router boundaries',
          );
        }
        Map<String, Object?>? trainingRoute;
        final player = find.byType(PlayerPage, skipOffstage: false);
        if (player.evaluate().isNotEmpty) {
          final route = ModalRoute.of(tester.element(player))!;
          expect(route, isA<TrainingRoute<dynamic>>());
          expect(route, isA<TrainerSlideRoute<dynamic>>());
          trainingRoute = {
            'type': route.runtimeType.toString(),
            'isActualSfTrainingRoute': true,
            'isSdkTrainerSlideRoute': true,
            'routeName': route.settings.name,
            'value': route.animation!.value,
            'status': route.animation!.status.name,
          };
        }
        late Uint8List png;
        await tester.runAsync(() async {
          final boundary =
              rootKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          png = bytes!.buffer.asUint8List();
          final file = File('${output.path}/$mode-$name.png');
          expect(await file.exists(), isFalse);
          await file.writeAsBytes(png, flush: true);
          image.dispose();
          final controller = activeController!;
          final fixtureBytes = await File(
            '${inputs.path}/$mode-$name.json',
          ).readAsBytes();
          final metadata = File('${output.path}/$mode-$name.json');
          expect(await metadata.exists(), isFalse);
          await metadata.writeAsString(
            jsonEncode({
              'frame': '$mode-$name',
              'sourceFixtureSha256': sha256.convert(fixtureBytes).toString(),
              'pngSha256': sha256.convert(png).toString(),
              'elapsedFromThemeStartMs': tester.binding.clock
                  .now()
                  .difference(themeStartedAt)
                  .inMilliseconds,
              'profileFactory': 'smartfit.createSmartfitChat(AppServices)',
              'profileAppId': controller.profile.appId,
              'hostActions': 'production controller.bindings.actions',
              'page': 'SF ChatHomePage -> SDK CoachChatPage',
              'bubbleRepaintBoundaryCount': bubbleBoundaries,
              'trainingRoute': trainingRoute,
              'sdkSourceTransitionHoldActive':
                  controller.transitionActivity.active,
              'fixtureControllerOverride':
                  'read-only suggestions getter only; normal snapshot restore/admission',
              'currentPlan': controller.currentPlan?.toJson(),
              'messages': [
                for (final message in controller.messages) message.toJson(),
              ],
              'coreSnapshot': controller.conversation.exportSession().toJson(),
              'isPhoneOrPerformanceEvidence': false,
            }),
            flush: true,
          );
        });
        final result = await tester.runAsync(() async {
          try {
            final comparison = await GoldenFileComparator.compareLists(
              png,
              await File('${baseline.path}/$mode-$name.png').readAsBytes(),
            );
            try {
              return (
                passed: comparison.passed,
                error: comparison.passed
                    ? null
                    : 'Non-zero pixel difference (${comparison.diffPercent})',
              );
            } finally {
              comparison.dispose();
            }
          } on Object catch (error) {
            return (passed: false, error: error.toString());
          }
        });
        if (result!.passed) {
          comparisons.add({'frame': '$mode-$name', 'passed': true});
          stdout.writeln('$mode/$name: pixels identical');
        } else {
          failures.add('$mode-$name');
          comparisons.add({
            'frame': '$mode-$name',
            'passed': false,
            'error': result.error,
          });
          stdout.writeln('$mode/$name: non-zero pixel difference');
        }
      }

      Future<({GlobalKey key, _FixtureController controller})> mount(
        String frame, {
        coach.FakeLlmClient? client,
        bool fresh = false,
      }) async {
        final data = source(frame);
        final core = coach.CoachSessionSnapshot.fromJson(data['snapshot']);
        final plan = data['plan'] == null
            ? null
            : const coach.PlanCodec().decode(data['plan']);
        final ref = core.sessionState.savedRef;
        final saves = <chat.CoachSavedPlanSnapshot>[
          if (frame == 'focused-saved-plan' && plan != null && ref != null)
            chat.CoachSavedPlanSnapshot(
              externalId: ref.externalId,
              title: plan.title,
              plan: plan,
              storageRevision: 'capture-r1',
            ),
        ];
        final history = _History(
          fresh
              ? null
              : chat.CoachChatSnapshot(
                  appId: profile.appId,
                  storageNamespace: 'capture',
                  session: core,
                  messages: [
                    for (final row in data['messages'] as List)
                      Map<String, Object?>.from(row as Map),
                  ],
                ),
        );
        late _FixtureController controller;
        controller = _FixtureController(
          profile: profile,
          catalog: fixture.catalog,
          context: production.context,
          displaySuggestions: frame.startsWith('plan-')
              ? profile.strings.planSuggestions
              : profile.strings.suggestions(),
          bindings: chat.CoachChatBindings(
            storageNamespace: 'capture',
            gateway: chat.CoachGatewayBinding.shared(
              client ?? coach.FakeLlmClient(const [], latency: Duration.zero),
            ),
            plans: _Plans(saves),
            history: history,
            preferences: _Preferences(),
            actions: hostActions,
          ),
        );
        final started = await controller.start();
        if (!started.ok && plan != null) {
          stdout.writeln('$mode/$frame normal snapshot restore rejected');
          stdout.writeln(
            coach.PlanValidator(
                  catalog: controller.catalog,
                  profile: fixture.profile,
                )
                .validate(plan)
                .issues
                .map((issue) => '${issue.code}:${issue.message}')
                .join('\n'),
          );
        }
        expect(
          started.ok,
          isTrue,
          reason: '${started.error} ${started.issues}',
        );
        final key = GlobalKey();
        activeController = controller;
        await tester.pumpWidget(
          DefaultAssetBundle(
            bundle: bundle,
            child: AppScope(
              services: services,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(palette),
                locale: const Locale('zh', 'CN'),
                supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                builder: (_, child) => Material(
                  type: MaterialType.transparency,
                  child: SfPaletteScope(
                    child: RepaintBoundary(key: key, child: child!),
                  ),
                ),
                home: ChatHomePage(
                  controller: controller,
                  clock: () => DateTime.parse(data['captureDate']! as String),
                ),
              ),
            ),
          ),
        );
        await settleArtwork();
        await tester.runAsync(() async {
          final context = key.currentContext!;
          for (final id in CoachV2Fixtures.stretching) {
            for (final role in ['cover', 'thumbnail']) {
              if (!context.mounted) throw StateError('Capture host unmounted');
              await precacheImage(
                AssetImage('posehub-r1/$id/$role', bundle: bundle),
                context,
              );
            }
            if (!context.mounted) throw StateError('Capture host unmounted');
            await precacheImage(
              AssetImage(
                'packages/ugk_trainer/assets/pose_hub/app-test-pack-r1/standing/$id.webp',
                bundle: bundle,
              ),
              context,
            );
          }
        });
        await tester.pumpAndSettle();
        return (key: key, controller: controller);
      }

      Future<void> unmount(_FixtureController controller) async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(controller.close);
      }

      Future<void> restoreFrame(
        _FixtureController controller,
        String frame,
      ) async {
        final data = source(frame);
        controller.displaySuggestions = profile.strings.suggestions();
        final restored = await controller.restoreSnapshot(
          chat.CoachChatSnapshot(
            appId: profile.appId,
            storageNamespace: 'capture',
            session: coach.CoachSessionSnapshot.fromJson(data['snapshot']),
            messages: [
              for (final row in data['messages'] as List)
                Map<String, Object?>.from(row as Map),
            ],
          ),
        );
        expect(
          restored.ok,
          isTrue,
          reason: '${restored.error} ${restored.issues}',
        );
        await settleArtwork();
      }

      if (wanted('empty') || wanted('waiting-250ms')) {
        final gate = Completer<coach.LlmResponse>();
        final client = coach.FakeLlmClient([
          (coach.LlmRequest _) => gate.future,
        ], latency: Duration.zero);
        final host = await mount('empty', client: client, fresh: true);
        await compare(host.key, 'empty');
        final pending = host.controller.send('在家徒手拉伸5分钟');
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await compare(host.key, 'waiting-250ms');
        host.controller.cancelRequest();
        gate.complete(
          const coach.LlmResponse(
            content: '已取消。',
            toolCalls: [],
            finishReason: 'stop',
          ),
        );
        await tester.pumpAndSettle();
        await pending;
        await unmount(host.controller);
      }
      if ([
        'plan-collapsed',
        'plan-expand-280ms',
        'plan-expanded',
        'recommendations',
        'focused-saved-plan',
        'training-enter-150ms',
        'training-enter-300ms',
        'training-exit-140ms',
        'training-return',
      ].any(wanted)) {
        final host = await mount('plan-collapsed');
        await compare(host.key, 'plan-collapsed');
        final plan = host.controller.currentPlan!;
        final expand = find.byKey(ValueKey('plan-expand-${plan.id}'));
        await tester.ensureVisible(expand);
        await tester.tap(expand);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 280));
        await compare(host.key, 'plan-expand-280ms');
        await settleArtwork();
        await compare(host.key, 'plan-expanded');
        await tester.tap(find.byKey(ValueKey('plan-expand-${plan.id}')));
        await tester.pumpAndSettle();
        await restoreFrame(host.controller, 'recommendations');
        await compare(host.key, 'recommendations');
        await restoreFrame(host.controller, 'focused-saved-plan');
        await compare(host.key, 'focused-saved-plan');
        if ([
          'training-enter-150ms',
          'training-enter-300ms',
          'training-exit-140ms',
          'training-return',
        ].any(wanted)) {
          final plan = host.controller.currentPlan!;
          final context = tester.element(find.byType(chat.CoachChatPage));
          await tester.runAsync(
            () => TrainingPosterImages.precache(
              context,
              fixture.library[plan.items.first.exerciseId],
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('start-disc')).hitTestable().last,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          expect(find.byType(PlayerPage, skipOffstage: false), findsOneWidget);
          await compare(host.key, 'training-enter-150ms');
          await tester.pump(const Duration(milliseconds: 150));
          await compare(host.key, 'training-enter-300ms');
          await tester.pump();
          final playerContext = tester.element(find.byType(PlayerPage));
          TrainingRouteScope.maybeOf(playerContext)!.beginExit();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 140));
          await compare(host.key, 'training-exit-140ms');
          await tester.pump(const Duration(milliseconds: 200));
          Navigator.of(playerContext).pop();
          await tester.pumpAndSettle();
          await compare(host.key, 'training-return');
        }
        await unmount(host.controller);
      }
      await tester.runAsync(production.close);
      store.dispose();
      media.dispose();
      await tester.runAsync(
        () => File(
          '${output.path}/$mode-comparison.json',
        ).writeAsString(jsonEncode(comparisons)),
      );
      expect(
        failures,
        isEmpty,
        reason: 'SF source frames with non-zero differences',
      );
    });
  }
}
