"""Exact RGBA pixel counts; conservative AA candidates never imply acceptance."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load_manifest(root, theme):
    path = root / theme / 'capture-manifest.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    assert data['theme'] == theme
    for item in data['frames']:
        file = root / item['frame']
        assert file.stat().st_size == item['bytes'] and sha(file) == item['sha256']
    return data

def local_edges(array):
    rgb = Image.fromarray(array[:, :, :3])
    high = np.asarray(rgb.filter(ImageFilter.MaxFilter(3)), dtype=np.int16)
    low = np.asarray(rgb.filter(ImageFilter.MinFilter(3)), dtype=np.int16)
    return np.max(high - low, axis=2) > 8

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--new', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    rows = []
    bindings = []
    new_focus_is_sdk = True
    for theme in ('light', 'dark'):
        base, new = load_manifest(args.base, theme), load_manifest(args.new, theme)
        new_focus_is_sdk = new_focus_is_sdk and new.get('focusImplementation') == 'SDK'
        for field in ('inputsSha256', 'driverSha256', 'logicalSize', 'dpr', 'fonts', 'container',
                      'focusSampleTimesMs', 'deliveryDurationUs'):
            assert base[field] == new[field], f'Capture contract differs: {theme}/{field}'
        for field in ('capturePlan', 'originalCaptureInputSha256', 'legacyAlpha'):
            if field in base or field in new:
                assert base.get(field) == new.get(field), f'Capture contract differs: {theme}/{field}'
        if 'capturePlan' in base:
            assert base['historicalOriginalFrameCount'] == 29
            assert base['historicalOriginalFramesByteIdentical'] is True
            assert base['bubbleRepaintBoundaryCounts'] == new['bubbleRepaintBoundaryCounts'] == [4]
        base_frames = {item['frame']: item for item in base['frames']}
        new_frames = {item['frame']: item for item in new['frames']}
        assert base_frames.keys() == new_frames.keys(), f'Frame set differs: {theme}'
        bindings.append({'theme': theme, 'base': {k: base[k] for k in (
            'source', 'publicInputsSha256', 'driverSha256', 'adapterSha256', 'inputsSha256')},
                         'new': {k: new[k] for k in (
            'source', 'publicInputsSha256', 'driverSha256', 'adapterSha256', 'inputsSha256')}})
        for frame in base_frames:
            for field in ('elapsedUs', 'fraction', 'expectedImageSemantics'):
                assert base_frames[frame].get(field) == new_frames[frame].get(field), f'Timeline differs: {frame}/{field}'
            a_runtime, b_runtime = base_frames[frame].get('runtime'), new_frames[frame].get('runtime')
            semantics = None if a_runtime is None or b_runtime is None else {
                'imageSemanticsEqual': a_runtime['imageSemantics'] == b_runtime['imageSemantics'],
                'focusClearSemanticsEqual': a_runtime['focusClearSemantics'] == b_runtime['focusClearSemantics'],
                'base': a_runtime,
                'new': b_runtime,
            }
            a = np.asarray(Image.open(args.base / frame).convert('RGBA'), dtype=np.int16)
            b = np.asarray(Image.open(args.new / frame).convert('RGBA'), dtype=np.int16)
            assert a.shape == b.shape
            delta = np.abs(a - b)
            maximum = delta.max(axis=2)
            changed = maximum > 0
            count = int(np.count_nonzero(changed))
            outside_edges = 0
            if count:
                edges = local_edges(a.astype(np.uint8)) | local_edges(b.astype(np.uint8))
                outside_edges = int(np.count_nonzero(changed & ~edges))
            ys, xs = np.nonzero(changed)
            box = None if count == 0 else [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
            rows.append({'frame': frame, 'width': int(a.shape[1]), 'height': int(a.shape[0]),
                'differentPixels': count, 'totalPixels': int(changed.size),
                'differentFraction': count / changed.size, 'maxChannelDelta': int(delta.max()),
                'meanChannelDelta': float(delta.mean()),
                'pixelsDelta1to2': int(np.count_nonzero((maximum > 0) & (maximum <= 2))),
                'pixelsDelta3to8': int(np.count_nonzero((maximum > 2) & (maximum <= 8))),
                'pixelsDeltaAbove8': int(np.count_nonzero(maximum > 8)),
                'changedOutsideOnePixelEdges': outside_edges,
                'smallEdgeDifferenceCandidate': bool(count and delta.max() <= 2 and outside_edges == 0),
                'bbox': box, 'baseSha256': base_frames[frame]['sha256'],
                'newSha256': new_frames[frame]['sha256'], 'runtimeComparison': semantics})
    semantic_rows = [row['runtimeComparison'] for row in rows if row['runtimeComparison'] is not None]
    summary = {'frames': len(rows), 'exactFrames': sum(row['differentPixels'] == 0 for row in rows),
        'differentFrames': sum(row['differentPixels'] > 0 for row in rows),
        'totalDifferentPixels': sum(row['differentPixels'] for row in rows),
        'maximumDifferentPixelsInFrame': max(row['differentPixels'] for row in rows),
        'maximumChannelDelta': max(row['maxChannelDelta'] for row in rows),
        'allFramesPixelIdentical': all(row['differentPixels'] == 0 for row in rows),
        'allDifferencesSmallAndOnEdges': all(row['differentPixels'] == 0 or row['smallEdgeDifferenceCandidate'] for row in rows),
        'harkAcceptance': 'pending; not inferred by pixel statistics',
        'newFocusUsesSdk': new_focus_is_sdk,
        'semanticComparedFrames': len(semantic_rows),
        'semanticDifferentFrames': sum(not row['imageSemanticsEqual'] or not row['focusClearSemanticsEqual'] for row in semantic_rows),
        'allComparedSemanticsIdentical': all(row['imageSemanticsEqual'] and row['focusClearSemanticsEqual'] for row in semantic_rows) if semantic_rows else None,
        'baseBubbleRepaintBoundaryCounts': sorted({row['base']['bubbleRepaintBoundaryCount'] for row in semantic_rows if row['base']['bubbleRepaintBoundaryCount'] is not None}),
        'newBubbleRepaintBoundaryCounts': sorted({row['new']['bubbleRepaintBoundaryCount'] for row in semantic_rows if row['new']['bubbleRepaintBoundaryCount'] is not None}),
        'legacyCropPainterCountDifferentFrames': sum(row['base']['legacyCropPainterCount'] != row['new']['legacyCropPainterCount'] for row in semantic_rows),
        'aaCandidateRule': 'Each changed pixel channel delta <=2/255 and every change lies on a 3x3 local contrast edge; descriptive only.',
        'noAnimationParametersChangedByCapture': True}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    json_path, md_path = args.output.with_suffix('.json'), args.output.with_suffix('.md')
    assert not json_path.exists() and not md_path.exists()
    with json_path.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump({'schema': 'smartfit-ui-kit-frame-diff@1', 'summary': summary,
                   'bindings': bindings, 'frames': rows}, stream, indent=2)
        stream.write('\n')
    lines = ['# UI kit frame pixel differences', '',
        'Logical 412 x 915, DPR 2.625, same capture driver, inputs, fonts and rendering runtime.', '',
        f"Exact frames: {summary['exactFrames']} / {summary['frames']}; total changed pixels: {summary['totalDifferentPixels']}.", '',
        f"Semantic comparisons: {summary['semanticComparedFrames']}; differing frames: {summary['semanticDifferentFrames']}. Actual bubble RepaintBoundary counts: base {summary['baseBubbleRepaintBoundaryCounts']}, new {summary['newBubbleRepaintBoundaryCounts']}.", '',
        'AA candidates are descriptive statistics. Hark visual review remains pending.', '',
        '| Frame | Different pixels | Delta >8 | Maximum channel delta | Outside edges | Semantics identical |',
        '| --- | ---: | ---: | ---: | ---: | --- |']
    for row in rows:
        runtime = row['runtimeComparison']
        equal = 'unrecorded' if runtime is None else str(runtime['imageSemanticsEqual'] and runtime['focusClearSemanticsEqual']).lower()
        lines.append(f"| {row['frame']} | {row['differentPixels']} | {row['pixelsDeltaAbove8']} | {row['maxChannelDelta']} | {row['changedOutsideOnePixelEdges']} | {equal} |")
    with md_path.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write('\n'.join(lines) + '\n')
    print(json.dumps(summary))

if __name__ == '__main__':
    main()
