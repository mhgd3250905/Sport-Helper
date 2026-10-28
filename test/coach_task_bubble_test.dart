import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/chat/coach_task_bubble.dart';
import 'package:smartfit/ui/theme/app_theme.dart';
import 'package:ugk_coach/ugk_coach.dart' as coach;

coach.CoachTaskState _task(bool complete) => coach.CoachTaskState.fromJson({
  'type': 'plan',
  'reused': false,
  'nodes': [
    {'id': 'understand', 'status': 'done', 'stamp': '用户要练核心', 'doneAtTurn': 1},
    {
      'id': 'parameters',
      'status': 'updated',
      'stamp': '居家 · 徒手 · 10 分钟',
      'doneAtTurn': 1,
    },
    {
      'id': 'output',
      'status': complete ? 'done' : 'current',
      'stamp': complete ? '已交付计划卡' : '',
    },
  ],
});

void main() {
  testWidgets('real SDK node order and stamps render as vertical check-ins', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: CoachTaskBubble(
            task: _task(false),
            waiting: true,
            onCancel: () => cancelled = true,
          ),
        ),
      ),
    );
    expect(find.text('用户要练核心'), findsOneWidget);
    expect(find.text('居家 · 徒手 · 10 分钟'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('用户要练核心')).dy,
      lessThan(tester.getTopLeft(find.text('居家 · 徒手 · 10 分钟')).dy),
    );
    await tester.tap(find.text('取消'));
    expect(cancelled, isTrue);
  });

  testWidgets('completed SDK task folds and can be expanded', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: CoachTaskBubble(task: _task(true))),
      ),
    );
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('用户要练核心'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('coach-task-toggle')));
    await tester.pump();
    expect(find.text('用户要练核心'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach-task-toggle')));
    await tester.pump();
    expect(find.text('用户要练核心'), findsNothing);
  });

  testWidgets('waiting for the first node does not invent an SDK status', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: CoachTaskBubble(waiting: true)),
      ),
    );
    expect(find.text('…'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });
}
