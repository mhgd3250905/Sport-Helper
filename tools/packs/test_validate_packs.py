"""Regression checks for explicit App media migration versus complete packs.

Run: python -m unittest discover -s tools/packs -p test_validate_packs.py -v
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import packlib as P


APP = Path(__file__).resolve().parents[2]
VALIDATOR = APP / 'tools/packs/validate_packs.py'


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='smartfit-pack-validation-')
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name)
        self.packs = self.app / 'assets/packs'
        for pid in ('_common', 'h-squat'):
            shutil.copytree(APP / 'assets/packs' / pid, self.packs / pid)
        for source in ('lib/app/services.dart', 'lib/domain/exercise.dart'):
            destination = self.app / source
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(APP / source, destination)
        self.media = self.app / 'assets/training_media'
        self.manifest = self.media / 'v0.3.0-app/app-manifest.json'
        self.write(self.media / 'v0.3.0/realistic/dark/h-squat.mp4', b'builtin video')
        for pid in ('h-squat', 'remote'):
            for group in ('covers', 'thumbs'):
                self.write(self.manifest.parent / f'common-lossy/{group}/{pid}.webp', b'lossy image')
        packages = {}
        for package_id, action, content in (
            ('builtin', 'h-squat', b'builtin video'),
            ('realistic-dark', 'remote', b'downloadable video'),
        ):
            entries = [{'path': f'../v0.3.0/realistic/dark/{action}.mp4',
                        'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()}]
            subpath = self.manifest.parent / f'packages/{package_id}.json'
            self.json(subpath, {'files': entries})
            packages[package_id] = {
                'kind': 'video', 'actionIds': [action], 'fileCount': 1,
                'totalBytes': len(content),
                'manifest': {'path': f'packages/{package_id}.json',
                             'bytes': subpath.stat().st_size, 'sha256': P.sha256(subpath)},
            }
        self.json(self.manifest, {'version': '0.3.0', 'packages': packages,
                                 'actions': [{'id': pid} for pid in ('h-squat', 'remote')]})
        directories = sorted({f.parent.relative_to(self.app).as_posix()
                              for f in self.media.rglob('*') if f.is_file()})
        (self.app / 'pubspec.yaml').write_text(
            'flutter:\n  assets:\n' + ''.join(f'    - {directory}/\n' for directory in directories))
        self.seal_index()
        self.seal_media_report()

    @staticmethod
    def write(path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def json(self, path, data):
        self.write(path, json.dumps(data).encode())

    def seal_index(self):
        self.json(self.packs / 'index.json', {
            'format': P.INDEX_FORMAT, 'formatVersion': P.FORMAT_VERSION,
            'packs': [{'id': d.name, 'version': P.read_json(d / 'pack.json')['version'],
                       'sha256': P.sha256(d / 'pack.json')} for d in P.pack_dirs(self.packs)],
        })

    def seal_media_report(self):
        inventory = ''.join(sorted(
            f'{f.relative_to(self.media).as_posix()}\0{f.stat().st_size}\0{P.sha256(f)}\n'
            for f in self.media.rglob('*') if f.is_file()))
        self.json(self.app / 'tools/media/builtin-assets-report.json', {
            'releaseVersion': '0.3.0', 'mainManifestSha256': P.sha256(self.manifest),
            'bundleInventorySha256': hashlib.sha256(inventory.encode()).hexdigest(),
        })

    def validate(self, *arguments):
        return subprocess.run([sys.executable, str(VALIDATOR), '--root', str(self.packs),
                               *arguments], capture_output=True, text=True)

    def assert_invalid(self, expected):
        result = self.validate('--on-demand-media')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected, result.stdout)

    def test_explicit_mode_passes_and_default_still_requires_legacy_media(self):
        migrated = self.validate('--on-demand-media')
        self.assertEqual(migrated.returncode, 0, migrated.stdout + migrated.stderr)
        self.assertIn('0 errors', migrated.stdout)
        strict = self.validate()
        self.assertEqual(strict.returncode, 1, strict.stdout + strict.stderr)
        self.assertIn('missing file demo.mp4', strict.stdout)
        self.assertIn('missing file cover-light.jpg', strict.stdout)
        self.assertIn('4 errors', strict.stdout)

    def test_full_pack_default_passes_and_still_rejects_corrupt_media(self):
        path = self.packs / 'h-squat/pack.json'
        pack = P.read_json(path)
        for rel in ('demo.mp4', 'cover.jpg', 'demo-light.mp4', 'cover-light.jpg'):
            f = path.parent / rel
            self.write(f, b'original complete-pack media')
            pack['files'][rel] = {'bytes': f.stat().st_size, 'sha256': P.sha256(f)}
        self.json(path, pack)
        self.seal_index()
        complete = self.validate()
        self.assertEqual(complete.returncode, 0, complete.stdout + complete.stderr)
        self.write(path.parent / 'demo.mp4', b'corrupt')
        strict = self.validate()
        self.assertEqual(strict.returncode, 1)
        self.assertIn('demo.mp4 changed since sealing', strict.stdout)
        self.assert_invalid('demo.mp4 changed since sealing')

    def test_missing_voice_is_never_exempted(self):
        (self.packs / 'h-squat/voice/zh/name.m4a').unlink()
        self.assert_invalid('missing file voice/zh/name.m4a')

    def test_voice_digest_is_still_checked(self):
        self.write(self.packs / 'h-squat/voice/zh/name.m4a', b'corrupt voice')
        self.assert_invalid('voice/zh/name.m4a changed since sealing')

    def test_common_chime_is_still_required(self):
        pack = P.read_json(self.packs / '_common/pack.json')
        (self.packs / '_common' / pack['chimes']['tick']['file']).unlink()
        self.assert_invalid('missing file chime/')

    def test_metadata_and_index_are_still_checked(self):
        path = self.packs / 'h-squat/pack.json'
        pack = P.read_json(path)
        pack['level'] = 99
        self.json(path, pack)
        self.assert_invalid('level 99')
        self.assert_invalid('h-squat pack.json changed since index was built')

    def test_stray_files_are_still_rejected(self):
        self.write(self.packs / 'h-squat/extra.mp4', b'stray')
        self.assert_invalid('stray file extra.mp4')

    def test_submanifest_hash_is_required_before_exemptions(self):
        self.write(self.manifest.parent / 'packages/realistic-dark.json', b'{"files": []}')
        self.assert_invalid('submanifest size/sha256 mismatch')
        self.assert_invalid('missing file demo.mp4')

    def test_verified_submanifest_still_requires_valid_video_integrity_metadata(self):
        subpath = self.manifest.parent / 'packages/realistic-dark.json'
        submanifest = P.read_json(subpath)
        submanifest['files'][0]['sha256'] = 'invalid-digest'
        self.json(subpath, submanifest)
        manifest = P.read_json(self.manifest)
        reference = manifest['packages']['realistic-dark']['manifest']
        reference.update(bytes=subpath.stat().st_size, sha256=P.sha256(subpath))
        self.json(self.manifest, manifest)
        self.seal_media_report()
        self.assert_invalid('media action/file index mismatch')

    def test_builtin_and_lossy_image_integrity_are_required(self):
        self.write(self.media / 'v0.3.0/realistic/dark/h-squat.mp4', b'corrupt')
        self.assert_invalid('builtin size/sha256 mismatch')
        self.write(self.media / 'v0.3.0/realistic/dark/h-squat.mp4', b'builtin video')
        self.write(self.manifest.parent / 'common-lossy/covers/h-squat.webp', b'corrupt image')
        self.assert_invalid('media build report integrity mismatch')

    def test_missing_action_or_manifest_is_not_exempted(self):
        path = self.packs / 'h-squat/pack.json'
        pack = P.read_json(path)
        # The pack id must be registered in builtin OR realistic-dark.
        new_path = self.packs / 'unknown-action'
        (self.packs / 'h-squat').rename(new_path)
        pack['id'] = 'unknown-action'
        self.json(new_path / 'pack.json', pack)
        self.seal_index()
        self.assert_invalid('missing replacement action/video')
        self.manifest.unlink()
        self.assert_invalid('expected one bundled app-manifest.json')

    def test_pubspec_and_actual_app_mapping_must_be_wired(self):
        (self.app / 'pubspec.yaml').write_text('flutter:\n  assets:\n')
        self.assert_invalid('missing from pubspec assets')
        shutil.copyfile(APP / 'pubspec.yaml', self.app / 'pubspec.yaml')
        self.write(self.app / 'lib/app/services.dart', b'// mediaOverride: ExerciseMedia.fromPoseHub(p)')
        self.assert_invalid('App fromPoseHub replacement mapping is not wired')

    def test_arbitrary_reference_cannot_hide_a_missing_voice(self):
        path = self.packs / 'h-squat/pack.json'
        pack = P.read_json(path)
        pack['media']['video'] = 'voice/zh/name.m4a'
        self.json(path, pack)
        self.seal_index()
        (path.parent / 'voice/zh/name.m4a').unlink()
        self.assert_invalid('unrecognized migrated media reference')
        self.assert_invalid('missing file voice/zh/name.m4a')


if __name__ == '__main__':
    unittest.main()
