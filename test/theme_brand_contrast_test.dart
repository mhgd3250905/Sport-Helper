import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme/tokens.dart';

double _contrast(Color foreground, Color background) {
  final ink = Color.alphaBlend(foreground, background).computeLuminance();
  final paper = background.computeLuminance();
  return (ink > paper ? ink + .05 : paper + .05) /
      (ink > paper ? paper + .05 : ink + .05);
}

void main() {
  for (final palette in [SfPalette.light, SfPalette.dark]) {
    final name = palette.isDark ? 'dark' : 'light';
    final backgrounds = [
      palette.background,
      palette.surface,
      palette.surfaceHigh,
      palette.skyTop,
      palette.skyBottom,
      palette.userBubble,
      palette.assistantBubble,
    ];

    test('$name: primary and emphasis text meet AA in their page contexts', () {
      for (final background in backgrounds) {
        expect(
          _contrast(palette.accent, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name primary on $background',
        );
        expect(
          _contrast(palette.accentText, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name primary text on $background',
        );
        expect(
          _contrast(palette.emphasisText, background),
          greaterThanOrEqualTo(4.5),
          reason: '$name emphasis text on $background',
        );
        expect(
          _contrast(
            palette.accentText,
            Color.alphaBlend(palette.accentSoft, background),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$name selected option label on $background',
        );
        expect(
          _contrast(
            palette.emphasisText,
            Color.alphaBlend(palette.emphasisSoft, background),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '$name completion mark on $background',
        );
      }
    });

    test('$name: primary and coral button labels retain AA while pressed', () {
      for (final (ink, fill) in [
        (palette.onAccent, palette.accent),
        (palette.onEmphasis, palette.emphasis),
      ]) {
        expect(_contrast(ink, fill), greaterThanOrEqualTo(4.5));
        expect(
          _contrast(ink, Color.lerp(fill, Colors.black, .10)!),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test(
      '$name: conversation and metadata remain readable on tinted bubbles',
      () {
        for (final bubble in [palette.userBubble, palette.assistantBubble]) {
          expect(_contrast(palette.text, bubble), greaterThanOrEqualTo(7));
          expect(_contrast(palette.muted, bubble), greaterThanOrEqualTo(4.5));
        }
      },
    );
  }
}
