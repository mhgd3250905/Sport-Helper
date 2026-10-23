import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_fixture.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/diagnostics/performance_report.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/plan_glass_prewarm.dart';
import 'package:smartfit/ui/exercise_video.dart';
import 'package:smartfit/ui/fixed_glass_lab_page.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/ui/theme/fixed_glass_policy.dart';
import 'package:smartfit/ui/theme/glass.dart';

import 'app_flow_test.dart' show services, tall;

class _VerifiedPhone implements PerformanceReportPlatform {
  @override
  Future<Map<String, Object?>> deviceInfo() async => {
    'renderer': 'impeller',
    'rendererBackend': 'vulkan',
    'rendererVerified': true,
    'rendererSource': 'test_engine_probe',
    'refreshRateHz': 120.0,
    'model': 'Test phone',
    'osVersion': '16',
    'isEmulator': true,
  };

  @override
  Future<void> share({
    required String filename,
    required String contents,
  }) async {}
}

List<Widget> _declared(WidgetTester tester) =>
    (tester.widget<ListView>(find.byType(ListView)).childrenDelegate
            as SliverChildListDelegate)
        .children;

void main() {
  setUp(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = GlassQuality.minimal;
  });
  tearDown(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = null;
  });

  testWidgets('disabled recorder omits the fixed-glass experiment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FixedGlassLabPage(
          service: PerformanceReportService(
            recorder: FrameRecorder(enabled: false),
          ),
        ),
      ),
    );
    expect(find.byType(Scaffold), findsNothing);
  });

  testWidgets(
    'prewarm scene paints real card and fixed controls without video',
    (tester) async {
      tall(tester);
      final source = services();
      final fixture = PerformanceFixture.create(
        library: source.library,
        scenario: FrameScenario.planCardScroll,
        starfield: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 390,
              height: 480,
              child: SfFixedGlassScope(
                isPlanContext: true,
                policy: SfFixedGlassPolicy.baseline,
                child: PlanGlassPrewarmScene(
                  library: source.library,
                  plan: fixture.controller.messages
                      .firstWhere((m) => m.plan != null)
                      .plan!,
                  suggestions: fixture.controller.suggestions,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.byType(ChatInputBar), findsOneWidget);
      expect(find.byType(SuggestionStrip), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.byType(ExerciseVideo), findsNothing);
      expect(source.store.chatLog, isEmpty);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    },
  );

  testWidgets('prewarm never reports success when the fixture has no plan', (
    tester,
  ) async {
    final source = services();
    final fixture = PerformanceFixture.create(
      library: source.library,
      scenario: FrameScenario.longChatScroll,
      starfield: false,
    );
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    final result = await PlanGlassPrewarmer.prepare(
      context: pageContext,
      fixture: fixture,
      library: source.library,
      policy: SfFixedGlassPolicy.baseline,
    );
    expect(result.status, 'unsupported');
    expect(result.logicalWidth, isNull);
    expect(find.byType(PlanGlassPrewarmScene), findsNothing);
    fixture.dispose();
  });

  testWidgets(
    'nine real cells; absent bars are N/A and cannot be toggled',
    (tester) async {
      final source = services();
      final recorder = FrameRecorder(enabled: true);
      await tester.pumpWidget(
        AppScope(
          services: source,
          child: MaterialApp(
            home: FixedGlassLabPage(
              service: PerformanceReportService(recorder: recorder),
            ),
          ),
        ),
      );
      final declared = _declared(tester);
      final switches = declared.whereType<SwitchListTile>().toList();
      expect(switches, hasLength(6));
      expect(switches[0].onChanged, isNull);
      expect(switches[1].onChanged, isNull);
      expect(switches.skip(2).every((tile) => tile.onChanged != null), isTrue);
      final keys = <String>[];
      void visit(Widget widget) {
        if (widget.key case final ValueKey<String> key
            when key.value.startsWith('fixed-glass-case-')) {
          keys.add(key.value);
        }
        if (widget is SfPanel) visit(widget.child);
        if (widget is SingleChildRenderObjectWidget && widget.child != null) {
          visit(widget.child!);
        }
        if (widget is MultiChildRenderObjectWidget) {
          for (final child in widget.children) {
            visit(child);
          }
        }
      }

      for (final widget in declared) {
        visit(widget);
      }
      expect(keys, hasLength(10)); // nine presets plus one bounded manual cell.
      expect(keys.where((key) => key.contains('top_bar')), isEmpty);
      expect(keys.where((key) => key.contains('bottom_bar')), isEmpty);
      expect(source.store.chatLog, isEmpty);
      expect(recorder.snapshot()['fixedGlassCases'], isEmpty);
      expect(PerformanceLab.instance.freezeAdaptation, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(PerformanceLab.instance.freezeAdaptation, isFalse);
      recorder.stop();
    },
    skip: !PerformanceLab.buildEnabled,
  );

  testWidgets(
    'target route waits for prewarm completion and records failure',
    (tester) async {
      tall(tester);
      final source = services();
      source.store.starfield = false;
      final recorder = FrameRecorder(enabled: true);
      final service = PerformanceReportService(
        recorder: recorder,
        platform: _VerifiedPhone(),
      );
      final warm = Completer<PlanGlassPrewarmResult>();
      var requested = false;
      await tester.pumpWidget(
        AppScope(
          services: source,
          child: MaterialApp(
            home: FixedGlassLabPage(
              service: service,
              prewarm:
                  ({
                    required context,
                    required fixture,
                    required library,
                    required policy,
                  }) {
                    requested = true;
                    expect(find.byType(ChatHomePage), findsNothing);
                    expect(fixture.controller.messages, hasLength(72));
                    expect(policy, SfFixedGlassPolicy.baseline);
                    return warm.future;
                  },
            ),
          ),
        ),
      );
      final button = find.byKey(
        const ValueKey('fixed-glass-case-baseline_prewarmed'),
      );
      await tester.scrollUntilVisible(
        button,
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pump();
      expect(requested, isTrue);
      expect(find.byType(ChatHomePage), findsNothing);
      expect(PerformanceLab.instance.prewarmStatus, 'pending');
      expect(recorder.snapshot()['fixedGlassCases'], isEmpty);
      warm.complete(const PlanGlassPrewarmResult('failed', 12));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatHomePage), findsOneWidget);
      expect(PerformanceLab.instance.prewarmStatus, 'failed');
      expect(PerformanceLab.instance.prewarmDurationMs, 12);
      expect(PerformanceLab.instance.starfieldFor(false), isFalse);
      expect(PerformanceLab.instance.scrollingGlassEnabled, isFalse);
      expect(source.store.chatLog, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      recorder.stop();
    },
    skip: !PerformanceLab.buildEnabled,
  );

  testWidgets(
    'input-only follow-up is available only in light without replacing presets',
    (tester) async {
      final source = services();
      final recorder = FrameRecorder(enabled: true);
      final service = PerformanceReportService(recorder: recorder);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          AppScope(
            services: source,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              themeAnimationDuration: Duration.zero,
              home: FixedGlassLabPage(service: service),
            ),
          ),
        );
        final buttons = _declared(tester).whereType<SfPrimaryButton>();
        final followUp = buttons.singleWhere(
          (button) =>
              button.key == const ValueKey('fixed-glass-chat-input-1-2'),
        );
        expect(followUp.onPressed != null, brightness == Brightness.light);
        final currentChat = buttons.singleWhere(
          (button) => button.key == const ValueKey('fixed-glass-default-chat'),
        );
        expect(currentChat.onPressed, isNotNull);
        expect(fixedGlassConfigurations, hasLength(9));
        expect(fixedGlassConfigurations['chat_baseline'], contains('真玻璃'));
        expect(
          fixedGlassConfigurations.containsKey(
            'chat_suggestions_static_input_blur_1_2',
          ),
          isFalse,
        );
      }
      expect(recorder.snapshot()['fixedGlassCases'], isEmpty);
      expect(source.store.chatLog, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      recorder.stop();
    },
    skip: !PerformanceLab.buildEnabled,
  );

  testWidgets(
    'current chat button samples the real default without an ancestor override',
    (tester) async {
      tall(tester);
      final source = services();
      source.store.appearance = 'light';
      final recorder = FrameRecorder(enabled: true);
      final service = PerformanceReportService(
        recorder: recorder,
        platform: _VerifiedPhone(),
      );
      await tester.pumpWidget(
        AppScope(
          services: source,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: FixedGlassLabPage(service: service),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('fixed-glass-default-chat'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatHomePage), findsOneWidget);
      final page = tester.element(find.byType(ChatHomePage));
      expect(SfFixedGlassScope.maybeOf(page), isNull);
      final input = tester.element(find.byType(ChatInputBar));
      expect(SfFixedGlassScope.maybeOf(input)?.policy, SfFixedGlassPolicy.chat);
      expect(
        PerformanceLab.instance.fixedGlassConfigurationId,
        'chat_suggestions_static',
      );
      expect(PerformanceLab.instance.fixedGlassPolicy, SfFixedGlassPolicy.chat);
      expect(PerformanceLab.instance.prewarmEnabled, isFalse);
      expect(PerformanceLab.instance.prewarmStatus, 'disabled');
      expect(PerformanceLab.instance.starfieldFor(false), isFalse);
      expect(source.store.chatLog, isEmpty);
      final entries = recorder.snapshot()['fixedGlassEntries'] as Map;
      expect(entries.keys, ['chat_suggestions_static']);
      expect(
        (entries['chat_suggestions_static'] as Map)['entryTargetPage'],
        'performance_chat',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      recorder.stop();
    },
    skip: !PerformanceLab.buildEnabled,
  );
}
