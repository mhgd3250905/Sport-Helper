"""Measure APK ZIP occupancy, verify assets and assert release/ABI structure."""
import argparse
import collections
import hashlib
import json
import zipfile
from pathlib import Path

from report_apk_size import PREFIX, verify_candidate


def category(name):
    if name.endswith('/libflutter.so'):
        return 'flutterEngine'
    if name.endswith('/libapp.so'):
        return 'compiledDartApp'
    if 'VkLayer' in name:
        return 'graphicsValidation'
    if 'kernel_blob' in name or 'snapshot_data' in name:
        return 'debugKernelAndSnapshots'
    if name.startswith(PREFIX + 'training_media/'):
        return 'trainingMedia'
    if name.startswith(PREFIX + 'packs/') and '/voice/' in name:
        return 'trainingVoice'
    if name.endswith(('.ttf', '.otf', '.woff', '.woff2')):
        return 'fonts'
    if name.endswith('.dex'):
        return 'androidCode'
    return 'otherFiles'


def measure(path, app_root, release):
    verify_candidate(path, app_root)
    groups = collections.defaultdict(lambda: {'files': 0, 'zipBytes': 0, 'uncompressedBytes': 0})
    with zipfile.ZipFile(path) as apk:
        entries = [entry for entry in apk.infolist() if not entry.is_dir()]
        for entry in entries:
            group = groups[category(entry.filename)]
            group['files'] += 1
            group['zipBytes'] += entry.compress_size
            group['uncompressedBytes'] += entry.file_size
        abis = sorted({entry.filename.split('/')[1] for entry in entries
                       if entry.filename.startswith('lib/')})
        if release:
            if abis != ['arm64-v8a']:
                raise ValueError(f'Expected only arm64-v8a: {abis}')
            if groups['debugKernelAndSnapshots']['files'] or groups['graphicsValidation']['files']:
                raise ValueError('Release APK still contains debug kernel/snapshots/validation')
            if groups['compiledDartApp']['files'] != 1:
                raise ValueError('Release APK needs its AOT app library')
        voices = [entry for entry in entries if category(entry.filename) == 'trainingVoice']
        if len(voices) != 695 or sum(entry.file_size for entry in voices) != 15662531:
            raise ValueError('Voice inventory changed')
        for entry in voices:
            source = app_root / entry.filename.removeprefix('assets/flutter_assets/')
            if hashlib.sha256(apk.read(entry)).digest() != hashlib.file_digest(source.open('rb'), 'sha256').digest():
                raise ValueError(f'Voice asset changed in APK: {entry.filename}')
        headers = path.stat().st_size - sum(entry.compress_size for entry in entries)
        groups['zipHeadersSigningPadding'] = {'files': 0, 'zipBytes': headers, 'uncompressedBytes': None}
        return {
            'file': path.name,
            'bytes': path.stat().st_size,
            'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest(),
            'abis': abis,
            'groups': {name: {**value, 'percent': round(value['zipBytes'] / path.stat().st_size * 100, 2)}
                       for name, value in sorted(groups.items(), key=lambda pair: -pair[1]['zipBytes'])},
            'topFiles': [{'path': entry.filename, 'zipBytes': entry.compress_size,
                          'uncompressedBytes': entry.file_size}
                         for entry in sorted(entries, key=lambda entry: -entry.compress_size)[:12]],
            'mediaAndVoiceSourceHashesVerified': True,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--production', type=Path, required=True)
    parser.add_argument('--internal', type=Path, required=True)
    parser.add_argument('--debug', type=Path, required=True)
    parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    app = args.app_root.resolve()
    report = {
        'unit': 'bytes; MB = 1,000,000 bytes; occupancy = ZIP compressed bytes plus headers/signing/padding',
        'debugUniversal': measure(args.debug, app, False),
        'productionArm64Release': measure(args.production, app, True),
        'internalArm64Release': measure(args.internal, app, True),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
    for name, info in report.items():
        if isinstance(info, dict):
            print(f"{name}: {info['bytes']:,} B ({info['bytes']/1000000:.2f} MB), SHA256 {info['sha256']}")


if __name__ == '__main__':
    main()
