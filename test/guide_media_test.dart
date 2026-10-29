import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/ui/guide_media.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_trainer/ugk_trainer.dart';

import 'posehub_ui_support.dart';

class _VideoPlatform extends PackedAlphaPlatform
    implements PackedAlphaUriPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final sources = <Uri>[];
  final operations = <(String, int)>[];
  final positions = <int, double>{};
  final pendingCreates = <int, Completer<void>>{};

  @override
  bool get isSupported => true;
  @override
  Stream<Map<Object?, Object?>> get events => _events.stream;
  @override
  Future<({int playerId, int textureId})> create(String asset) =>
      createUri(Uri(scheme: 'asset', host: '', path: '/$asset'));
  @override
  Future<({int playerId, int textureId})> createUri(Uri uri) async {
    sources.add(uri);
    final id = sources.length;
    operations.add(('create', id));
    final gate = pendingCreates[id];
    if (gate != null) await gate.future;
    return (playerId: id, textureId: 100 + id);
  }

  @override
  Future<Object?> command(int id, String type, [Object? value]) async {
    operations.add((type, id));
    return type == 'position' ? positions[id] ?? 0 : null;
  }

  void ready(int id) => _events.add({'playerId': id, 'type': 'ready'});
  void firstFrame(int id) =>
      _events.add({'playerId': id, 'type': 'first-frame'});
  Future<void> close() => _events.close();
}

Finder _media(String slot) => find.byKey(ValueKey('guide-media-$slot'));
Finder _control(String slot) =>
    find.byKey(ValueKey('guide-media-control-$slot'));
Finder _poster(String slot) => find.byKey(ValueKey('guide-media-poster-$slot'));
Finder _video(String slot) => find.byKey(ValueKey('guide-media-video-$slot'));

double _opacity(WidgetTester tester, String slot) => tester
    .widget<FadeTransition>(
      find.descendant(of: _poster(slot), matching: find.byType(FadeTransition)),
    )
    .opacity
    .value;

void main() {
  late coach.PoseHubAppTestCatalog catalog;
  late _VideoPlatform platform;
  setUpAll(() async => catalog = await PoseHubActionLibrary.load());
  setUp(() {
    platform = _VideoPlatform();
    UgkPackedAlphaVideo.debugPlatform = platform;
    UgkPackedAlphaVideo.debugFilterBuilder = (_) => const SizedBox.expand();
  });
  tearDown(() async {
    UgkPackedAlphaVideo.debugPlatform = null;
    UgkPackedAlphaVideo.debugFilterBuilder = null;
    SfColors.palette = SfPalette.dark;
    await platform.close();
  });

  Future<(GuidePreviewCoordinator, PoseHubUiRepository)> show(
    WidgetTester tester, {
    SfPalette palette = SfPalette.light,
    int count = 2,
    Future<Uri> Function(String)? onEnsureAction,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final coordinator = GuidePreviewCoordinator();
    addTearDown(coordinator.dispose);
    final repo = PoseHubUiRepository(
      mediaBaseUri: Uri.parse('file:///verified-guide-pack/'),
      onEnsureAction: onEnsureAction,
    );
    final actions = catalog.semanticCompleteActions.take(count).toList();
    final services = poseHubUiServices(
      catalog: catalog,
      media: repo,
      library: ExerciseLibrary([
        for (final action in actions) poseHubUiExercise(action),
      ]),
    );
    addTearDown(services.dispose);
    await tester.pumpWidget(
      poseHubUiApp(
        palette: palette,
        services: services,
        home: Scaffold(
          body: ListView(
            children: [
              for (var index = 0; index < count; index++)
                Center(
                  child: SizedBox(
                    width: 320,
                    height: 240,
                    child: GuideMedia(
                      exercise: poseHubUiExercise(actions[index]),
                      slot: '$index',
                      coordinator: coordinator,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (coordinator, repo);
  }

  Future<void> tap(WidgetTester tester, String slot) async {
    final expectedSources = platform.sources.length + 1;
    await tester.tap(_control(slot));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (platform.sources.length >= expectedSources) return;
    }
    final services = AppServices.of(tester.element(_media(slot)));
    final repo = services.poseHubMedia! as PoseHubUiRepository;
    final state = tester.state(
      find.byWidgetPredicate(
        (widget) => widget is GuideMedia && widget.slot == slot,
      ),
    );
    expect(
      platform.sources.length,
      expectedSources,
      reason: 'prepareAction=${repo.actionRequests}; $state',
    );
  }

  Future<void> advance(WidgetTester tester, int id) async {
    platform.ready(id);
    platform.firstFrame(id);
    platform.positions[id] = .25;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('opening and scrolling create no playback or preparation', (
    tester,
  ) async {
    final (coordinator, repo) = await show(tester, count: 6);
    expect(find.byType(UgkPackedAlphaVideo), findsNothing);
    expect(find.byType(DrillMediaView), findsNothing);
    expect(coordinator.activeSlot, isNull);
    expect(platform.sources, isEmpty);
    expect(repo.actionRequests, isEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(platform.sources, isEmpty);
    expect(repo.actionRequests, isEmpty);
    expect(coordinator.activeSlot, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'control geometry and colors are exact ${palette.brightness.name}',
      (tester) async {
        await show(tester, palette: palette);
        final media = tester.getRect(_media('0'));
        final control = tester.getRect(_control('0'));
        final faceFinder = find.byKey(
          const ValueKey('guide-media-control-face-0'),
        );
        final face = tester.getRect(faceFinder);
        expect(media.size, const Size(320, 240));
        expect(control.size, const Size(44, 44));
        expect(face.size, const Size(36, 36));
        expect(face.top - media.top, 12);
        expect(media.right - face.right, 12);
        final decoration =
            tester.widget<Container>(faceFinder).decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(
          decoration.color,
          palette.isDark
              ? Colors.black.withValues(alpha: .55)
              : Colors.white.withValues(alpha: .92),
        );
        if (palette.isDark) {
          expect(decoration.boxShadow, isNull);
        } else {
          expect(decoration.boxShadow!.single.offset, const Offset(0, 2));
          expect(decoration.boxShadow!.single.blurRadius, 8);
          expect(
            decoration.boxShadow!.single.color,
            Colors.black.withValues(alpha: .12),
          );
        }
        final icon = tester.widget<Icon>(
          find.descendant(of: _control('0'), matching: find.byType(Icon)),
        );
        expect(icon.icon, Icons.play_arrow_rounded);
        expect(icon.size, 20);
        expect(icon.color, palette.isDark ? Colors.white : palette.accent);
        final switcher = tester.widget<AnimatedSwitcher>(
          find.descendant(
            of: _control('0'),
            matching: find.byType(AnimatedSwitcher),
          ),
        );
        expect(switcher.duration, const Duration(milliseconds: 150));
        await tap(tester, '0');
        final loading = find.byKey(const ValueKey('guide-media-loading-0'));
        expect(tester.getSize(loading), const Size(16, 16));
        expect(
          tester
              .widget<CircularProgressIndicator>(
                find.descendant(
                  of: loading,
                  matching: find.byType(CircularProgressIndicator),
                ),
              )
              .strokeWidth,
          2,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('ready and first frame at position zero keep the poster opaque', (
    tester,
  ) async {
    final (coordinator, _) = await show(tester);
    await tap(tester, '0');
    expect(platform.sources, hasLength(1));
    expect(coordinator.activeSlot, '0');
    platform.ready(1);
    platform.firstFrame(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.widget<AnimatedOpacity>(_poster('0')).opacity, 1);
    expect(_opacity(tester, '0'), 1);
    platform.positions[1] = .1;
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();
    final fade = tester.widget<AnimatedOpacity>(_poster('0'));
    expect(fade.opacity, 0);
    expect(fade.duration, const Duration(milliseconds: 200));
    expect(fade.curve, Curves.easeOutCubic);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, '0'), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_opacity(tester, '0'), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pause and resume retain the same sole decoder', (tester) async {
    final (coordinator, _) = await show(tester);
    await tap(tester, '0');
    await advance(tester, 1);
    final controller = tester
        .widget<UgkPackedAlphaVideo>(_video('0'))
        .controller;
    await tester.tap(_control('0'));
    await tester.pump();
    expect(coordinator.activeSlot, '0');
    expect(platform.sources, hasLength(1));
    expect(
      tester.widget<UgkPackedAlphaVideo>(_video('0')).controller,
      same(controller),
    );
    expect(platform.operations, contains(('pause', 1)));
    await tester.tap(_media('0'));
    await tester.pump();
    expect(platform.sources, hasLength(1));
    expect(
      tester.widget<UgkPackedAlphaVideo>(_video('0')).controller,
      same(controller),
    );
    expect(controller.wantsPlay, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'switching retires the old surface before creating its successor',
    (tester) async {
      final (coordinator, _) = await show(tester);
      await tap(tester, '0');
      await advance(tester, 1);
      await tap(tester, '1');
      expect(coordinator.activeSlot, '1');
      expect(find.byType(UgkPackedAlphaVideo), findsOneWidget);
      expect(_video('0'), findsNothing);
      expect(tester.widget<AnimatedOpacity>(_poster('0')).opacity, 1);
      expect(
        tester.widget<AnimatedOpacity>(_poster('0')).duration,
        Duration.zero,
      );
      expect(
        platform.operations.indexOf(('dispose', 1)),
        lessThan(platform.operations.indexOf(('create', 2))),
      );
      await coordinator.release('other-slot');
      expect(coordinator.activeSlot, '1');
      final release = coordinator.release('1');
      await tester.pump();
      await tester.pump();
      await release;
      expect(coordinator.activeSlot, isNull);
      expect(find.byType(UgkPackedAlphaVideo), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'switching while a pack prepares never waits for the old download',
    (tester) async {
      final pending = Completer<Uri>();
      final first = catalog.semanticCompleteActions.first.id;
      final base = Uri.parse('file:///verified-guide-pack/');
      final (coordinator, repo) = await show(
        tester,
        onEnsureAction: (id) =>
            id == first ? pending.future : Future.value(base),
      );
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(base);
      });
      await tester.tap(_control('0'));
      await tester.pump();
      expect(repo.actionRequests, contains(first));
      expect(coordinator.activeSlot, '0');
      expect(platform.sources, isEmpty);
      await tap(tester, '1');
      expect(coordinator.activeSlot, '1');
      expect(platform.sources, hasLength(1));
      pending.complete(base);
      await tester.pump();
      expect(coordinator.activeSlot, '1');
      expect(platform.sources, hasLength(1));
      expect(_video('0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a late initialization cannot revive a switched or closed slot', (
    tester,
  ) async {
    final gate = Completer<void>();
    platform.pendingCreates[1] = gate;
    final (coordinator, _) = await show(tester);
    await tap(tester, '0');
    expect(platform.sources, hasLength(1));
    await tap(tester, '1');
    expect(coordinator.activeSlot, '1');
    gate.complete();
    await tester.pump();
    expect(platform.operations, contains(('dispose', 1)));
    expect(_video('0'), findsNothing);
    expect(find.byType(UgkPackedAlphaVideo), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(coordinator.activeSlot, isNull);
  });

  testWidgets(
    'disposing the page coordinator while active never repaints a locked tree',
    (tester) async {
      final (coordinator, _) = await show(tester);
      await tap(tester, '0');
      coordinator.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(platform.operations, contains(('dispose', 1)));
    },
  );
}
