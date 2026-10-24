"""Release identity and platform configuration contracts; no credentials read."""
import re
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
SDK = "f684e02f38e652633c23fa8946a53d02b6aa3ea2"


class ReleaseContractTest(unittest.TestCase):
    def test_version_identity(self):
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        version = re.search(r"(?m)^version: (1\.0\.0)\+(\d+)$", pubspec)
        self.assertIsNotNone(version)
        self.assertGreater(int(version[2]), 22)
        identity = (ROOT / "lib/app/build_info.dart").read_text(encoding="utf-8")
        self.assertIn(f"version = '{version[1]}+{version[2]}'", identity)

    def test_both_sdk_dependencies_are_immutable(self):
        pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"(?m)^\s+ref: (\S+)$", pubspec), [SDK, SDK])
        lock = (ROOT / "pubspec.lock").read_text(encoding="utf-8")
        self.assertEqual(lock.count("resolved-ref: " + SDK), 2)
        self.assertFalse((ROOT / "pubspec_overrides.yaml").exists())

    def test_application_id_and_upload_signer(self):
        gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
        self.assertIn('applicationId = "com.ugk.smartfit"', gradle)
        self.assertIn('environmentVariable("SMARTFIT_SIGNING_PROPERTIES")', gradle)
        self.assertNotIn('signingConfigs.getByName("debug")', gradle)
        self.assertIn('signingConfigs.getByName("upload")', gradle)

    def test_android_backup_is_disabled(self):
        app = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml").getroot().find("application")
        self.assertEqual(app.get(ANDROID + "allowBackup"), "false")
        self.assertEqual(app.get(ANDROID + "fullBackupContent"), "false")
        rules = ET.parse(ROOT / "android/app/src/main/res/xml/data_extraction_rules.xml").getroot()
        required = {"root", "file", "database", "sharedpref", "device_root", "device_file",
                    "device_database", "device_sharedpref", "external"}
        for scope in ("cloud-backup", "device-transfer"):
            exclusions = rules.find(scope).findall("exclude")
            self.assertEqual({item.get("domain") for item in exclusions}, required)
            self.assertTrue(all(item.get("path") == "." for item in exclusions))

    def test_ios_production_scheme_has_matching_configurations(self):
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        scheme = ET.parse(ROOT / "ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme")
        configurations = {node.get("buildConfiguration") for node in scheme.getroot()
                          if node.get("buildConfiguration")}
        self.assertEqual(configurations, {"Debug-production", "Release-production", "Profile-production"})
        for config in configurations:
            self.assertEqual(project.count(f'name = "{config}";'), 3)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.ugk.smartfit;", project)

    def test_build_helper_never_injects_ai_or_download_credentials(self):
        script = (ROOT / "tools/release/build_play_bundle.ps1").read_text(encoding="utf-8")
        self.assertNotIn("--dart-define=SMARTFIT_AI_TOKEN=", script)
        self.assertNotIn("--dart-define=SMARTFIT_AI_BASE_URL=", script)
        self.assertNotIn("--dart-define-from-file=", script)
        self.assertIn("--enforce-lockfile", script)
        self.assertIn("--release --flavor production --no-pub", script)


if __name__ == "__main__":
    unittest.main()
