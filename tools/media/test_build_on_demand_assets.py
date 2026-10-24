"""Regression coverage for release integrity and the small bundle contract."""

import json
from pathlib import Path
import tempfile
import unittest

from build_on_demand_assets import APP_ROOT, AssetError, build, digest


class BuiltinAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "workspace"
        self.source = self.root / "release" / "v0.3.0-app"
        (self.app / "assets" / "packs" / "action-00").mkdir(parents=True)
        (self.source / "packages").mkdir(parents=True)
        self.pubspec = ("name: fixture\nversion: 0.1.0+9\n"
                        "dependencies:\n  fixture: 1.2.3\nflutter:\n"
                        "  assets:\n    - assets/cutouts/ # legacy\n"
                        "    - assets/packs/action-00/\n  fonts: []\n")
        (self.app / "pubspec.yaml").write_text(self.pubspec, encoding="utf-8")
        self.metadata = self.app / "assets" / "packs" / "action-00" / "pack.json"
        self.metadata.write_text('{"media":{"video":"demo.mp4"},"sha256":"historic"}', encoding="utf-8")
        self.legacy = [self.metadata.parent / "demo.mp4", self.metadata.parent / "cover-light.jpg"]
        for path in self.legacy:
            path.write_bytes(b"old-media")
        self.voice = self.metadata.parent / "voice" / "zh" / "intro.m4a"
        self.voice.parent.mkdir(parents=True)
        self.voice.write_bytes(b"preserved-voice")
        self.actions = [f"action-{i:02}" for i in range(33)]
        self.manifest = {"version": "0.3.0", "mainCommit": "fixture",
                         "actions": [{"id": action, "releaseEligible": False} for action in self.actions],
                         "packages": {}}
        for package_id in ("builtin", "realistic-dark", "common"):
            ids = self.actions[:32] if package_id == "builtin" else self.actions[32:]
            if package_id == "common":
                ids = self.actions
                paths = [f"common-lossy/{group}/{action}.webp" for group in ("covers", "thumbs") for action in ids]
            else:
                paths = [f"../v0.3.0/realistic/dark/{action}.mp4" for action in ids]
            entries = []
            for relative in paths:
                path = self.source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                content = relative.encode("utf-8")
                path.write_bytes(content)
                entries.append({"path": relative, "bytes": len(content), "sha256": digest(path)})
            path = self.source / "packages" / f"{package_id}.json"
            path.write_text(json.dumps({"files": entries}), encoding="utf-8")
            self.manifest["packages"][package_id] = {
                "actionIds": ids, "fileCount": len(entries),
                "totalBytes": sum(item["bytes"] for item in entries),
                "manifest": {"path": f"packages/{package_id}.json", "bytes": path.stat().st_size,
                             "sha256": digest(path)}}
        self.write_manifest()

    def write_manifest(self):
        (self.source / "app-manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def snapshot(self, root):
        return {path.relative_to(root).as_posix(): digest(path)
                for path in root.rglob("*") if path.is_file()}

    def test_exact_bundle_and_source_voice_metadata_unchanged(self):
        source_before = self.snapshot(self.source.parent)
        metadata_before, voice_before = self.metadata.read_bytes(), self.voice.read_bytes()
        report = build(self.source, self.app, apply=True)
        assets = self.app / "assets" / "training_media"
        self.assertEqual(len(list(assets.rglob("*.mp4"))), 32)
        self.assertEqual(report["groups"]["videos"]["files"], 32)
        self.assertEqual(report["groups"]["covers"]["files"], 33)
        manifests = {path.name for path in (assets / "v0.3.0-app" / "packages").glob("*.json")}
        self.assertEqual(manifests, {"builtin.json", "realistic-dark.json"})
        self.assertEqual(self.snapshot(self.source.parent), source_before)
        self.assertEqual(self.metadata.read_bytes(), metadata_before)
        self.assertEqual(self.voice.read_bytes(), voice_before)
        self.assertTrue(all(not path.exists() for path in self.legacy))
        after = (self.app / "pubspec.yaml").read_text("utf-8")
        self.assertEqual(after.split("flutter:")[0], self.pubspec.split("flutter:")[0])
        self.assertNotIn("assets/cutouts/", after)
        self.assertEqual(report, build(self.source, self.app, apply=True))
        self.assertEqual(report, build(self.source, self.app, verify_only=True))

    def test_preview_does_not_change_workspace(self):
        before = self.snapshot(self.root)
        report = build(self.source, self.app)
        self.assertEqual(before, self.snapshot(self.root))
        self.assertEqual(report["previewLegacyRemoval"]["files"], 2)
        self.assertFalse(report["validatedOutput"])

    def test_corrupt_video_rejected_before_legacy_cleanup(self):
        path = self.source.parent / "v0.3.0" / "realistic" / "dark" / "action-00.mp4"
        path.write_bytes(b"corrupt")
        before = self.snapshot(self.app)
        with self.assertRaisesRegex(AssetError, "mismatch"):
            build(self.source, self.app, apply=True)
        self.assertEqual(before, self.snapshot(self.app))

    def test_corrupt_common_manifest_rejected(self):
        path = self.source / "packages" / "common.json"
        path.write_text("{}", encoding="utf-8")
        with self.assertRaisesRegex(AssetError, "mismatch"):
            build(self.source, self.app, apply=True)
        self.assertTrue(self.legacy[0].exists())

    def test_unrecognized_existing_output_preserved(self):
        path = self.app / "assets" / "training_media" / "private.txt"
        path.parent.mkdir(parents=True)
        path.write_text("keep me", encoding="utf-8")
        before = self.snapshot(self.app)
        with self.assertRaisesRegex(AssetError, "Unexpected existing asset"):
            build(self.source, self.app, apply=True)
        self.assertEqual(before, self.snapshot(self.app))

    def test_path_traversal_rejected_even_with_matching_manifest_hash(self):
        path = self.source / "packages" / "builtin.json"
        submanifest = json.loads(path.read_bytes())
        submanifest["files"][0]["path"] = "../../outside.mp4"
        path.write_text(json.dumps(submanifest), encoding="utf-8")
        descriptor = self.manifest["packages"]["builtin"]["manifest"]
        descriptor["bytes"], descriptor["sha256"] = path.stat().st_size, digest(path)
        self.write_manifest()
        with self.assertRaisesRegex(AssetError, "Unexpected or duplicate media path"):
            build(self.source, self.app, apply=True)
        self.assertTrue(self.legacy[0].exists())

    def test_post_build_corruption_is_detected(self):
        build(self.source, self.app, apply=True)
        path = self.app / "assets" / "training_media" / "v0.3.0" / "realistic" / "dark" / "action-00.mp4"
        path.write_bytes(b"corrupt")
        with self.assertRaisesRegex(AssetError, "mismatch"):
            build(self.source, self.app, verify_only=True)


class CheckedInBundleTests(unittest.TestCase):
    def test_offline_theme_assets_match_original_manifests_and_their_index(self):
        root = APP_ROOT / "assets" / "training_media"
        files = [path for path in root.rglob("*") if path.is_file()]
        self.assertGreater(sum(path.stat().st_size for path in files), 85_000_000)
        self.assertLess(sum(path.stat().st_size for path in files), 100_000_000)
        self.assertEqual(len(files), 946)
        main_paths = list(root.rglob("app-manifest.json"))
        self.assertEqual(len(main_paths), 1)
        app = main_paths[0].parent
        manifest = json.loads(main_paths[0].read_bytes())
        self.assertEqual(len(list(root.rglob("*.mp4"))), 191)
        self.assertEqual({path.relative_to(app).as_posix() for path in app.rglob("*.json")},
                         {"app-manifest.json", "assets-index.json", "packages/builtin.json", "packages/realistic-dark.json", "packages/realistic-light.json"})
        references = {}
        for package in ("builtin", "realistic-dark", "realistic-light"):
            descriptor = manifest["packages"][package]["manifest"]
            path = app / descriptor["path"]
            self.assertEqual(path.stat().st_size, descriptor["bytes"])
            self.assertEqual(digest(path), descriptor["sha256"])
            for ref in json.loads(path.read_bytes())['files']:
                references[ref['path']] = ref
        builtin = json.loads((app / "packages" / "builtin.json").read_bytes())
        for descriptor in builtin["files"]:
            path = app / descriptor["path"]
            self.assertEqual(path.stat().st_size, descriptor["bytes"])
            self.assertEqual(digest(path), descriptor["sha256"])
        action_ids = {action["id"] for action in manifest["actions"]}
        for group in ("covers", "thumbs"):
            self.assertEqual({path.stem for path in (app / "common-lossy" / group).glob("*.webp")}, action_ids)
        local = json.loads((app / 'assets-index.json').read_bytes())
        self.assertEqual(local['sourceAppManifestSha256'], digest(main_paths[0]))
        self.assertEqual(len(local['actions']), 93)
        for aid, themes in local['actions'].items():
            self.assertEqual(set(themes), {'dark', 'light'})
            for theme, media in themes.items():
                for role in ('video', 'poster', 'thumbnail'):
                    descriptor = media[role]
                    path = APP_ROOT / descriptor['asset']
                    self.assertTrue(path.is_file())
                    self.assertEqual(path.stat().st_size, descriptor['bytes'])
                    self.assertEqual(digest(path), descriptor['sha256'])
                ref = references[f'../v0.3.0/realistic/{theme}/{aid}.mp4']
                self.assertEqual(media['video']['sha256'], ref['sha256'])
                self.assertEqual(media['video']['bytes'], ref['bytes'])
                self.assertIn('/' + theme + '/', media['poster']['asset'])


class OfflineThemeBuildTests(BuiltinAssetsTests):
    def setUp(self):
        super().setUp()
        from PIL import Image
        self.manifest['packages']['builtin']['kind'] = 'video'
        self.manifest['packages']['realistic-dark']['kind'] = 'video'
        self.selected = ['action-00', 'action-32']
        (self.app / 'assets/packs/index.json').write_text(json.dumps({'packs': [
            {'id': aid, 'kind': 'exercise'} for aid in self.selected]}), encoding='utf-8')
        for theme in ('dark', 'light'):
            keyframes = []
            for aid in self.selected:
                relative = f'../v0.3.0/realistic/{theme}/keyframes/{aid}_2.webp'
                path = self.source / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                Image.new('RGB', (32, 32), '#f3f1ef' if theme == 'light' else '#101013').save(path, format='WEBP', lossless=True)
                keyframes.append({'path': relative, 'bytes': path.stat().st_size, 'sha256': digest(path)})
            self.put_package(f'keyframes-realistic-{theme}', 'keyframes', keyframes)
        light_videos = []
        for aid in self.selected:
            relative = f'../v0.3.0/realistic/light/{aid}.mp4'
            path = self.source / relative
            path.write_bytes(relative.encode())
            light_videos.append({'path': relative, 'bytes': path.stat().st_size, 'sha256': digest(path)})
        self.put_package('realistic-light', 'video', light_videos)
        self.write_manifest()

    def put_package(self, name, kind, files):
        path = self.source / f'packages/{name}.json'
        path.write_text(json.dumps({'files': files}), encoding='utf-8')
        self.manifest['packages'][name] = {
            'kind': kind, 'fileCount': len(files), 'totalBytes': sum(f['bytes'] for f in files),
            'manifest': {'path': f'packages/{name}.json', 'bytes': path.stat().st_size, 'sha256': digest(path)}}

    def test_two_themes_are_offline_and_source_metadata_voice_unchanged(self):
        before = self.snapshot(self.source.parent)
        metadata, voice = self.metadata.read_bytes(), self.voice.read_bytes()
        report = build(self.source, self.app, apply=True, offline_themes=True)
        self.assertEqual(report['offlineActionCount'], 2)
        self.assertEqual(report['offlineThemes'], ['dark', 'light'])
        index = json.loads((self.app / 'assets/training_media/v0.3.0-app/assets-index.json').read_bytes())
        for aid in self.selected:
            for theme in ('dark', 'light'):
                for role in ('video', 'poster', 'thumbnail'):
                    ref = index['actions'][aid][theme][role]
                    self.assertEqual(digest(self.app / ref['asset']), ref['sha256'])
        self.assertEqual(before, self.snapshot(self.source.parent))
        self.assertEqual(metadata, self.metadata.read_bytes())
        self.assertEqual(voice, self.voice.read_bytes())
        self.assertEqual(report, build(self.source, self.app, verify_only=True, offline_themes=True))

    def test_corrupt_light_clip_is_rejected_before_changes(self):
        (self.source.parent / 'v0.3.0/realistic/light/action-00.mp4').write_bytes(b'bad')
        before = self.snapshot(self.app)
        with self.assertRaisesRegex(AssetError, 'mismatch'):
            build(self.source, self.app, apply=True, offline_themes=True)
        self.assertEqual(before, self.snapshot(self.app))

    def test_missing_light_still_requests_export_instead_of_dark_fallback(self):
        self.put_package('keyframes-realistic-light', 'keyframes', [])
        self.write_manifest()
        before = self.snapshot(self.app)
        with self.assertRaisesRegex(AssetError, 'Missing light exported still'):
            build(self.source, self.app, apply=True, offline_themes=True)
        self.assertEqual(before, self.snapshot(self.app))

    def test_existing_still_with_no_video_is_indexed_without_fake_video_path(self):
        self.put_package('realistic-light', 'video', [])
        self.write_manifest()
        build(self.source, self.app, apply=True, offline_themes=True)
        index = json.loads((self.app / 'assets/training_media/v0.3.0-app/assets-index.json').read_bytes())
        self.assertIsNone(index['actions']['action-00']['light']['video'])
        self.assertIn('/light/', index['actions']['action-00']['light']['poster']['asset'])


if __name__ == "__main__":
    unittest.main()
