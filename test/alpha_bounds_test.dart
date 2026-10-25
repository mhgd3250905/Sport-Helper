import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/alpha_bounds.dart';

void main() {
  Map<String, Object> index() => {
    'format': 'smartfit-app-test-pack-index@1',
    'internalOnly': true,
    'actions': {
      'move': {
        'alphaCover': {
          'asset': 'cover.webp',
          'sha256': 'source',
          'width': 720,
          'height': 720,
        },
        'alphaPlaybackPoster': {
          'asset': 'frame0.webp',
          'sha256': 'frame0',
          'width': 720,
          'height': 720,
        },
      },
    },
  };
  Map<String, Object> metadata({String sha = 'source', List<num>? bounds}) => {
    'format': 'smartfit-alpha-bounds@1',
    'assets': {
      'cover.webp': {
        'sourceSha256': sha,
        'width': 720,
        'height': 720,
        'bounds': bounds ?? [72, 144, 648, 720],
      },
      'frame0.webp': {
        'sourceSha256': 'frame0',
        'width': 720,
        'height': 720,
        'bounds': [72, 144, 648, 720],
      },
    },
  };
  test(
    'verified bounds normalize cover without reframing video frame zero',
    () {
      final bounds = SfAlphaBounds.parse(metadata(), index());
      expect(bounds.entries['cover.webp'], const Rect.fromLTRB(.1, .2, .9, 1));
      expect(bounds.entries.containsKey('frame0.webp'), isFalse);
    },
  );
  test('stale SHA, out-of-range or missing metadata keep original framing', () {
    expect(SfAlphaBounds.parse(metadata(sha: 'old'), index()).entries, isEmpty);
    expect(
      SfAlphaBounds.parse(metadata(bounds: [-1, 0, 720, 720]), index()).entries,
      isEmpty,
    );
    expect(
      SfAlphaBounds.parse(metadata(bounds: [0, 0, 721, 720]), index()).entries,
      isEmpty,
    );
    expect(
      SfAlphaBounds.parse(
        metadata(bounds: [0, 0, double.nan, 720]),
        index(),
      ).entries,
      isEmpty,
    );
    expect(SfAlphaBounds.parse(null, index()).entries, isEmpty);
  });
}
