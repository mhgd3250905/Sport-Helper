import 'package:flutter/material.dart';

import 'theme/tokens.dart';

/// Approved training-guide layout; colour roles follow the current App theme.
abstract final class SfGuideTokens {
  static const pageInset = 20.0;
  static const bottomSpace = 96.0;
  static const cardGap = 14.0;
  static const cardRadius = 20.0;
  static const mediaRatio = 4 / 3;
  static const bodyPadding = EdgeInsets.fromLTRB(16, 14, 16, 16);
  static const sectionPadding = EdgeInsets.only(top: 28, bottom: 10);
  static const tagHeight = 26.0;
  static const tagRadius = 13.0;
  static const tagPadding = EdgeInsets.symmetric(horizontal: 10);
  static const tagGap = 6.0;
  static const numberSize = 24.0;
  static const numberRadius = 12.0;
  static const nameGap = 10.0;
  static const muscleGap = 6.0;
  static const dividerGap = 12.0;
  static const instructionGap = 12.0;
  static const stepSize = 18.0;
  static const stepGap = 8.0;
  static const buttonHeight = 52.0;
  static const buttonRadius = 26.0;
  static const buttonBottom = 12.0;
  static const footerFade = 24.0;

  static Color cardFill(BuildContext context) => SfColors.isDark
      ? Theme.of(context).colorScheme.surfaceContainer
      : Theme.of(context).colorScheme.surface;

  static Color get doseFill =>
      SfColors.accent.withValues(alpha: SfColors.isDark ? .18 : .10);

  static List<BoxShadow> get cardShadow => SfColors.isDark
      ? const []
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ];

  static TextStyle get title =>
      SfType.title.copyWith(fontSize: 24, fontWeight: FontWeight.w700);
  static TextStyle get tag => SfType.label.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
  static TextStyle get section => SfType.label.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: .5,
  );
  static TextStyle get number => SfType.label.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1,
    color: SfColors.accent,
  );
  static TextStyle get name =>
      SfType.headline.copyWith(fontSize: 17, fontWeight: FontWeight.w600);
  static TextStyle get dose => SfType.label.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SfColors.accent,
  );
  static TextStyle get muscles => SfType.label.copyWith(fontSize: 13);
  static TextStyle get caption =>
      SfType.label.copyWith(fontSize: 12, fontWeight: FontWeight.w600);
  static TextStyle get step => SfType.body.copyWith(fontSize: 14, height: 1.5);
  static TextStyle get stepNumber => SfType.label.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1,
  );
  static TextStyle get button => SfType.body.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: SfColors.onAccent,
  );
}
