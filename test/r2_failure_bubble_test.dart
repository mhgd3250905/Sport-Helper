import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/app/services.dart';
import 'package:smartfit/chat/ai_chat_engine.dart';
import 'package:smartfit/chat/chat_controller.dart';
import 'package:smartfit/chat/chat_models.dart';
import 'package:smartfit/chat/app_chat_actions.dart';
import 'package:smartfit/ui/chat/chat_home_page.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;
import 'package:ugk_coach_ui/ugk_coach_ui.dart';
import 'package:ugk_trainer/ugk_trainer.dart' show PoseHubActionLibrary;

import 'app_flow_test.dart' show services, tall;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'confirmation and answered selections survive persistence; malformed cards are rejected',
    () {
      final question = coach.AskUserQuestion.confirmation(
        question: '先确认一下训练条件',
        focus: '大腿内侧',
        fields: [
          coach.AskUserField(
            key: 'scene',
            label: '场景',
            options: ['家里', '办公室'],
            preselected: ['家里'],
            previousSelections: ['家里'],
          ),
          coach.AskUserField(
            key: 'equipment',
            label: '器械',
            options: ['徒手', '椅子'],
            multiple: true,
            preselected: ['椅子'],
            previousSelections: ['椅子'],
            optionsByScene: {
              '家里': ['徒手', '椅子'],
            },
          ),
          coach.AskUserField(
            key: 'minutes',
            label: '时长',
            options: ['10 分钟', '15 分钟'],
            preselected: ['10 分钟'],
          ),
        ],
        defaultSelections: {
          'scene': ['家里'],
          'equipment': ['徒手'],
          'minutes': ['10 分钟'],
        },
      );
      final message = ChatMessage(
        id: 'q',
        role: ChatRole.assistant,
        at: DateTime(2026),
        question: question,
        questionAnswered: true,
        answeredForm: const {
          'scene': ['家里'],
          'equipment': ['椅子'],
          'minutes': ['10 分钟'],
        },
      );
      final decoded = ChatMessage.fromJson(
        jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.question?.isConfirmation, isTrue);
      expect(decoded.question?.focus, '大腿内侧');
      expect(decoded.question?.fields[1].previousSelections, ['椅子']);
      expect(decoded.answeredForm, message.answeredForm);
      final malformed =
          jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>;
      ((malformed['question'] as Map)['fields']
          as List)[1]['previousSelections'] = [
        '不在选项中',
      ];
      final rejected = ChatMessage.fromJson(malformed);
      expect(rejected.question, isNull);
      expect(rejected.answeredForm, isEmpty);
    },
  );

  testWidgets(
    'planning error renders one retry bubble and persists no diagnostic',
    (tester) async {
      tall(tester);
      final app = services();
      await app.store.acceptSafety(blocked: false);
      final client = coach.FakeLlmClient([
        const coach.LlmException(
          coach.LlmErrorKind.http,
          'private-diagnostic',
          statusCode: 401,
        ),
        const coach.LlmException(
          coach.LlmErrorKind.http,
          'private-diagnostic',
          statusCode: 401,
        ),
      ], latency: Duration.zero);
      final engine = AiChatEngine(
        local: const AppChatActions(),
        catalog: (await PoseHubActionLibrary.load()).toAiCatalog(),
        profile: coach.CoachProfile.fromJson(
          jsonDecode(File('assets/coach/smartfit.json').readAsStringSync()),
        ),
        client: client,
        enableUserMemory: false,
      );
      addTearDown(engine.dispose);
      final chat = ChatController(
        engine: engine,
        store: app.store,
        replyDelay: Duration.zero,
      )..start();
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        AppScope(
          services: app,
          child: MaterialApp(
            theme: buildTheme(),
            home: ChatHomePage(controller: chat),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await chat.send('在家徒手10分钟训练');
      await tester.pumpAndSettle();
      expect(find.byType(CoachFailureBubble), findsOneWidget);
      expect(find.textContaining('private-diagnostic'), findsNothing);
      expect(find.textContaining('预设方案 · AI'), findsNothing);
      expect(chat.messages.where((m) => m.isPlanningFailure), hasLength(1));
      final saved = chat.messages.last.toJson();
      final restored = ChatMessage.fromJson(saved);
      expect(restored.isPlanningFailure, isTrue);
      expect(jsonEncode(saved), isNot(contains('private-diagnostic')));
      await tester.tap(find.byKey(const ValueKey('coach-failure-retry')));
      await tester.pumpAndSettle();
      expect(client.requests, hasLength(2));
      expect(chat.messages.where((m) => m.isUser).last.text, '重试');
    },
  );
}
