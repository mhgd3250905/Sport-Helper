import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/domain/scenario.dart';

import 'app_flow_test.dart' show services;

void main() {
  test(
    'every bundled template generates a valid plan on the SDK library',
    () async {
      final s = services();
      for (final template in s.catalog.templates) {
        final result = await s.generator.generate(
          ScenarioRequest(templateId: template.id),
        );
        expect(result.issues, isEmpty, reason: template.id);
        expect(result.plan, isNotNull, reason: template.id);
        // perSide follows the SDK definition, not the bundled template.
        for (final item in result.plan!.items) {
          expect(
            item.perSide,
            s.library[item.exerciseId].unilateral,
            reason: '${template.id}/${item.exerciseId}',
          );
        }
      }
    },
  );
}
