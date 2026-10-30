import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/core/storage/local_state_storage.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/scenario.dart';
import 'package:smartfit/ui/custom_plan_page.dart';
import 'package:smartfit/voice/voice_library.dart';
import 'package:smartfit/voice/voice_queue.dart';

import 'support.dart';
import 'app_flow_test.dart' show widgetFixtureStateEncoder;

class _MemoryStorage implements LocalStateStorage {
  final _data = <String, String>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;
}

void main() {
  const matcher = DescriptionMatcher();

  test('built-in discomfort descriptions protect the affected part', () {
    for (final (text, part) in [
      ('膝盖不太好，想练练臀腿', '膝'),
      ('在家 15 分钟，没有器械，想练核心，腰不太好', '腰'),
      ('睡前放松一下，腰有点酸', '腰'),
      ('手腕有点胀', '手腕'),
    ]) {
      expect(
        matcher.apply(text, const ScenarioRequest()).avoid,
        contains(part),
        reason: text,
      );
    }
    expect(matcher.apply('想练核心和臀腿', const ScenarioRequest()).avoid, isEmpty);
    expect(
      matcher.apply('想放松肩颈', const ScenarioRequest(goal: 'core')).goal,
      'core',
    );
  });

  Future<AppServices> showHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final services = AppServices(
      library: loadLibrary(),
      catalog: loadCatalog(),
      store: AppStore(
        _MemoryStorage(),
        stateEncoder: widgetFixtureStateEncoder,
      ),
      voiceLibrary: VoiceLibrary.empty,
      voiceOutput: const MutedVoiceOutput(),
    );
    await services.store.acceptSafety(blocked: false);
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CustomPlanPage()),
      ),
    );
    await tester.pumpAndSettle();
    return services;
  }

  testWidgets('editing an example recalculates its inferred goal', (
    tester,
  ) async {
    final services = await showHome(tester);
    await tester.scrollUntilVisible(
      find.text('跑步前热身'),
      300,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    await tester.tap(find.text('跑步前热身'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('prompt')), '想练核心15分钟');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(services.store.lastPlan?.goal, 'core');
    expect(services.store.lastPlan?.targetMinutes, 15);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a manual goal still takes priority over an example', (
    tester,
  ) async {
    final services = await showHome(tester);
    final goal = find.widgetWithText(SfChoiceChip, '核心腰腹');
    await tester.ensureVisible(goal);
    await tester.tap(goal);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('跑步前热身'),
      300,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    await tester.tap(find.text('跑步前热身'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('generate')));
    await tester.tap(find.byKey(const ValueKey('generate')));
    await tester.pumpAndSettle();
    expect(services.store.lastPlan?.goal, 'core');
    await tester.pumpWidget(const SizedBox());
  });
}
