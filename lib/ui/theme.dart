// Theme entry point for plain pages: the tokens, the Material theme, the
// icon set and the shared controls (lib/ui/theme/), plus small text helpers.
export 'theme/app_theme.dart';
export 'theme/sf_icons.dart';
export 'theme/tokens.dart';
export 'theme/media_theme.dart';
export 'theme/widgets.dart';

String levelZh(int l) => switch (l) {
  1 => '入门',
  2 => '基础',
  _ => '进阶',
};

String minutesZh(double seconds) {
  final m = (seconds / 60).round();
  return m < 1 ? '不到 1 分钟' : '约 $m 分钟';
}
