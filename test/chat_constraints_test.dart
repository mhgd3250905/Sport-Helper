import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/rule_chat_engine.dart';
import 'package:smartfit/data/app_store.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/saved_plan.dart';
import 'package:smartfit/domain/scenario.dart';

import 'app_flow_test.dart' show MemoryStorage;
import 'support.dart';

void main() {
  final lib = loadLibrary();
  final templates = TemplatePlanGenerator(lib: lib, catalog: loadCatalog());
  final engine = RuleChatEngine(lib: lib, templates: templates);

  for (final text in [
    '膝盖不太好，在家20分钟练臀腿，徒手',
    '腰不太好，在家20分钟练核心，徒手',
    '肩不太好，在家20分钟全身力量，有哑铃',
    '手腕不太好，在家20分钟全身力量，徒手',
  ]) {
    test('saved recall and harder edits preserve protection: $text', () async {
      final initial = await engine.reply(text, const ChatState());
      final p = initial.state.plan!;
      final request = initial.state.request!;
      expect(p.avoid, request.avoid);
      final saved = SavedPlan(
        id: 'saved',
        name: '保护部位',
        plan: p,
        savedAt: DateTime(2026),
      );
      final restored = SavedPlan.fromJson(
        saved.toJson().cast<String, dynamic>(),
      );
      final recalled = await engine.reply(
        '@saved:saved',
        ChatState(saved: [restored]),
      );
      expect(recalled.state.request!.avoid, request.avoid);
      final harder = await engine.reply('难一点', recalled.state);
      final next = harder.state.plan!;
      expect(next.level, p.level + 1);
      expect(next.avoid, request.avoid);
      expect(PlanValidator(lib).validate(next, request), isEmpty);
    });
  }

  test(
    'retiming, replacing and last-plan persistence retain body-part protection',
    () async {
      final initial = await engine.reply(
        '膝盖不太好，在家20分钟练臀腿，徒手',
        const ChatState(),
      );
      final original = initial.state.plan!;
      for (final edit in ['再短一点', '换掉第2个']) {
        final reply = await engine.reply(edit, initial.state);
        final edited = reply.state.plan!;
        expect(edited.id, isNot(original.id));
        expect(edited.avoid, original.avoid);
      }
      final mem = MemoryStorage();
      final store = AppStore(mem);
      await store.rememberPlan(original);
      final loaded = AppStore(mem);
      await loaded.load();
      final recalled = await engine.reply(
        '上次那个',
        ChatState(lastPlan: loaded.lastPlan),
      );
      expect(recalled.state.request!.avoid, original.avoid);
      final harder = await engine.reply('难一点', recalled.state);
      expect(
        PlanValidator(lib).validate(harder.state.plan!, initial.state.request),
        isEmpty,
      );
    },
  );

  test(
    'validator retains plan protection with no request or a less restrictive request',
    () async {
      final generated = await templates.generate(
        const ScenarioRequest(templateId: 'glutes-legs'),
      );
      // A stored plan may only be given its own persisted restrictions.
      final protected = TrainingPlan.fromJson({
        ...generated.plan!.toJson(),
        'avoid': ['膝'],
      });
      expect(PlanValidator(lib).validate(protected), isNotEmpty);
      expect(
        PlanValidator(lib).validate(protected, const ScenarioRequest()),
        isNotEmpty,
      );
      final legacy = TrainingPlan.fromJson(generated.plan!.toJson());
      expect(legacy.avoid, isEmpty);
    },
  );
}
