// Shared capture driver. Both checkouts run these exact bytes and input JSON.
// The tiny adapter only crosses the old/new public constructor boundary.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/app_test_catalog.dart';
import 'package:smartfit/app/app_test_content.dart';
import 'package:smartfit/app/posehub_asset_bundle.dart';
import 'package:smartfit/app/posehub_bundled_images.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/template.dart';
import 'package:smartfit/ui/chat/coach_ui_adapter.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/open_training.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/training_poster_image.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart' show CoachFailureBubble;
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'capture_adapter.dart';

const _dpr = 2.625;
const _size = Size(412, 915);
const _key = ValueKey('capture-bubble');
const _stageIds = [
  'understand',
  'parameters',
  'actions',
  'planning',
  'review',
  'output',
];

class _Memory implements LocalStateStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _Content {
  _Content(this.app, this.bundle, this.plan, this.repo);
  final AppServices app;
  final AssetBundle bundle;
  final TrainingPlan plan;
  final PoseHubMediaRepository repo;
}

enum _Scene { bubble, delivery, focus, failure, cancelled, card }

coach.CoachSessionState _session(
  Map<String, dynamic> input, {
  String stage = 'actions',
  bool complete = false,
  bool changed = false,
}) {
  final params = Map<String, dynamic>.from(input['params'] as Map);
  if (changed) params['level'] = {'value': 2, 'source': 'user'};
  return coach.CoachSessionState(
    params: {
      for (final entry in params.entries)
        entry.key: coach.CoachParamValue(
          value: (entry.value as Map)['value'],
          source: (entry.value as Map)['source'] as String,
          turn: 1,
        ),
    },
    picks: List<String>.from(input['picks'] as List),
    task: coach.CoachTaskState(
      type: 'plan',
      reused: false,
      nodes: [
        for (final (index, id) in _stageIds.indexed)
          coach.CoachNodeState(
            id: id,
            status: complete || index < _stageIds.indexOf(stage)
                ? 'done'
                : id == stage
                ? 'current'
                : 'pending',
            stamp: 'captured source fact',
          ),
      ],
    ),
  );
}

class _Host extends StatefulWidget {
  const _Host({
    super.key,
    required this.content,
    required this.palette,
    required this.input,
    required this.boundary,
  });
  final _Content content;
  final SfPalette palette;
  final Map<String, dynamic> input;
  final GlobalKey boundary;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final navigator = GlobalKey<NavigatorState>();
  _Scene scene = _Scene.cancelled;
  late coach.CoachSessionState session = _session(widget.input);
  bool waiting = true, complete = false, preparing = true;
  String? focusTitle;
  int epoch = 0;
  BuildContext? source;

  void mutate(VoidCallback callback) => setState(callback);
  void reset(_Scene next) => setState(() {
    scene = next;
    epoch++;
    session = _session(widget.input);
    waiting = true;
    complete = false;
    preparing = true;
    focusTitle = null;
  });

  Widget bubble(BuildContext context) => buildCaptureBubble(
    context: context,
    key: _key,
    state: session,
    library: widget.content.app.library,
    waiting: waiting,
    visualComplete: complete,
    onCancel: () => mutate(() => scene = _Scene.cancelled),
  );

  Widget card(BuildContext context) => PlanCard(
    plan: widget.content.plan,
    library: widget.content.app.library,
    saved: false,
    onSave: () {},
    onOpen: () {},
    onStart: () => unawaited(
      openTraining(
        context,
        plan: widget.content.plan,
        sourceEntry: 'golden_card',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => AppScope(
    services: widget.content.app,
    child: DefaultAssetBundle(
      bundle: widget.content.bundle,
      child: MaterialApp(
        navigatorKey: navigator,
        theme: buildTheme(widget.palette),
        themeAnimationDuration: Duration.zero,
        builder: (_, child) => RepaintBoundary(
          key: widget.boundary,
          child: SfPaletteScope(child: child!),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
            child: Builder(
              builder: (context) {
                source = context;
                return withSmartfitCoachUi(
                  context,
                  Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: ValueKey('scene-$epoch'),
                          child: switch (scene) {
                            _Scene.bubble => bubble(context),
                            _Scene.delivery => buildCaptureDelivery(
                              preparing: preparing,
                              successful: true,
                              child: preparing
                                  ? bubble(context)
                                  : card(context),
                            ),
                            _Scene.focus => buildCaptureFocus(
                              title: focusTitle,
                              onClear: () => mutate(() => focusTitle = null),
                            ),
                            _Scene.failure => CoachFailureBubble(
                              enabled: true,
                              onRetry: () async {},
                            ),
                            _Scene.cancelled => const SizedBox.shrink(),
                            _Scene.card => card(context),
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<Map<String, Object?>>> _fonts(WidgetTester tester) async {
  final result = <Map<String, Object?>>[];
  await tester.runAsync(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.cast<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List).cast<Map>()) {
        final asset = font['asset'] as String;
        final data = await rootBundle.load(asset);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        loader.addFont(Future.value(data));
        result.add({
          'family': family['family'],
          'asset': asset,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        });
      }
      await loader.load();
    }
  });
  expect(result.any((font) => font['family'] == 'NotoSansSC'), isTrue);
  return result;
}

Future<_Content> _content(
  WidgetTester tester,
  Map<String, dynamic> config,
  Map<String, dynamic> input,
  String theme,
) async {
  late _Content result;
  await tester.runAsync(() async {
    final sdk = await PoseHubActionLibrary.load();
    final content = AppTestContent.build(
      catalog: AppTestCatalog.fromSdk(sdk),
      legacyLibrary: ExerciseLibrary([]),
    );
    final images = await PoseHubBundledImages.load(
      catalogRevision: PoseHubActionLibrary.catalogSha256,
    );
    final repo = await PoseHubMediaRepository.create(
      catalog: sdk,
      catalogRevision: PoseHubActionLibrary.catalogSha256,
      mediaBaseUrls: const [],
      rootDirectory: '${config['mediaCache']}/$theme',
      bundledFileLoader: images.loadFile,
    );
    final store = AppStore(_Memory())..starfield = false;
    await store.acceptSafety(blocked: false);
    final app = AppServices(
      library: content.library,
      catalog: TemplateCatalog.fromJson(
        jsonDecode(await rootBundle.loadString('assets/library/templates.json'))
            as Map<String, dynamic>,
      ),
      store: store,
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
      poseHubCatalog: sdk,
      testCatalog: content.catalog,
    );
    result = _Content(
      app,
      PoseHubAssetBundle(catalog: sdk, installation: repo),
      TrainingPlan.fromJson(Map<String, dynamic>.from(input['plan'] as Map)),
      repo,
    );
  });
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const configPath = String.fromEnvironment('SMARTFIT_UI_KIT_CAPTURE_CONFIG');
  final config =
      jsonDecode(File(configPath).readAsStringSync()) as Map<String, dynamic>;
  final inputBytes = File(config['inputs'] as String).readAsBytesSync();
  final input = jsonDecode(utf8.decode(inputBytes)) as Map<String, dynamic>;
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final theme = palette.brightness.name;
    testWidgets('ui kit same-driver frames $theme', (tester) async {
      tester.view.physicalSize = _size * _dpr;
      tester.view.devicePixelRatio = _dpr;
      addTearDown(tester.view.reset);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      SfCutouts.animate = false;
      stdout.writeln('CAPTURE_STAGE $theme fonts');
      final fonts = await _fonts(tester);
      stdout.writeln('CAPTURE_STAGE $theme content');
      final content = await _content(tester, config, input, theme);
      final hostKey = GlobalKey<_HostState>();
      final boundaryKey = GlobalKey();
      final frames = <Map<String, Object?>>[];
      final output = Directory('${config['output']}/$theme');
      output.createSync(recursive: true);
      stdout.writeln('CAPTURE_STAGE $theme mount-blank');
      await tester.pumpWidget(
        _Host(
          key: hostKey,
          content: content,
          palette: palette,
          input: input,
          boundary: boundaryKey,
        ),
      );
      await tester.pump();
      final host = hostKey.currentState!;
      stdout.writeln('CAPTURE_STAGE $theme precache');
      await tester.runAsync(() async {
        for (final id in content.plan.exerciseIds) {
          final exercise = content.app.library[id];
          for (final asset in [
            exercise.media.alphaCover,
            exercise.media.alphaThumbnail,
          ]) {
            if (asset != null) {
              await precacheImage(AssetImage(asset), host.source!);
            }
          }
        }
        await TrainingPosterImages.precache(
          host.source!,
          content.app.library[content.plan.items.first.exerciseId],
        );
      });
      await tester.pump();
      stdout.writeln('CAPTURE_STAGE $theme ready');
      host.reset(_Scene.bubble);
      await tester.pump();

      Future<void> capture(
        String name, {
        int? elapsedUs,
        double? fraction,
        Map<String, Object?> extra = const {},
      }) async {
        stdout.writeln('CAPTURE_FRAME $theme/$name');
        await tester.pump();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        expect(boundary.size, _size);
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: _dpr);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final bytes = data!.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            final file = File('${output.path}/$name.png');
            if (await file.exists()) {
              expect(
                sha256.convert(await file.readAsBytes()).toString(),
                sha256.convert(bytes).toString(),
                reason: 'Preserve existing captured bytes',
              );
            } else {
              await file.writeAsBytes(bytes, flush: true);
            }
            frames.add({
              'frame': '$theme/$name.png',
              'bytes': bytes.length,
              'sha256': sha256.convert(bytes).toString(),
              'width': image.width,
              'height': image.height,
              'elapsedUs': ?elapsedUs,
              'fraction': ?fraction,
              ...extra,
            });
          } finally {
            image.dispose();
          }
        });
      }

      for (var i = 0; i <= 4; i++) {
        if (i > 0) await tester.pump(const Duration(milliseconds: 400));
        await capture('waiting-${i * 400}ms', elapsedUs: i * 400000);
      }
      await capture('parameters-before', elapsedUs: 1600000);
      host.mutate(() => host.session = _session(input, changed: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await capture('parameters-after', elapsedUs: 1860000);

      host.mutate(() {
        host.session = _session(
          input,
          stage: 'output',
          complete: true,
          changed: true,
        );
        host.waiting = false;
        host.complete = true;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      await capture('complete', elapsedUs: 260000);

      host.reset(_Scene.failure);
      await tester.pump();
      await capture('failure');
      host.reset(_Scene.bubble);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('generation-cancel-target')));
      await tester.pump();
      expect(host.scene, _Scene.cancelled);
      await capture('cancelled');

      host.reset(_Scene.delivery);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      host.mutate(() => host.preparing = false);
      await tester.pump();
      for (var i = 0; i <= 4; i++) {
        if (i > 0) await tester.pump(const Duration(microseconds: 222500));
        await capture(
          'delivery-${i * 25}pct',
          elapsedUs: i * 222500,
          fraction: i / 4,
        );
      }

      host.reset(_Scene.focus);
      await tester.pump();
      host.mutate(() => host.focusTitle = content.plan.title);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      await capture('focus-appearing', elapsedUs: 90000, fraction: .5);
      await tester.pump(const Duration(milliseconds: 90));
      await capture('focus-held', elapsedUs: 180000, fraction: 1);
      await tester.tap(find.byKey(const ValueKey('plan-focus-clear')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await capture('focus-clearing', elapsedUs: 60000, fraction: .5);
      await tester.pump(const Duration(milliseconds: 60));
      await capture('focus-cleared', elapsedUs: 120000, fraction: 1);

      host.reset(_Scene.card);
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => TrainingPosterImages.precache(
          host.source!,
          content.app.library[content.plan.items.first.exerciseId],
        ),
      );
      await tester.tap(find.byKey(ValueKey('plan-start-${content.plan.id}')));
      for (
        var i = 0;
        i < 12 &&
            find.byType(PlayerPage, skipOffstage: false).evaluate().isEmpty;
        i++
      ) {
        await tester.pump();
      }
      await tester.pump();
      final player = find.byType(PlayerPage, skipOffstage: false);
      expect(player, findsOneWidget);
      final route = ModalRoute.of(tester.element(player))!;
      expect(route.settings.name, 'player');
      for (var i = 0; i <= 4; i++) {
        if (i > 0) await tester.pump(const Duration(milliseconds: 75));
        await capture(
          'training-entry-${i * 25}pct',
          elapsedUs: i * 75000,
          fraction: i / 4,
          extra: {
            'routeValue': route.animation!.value,
            'routeStatus': route.animation!.status.name,
          },
        );
      }
      await tester.pump(const Duration(microseconds: 1));
      await tester.pump();
      beginCaptureExit(tester.element(player));
      await tester.pump();
      for (var i = 0; i <= 4; i++) {
        if (i > 0) await tester.pump(const Duration(milliseconds: 70));
        await capture(
          'training-exit-${i * 25}pct',
          elapsedUs: i * 70000,
          fraction: i / 4,
          extra: {
            'routeValue': route.animation!.value,
            'routeStatus': route.animation!.status.name,
          },
        );
      }
      host.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(frames, hasLength(29));
      await tester.runAsync(() async {
        final manifest = File('${output.path}/capture-manifest.json');
        expect(await manifest.exists(), isFalse);
        await manifest.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
            'schema': 'smartfit-ui-kit-same-driver-frames@1',
            'variant': config['variant'],
            'source': config['source'],
            'publicInputsSha256': config['publicInputsSha256'],
            'driverSha256': config['driverSha256'],
            'adapterSha256': config['adapterSha256'],
            'focusImplementation': config['focusImplementation'],
            'inputsSha256': sha256.convert(inputBytes).toString(),
            'logicalSize': {'width': 412, 'height': 915},
            'dpr': _dpr,
            'physicalSizeRounding': 'ceil in RenderRepaintBoundary.toImage',
            'theme': theme,
            'fonts': fonts,
            'frames': frames,
            'isPhoneScreenshot': false,
            'isPerformanceMeasurement': false,
            'container': {'left': 20, 'top': 64, 'right': 20, 'bottom': 20},
            'media': 'production PoseHubAssetBundle + verified bundled image loader',
            'routeExitTrigger': 'production public control.beginExit; no copied animation',
            'focusSampleTimesMs': {'appearing': 90, 'held': 180, 'clearing': 60, 'cleared': 120},
            'deliveryDurationUs': 890000,
          })}\n',
          flush: true,
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await content.app.dispose();
      content.repo.dispose();
      SfColors.palette = SfPalette.dark;
    });
  }
}
