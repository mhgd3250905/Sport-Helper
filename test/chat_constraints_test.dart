import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/plan.dart';
import 'package:smartfit/domain/plan_generator.dart';
import 'package:smartfit/domain/plan_validator.dart';
import 'package:smartfit/domain/scenario.dart';

import 'support.dart';

void main() {
  final lib = loadLibrary();
  final templates = TemplatePlanGenerator(lib: lib, catalog: loadCatalog());

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
