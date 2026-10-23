import 'package:flutter/widgets.dart';

import 'frame_recorder.dart';

/// Route names are fixed code identifiers, never titles, messages or plan IDs.
class PerformanceRouteObserver extends NavigatorObserver {
  PerformanceRouteObserver({FrameRecorder? recorder})
    : recorder = recorder ?? FrameRecorder.instance;
  final FrameRecorder recorder;
  final _routes = <Route<dynamic>>[];

  String _page(Route<dynamic>? route) => switch (route?.settings.name) {
    '/' => 'chat',
    'library' => 'action_library',
    'exercise_details' => 'exercise_details',
    'player' => 'training',
    'plan' => 'plan_details',
    'custom_plan' => 'custom_plan',
    'settings' => 'settings',
    'performance_settings' => 'performance_settings',
    'performance_lab' => 'performance_lab',
    'fixed_glass_lab' => 'fixed_glass_lab',
    'performance_chat' => 'performance_chat',
    'performance_plan_cards' => 'performance_plan_cards',
    _ => 'other_route',
  };

  void _update() => recorder.setPage(_page(_routes.lastOrNull));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _update();
  }
}
