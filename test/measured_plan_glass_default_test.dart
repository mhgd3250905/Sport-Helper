import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/diagnostics/performance_lab.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/ui/chat/action_card.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/chat/chat_widgets.dart';
import 'package:smartfit/ui/chat/plan_card.dart';
import 'package:smartfit/ui/chat/validated_plan_card.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:smartfit/ui/theme/fixed_glass_policy.dart';
import 'package:smartfit/ui/theme/glass.dart';
import 'package:smartfit/ui/theme/tokens.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'app_flow_test.dart' show services, tall;
import 'support.dart';

const _suggestions = ['短一点', '换一套'];
const _plan = TrainingPlan(
  id: 'measured-plan-default',
  source: 'template',
  title: '轻松提踵',
  summary: '保持动作平稳。',
  goal: 'fullbody',
  scene: 'home',
  equipment: [],
  level: 1,
  targetMinutes: 10,
  blocks: [
    PlanBlock(
      id: 'main',
      name: '主训练',
      type: BlockType.main,
      rounds: 1,
      restBetweenRoundsSeconds: 0,
      items: [
        PlanItem(
          exerciseId: 'h-calf-raise',
          mode: DoseMode.reps,
          sets: 1,
          reps: 10,
          perSide: false,
          restSeconds: 10,
        ),
      ],
    ),
  ],
);

class _ReplyEngine implements ChatEngine {
  BotMessage next = const BotMessage('保持自然呼吸。');
  @override
  String get id => 'measured-glass-default-test';
  @override
  Future<ChatReply> reply(String text, ChatState state) async =>
      ChatReply(messages: [next], state: state, suggestions: _suggestions);
}

Future<(AppServices, ChatController, _ReplyEngine)> _conversation({
  List<ChatMessage> messages = const [],
}) async {
  final app = services();
  await app.store.acceptSafety(blocked: false);
  final engine = _ReplyEngine();
  final chat = ChatController(
    engine: engine,
    store: app.store,
    replyDelay: Duration.zero,
  )..start();
  chat.messages
    ..clear()
    ..addAll(messages);
  chat.suggestions = _suggestions;
  addTearDown(chat.dispose);
  return (app, chat, engine);
}

Future<void> _show(
  WidgetTester tester,
  AppServices app,
  ChatController chat,
  SfPalette palette, {
  SfFixedGlassPolicy? override,
  bool overridePlanContext = true,
}) async {
  Widget page = ChatHomePage(controller: chat);
  if (override != null) {
    page = SfFixedGlassScope(
      isPlanContext: overridePlanContext,
      policy: override,
      child: page,
    );
  }
  await tester.pumpWidget(
    AppScope(
      services: app,
      child: MaterialApp(theme: buildTheme(palette), home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inside(Type parent, Type child) =>
    find.descendant(of: find.byType(parent), matching: find.byType(child));

void _expectControls(WidgetTester tester, {bool staticSuggestions = true}) {
  final input = _inside(ChatInputBar, GlassContainer);
  expect(input, findsOneWidget);
  final material = tester.widget<GlassContainer>(input).settings!;
  expect(material.blur, SfGlass.standardMaterial.blur);
  expect(material.saturation, SfGlass.standardMaterial.saturation);
  expect(_inside(ChatInputBar, BackdropFilter), findsNWidgets(2));
  expect(
    _inside(SuggestionStrip, GlassContainer),
    staticSuggestions ? findsNothing : findsWidgets,
  );
  expect(
    _inside(SuggestionStrip, BackdropFilter),
    staticSuggestions ? findsNothing : findsWidgets,
  );
  expect(
    _inside(SuggestionStrip, SfStaticGlassFace),
    staticSuggestions ? findsWidgets : findsNothing,
  );
  expect(tester.takeException(), isNull);
}

ChatMessage _message({
  TrainingPlan? plan,
  coach.ValidatedPlan? validated,
  coach.ValidatedActions? actions,
  bool greeting = false,
}) => ChatMessage(
  id: 'measured-glass-message',
  role: ChatRole.assistant,
  at: DateTime(2026, 10, 23, 9, 41),
  text: '按自己的节奏练习。',
  plan: plan,
  validatedPlan: validated,
  actions: actions,
  greeting: greeting,
);

void main() {
  final catalog = const coach.DrillPackAdapter().build(
    version: 'measured-glass-default-test',
    packs: {for (final pack in loadPacksSync().exercises) pack.id: pack.json},
  );
  final gate = coach.ToolGate(
    catalog: catalog,
    profile: coach.CoachProfile.fromJson(
      jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
    ),
  );

  setUp(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = GlassQuality.minimal;
  });
  tearDown(() {
    PerformanceLab.instance.resetOverrides();
    SfGlass.qualityOverride = null;
  });

  test('approved chat policy changes only the suggestion material', () {
    expect(SfFixedGlassPolicy.chat.suggestions, isFalse);
    expect(SfFixedGlassPolicy.planCards, SfFixedGlassPolicy.chat);
    expect(SfFixedGlassPolicy.chat.inputBlur, isNull);
    expect(
      SfFixedGlassPolicy.chat.copyWith(suggestions: true),
      SfFixedGlassPolicy.baseline,
    );
  });

  test('input blur follow-up is explicit and preserves legacy metadata', () {
    final policy = SfFixedGlassPolicy.chat.copyWith(inputBlur: 1.2);
    expect(SfFixedGlassPolicy.chat.toJson().containsKey('inputBlur'), isFalse);
    expect(policy.toJson()['inputBlur'], 1.2);
    expect(policy.key, isNot(SfFixedGlassPolicy.chat.key));
    expect(
      policy,
      const SfFixedGlassPolicy(suggestions: false, inputBlur: 1.2),
    );
    expect(policy.copyWith(), policy);
    expect(() => SfFixedGlassPolicy(inputBlur: .6), throwsAssertionError);
    expect(
      SfFixedGlassPolicy.forConfiguration('chat_baseline'),
      SfFixedGlassPolicy.baseline,
    );
    expect(
      SfFixedGlassPolicy.forConfiguration('chat_suggestions_static'),
      SfFixedGlassPolicy.chat,
    );
    expect(
      SfFixedGlassPolicy.forConfiguration(
        'chat_suggestions_static_input_blur_1_2',
      ),
      policy,
    );
    for (final id in [
      'chat_baseline',
      'chat_suggestions_static',
      'chat_suggestions_static_input_blur_1_2',
      'custom_chat',
    ]) {
      expect(SfFixedGlassPolicy.isChatConfiguration(id), isTrue);
      expect(SfFixedGlassPolicy.experimentIds, contains(id));
    }
    for (final id in ['baseline', 'suggestions_static', 'custom_plan', '']) {
      expect(SfFixedGlassPolicy.isChatConfiguration(id), isFalse);
    }
  });

  for (final palette in [SfPalette.light, SfPalette.dark]) {
    testWidgets(
      'ordinary ${palette.brightness} chat stays static as plan context changes',
      (tester) async {
        tall(tester);
        final previous = SfColors.palette;
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = previous);
        final (app, chat, engine) = await _conversation(messages: [_message()]);
        await _show(tester, app, chat, palette);
        _expectControls(tester);
        expect(
          SfFixedGlassScope.maybeOf(
            tester.element(find.byType(ChatInputBar)),
          )!.isPlanContext,
          isFalse,
        );

        // Exercise the existing controller notifications, not a benchmark scope.
        engine.next = const BotMessage('安排好了。', plan: _plan);
        await chat.send('给我一个计划');
        await tester.pumpAndSettle();
        expect(find.byType(PlanCard), findsOneWidget);
        _expectControls(tester);
        expect(
          SfFixedGlassScope.maybeOf(
            tester.element(find.byType(ChatInputBar)),
          )!.isPlanContext,
          isTrue,
        );

        await chat.newConversation();
        await tester.pumpAndSettle();
        expect(find.byType(PlanCard), findsNothing);
        _expectControls(tester);
        expect(
          SfFixedGlassScope.maybeOf(
            tester.element(find.byType(ChatInputBar)),
          )!.isPlanContext,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '${palette.brightness} plan defaults preserve control geometry and overrides',
      (tester) async {
        tall(tester);
        final previous = SfColors.palette;
        SfColors.palette = palette;
        addTearDown(() => SfColors.palette = previous);
        final (app, chat, _) = await _conversation(
          messages: [_message(plan: _plan)],
        );
        await _show(tester, app, chat, palette);
        _expectControls(tester);
        final input = tester.getRect(find.byType(ChatInputBar));
        final suggestions = tester.getRect(find.byType(SuggestionStrip));

        await _show(
          tester,
          app,
          chat,
          palette,
          override: SfFixedGlassPolicy.baseline,
        );
        _expectControls(tester, staticSuggestions: false);
        expect(tester.getRect(find.byType(ChatInputBar)), input);
        expect(tester.getRect(find.byType(SuggestionStrip)), suggestions);

        await _show(
          tester,
          app,
          chat,
          palette,
          override: const SfFixedGlassPolicy(input: false, suggestions: false),
        );
        expect(_inside(ChatInputBar, GlassContainer), findsNothing);
        expect(_inside(SuggestionStrip, GlassContainer), findsNothing);
        expect(tester.getRect(find.byType(ChatInputBar)), input);
        expect(tester.getRect(find.byType(SuggestionStrip)), suggestions);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('validated AI plan selects the same measured default', (
    tester,
  ) async {
    tall(tester);
    final validated = gate.admitTemplate(
      const coach.PlanCodec().decode(_plan.toJson()),
    )!;
    final (app, chat, _) = await _conversation(
      messages: [_message(validated: validated)],
    );
    await _show(tester, app, chat, SfColors.palette);
    expect(find.byType(ValidatedPlanCard), findsOneWidget);
    _expectControls(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('actions alone also use static chat suggestions', (tester) async {
    tall(tester);
    final actions = gate.check('', [
      coach.LlmToolCall(
        id: 'actions',
        name: 'show_actions',
        arguments: jsonEncode({
          'items': [
            {'actionId': 'h-wall-angel'},
          ],
        }),
      ),
    ]).actions!;
    final (app, chat, _) = await _conversation(
      messages: [_message(actions: actions)],
    );
    await _show(tester, app, chat, SfColors.palette);
    expect(find.byType(ActionCard), findsOneWidget);
    expect(find.byType(PlanCard), findsNothing);
    _expectControls(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'hidden or unvalidated plan payloads do not change chat material',
    (tester) async {
      tall(tester);
      final rawAi = TrainingPlan.fromJson({..._plan.toJson(), 'source': 'ai'});
      for (final message in [
        _message(plan: _plan, greeting: true),
        _message(plan: rawAi),
      ]) {
        final (app, chat, _) = await _conversation(messages: [message]);
        await _show(tester, app, chat, SfColors.palette);
        expect(find.byType(PlanCard), findsNothing);
        _expectControls(tester);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
