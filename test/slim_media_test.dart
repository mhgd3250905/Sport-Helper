import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/posehub_media_repository.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/cached_exercise_media.dart';
import 'package:smartfit/ui/player_page.dart';
import 'package:smartfit/ui/plan_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

final _base = Uri.parse('file:///slim-media-contract/');

class _Cache extends PoseHubUiRepository implements PoseHubVideoCacheAccess {
  _Cache({Future<Uri> Function(String)? prepare})
    : super(mediaBaseUri: _base, onEnsureAction: prepare);
  final hits = <String, Uri>{};
  final queries = <String>[];
  final pins = <String, int>{};
  final events = <String>[];

  @override
  Future<Uri?> cachedVideo(String id) async {
    queries.add(id);
    events.add('query:$id');
    return hits[id];
  }

  @override
  VoidCallback retainVideo(String id) {
    pins.update(id, (n) => n + 1, ifAbsent: () => 1);
    events.add('pin:$id');
    var released = false;
    return () {
      if (released) return;
      released = true;
      pins[id] = pins[id]! - 1;
      events.add('release:$id');
    };
  }
}

class _Platform extends PackedAlphaPlatform implements PackedAlphaUriPlatform {
  final sources = <Uri>[];
  final operations = <(String, int)>[];
  final positions = <int, double?>{};
  final creates = <int, Completer<void>>{};
  final stream = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => stream.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      throw StateError('Catalog media must use a verified external source');
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    sources.add(uri);
    final id = sources.length;
    operations.add(('create', id));
    await creates[id]?.future;
    return (playerId: id, textureId: id + 100);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    operations.add((type, id));
    return type == 'position'
        ? positions.containsKey(id)
              ? positions[id]
              : 0.0
        : null;
  }

  void emit(int id, String type) => stream.add({'playerId': id, 'type': type});
  int get inspections => operations.where((op) => op.$1 == 'position').length;
}

class _Voice extends MutedVoiceOutput {
  int begins = 0;
  @override
  Future<void> begin() async => begins++;
}

TrainingPlan _plan(List<coach.PoseHubPackAction> actions) => TrainingPlan(
  id: 'slim-media-training',
  source: 'test',
  title: '缓存训练',
  summary: '',
  goal: 'core',
  scene: 'home',
  equipment: const [],
  level: 1,
  targetMinutes: 1,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        for (final action in actions)
          PlanItem(
            exerciseId: action.id,
            mode: DoseMode.time,
            sets: 1,
            workSeconds: 2,
            perSide: false,
            restSeconds: 0,
          ),
      ],
    ),
  ],
);

Finder _control(String slot) =>
    find.byKey(ValueKey('guide-media-control-$slot'));
Finder _poster(String slot) =>
    find.byKey(ValueKey('cached-media-poster-$slot'));
Finder _video(String slot) => find.byKey(ValueKey('cached-media-video-$slot'));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late coach.PoseHubAppTestCatalog catalog;
  late _Platform platform;
  final cleanup = <VoidCallback>[];
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    platform = _Platform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() async {
    for (final dispose in cleanup.reversed) {
      dispose();
    }
    cleanup.clear();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.stream.close();
  });

  Future<AppServices> mount(
    WidgetTester tester,
    _Cache cache,
    Widget Function(AppServices) content, {
    SfPalette palette = SfPalette.light,
    VoiceOutput voice = const MutedVoiceOutput(),
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    final actions = catalog.semanticCompleteActions.take(6).toList();
    final services = poseHubUiServices(
      catalog: catalog,
      media: cache,
      voiceOutput: voice,
      library: ExerciseLibrary(actions.map(poseHubUiExercise).toList()),
    );
    cleanup.add(cache.dispose);
    cleanup.add(services.store.dispose);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          theme: buildTheme(palette),
          themeAnimationDuration: Duration.zero,
          builder: (_, child) => SfPaletteScope(child: child!),
          home: content(services),
        ),
      ),
    );
    await tester.pump();
    return services;
  }

  Future<void> frames(WidgetTester tester, [int count = 8]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump();
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<GuidePreviewCoordinator> guide(
    WidgetTester tester,
    _Cache cache, {
    int count = 2,
    SfPalette palette = SfPalette.light,
  }) async {
    final coordinator = GuidePreviewCoordinator();
    cleanup.add(coordinator.dispose);
    await mount(
      tester,
      cache,
      (services) => Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              for (var i = 0; i < count; i++)
                SizedBox(
                  width: 320,
                  height: 320,
                  child: GuideMedia(
                    exercise:
                        services.library[catalog.semanticCompleteActions
                            .elementAt(i)
                            .id],
                    slot: '$i',
                    coordinator: coordinator,
                  ),
                ),
            ],
          ),
        ),
      ),
      palette: palette,
    );
    return coordinator;
  }

  Future<void> tap(WidgetTester tester, String slot) async {
    await tester.tap(_control(slot));
    await frames(tester);
  }

  Future<void> ready(WidgetTester tester, int id, double position) async {
    platform.emit(id, 'ready');
    platform.emit(id, 'first-frame');
    platform.positions[id] = position;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
  }

  testWidgets('guide starts and scrolls with zero decoder, query or download', (
    tester,
  ) async {
    final cache = _Cache();
    final coordinator = await guide(tester, cache, count: 6);
    expect(platform.sources, isEmpty);
    expect(cache.queries, isEmpty);
    expect(cache.actionRequests, isEmpty);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(platform.sources, isEmpty);
    expect(cache.pins, isEmpty);
    expect(coordinator.activeSlot, isNull);
    await unmount(tester);
  });

  testWidgets(
    'main article layout stays square and releases a mostly hidden preview',
    (tester) async {
      final actions = catalog.semanticCompleteActions.take(2).toList();
      final cache = _Cache()
        ..hits[actions.first.id] = actions.first.video.resolve(_base);
      await mount(tester, cache, (_) => PlanPage(plan: _plan(actions)));
      expect(platform.sources, isEmpty);
      expect(cache.queries, isEmpty);
      final rectangle = tester.getSize(
        find.byKey(const ValueKey('article-video-0:0')),
      );
      expect(rectangle.width, rectangle.height);
      await tap(tester, '0:0');
      await ready(tester, 1, .1);
      final coordinator = tester
          .widget<GuideMedia>(find.byType(GuideMedia).first)
          .coordinator;
      expect(coordinator.activeSlot, '0:0');
      await tester.drag(
        find.byKey(const ValueKey('plan-article')),
        const Offset(0, -650),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await frames(tester);
      expect(coordinator.activeSlot, isNull);
      expect(cache.pins[actions.first.id], 0);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      await unmount(tester);
    },
  );

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'guide control geometry and progress use approved ${palette.brightness.name} values',
      (tester) async {
        final gate = Completer<Uri>();
        final cache = _Cache(prepare: (_) => gate.future);
        final action = catalog.semanticCompleteActions.first;
        await guide(tester, cache, palette: palette);
        final media = tester.getRect(
          find.byKey(const ValueKey('guide-media-0')),
        );
        final face = find.byKey(const ValueKey('guide-media-control-face-0'));
        final rect = tester.getRect(face);
        expect(tester.getSize(_control('0')), const Size(44, 44));
        expect(rect.size, const Size(36, 36));
        expect(rect.top - media.top, 12);
        expect(media.right - rect.right, 12);
        final decoration =
            tester.widget<Container>(face).decoration! as BoxDecoration;
        expect(
          decoration.color,
          palette.isDark
              ? Colors.black.withValues(alpha: .55)
              : Colors.white.withValues(alpha: .92),
        );
        await tap(tester, '0');
        cache.setFileState(
          action.video,
          PoseHubDownloadState(
            phase: PoseHubDownloadPhase.downloading,
            receivedBytes: 25,
            totalBytes: 100,
          ),
        );
        await frames(tester, 3);
        final progress = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(progress.strokeWidth, 2);
        expect(progress.value, .25);
        expect(progress.color, palette.accent);
        expect(cache.events.take(2), [
          'pin:${action.id}',
          'query:${action.id}',
        ]);
        await unmount(tester);
        gate.complete(_base);
        await frames(tester, 2);
        expect(cache.pins[action.id], 0);
      },
    );
  }

  testWidgets(
    'offline guide keeps frame zero, shows cloud_off and retries successfully',
    (tester) async {
      var attempts = 0;
      final cache = _Cache(
        prepare: (_) async {
          if (++attempts == 1) throw StateError('offline fixture');
          return _base;
        },
      );
      await guide(tester, cache);
      await tap(tester, '0');
      await tester.pump(const Duration(milliseconds: 160));
      await frames(tester, 3);
      final offline = find.byKey(const ValueKey('guide-media-offline-0'));
      expect(tester.widget<Icon>(offline).icon, Icons.cloud_off_rounded);
      expect(tester.widget<Icon>(offline).size, 20);
      expect(tester.widget<AnimatedOpacity>(_poster('0')).opacity, 1);
      expect(platform.sources, isEmpty);
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.duration, const Duration(seconds: 2));
      final label = tester.widget<Text>(find.text('连上网络后可以播放视频'));
      expect(label.style!.fontSize, 13);
      expect(label.style!.fontWeight, FontWeight.w500);
      await tap(tester, '0');
      expect(platform.sources, hasLength(1));
      await ready(tester, 1, .1);
      expect(tester.widget<AnimatedOpacity>(_poster('0')).opacity, 0);
      expect(attempts, 2);
      await unmount(tester);
    },
  );

  testWidgets(
    'guide cache hit skips preparation and fades only after a real advancing frame',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final cache = _Cache()..hits[action.id] = action.video.resolve(_base);
      await guide(tester, cache);
      await tap(tester, '0');
      expect(cache.actionRequests, isEmpty);
      expect(platform.sources.single, action.video.resolve(_base));
      expect(_video('0'), findsOneWidget);
      await ready(tester, 1, 0);
      expect(tester.widget<AnimatedOpacity>(_poster('0')).opacity, 1);
      platform.positions[1] = .1;
      await tester.pump(const Duration(milliseconds: 80));
      final poster = tester.widget<AnimatedOpacity>(_poster('0'));
      expect(poster.opacity, 0);
      expect(poster.duration, const Duration(milliseconds: 200));
      expect(poster.curve, Curves.easeOutCubic);
      await tester.pump(const Duration(milliseconds: 200));
      final inspections = platform.inspections;
      await tester.pump(const Duration(seconds: 1));
      expect(platform.inspections, inspections);
      await unmount(tester);
    },
  );

  testWidgets('rapid play pause play keeps distinct 150ms transition entries', (
    tester,
  ) async {
    final action = catalog.semanticCompleteActions.first;
    final cache = _Cache()..hits[action.id] = action.video.resolve(_base);
    await guide(tester, cache);
    await tap(tester, '0');
    await ready(tester, 1, .1);
    for (var i = 0; i < 6; i++) {
      await tap(tester, '0');
    }
    final switcher = find.descendant(
      of: _control('0'),
      matching: find.byType(AnimatedSwitcher),
    );
    expect(
      tester.widget<AnimatedSwitcher>(switcher).duration,
      const Duration(milliseconds: 150),
    );
    expect(platform.sources, hasLength(1));
    expect(cache.pins[action.id], 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester);
    expect(cache.pins[action.id], 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('switch and late download cannot revive an old guide slot', (
    tester,
  ) async {
    final first = catalog.semanticCompleteActions.first;
    final gate = Completer<Uri>();
    final cache = _Cache(
      prepare: (id) => id == first.id ? gate.future : Future.value(_base),
    );
    final coordinator = await guide(tester, cache);
    await tap(tester, '0');
    expect(platform.sources, isEmpty);
    await tap(tester, '1');
    expect(coordinator.activeSlot, '1');
    expect(platform.sources, hasLength(1));
    expect(cache.pins[first.id], 0);
    gate.complete(_base);
    await frames(tester);
    expect(platform.sources, hasLength(1));
    await ready(tester, 1, .1);
    await tap(tester, '0');
    expect(
      platform.operations.indexOf(('dispose', 1)),
      lessThan(platform.operations.indexOf(('create', 2))),
    );
    expect(find.byType(UgkPackedAlphaVideo), findsOneWidget);
    await unmount(tester);
    expect(cache.pins.values, everyElement(0));
    expect(coordinator.activeSlot, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'training miss waits for actual decoder wrap and ignores null or jitter',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final gate = Completer<Uri>();
      final cache = _Cache(prepare: (_) => gate.future);
      await mount(
        tester,
        cache,
        (s) => Scaffold(
          body: SizedBox.square(
            dimension: 320,
            child: CachedExerciseMedia(
              exercise: s.library[action.id],
              waitForLoopOnMiss: true,
            ),
          ),
        ),
      );
      expect(platform.sources, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete(_base);
      await frames(tester);
      await ready(tester, 1, 6.0);
      expect(tester.widget<AnimatedOpacity>(_poster(action.id)).opacity, 1);
      platform.positions[1] = 5.95;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedOpacity>(_poster(action.id)).opacity, 1);
      platform.positions[1] = null;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedOpacity>(_poster(action.id)).opacity, 1);
      platform.positions[1] = .05;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedOpacity>(_poster(action.id)).opacity, 0);
      await unmount(tester);
      expect(cache.pins[action.id], 0);
    },
  );

  testWidgets(
    'training cache hit reveals without waiting a loop and pause stops inspections',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final cache = _Cache()..hits[action.id] = action.video.resolve(_base);
      final paused = ValueNotifier(false);
      cleanup.add(paused.dispose);
      await mount(
        tester,
        cache,
        (s) => Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: paused,
            builder: (_, value, _) => SizedBox.square(
              dimension: 320,
              child: CachedExerciseMedia(
                exercise: s.library[action.id],
                paused: value,
                waitForLoopOnMiss: true,
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      await ready(tester, 1, 0);
      paused.value = true;
      await tester.pump();
      final inspected = platform.inspections;
      await tester.pump(const Duration(seconds: 1));
      expect(platform.inspections, inspected);
      expect(cache.pins[action.id], 1);
      expect(platform.sources, hasLength(1));
      paused.value = false;
      await tester.pump();
      platform.positions[1] = .1;
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedOpacity>(_poster(action.id)).opacity, 0);
      expect(cache.actionRequests, isEmpty);
      await unmount(tester);
      expect(cache.pins[action.id], 0);
    },
  );

  testWidgets(
    'background and exit retire decoder, pin and pending inspections',
    (tester) async {
      final action = catalog.semanticCompleteActions.first;
      final cache = _Cache()..hits[action.id] = action.video.resolve(_base);
      final coordinator = await guide(tester, cache);
      await tap(tester, '0');
      await ready(tester, 1, 0);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await frames(tester);
      expect(platform.operations, contains(('dispose', 1)));
      expect(cache.pins[action.id], 0);
      expect(coordinator.activeSlot, isNull);
      final inspected = platform.inspections;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      expect(platform.sources, hasLength(1));
      expect(platform.inspections, inspected);
      await unmount(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TrainerPlayer clocks, voice and result finish while videos remain unavailable',
    (tester) async {
      final actions = catalog.semanticCompleteActions.take(2).toList();
      final pending = {
        for (final action in actions) action.id: Completer<Uri>(),
      };
      final cache = _Cache(prepare: (id) => pending[id]!.future);
      final voice = _Voice();
      final services = await mount(
        tester,
        cache,
        (_) => PlayerPage(plan: _plan(actions)),
        voice: voice,
      );
      expect(voice.begins, 1);
      expect(find.byType(PoseHubMediaPreparationPanel), findsNothing);
      expect(find.text('连上网络后可以播放视频'), findsNothing);
      expect(platform.sources, isEmpty);
      for (var i = 0; i < 340; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(services.store.sessionResults, hasLength(1));
      expect(services.store.sessionResults.single.full, isTrue);
      expect(platform.sources, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await unmount(tester);
      for (final gate in pending.values) {
        gate.complete(_base);
      }
      await frames(tester);
      expect(cache.pins.values, everyElement(0));
      expect(tester.takeException(), isNull);
    },
  );
}
