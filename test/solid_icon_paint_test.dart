import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/theme/sf_icons.dart';

const _left = Color(0xFF204060);
const _right = Color(0xFFAC3560);
const _ink = Color(0xFFFFFFFF);

Future<ByteData> _paint(SfGlyph glyph, {bool filled = true}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 240, 240), Paint()..color = _left);
  canvas.drawRect(
    const Rect.fromLTWH(120, 0, 120, 240),
    Paint()..color = _right,
  );
  SfIconPainter(
    glyph,
    color: _ink,
    filled: filled,
  ).paint(canvas, const Size(240, 240));
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 240);
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return pixels;
}

Color _at(ByteData pixels, Offset gridPoint) {
  final offset =
      ((gridPoint.dy * 10).round() * 240 + (gridPoint.dx * 10).round()) * 4;
  return Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all glyphs paint visible ink in both states', () async {
    for (final glyph in SfGlyph.values) {
      for (final filled in [false, true]) {
        final pixels = await _paint(glyph, filled: filled);
        var inkPixels = 0;
        for (var i = 0; i < pixels.lengthInBytes; i += 4) {
          if (pixels.getUint8(i) > 245 &&
              pixels.getUint8(i + 1) > 245 &&
              pixels.getUint8(i + 2) > 245) {
            inkPixels++;
          }
        }
        expect(inkPixels, greaterThan(20), reason: '$glyph filled=$filled');
      }
    }
  });

  test(
    'filled symbol cutouts preserve the real backdrop beneath them',
    () async {
      const holes = <SfGlyph, Offset>{
        SfGlyph.checkCircle: Offset(10.9, 15.2),
        SfGlyph.home: Offset(12, 18.5),
        SfGlyph.flame: Offset(12, 16.6),
        SfGlyph.today: Offset(12, 12),
        SfGlyph.checkup: Offset(10.7, 9.2),
        SfGlyph.subtitles: Offset(9, 11.4),
        SfGlyph.info: Offset(12, 14),
        SfGlyph.clipboard: Offset(12, 13.5),
        SfGlyph.shield: Offset(11.2, 14.3),
        SfGlyph.stop: Offset(12, 12),
        SfGlyph.bandage: Offset(12, 12),
        SfGlyph.clock: Offset(12, 12),
      };
      for (final MapEntry(:key, :value) in holes.entries) {
        final pixels = await _paint(key);
        expect(
          _at(pixels, value),
          value.dx < 12 ? _left : _right,
          reason: '$key hole',
        );
      }
    },
  );

  test(
    'overlapping outline symbols leave their open interiors visible',
    () async {
      for (final (glyph, point) in const [
        (SfGlyph.copy, Offset(12, 12)),
        (SfGlyph.sliders, Offset(15, 7)),
      ]) {
        expect(_at(await _paint(glyph, filled: false), point), _right);
      }
    },
  );
}
