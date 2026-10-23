"""Resource integrity and mask geometry checks; no Flutter/emulator required."""

from __future__ import annotations

import io
import json
import math
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from PIL import Image

import build_icons as icons


class IconAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.assets = icons.build_assets()

    def test_reviewed_sources_are_full_bleed_and_unchanged(self):
        for variant in icons.VARIANTS:
            with self.subTest(variant=variant):
                image, _ = icons.read_source(icons.ROOT, variant)
                self.assertEqual(image.size, (1024, 1024))
                self.assertEqual(image.mode, "RGB")

    def test_all_generated_files_match_checked_in_bytes(self):
        for path, content in self.assets.items():
            with self.subTest(path=path):
                self.assertEqual((icons.ROOT / path).read_bytes(), content)

    def test_selected_production_icons_match_snapshot_and_generator_never_writes_them(self):
        self.assertEqual(len(icons.protected_assets(icons.ROOT)), 38)
        self.assertNotIn("android/app/src/main", "\n".join(self.assets))
        self.assertNotIn("AppIcon.appiconset/", "\n".join(self.assets))
        project = (icons.ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text("utf-8")
        self.assertEqual(project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"), 3)
        self.assertNotIn("IconA.internal.xcconfig", project)
        self.assertNotIn("IconB.internal.xcconfig", project)
        self.assertNotIn("IconA2.internal.xcconfig", project)

    def test_local_default_android_and_ios_slots_use_pending_a2(self):
        expected = icons.selected_production_assets(self.assets)
        self.assertEqual(len(expected), 38)
        for path, content in expected.items():
            with self.subTest(path=path):
                actual = (icons.ROOT / path).read_bytes()
                if path.endswith("/Contents.json"):
                    self.assertEqual(json.loads(actual), json.loads(content))
                    self.assertEqual(len(json.loads(actual)["images"]), 19)
                else:
                    self.assertEqual(actual, content)
        namespace = "{http://schemas.android.com/apk/res/android}"
        manifest = ET.parse(icons.ROOT / "android/app/src/main/AndroidManifest.xml")
        application = manifest.getroot().find("application")
        self.assertEqual(application.get(namespace + "icon"), "@mipmap/ic_launcher")
        self.assertEqual(application.get(namespace + "roundIcon"), "@mipmap/ic_launcher_round")
        selection = icons.verify_selected_production(
            icons.ROOT, self.assets, icons.protected_assets(icons.ROOT)
        )
        self.assertEqual(selection["variant"], "A2")
        self.assertEqual(selection["status"], "awaiting_user_visual_confirmation")
        self.assertFalse(selection["productionReleaseApproved"])
        self.assertFalse(selection["brandMergeApproved"])

    def test_rebaselining_wrong_production_artwork_is_rejected_without_repair(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            selection = root / "tools/branding/production-icon-selection.json"
            selection.parent.mkdir(parents=True)
            selection.write_bytes((icons.ROOT / selection.relative_to(root)).read_bytes())
            expected = icons.selected_production_assets(self.assets)
            for path, content in expected.items():
                destination = root / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
            changed = "android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
            wrong = self.assets[
                "android/app/src/internal/iconVariants/A/res/mipmap-mdpi/ic_launcher.png"
            ]
            (root / changed).write_bytes(wrong)
            records = {path: icons.sha256((root / path).read_bytes()) for path in expected}
            (root / "tools/branding/production-icons.sha256.json").write_bytes(
                icons.json_bytes(records)
            )
            protected = icons.protected_assets(root)
            with self.assertRaisesRegex(ValueError, "Default production A2 differs"):
                icons.verify_selected_production(root, self.assets, protected)
            self.assertEqual((root / changed).read_bytes(), wrong)

    def test_preview_preserves_all_three_candidates_and_labels_the_full_body_zoom(self):
        self.assertEqual(set(icons.VARIANTS), {"A", "B", "A2"})
        self.assertEqual(icons.VARIANT_LABELS["A2"], "enlarged full body")
        with tempfile.TemporaryDirectory() as temporary:
            preview = Path(temporary) / "three-candidates.png"
            icons.mask_preview(icons.ROOT, preview)
            with Image.open(preview) as image:
                self.assertEqual(image.size, (1500, 1560))
                # The final candidate's full 432px image must fit below its label.
                last = image.crop((28, 1108, 460, 1540))
                self.assertGreater(len(last.getcolors(last.width * last.height)), 100)

    def test_android_whole_foreground_fits_safe_circle_at_every_density(self):
        for variant in icons.VARIANTS:
            for density, scale in icons.DENSITIES.items():
                with self.subTest(variant=variant, density=density):
                    directory = f"android/app/src/internal/iconVariants/{variant}/res/mipmap-{density}"
                    foreground = Image.open(io.BytesIO(self.assets[f"{directory}/ic_launcher_foreground.png"]))
                    background = Image.open(io.BytesIO(self.assets[f"{directory}/ic_launcher_background.png"]))
                    expected_size = round(108 * scale)
                    self.assertEqual(foreground.size, (expected_size, expected_size))
                    self.assertEqual(background.size, foreground.size)
                    self.assertEqual(background.mode, "RGB")
                    self.assertEqual(foreground.mode, "RGBA")
                    alpha = foreground.getchannel("A")
                    left, top, right, bottom = alpha.getbbox()
                    side = round(46 * scale)
                    self.assertEqual((right - left, bottom - top), (side, side))
                    self.assertEqual(alpha.crop((left, top, right, bottom)).getextrema(), (255, 255))
                    center = expected_size / 2
                    safe_radius = 33 * scale
                    for x, y in ((left, top), (left, bottom), (right, top), (right, bottom)):
                        self.assertLessEqual(math.hypot(x - center, y - center), safe_radius)

    def test_android_legacy_icons_have_all_standard_sizes(self):
        for variant in icons.VARIANTS:
            for density, scale in icons.DENSITIES.items():
                directory = f"android/app/src/internal/iconVariants/{variant}/res/mipmap-{density}"
                for name in ("ic_launcher", "ic_launcher_round"):
                    with self.subTest(variant=variant, density=density, name=name):
                        image = Image.open(io.BytesIO(self.assets[f"{directory}/{name}.png"]))
                        self.assertEqual(image.size, (round(48 * scale),) * 2)
                        self.assertEqual(image.mode, "RGB")

    def test_adaptive_xml_resolves_both_layers_with_no_fixed_mask(self):
        namespace = "{http://schemas.android.com/apk/res/android}"
        for variant in icons.VARIANTS:
            for name in ("ic_launcher", "ic_launcher_round"):
                path = f"android/app/src/internal/iconVariants/{variant}/res/mipmap-anydpi-v26/{name}.xml"
                tree = ET.fromstring(self.assets[path])
                self.assertEqual(tree.tag, "adaptive-icon")
                self.assertEqual(tree.find("foreground").get(namespace + "drawable"), "@mipmap/ic_launcher_foreground")
                self.assertEqual(tree.find("background").get(namespace + "drawable"), "@mipmap/ic_launcher_background")

    def test_ios_every_original_slot_is_opaque_and_correctly_sized(self):
        original = json.loads((icons.ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json").read_text("utf-8"))
        for variant in icons.VARIANTS:
            directory = f"ios/Runner/Assets.xcassets/AppIcon{variant}.appiconset"
            contents = json.loads(self.assets[f"{directory}/Contents.json"])
            self.assertEqual(contents, original)
            for slot in contents["images"]:
                with self.subTest(variant=variant, slot=slot):
                    image = Image.open(io.BytesIO(self.assets[f"{directory}/{slot['filename']}"]))
                    size = round(float(slot["size"].split("x")[0]) * int(slot["scale"].rstrip("x")))
                    self.assertEqual(image.size, (size, size))
                    self.assertEqual(image.mode, "RGB")
            self.assertTrue(any(slot["idiom"] == "ios-marketing" and slot["size"] == "1024x1024" for slot in contents["images"]))

    def test_ios_overrides_do_not_change_identity_or_existing_scheme(self):
        for variant in icons.VARIANTS:
            config = self.assets[f"ios/Flutter/Icon{variant}.internal.xcconfig"].decode("utf-8")
            assignments = [line for line in config.splitlines() if line and not line.startswith("//")]
            self.assertEqual(assignments, [f"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon{variant}"])

    def test_extra_png_in_each_owned_resource_root_is_rejected_without_deletion(self):
        for directory in icons.OWNED_RESOURCE_ROOTS:
            with self.subTest(directory=directory), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                extra = root / directory / "stale.png"
                extra.parent.mkdir(parents=True)
                payload = icons.png_bytes(Image.new("RGB", (1, 1), "red"))
                extra.write_bytes(payload)
                with self.assertRaisesRegex(ValueError, "Unexpected candidate icon files") as error:
                    icons.verify_owned_inventory(root, self.assets)
                self.assertIn(f"{directory}/stale.png", str(error.exception))
                self.assertEqual(extra.read_bytes(), payload)

    def test_inventory_scanner_ignores_unowned_tooling_and_production_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for path in (
                "tools/branding/build_icon_candidates.ps1",
                "android/app/src/internal/res/values/strings.xml",
                "android/app/src/main/res/mipmap-mdpi/ic_launcher.png",
                "ios/Runner/Assets.xcassets/AppIcon.appiconset/other.png",
            ):
                destination = root / path
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(b"unrelated")
            icons.verify_owned_inventory(root, self.assets)

    def test_inventory_scanner_accepts_expected_candidate_files_and_empty_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            expected_path = "android/app/src/internal/iconVariants/A/res/mipmap-mdpi/ic_launcher.png"
            expected = root / expected_path
            expected.parent.mkdir(parents=True)
            expected.write_bytes(self.assets[expected_path])
            (root / "android/app/src/internal/iconVariants/B/res/drawable").mkdir(parents=True)
            icons.verify_owned_inventory(root, self.assets)


if __name__ == "__main__":
    unittest.main()
