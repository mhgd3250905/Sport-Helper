import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import 'support/coach_v2_fixtures.dart';

void main() {
  late CoachV2Fixtures fixture;
  setUpAll(() async {
    fixture = await CoachV2Fixtures.load();
  });

  AiChatEngine engine(List<Object> script) {
    final ai = AiChatEngine(
      local: const AppChatActions(),
      catalog: fixture.catalog,
      profile: fixture.profile,
      client: coach.FakeLlmClient(script, latency: Duration.zero),
      enableUserMemory: false,
    );
    addTearDown(ai.dispose);
    return ai;
  }

  test(
    'absolute seven-minute update is taken from SDK sourced parameters',
    () async {
      final ai = engine([
        ...fixture.planTurn(),
        ...fixture.planTurn(
          prefix: 'seven',
          reuse: true,
          minutes: 7,
          minutesQuote: '7分钟',
          goalQuote: null,
          sceneQuote: null,
          equipmentQuote: null,
          operation: 'edit',
          operationQuote: '缩短',
        ),
      ]);
      final first = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
      final second = await ai.reply('缩短到7分钟', first.state);
      final plan = second.messages.single.validatedPlan;
      expect(plan, isNotNull, reason: '${ai.lastResult?.issues}');
      expect(plan!.plan.targetMinutes, 7);
      expect(plan.plan.id, first.messages.single.plan!.id);
      final minutes = ai.agent.sessionState.params['minutes']!;
      expect(
        (minutes.value, minutes.source, minutes.quote, minutes.turn),
        (7, 'user', '7分钟', 2),
      );
    },
  );

  for (final (phrase, value, direction) in [
    ('短一点', 5, 'shorter'),
    ('长一点', 15, 'longer'),
  ]) {
    test(
      'relative "$phrase" records derived value and original source in SDK ledger',
      () async {
        final ai = engine([
          ...fixture.planTurn(),
          ...fixture.planTurn(
            prefix: 'relative',
            reuse: true,
            minutes: null,
            goalQuote: null,
            sceneQuote: null,
            equipmentQuote: null,
            operation: 'edit',
            operationQuote: phrase,
            fields: {
              'minutes': {
                'value': value,
                'source': 'derived',
                'quote': phrase,
                'direction': direction,
              },
            },
          ),
        ]);
        final first = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
        final before = first.messages.single.validatedPlan!.plan;
        final next = await ai.reply(phrase, first.state);
        final plan = next.messages.single.validatedPlan?.plan;
        expect(plan, isNotNull, reason: '${ai.lastResult?.issues}');
        expect(plan!.targetMinutes, value);
        final param = ai.agent.sessionState.params['minutes']!;
        expect((param.source, param.direction), ('derived', direction));
        expect((param.basedOn!.value, param.basedOn!.source), (10, 'user'));
        final duration = const coach.PlanDuration();
        expect(
          duration.estimateSeconds(plan, fixture.catalog),
          direction == 'shorter'
              ? lessThan(duration.estimateSeconds(before, fixture.catalog))
              : greaterThan(duration.estimateSeconds(before, fixture.catalog)),
        );
        expect(next.messages.single.question, isNull);
      },
    );
  }

  test(
    'user can reduce available gear; App does not merge stale equipment back',
    () async {
      final ai = engine([
        ...fixture.planTurn(
          equipmentQuote: '哑铃',
          fields: {
            'equipment': CoachV2Fixtures.sourced(['equip.dumbbell'], '哑铃'),
          },
        ),
        ...fixture.planTurn(
          prefix: 'barehand',
          reuse: true,
          minutes: null,
          goalQuote: null,
          sceneQuote: null,
          equipmentQuote: '徒手',
          operation: 'edit',
          operationQuote: '改成',
        ),
      ]);
      final first = await ai.reply('在家有哑铃10分钟做拉伸', const ChatState());
      expect(
        first.messages.single.plan,
        isNotNull,
        reason: '${ai.lastResult?.issues}',
      );
      expect(ai.agent.sessionState.params['equipment']!.value, [
        'equip.dumbbell',
      ]);
      final next = await ai.reply('改成徒手', first.state);
      expect(
        next.messages.single.plan,
        isNotNull,
        reason: '${ai.lastResult?.issues}',
      );
      expect(ai.agent.sessionState.params['equipment']!.value, isEmpty);
      expect(ai.agent.sessionState.params['equipment']!.quote, '徒手');
      expect(next.messages.single.plan!.equipment, isNot(contains('dumbbell')));
    },
  );

  test(
    'scene update uses new SDK conditions and compliant office actions',
    () async {
      final ai = engine([
        ...fixture.planTurn(),
        ...fixture.planTurn(
          prefix: 'office',
          reuse: true,
          minutes: null,
          goalQuote: null,
          sceneQuote: null,
          equipmentQuote: '徒手',
          fields: {'scene': CoachV2Fixtures.sourced('office', '办公室')},
          ids: const ['o-stand-sidebend', 'o-stand-lunge', 'o-stand-quad'],
          operation: 'edit',
          operationQuote: '改成',
        ),
      ]);
      final first = await ai.reply('在家徒手10分钟做拉伸', const ChatState());
      final next = await ai.reply('改成办公室徒手', first.state);
      expect(
        next.messages.single.plan,
        isNotNull,
        reason: '${ai.lastResult?.issues}',
      );
      expect(next.messages.single.plan!.scene, 'office');
      expect(ai.agent.sessionState.params['scene']!.value, 'office');
      expect(ai.agent.sessionState.params['scene']!.turn, 2);
      expect(
        next.messages.single.plan!.items.map((m) => m.exerciseId).toSet(),
        {'o-stand-sidebend', 'o-stand-lunge', 'o-stand-quad'},
      );
    },
  );

  test('replacement plus explicit duration is one SDK plan version', () async {
    final ai = engine([
      ...fixture.planTurn(minutes: 20, minutesQuote: '20分钟'),
      ...fixture.planTurn(
        prefix: 'replace-ten',
        reuse: true,
        minutes: 10,
        minutesQuote: '10分钟',
        goalQuote: null,
        sceneQuote: null,
        equipmentQuote: null,
        operation: 'replace_all',
        operationQuote: '换一套',
        ids: CoachV2Fixtures.alternativeStretching,
      ),
    ]);
    final first = await ai.reply('在家徒手20分钟做拉伸', const ChatState());
    final next = await ai.reply('换一套，缩短到10分钟', first.state);
    expect(
      next.messages.single.plan,
      isNotNull,
      reason: '${ai.lastResult?.issues}',
    );
    final plan = next.messages.single.plan!;
    expect(plan.targetMinutes, 10);
    expect(plan.id, first.messages.single.plan!.id);
    final oldIds = first.messages.single.plan!.items
        .map((m) => m.exerciseId)
        .toSet();
    final newIds = plan.items.map((m) => m.exerciseId).toSet();
    expect(
      newIds.difference(oldIds).length / newIds.length,
      greaterThanOrEqualTo(.5),
    );
    expect(ai.agent.sessionState.plans[plan.id]!.last.version, 2);
    expect(next.messages.single.question, isNull);
  });
}
