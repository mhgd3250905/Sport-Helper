import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

import '../../../tools/coach/smoke_observation.dart';

coach.LlmToolCall call(String name, Object? arguments) => coach.LlmToolCall(
  id: 'call-test',
  name: name,
  arguments: jsonEncode(arguments),
);

void main() {
  group('safe smoke protocol observations', () {
    test('response retains metrics and IDs without reply or tool text', () {
      final observation = smokeResponseProtocol(
        2,
        coach.LlmResponse(
          content: 'private-content',
          reasoning: 'private-reasoning',
          finishReason: 'tool_calls',
          usage: const coach.TokenUsage(
            promptTokens: 100,
            completionTokens: 20,
            reasoningTokens: 10,
          ),
          toolCalls: [
            call('show_plan', {
              'title': 'private-title',
              'blocks': [
                {
                  'items': [
                    {'exerciseId': 'known-squat', 'note': 'private-note'},
                  ],
                },
              ],
            }),
          ],
        ),
      );
      expect(observation['requestIndex'], 2);
      expect(observation['reasoningPresent'], isTrue);
      expect(observation['reasoningLength'], 'private-reasoning'.length);
      expect(observation['usage'], containsPair('promptTokens', 100));
      expect(observation['finishReason'], 'tool_calls');
      expect((observation['tools'] as List).single, {
        'name': 'show_plan',
        'argumentsJson': true,
        'actionIds': ['known-squat'],
      });
      expect(jsonEncode(observation), isNot(contains('private-')));
    });

    test('failure stores safe SDK diagnostics without exception message', () {
      final observation = smokeErrorProtocol(
        3,
        const coach.LlmException(
          coach.LlmErrorKind.badResponse,
          'private-provider-response',
          usage: coach.TokenUsage(promptTokens: 11, completionTokens: 7),
          responseDiagnostic: coach.LlmResponseDiagnostic(
            subtype: coach.LlmResponseProblem.reasoningOnly,
            statusCode: 200,
            bodyBytes: 400,
            bodySha256: 'test-body-sha256',
            contentLength: 0,
            reasoningLength: 200,
          ),
        ),
      );
      expect(observation['errorKind'], 'badResponse');
      expect(observation['httpStatus'], 200);
      expect(observation['usage'], containsPair('completionTokens', 7));
      expect(
        observation['responseDiagnostic'],
        containsPair('subtype', 'reasoningOnly'),
      );
      expect(jsonEncode(observation), isNot(contains('private-provider')));
    });

    test(
      'transport failure without response diagnostics remains observable',
      () {
        final observation = smokeErrorProtocol(
          4,
          const coach.LlmException(
            coach.LlmErrorKind.timeout,
            'private-timeout',
          ),
        );
        expect(observation['requestIndex'], 4);
        expect(observation['errorKind'], 'timeout');
        expect(observation['responseDiagnostic'], isNull);
        expect(jsonEncode(observation), isNot(contains('private-timeout')));
      },
    );

    test('unrecognised finish tags are replaced by a fixed label', () {
      final observation = smokeResponseProtocol(
        1,
        const coach.LlmResponse(
          content: '',
          finishReason: 'private-finish-tag',
        ),
      );
      expect(observation['finishReason'], 'unknown');
      expect(jsonEncode(observation), isNot(contains('private-finish')));
    });

    test('malformed tool arguments are marked without logging raw JSON', () {
      final summary = smokeToolSummary(
        const coach.LlmToolCall(
          id: 'bad-json',
          name: 'show_actions',
          arguments: '{private-invalid-json',
        ),
      );
      expect(summary, {'name': 'show_actions', 'argumentsJson': false});
    });

    test('show_actions and check_plan proposals retain nested action IDs', () {
      expect(
        smokeToolSummary(
          call('show_actions', {
            'items': [
              {'actionId': 'known-bridge'},
              {'actionId': 'unknown-bridge'},
            ],
          }),
        )['actionIds'],
        ['known-bridge', 'unknown-bridge'],
      );
      expect(
        smokeToolSummary(
          call('check_plan', {
            'plan': {
              'blocks': [
                {
                  'items': [
                    {'exerciseId': 'known-squat'},
                  ],
                },
              ],
            },
          }),
        )['actionIds'],
        ['known-squat'],
      );
    });

    test('memory, paths and unknown tool names are not exported', () {
      for (final tool in ['remember', 'read', 'private-tool-name']) {
        final summary = smokeToolSummary(
          call(tool, {
            'text': 'private-memory',
            'path': 'private-path',
            'exerciseId': 'private-field',
          }),
        );
        expect(summary.containsKey('actionIds'), isFalse);
        expect(jsonEncode(summary), isNot(contains('private-')));
      }
    });

    test('unknown proposal counting excludes preceding turns and errors', () {
      Map<String, Object?> response(int index, String id) =>
          smokeResponseProtocol(
            index,
            coach.LlmResponse(
              content: '',
              toolCalls: [
                call('show_actions', {
                  'items': [
                    {'actionId': id},
                  ],
                }),
              ],
            ),
          );
      final protocols = [
        response(1, 'previous-unknown'),
        response(2, 'current-unknown'),
        smokeErrorProtocol(
          3,
          const coach.LlmException(coach.LlmErrorKind.timeout, 'timeout'),
        ),
        response(4, 'known-bridge'),
      ];
      expect(
        smokeUnknownActionIds(
          protocols,
          afterRequest: 1,
          containsAction: (id) => id == 'known-bridge',
        ),
        ['current-unknown'],
      );
    });
  });

  group('six-case smoke speed targets', () {
    for (final id in [
      'core',
      'back-protection',
      'memory-on-plan',
      'memory-off-plan',
    ]) {
      test('$id accepts exact plan limits and rejects each excess', () {
        List<String> check({
          int steps = 4,
          int ms = 60000,
          int tokens = 30000,
        }) => smokePerformanceFailures(
          caseId: id,
          steps: steps,
          elapsedMs: ms,
          totalTokens: tokens,
        );
        expect(check(), isEmpty);
        expect(check(steps: 5), ['$id: steps 5 > 4']);
        expect(check(ms: 60001), ['$id: elapsedMs 60001 > 60000']);
        expect(check(tokens: 30001), ['$id: totalTokens 30001 > 30000']);
      });
    }

    test('how-to has its own limits and no inherited plan token cap', () {
      expect(
        smokePerformanceFailures(
          caseId: 'actions',
          steps: 2,
          elapsedMs: 30000,
          totalTokens: 40000,
        ),
        isEmpty,
      );
      expect(
        smokePerformanceFailures(
          caseId: 'actions',
          steps: 3,
          elapsedMs: 30001,
          totalTokens: 40000,
        ),
        ['actions: steps 3 > 2', 'actions: elapsedMs 30001 > 30000'],
      );
    });

    test('remember and explicit card cases do not inherit speed gates', () {
      for (final id in ['remember', 'actions-card', 'new-case']) {
        expect(
          smokePerformanceFailures(
            caseId: id,
            steps: 10,
            elapsedMs: 120000,
            totalTokens: 60000,
          ),
          isEmpty,
        );
      }
    });
  });
}
