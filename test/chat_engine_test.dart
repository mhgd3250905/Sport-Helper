// ChatEngine (rules): slot parsing, follow-up questions, plan edits.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/chat/slot_parser.dart';
import 'package:smartfit/domain/exercise.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/domain/session.dart';

import 'support.dart';

void main() {
  final lib = loadLibrary();
  final templates = TemplatePlanGenerator(lib: lib, catalog: loadCatalog());
  final engine = RuleChatEngine(lib: lib, templates: templates);
  const parser = SlotParser();

  /// Runs [lines] through the engine; returns every reply.
  Future<(List<ChatReply>, ChatState)> talk(List<String> lines, [ChatState s = const ChatState()]) async {
    final out = <ChatReply>[];
    for (final l in lines) {
      final r = await engine.reply(l, s);
      out.add(r);
      s = r.state;
    }
    return (out, s);
  }

  TrainingPlan? planOf(ChatReply r) => r.messages.map((m) => m.plan).whereType<TrainingPlan>().firstOrNull;
  double secs(TrainingPlan p) => SessionBuilder(lib).planSeconds(p);

  group('slot parser', () {
    test('minutes in digits, Chinese numerals and phrases', () {
      expect(parser.parseMinutes('练 20 分钟'), 20);
      expect(parser.parseMinutes('十五分钟就行'), 15);
      expect(parser.parseMinutes('半小时'), 30);
      expect(parser.parseMinutes('一刻钟'), 15);
      expect(parser.parseMinutes('1小时'), 45);
      expect(parser.parseMinutes('3 分钟'), 5);
      expect(parser.parse('10', asked: 'minutes').minutes, 10);
      expect(parser.parse('10').minutes, isNull);
    });

    test('gear: said, bare hands, short answers', () {
      expect(parser.parse('家里有哑铃').equipment, {Equipment.dumbbell});
      expect(parser.parse('有弹力带和哑铃').equipment, {Equipment.band, Equipment.dumbbell});
      expect(parser.parse('徒手就行').equipment, isEmpty);
      expect(parser.parse('都有', asked: 'equipment').equipment, {Equipment.band, Equipment.dumbbell});
      expect(parser.parse('没有', asked: 'equipment').equipment, isEmpty);
      expect(parser.parse('想练核心').equipment, isNull);
      // Gear alone is not a goal.
      expect(parser.parse('有哑铃').goal, isNull);
    });

    test('scene, goal, focus, level, parts to protect', () {
      final a = parser.parse('在办公室午休 10 分钟，肩颈很僵');
      expect(a.scene, 'office');
      expect(a.minutes, 10);
      expect(a.goal, 'relax');
      expect(a.focus, contains('肩颈'));
      final b = parser.parse('膝盖不太好，想练练臀腿');
      expect(b.avoid, contains('膝'));
      expect(b.goal, 'strength');
      expect(parser.parse('新手，想练核心马甲线').level, 1);
      expect(parser.parse('力量塑形').goal, 'strength');
      expect(parser.parse('核心腰腹').goal, 'core');
      expect(parser.parse('今天天气怎么样').isEmpty, isTrue);
    });

    test('plan edits', () {
      const names = ['四足猫牛式', '死虫式', '卷腹'];
      EditKind? kind(String t) => parser.parseEdit(t, names)?.kind;
      expect(kind('再短一点'), EditKind.shorter);
      expect(kind('能长一点吗'), EditKind.longer);
      expect(kind('简单点'), EditKind.easier);
      expect(kind('太难了'), EditKind.easier);
      expect(kind('难一点'), EditKind.harder);
      expect(kind('太简单了'), EditKind.harder);
      expect(kind('换一套'), EditKind.another);
      expect(parser.parseEdit('换掉第3个', names)?.index, 3);
      expect(parser.parseEdit('第二个不想做', names)?.index, 2);
      expect(parser.parseEdit('不想做死虫式', names)?.name, '死虫式');
      expect(parser.parseEdit('换一个', names)?.index, isNull);
      expect(parser.parseEdit('改成 20 分钟', names)?.minutes, 20);
      expect(parser.parseEdit('想练核心', names), isNull);
    });
  });

  group('conversation', () {
    test('vague ask → goal → minutes → plan (at most two questions)', () async {
      final (r, s) = await talk(['练一下', '核心腰腹', '15']);
      expect(r[0].messages.single.text, contains('哪方面'));
      expect(r[0].messages.single.options, hasLength(4));
      expect(r[1].messages.single.text, contains('几分钟'));
      final plan = planOf(r[2])!;
      expect(plan.templateId, 'core');
      expect(r[2].messages.first.text, contains('徒手'));
      expect(s.pending, isNull);
      expect(PlanValidator(lib).validate(plan, s.request), isEmpty);
    });

    test('a full description plans right away', () async {
      final (r, s) = await talk(['在办公室午休 10 分钟，肩颈很僵']);
      expect(planOf(r.single)?.templateId, 'office-relax');
      expect(s.request?.scene, 'office');
      expect(r.single.suggestions, contains('再短一点'));
    });

    test('strength asks about gear; tapping an option answers it', () async {
      final (r, _) = await talk(['在家练 20 分钟力量', '有哑铃']);
      expect(r[0].messages.single.text, contains('哑铃或弹力带'));
      final plan = planOf(r[1])!;
      expect(plan.templateId, 'dumbbell-fullbody');
    });

    test('a different goal while a question is open starts over', () async {
      final (r, s) = await talk(['睡前放松一下', '新手，想练核心马甲线，15 分钟']);
      expect(r[1].messages.single.text, contains('哑铃或弹力带'));
      expect(s.pending?.goal, 'core');
      expect(s.pending?.avoid, isEmpty);
    });

    test('pain words: plan avoids the part and says when to stop', () async {
      final (r, _) = await talk(['膝盖不太好，想练练臀腿，20分钟，徒手']);
      expect(r.single.messages.first.text, contains('膝'));
      final plan = planOf(r.single)!;
      for (final i in plan.items) {
        expect(lib[i.exerciseId].cautions, isNot(contains('膝')));
      }
    });

    test('red-flag symptoms stop instead of planning', () async {
      final (r, _) = await talk(['胸口有点闷']);
      expect(planOf(r.single), isNull);
      expect(r.single.messages.single.text, contains('就医'));
    });

    test('small talk is steered back to training, not answered', () async {
      final (r, _) = await talk(['讲个笑话']);
      expect(planOf(r.single), isNull);
      expect(r.single.messages.single.text, contains('训练'));
      expect(r.single.suggestions, isNotEmpty);
    });

    test('safety "是" blocks plans', () async {
      final (r, _) = await talk(['在家 10 分钟拉伸'], const ChatState(safetyBlocked: true));
      expect(planOf(r.single), isNull);
      expect(r.single.messages.single.options.map((o) => o.value), contains('@library'));
    });
  });

  group('editing the current plan', () {
    late ChatState start;
    late TrainingPlan plan;
    setUp(() async {
      final (r, s) = await talk(['在家 15 分钟练核心，徒手']);
      start = s;
      plan = planOf(r.single)!;
    });

    test('再短一点 / 长一点 change the length', () async {
      final shorter = planOf((await engine.reply('再短一点', start)))!;
      expect(secs(shorter), lessThan(secs(plan) - 30));
      final longer = planOf((await engine.reply('长一点', start)))!;
      expect(secs(longer), greaterThan(secs(plan) + 30));
      expect(shorter.id, isNot(plan.id)); // a new version, saved separately
    });

    test('难一点 raises the level; 简单点 at 入门 says so', () async {
      final r = await engine.reply('难一点', start);
      expect(planOf(r)!.level, 2);
      expect(r.state.request?.level, 2);
      final easier = await engine.reply('简单点', start);
      expect(planOf(easier), isNull);
      expect(easier.messages.single.text, contains('入门'));
    });

    test('换掉第 N 个 swaps that move only', () async {
      final r = await engine.reply('换掉第2个', start);
      final next = planOf(r)!;
      final before = plan.items.toList();
      final after = next.items.toList();
      expect(after[1].exerciseId, isNot(before[1].exerciseId));
      expect(after[1].replacedFrom, before[1].exerciseId);
      for (var i = 0; i < before.length; i++) {
        if (i != 1) expect(after[i].exerciseId, before[i].exerciseId);
      }
      expect(PlanValidator(lib).validate(next, r.state.request), isEmpty);
      final bad = await engine.reply('换掉第99个', start);
      expect(planOf(bad), isNull);
      expect(bad.messages.single.text, contains('一共'));
    });

    test('换一个 asks which one', () async {
      final r = await engine.reply('换一个', start);
      expect(r.messages.single.options.first.value, '换掉第 1 个');
    });

    test('new gear after a card rebuilds that plan', () async {
      final (r, _) = await talk(['在家练 20 分钟力量，徒手', '有哑铃']);
      expect(planOf(r[1])!.templateId, 'dumbbell-fullbody');
      expect(r[1].state.request?.equipment, contains(Equipment.dumbbell));
    });
  });

  group('saved plans in the conversation', () {
    late TrainingPlan core;
    late TrainingPlan office;
    setUp(() async {
      core = planOf((await talk(['在家 15 分钟练核心，徒手'])).$1.single)!;
      office = planOf((await talk(['在办公室午休 10 分钟，肩颈很僵'])).$1.single)!;
    });

    SavedPlan saved(String id, TrainingPlan p, {DateTime? used}) =>
        SavedPlan(id: id, name: p.title, plan: p, savedAt: DateTime(2026, 10, 1), lastUsedAt: used);

    test('上次那个: nothing yet → asks; otherwise the last started plan', () async {
      final none = await engine.reply('上次那个', const ChatState());
      expect(planOf(none), isNull);
      expect(none.messages.single.text, contains('还没有'));

      final r = await engine.reply('来个上次那个', ChatState(lastPlan: office, saved: [saved('a', core)]));
      expect(planOf(r)?.id, office.id);
      expect(r.state.plan?.id, office.id); // edits now apply to it
      final bySaved = await engine.reply('老样子', ChatState(saved: [
        saved('a', core, used: DateTime(2026, 10, 2)),
        saved('b', office, used: DateTime(2026, 10, 5)),
      ]));
      expect(planOf(bySaved)?.id, office.id);
    });

    test('我的计划 lists saved plans as options; tapping one shows its card', () async {
      final empty = await engine.reply('我的计划', const ChatState());
      expect(empty.messages.single.text, contains('还没有保存'));

      final list = [for (var i = 0; i < 5; i++) saved('s$i', i.isEven ? core : office)];
      final r = await engine.reply('看看我的计划', ChatState(saved: list));
      final values = r.messages.single.options.map((o) => o.value).toList();
      expect(values.take(4), everyElement(startsWith('@saved:')));
      expect(values.last, '@drawer');

      final card = await engine.reply('@saved:s1', ChatState(saved: list));
      expect(planOf(card)?.id, office.id);
      final gone = await engine.reply('@saved:nope', ChatState(saved: list));
      expect(planOf(gone), isNull);
    });

    test('a recalled plan is still blocked after a "是" safety answer', () async {
      final r = await engine.reply('上次那个', ChatState(lastPlan: core, safetyBlocked: true));
      expect(planOf(r), isNull);
    });
  });

  group('app intents (§4.2)', () {
    test('library: plain, by category; plan requests and swaps are not library asks', () async {
      for (final t in ['看看动作库', '有哪些动作', '浏览动作库']) {
        final (r, _) = await talk([t]);
        expect(r.single.action, '@library', reason: t);
      }
      final (a, _) = await talk(['有哪些拉伸动作']);
      expect(a.single.action, '@library:stretch');
      final (b, _) = await talk(['力量动作有哪些']);
      expect(b.single.action, '@library:strength');
      final (c, _) = await talk(['看看核心动作']);
      expect(c.single.action, '@library:core');
      final (d, _) = await talk(['睡前拉伸 10 分钟']);
      expect(d.single.action, isNull);
      expect(planOf(d.single), isNotNull);
    });

    test('history: nothing yet; otherwise the last workout, this week and 再来一次', () async {
      final (none, _) = await talk(['上次练了什么']);
      expect(none.single.messages.single.text, contains('还没有训练记录'));
      expect(planOf(none.single), isNull);

      final now = DateTime(2026, 10, 22, 20); // a Thursday
      final core = planOf((await talk(['在家 15 分钟练核心，徒手'])).$1.last)!;
      final s = ChatState(
        now: now,
        lastPlan: core,
        history: [
          WorkoutLog(title: '核心激活', at: DateTime(2026, 10, 21, 19), minutes: 15, completed: 8, total: 8),
          WorkoutLog(title: '肩颈放松', at: DateTime(2026, 10, 19, 12), minutes: 9, completed: 3, total: 6),
          WorkoutLog(title: '更早的', at: DateTime(2026, 10, 12, 12), minutes: 20, completed: 6, total: 6),
        ],
      );
      for (final t in ['上次练了什么', '训练记录', '这周练了多少']) {
        final r = await engine.reply(t, s);
        final m = r.messages.single;
        expect(m.text, contains('昨天的「核心激活」'), reason: t);
        expect(m.text, contains('这周练了 2 次，一共约 24 分钟'), reason: t);
        expect(m.options.single.label, '再来一次');
        expect(m.options.single.value, '上次那个');
      }
      // Blocked by the safety check: no 再来一次.
      final blocked = await engine.reply('训练记录', s.copyWith(safetyBlocked: true));
      expect(blocked.messages.single.options, isEmpty);
    });

    test('appearance, voice and chimes change through the conversation', () async {
      Future<String?> act(String t, [ChatState s = const ChatState()]) async => (await engine.reply(t, s)).action;
      expect(await act('换浅色'), '@appearance:light');
      expect(await act('深色模式'), '@appearance:dark');
      expect(await act('跟随系统'), '@appearance:system');
      final same = await engine.reply('换深色', const ChatState(appearance: 'dark'));
      expect(same.messages.single.text, contains('现在就是深色'));
      expect(await act('关掉语音'), '@voice:off');
      expect(await act('打开语音'), '@voice:on');
      expect(await act('静音'), '@voice:mute');
      expect(await act('打开提示音'), '@chimes:on');
      expect(await act('关掉提示音'), '@chimes:off');
    });

    test('settings, the form, the safety re-check; 深蹲 is still a move', () async {
      Future<String?> act(String t) async => (await engine.reply(t, const ChatState())).action;
      expect(await act('设置'), '@settings');
      expect(await act('关于'), '@settings');
      expect(await act('自己选条件'), '@custom');
      expect(await act('用表单'), '@custom');
      expect(await act('重新做安全确认'), '@safety');
      final (r, _) = await talk(['在家 20 分钟练深蹲']);
      expect(r.single.action, isNull);
    });

    test('你能做什么: a short explanation with four discovery options', () async {
      final r = await engine.reply('你能做什么', const ChatState());
      final m = r.messages.single;
      expect(m.options, hasLength(4));
      expect(m.options.map((o) => o.label), containsAll(['看看动作库', '自己选条件', '换浅色']));
      expect(m.options.first.value, '@library');
    });

    test('not understood: says what it can do and offers discovery chips', () async {
      final (r, _) = await talk(['讲个笑话']);
      expect(r.single.messages.single.text, contains('我只会帮你安排训练'));
      expect(r.single.suggestions, contains('你能做什么'));
    });

    test('discovery chips by state (§4.3)', () {
      final first = discoverySuggestions(returning: false);
      expect(first, hasLength(5));
      expect(first.last, '你能做什么');
      final back = discoverySuggestions(returning: true);
      expect(back.take(2), ['上次那个', '上次练了什么']);
      expect(back, contains('看看动作库'));
      expect(discoverySuggestions(returning: true, blocked: true), isNot(contains('上次那个')));
    });
  });
}
