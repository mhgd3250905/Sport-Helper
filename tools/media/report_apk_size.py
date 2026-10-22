"""Compare APK bytes and assert the exact on-demand media payload."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


PREFIX = 'assets/flutter_assets/assets/'


def inspect(path):
    with zipfile.ZipFile(path) as apk:
        entries = [entry for entry in apk.infolist() if not entry.is_dir()]

        def group(predicate):
            files = [entry for entry in entries if predicate(entry.filename)]
            return {'files': len(files), 'bytes': sum(e.file_size for e in files),
                    'compressedBytes': sum(e.compress_size for e in files)}

        return {
            'file': path.name,
            'bytes': path.stat().st_size,
            'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest(),
            'trainingMedia': group(lambda name: name.startswith(PREFIX + 'training_media/')),
            'legacyMedia': group(lambda name: name.startswith(PREFIX + 'packs/') and
                                 name.endswith(('.mp4', '.jpg'))),
            'cutouts': group(lambda name: name.startswith(PREFIX + 'cutouts/')),
            'videos': group(lambda name: name.startswith(PREFIX) and name.endswith('.mp4')),
            'nativeLibraries': group(lambda name: name.startswith('lib/')),
        }


def verify_candidate(path, app):
    root = app / 'assets/training_media'
    expected = {PREFIX + p.relative_to(app / 'assets').as_posix(): p
                for p in root.rglob('*') if p.is_file()}
    with zipfile.ZipFile(path) as apk:
        actual = {name for name in apk.namelist() if name.startswith(PREFIX + 'training_media/')}
        if actual != expected.keys():
            raise ValueError('APK media inventory differs from verified source assets')
        for name, source in expected.items():
            if hashlib.sha256(apk.read(name)).digest() != hashlib.file_digest(source.open('rb'), 'sha256').digest():
                raise ValueError(f'APK media differs from source: {name}')
    candidate = inspect(path)
    if (candidate['trainingMedia']['files'] != 413 or candidate['trainingMedia']['bytes'] != 14883430
            or candidate['legacyMedia']['files'] != 0 or candidate['cutouts']['files'] != 0
            or candidate['videos']['files'] != 32):
        raise ValueError('APK does not contain the required minimal media bundle')
    return candidate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    before = inspect(args.before)
    after = verify_candidate(args.after, args.app_root.resolve())
    old_media = before['legacyMedia']['bytes'] + before['cutouts']['bytes']
    report = {'buildMode': 'debug, universal APK (same ABI set)',
              'before': before, 'after': after,
              'apkBytesSaved': before['bytes'] - after['bytes'],
              'mediaBytesSaved': old_media - after['trainingMedia']['bytes'],
              'mediaBeforeBytes': old_media,
              'apkInventoryAndMediaHashesVerified': True}
    encoded = json.dumps(report, indent=2) + '\n'
    args.report.write_text(encoded, encoding='utf-8')
    print(encoded)


if __name__ == '__main__':
    main()
