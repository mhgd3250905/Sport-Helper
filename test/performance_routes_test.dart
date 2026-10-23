import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/diagnostics/frame_recorder.dart';
import 'package:smartfit/diagnostics/performance_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('navigation restores each previous fixed page label on pop', (
    tester,
  ) async {
    final recorder = FrameRecorder(enabled: true);
    final observer = PerformanceRouteObserver(recorder: recorder);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: const SizedBox(),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SizedBox(),
        ),
      ),
    );
    expect(recorder.currentPage, 'chat');
    navigator.currentState!.pushNamed('library');
    await tester.pumpAndSettle();
    expect(recorder.currentPage, 'action_library');
    navigator.currentState!.pushNamed('exercise_details');
    await tester.pumpAndSettle();
    expect(recorder.currentPage, 'exercise_details');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(recorder.currentPage, 'action_library');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(recorder.currentPage, 'chat');
  });

  test(
    'replace/remove preserve the visible page and unknown titles stay private',
    () {
      final recorder = FrameRecorder(enabled: true);
      final observer = PerformanceRouteObserver(recorder: recorder);
      Route<void> route(String name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => const SizedBox(),
      );
      final chat = route('/');
      final library = route('library');
      final settings = route('settings');
      final performance = route('performance_settings');
      observer.didPush(chat, null);
      observer.didPush(library, chat);
      observer.didPush(settings, library);
      observer.didReplace(oldRoute: settings, newRoute: performance);
      expect(recorder.currentPage, 'performance_settings');
      observer.didRemove(library, chat);
      expect(recorder.currentPage, 'performance_settings');
      observer.didPop(performance, chat);
      expect(recorder.currentPage, 'chat');
      final privateRoute = route('private user message or exercise title');
      observer.didPush(privateRoute, chat);
      expect(recorder.currentPage, 'other_route');
      expect(
        recorder.snapshot().toString(),
        isNot(contains('private user message')),
      );
      observer.didPop(privateRoute, chat);
      observer.didReplace(oldRoute: chat);
      expect(recorder.currentPage, 'other_route');
    },
  );
}
