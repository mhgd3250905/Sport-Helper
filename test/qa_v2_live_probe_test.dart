import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach/ugk_coach_qa_v2.dart';

import '../tools/coach/qa_v2_live_probe.dart' as probe;

class _LiveHttp extends HttpOverrides {}

void main() {
  test(
    'QA observation forwards actual max body and preserves raw dialogue without reasoning',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = _LiveHttp();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var received = 0;
      Map<String, Object?>? sent;
      final listener = server.listen((request) async {
        received++;
        sent = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'model': probe.qaProbeModel,
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': '原始正文\n第二行',
                  'reasoning_content': 'PRIVATE_REASONING_SENTINEL',
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 3,
              'completion_tokens_details': {'reasoning_tokens': 2},
            },
          }),
        );
        await request.response.close();
      });
      final inner = coach.OpenAiCompatibleClient(
        config: coach.LlmConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: probe.qaProbeModel,
          maxRetries: 0,
        ),
        auth: coach.ApiKeyAuth('SYNTHETIC_KEY_SENTINEL'),
      );
      final observed = probe.ObservedQaClient(inner);
      try {
        expect(identical(observed.config, inner.config), isTrue);
        expect(identical(observed.auth, inner.auth), isTrue);
        final response = await observed.complete(
          const coach.LlmRequest(
            messages: [coach.LlmMessage.user('原始输入')],
            extraBody: {
              'thinking': {'type': 'enabled'},
              'reasoning_effort': 'max',
            },
          ),
        );
        expect(sent?['model'], probe.qaProbeModel);
        expect(sent?['thinking'], {'type': 'enabled'});
        expect(sent?['reasoning_effort'], 'max');
        expect(response.content, '原始正文\n第二行');
        expect(response.reasoning, 'PRIVATE_REASONING_SENTINEL');
        expect(observed.calls.single['requestContractVerified'], isTrue);
        expect((observed.calls.single['usage'] as Map)['reasoningTokens'], 2);
        final reply = CoachQaReply(
          kind: 'ask',
          text: response.content,
          question: coach.AskUserQuestion.direct(
            '原问句？',
            options: ['居家原文', '健身房原文'],
          ),
          askStep: QaAskStep.place,
          cards: const [
            CoachQaCard(id: 'original-id', name: '原始动作', why: '原始理由'),
          ],
          chips: const ['原始 chip'],
        );
        expect(
          probe.selectProbeAnswer(reply, place: '居家', equipment: '徒手'),
          '居家原文',
        );
        final report = <String, Object?>{
          'sourceCommit': 'source',
          'sdk': 'sdk',
          'model': probe.qaProbeModel,
          'conversations': [
            {
              'id': 'fixture',
              'tagCoverage': '209/211',
              'turns': [
                {
                  'turn': 1,
                  'input': '原始输入',
                  'reply': probe.qaReplyRecord(reply),
                },
              ],
              'observations': [],
              'calls': observed.calls,
            },
          ],
        };
        final evidence = jsonEncode(report) + probe.renderProbeMarkdown(report);
        expect(evidence, contains('原始正文'));
        expect(evidence, contains('第二行'));
        expect(evidence, contains('原问句？'));
        expect(evidence, contains('原始理由'));
        expect(evidence, contains('原始 chip'));
        expect(evidence, isNot(contains('PRIVATE_REASONING_SENTINEL')));
        expect(evidence, isNot(contains('SYNTHETIC_KEY_SENTINEL')));
        await expectLater(
          observed.complete(
            const coach.LlmRequest(
              messages: [coach.LlmMessage.user('blocked')],
            ),
          ),
          throwsStateError,
        );
        expect(
          received,
          1,
          reason: 'Wrong thinking/max must be blocked before HTTP.',
        );
      } finally {
        observed.close();
        await listener.cancel();
        await server.close(force: true);
        HttpOverrides.global = previous;
      }
    },
  );
}
