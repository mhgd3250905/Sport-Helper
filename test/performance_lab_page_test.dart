import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_fixture.dart';
import 'package:smartfit/diagnostics/performance_report.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/performance_lab_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/fixed_glass_policy.dart';
import 'package:smartfit/ui/theme/glass.dart';

import 'app_flow_test.dart' show services, tall;

void main() {
  for (final plan in [true, false]) {
    testWidgets('acceptance ${plan ? 'plan' : 'chat'} uses the page default', (
      tester,
    ) async {
      tall(tester);
      SfGlass.qualityOverride = GlassQuality.minimal;
      addTearDown(() => SfGlass.qualityOverride = null);
      final source = services();
      final scenario = plan
          ? FrameScenario.planCardScroll
          : FrameScenario.longChatScroll;
      final fixture = PerformanceFixture.create(
        library: source.library,
        scenario: scenario,
        starfield: false,
      );
      final recorder = FrameRecorder(enabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: PerformanceCaseRunner(
            source: source,
            fixture: fixture,
            recorder: recorder,
            variant: 'glass_on_stars_off',
            scenario: scenario,
            fixedGlassConfigurationId: plan
                ? 'suggestions_static'
                : 'chat_suggestions_static',
            fixedGlassPolicy: SfFixedGlassPolicy.chat,
            variantLabel: 'current default',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        find.ancestor(
          of: find.byType(ChatHomePage),
          matching: find.byType(SfFixedGlassScope),
        ),
        findsNothing,
        reason: 'A benchmark override must not hide a missing page default.',
      );
      expect(
        find.descendant(
          of: find.byType(SuggestionStrip),
          matching: find.byType(GlassContainer),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ChatInputBar),
          matching: find.byType(GlassContainer),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      recorder.stop();
    });
  }

  testWidgets(
    'internal panel exposes eight cells and does not create real chat',
    (tester) async {
      final source = services();
      final recorder = FrameRecorder(enabled: true);
      final service = PerformanceReportService(recorder: recorder);
      await tester.pumpWidget(
        AppScope(
          services: source,
          child: MaterialApp(home: PerformanceLabPage(service: service)),
        ),
      );
      final panel = tester.widget<ListView>(find.byType(ListView));
      final children =
          (panel.childrenDelegate as SliverChildListDelegate).children;
      // ListView remains lazy; inspect its fixed eight panel declarations.
      var count = 0;
      void visit(Widget widget) {
        if (widget.key case final ValueKey<String> key
            when key.value.startsWith('performance-case-')) {
          count++;
        }
        if (widget is SingleChildRenderObjectWidget && widget.child != null) {
          visit(widget.child!);
        }
        if (widget is SfPanel) visit(widget.child);
        if (widget is MultiChildRenderObjectWidget) {
          for (final child in widget.children) {
            visit(child);
          }
        }
      }

      for (final child in children) {
        visit(child);
      }
      expect(count, 8);
      expect(source.store.chatLog, isEmpty);
      expect(source.store.history, isEmpty);
      recorder.stop();
    },
  );

  testWidgets('disabled recorder omits the internal panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PerformanceLabPage(
          service: PerformanceReportService(
            recorder: FrameRecorder(enabled: false),
          ),
        ),
      ),
    );
    expect(find.text('Raster 对照采样'), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
  });

  testWidgets('system remove animations blocks the starfield comparison', (
    tester,
  ) async {
    final source = services();
    final recorder = FrameRecorder(enabled: true);
    await tester.pumpWidget(
      AppScope(
        services: source,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: PerformanceLabPage(
            service: PerformanceReportService(recorder: recorder),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('performance-case-glass_on_stars_on-longChatScroll'),
      ),
    );
    await tester.pump();
    expect(find.byType(ChatHomePage), findsNothing);
    expect(recorder.snapshot()['cases'], isEmpty);
    // The explanation is after the eight cells; inspect the declared widgets
    // without forcing the entire settings list onscreen.
    final list = tester.widget<ListView>(find.byType(ListView));
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    expect(
      children.whereType<Text>().any(
        (text) => text.data?.contains('系统“移除动画”已开启') == true,
      ),
      isTrue,
    );
  });

  testWidgets(
    'backgrounding during tail delivery invalidates the completed cell',
    (tester) async {
      final source = services();
      final fixture = PerformanceFixture.create(
        library: source.library,
        scenario: FrameScenario.longChatScroll,
        starfield: false,
      );
      final recorder = FrameRecorder(enabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: PerformanceCaseRunner(
            source: source,
            fixture: fixture,
            recorder: recorder,
            variant: 'glass_on_stars_off',
            scenario: FrameScenario.longChatScroll,
            sampleDuration: const Duration(milliseconds: 100),
            tailDelay: const Duration(seconds: 5),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();
      const id = 'glass_on_stars_off__longChatScroll';
      expect(recorder.snapshot()['currentCaseId'], id);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(recorder.snapshot()['currentCaseId'], isNull);
      Map cell() => (recorder.snapshot()['cases'] as Map)[id] as Map;
      expect(cell()['completed'], isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(cell()['completed'], isFalse);
      expect(cell()['comparisonReady'], isFalse);
      await tester.pumpWidget(const SizedBox());
      recorder.stop();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'script uses real ChatHomePage and isolated controller without video',
    (tester) async {
      tall(tester);
      final source = services();
      final originalChat = List<Map<String, dynamic>>.of(source.store.chatLog);
      final fixture = PerformanceFixture.create(
        library: source.library,
        scenario: FrameScenario.planCardScroll,
        starfield: false,
      );
      final recorder = FrameRecorder(enabled: true);
      await tester.pumpWidget(
        MaterialApp(
          home: PerformanceCaseRunner(
            source: source,
            fixture: fixture,
            recorder: recorder,
            variant: 'glass_on_stars_off',
            scenario: FrameScenario.planCardScroll,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();
      final chat = tester.widget<ChatHomePage>(find.byType(ChatHomePage));
      expect(identical(chat.controller, fixture.controller), isTrue);
      expect(chat.scrollController, isNotNull);
      expect(identical(fixture.store, source.store), isFalse);
      expect(find.byType(PlanCard), findsWidgets);
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(find.text('测试会话 · 计划卡滑动 · 72 条'), findsOneWidget);
      expect(source.store.chatLog, originalChat);
      final current = recorder.snapshot()['currentCaseId'];
      expect(current, 'glass_on_stars_off__planCardScroll');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      final cases = recorder.snapshot()['cases'] as Map;
      expect((cases[current] as Map)['completed'], isFalse);
      expect((cases[current] as Map)['comparisonReady'], isFalse);
      expect(source.store.chatLog, originalChat);
      recorder.stop();
    },
  );

  testWidgets('injected scroll controller stays owned by its caller', (
    tester,
  ) async {
    final source = services();
    final fixture = PerformanceFixture.create(
      library: source.library,
      scenario: FrameScenario.longChatScroll,
      starfield: false,
    );
    final scroll = ScrollController();
    await tester.pumpWidget(
      AppScope(
        services: source,
        child: MaterialApp(
          home: ChatHomePage(
            controller: fixture.controller,
            scrollController: scroll,
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    void listener() {}
    // ChangeNotifier throws in debug if ChatHomePage disposed this controller.
    scroll.addListener(listener);
    scroll.removeListener(listener);
    scroll.dispose();
    fixture.dispose();
  });
}
