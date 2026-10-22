"""Prevent stale encoded speech and accidental packaging of both inventories."""
import json
import tempfile
import unittest
from pathlib import Path

import build_packs as B


class VoiceBundlePackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='voice-bundle-packaging-')
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name).resolve()
        self.root = self.repo / 'assets/packs'
        self.original = self.root / '_common/voice/zh/n.1.m4a'
        self.original.parent.mkdir(parents=True)
        self.original.write_bytes(b'original aac')
        self.target = self.repo / 'assets/voice_lc32/v1/_common/zh/n.1.m4a'
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b'encoded aac')
        self.manifest = self.repo / 'assets/voice_lc32/v1/manifest.json'
        clip = {'pack': '_common', 'line': 'n.1', 'lang': 'zh',
                'asset': self.target.relative_to(self.repo).as_posix(),
                'bytes': self.target.stat().st_size, 'sha256': B.P.sha256(self.target),
                'source': {'asset': self.original.relative_to(self.repo).as_posix(),
                           'sha256': B.P.sha256(self.original)}}
        self.manifest.write_text(json.dumps({'schema_version': 1, 'clips': [clip]}), encoding='utf-8')
        descriptor = {'asset': self.manifest.relative_to(self.repo).as_posix(),
                      'bytes': self.manifest.stat().st_size, 'sha256': B.P.sha256(self.manifest)}
        (self.root / 'index.json').write_text(json.dumps({'voiceBundle': descriptor}), encoding='utf-8')
        (self.root / '_common/pack.json').write_text(json.dumps({
            'chimes': {'tick': {'file': 'chime/tick.m4a'}}, 'voice': {'languages': ['zh']},
        }), encoding='utf-8')

    def test_selected_bundle_excludes_original_speech_but_keeps_chimes(self):
        block = B.pubspec_block(self.root, self.repo, [self.root / '_common'])
        self.assertNotIn('    - assets/packs/_common/voice/zh/', block)
        self.assertIn('    - assets/packs/_common/chime/', block)
        self.assertIn('    - assets/voice_lc32/v1/', block)
        self.assertIn('    - assets/voice_lc32/v1/_common/zh/', block)

    def test_regenerated_original_rejects_stale_compressed_bundle(self):
        self.original.write_bytes(b'newly generated speech')
        with self.assertRaisesRegex(ValueError, 'source changed'):
            B.pubspec_block(self.root, self.repo, [self.root / '_common'])

    def test_changed_target_or_manifest_is_rejected(self):
        self.target.write_bytes(b'broken encoded file')
        with self.assertRaisesRegex(ValueError, 'clip size/sha256 mismatch'):
            B.pubspec_block(self.root, self.repo, [self.root / '_common'])
        self.manifest.write_text('{}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'manifest size/sha256 mismatch'):
            B.pubspec_block(self.root, self.repo, [self.root / '_common'])


if __name__ == '__main__':
    unittest.main()
