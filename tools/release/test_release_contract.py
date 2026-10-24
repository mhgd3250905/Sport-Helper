"""Release identity and platform configuration contracts; no credentials read."""
import re
import subprocess
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

    def test_launcher_name_matches_store_identity(self):
        strings = ET.parse(ROOT / "android/app/src/main/res/values/strings.xml").getroot()
        self.assertEqual(strings.find("string[@name='app_name']").text, "智能健身助手")

    def test_app_runtime_and_assets_match_the_accepted_version(self):
        changed = subprocess.run(
            ["git", "diff", "--name-only", "f5332bfe3746ecbf69d3f5e48c71ba5c90812499", "--",
             "lib", "assets", "android/app/src/main/AndroidManifest.xml",
             "android/app/src/main/res/values/strings.xml", "ios/Runner/Info.plist"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.splitlines()
        self.assertEqual(changed, ["lib/app/build_info.dart"])

    def test_ios_production_scheme_has_matching_configurations(self):
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        scheme = ET.parse(ROOT / "ios/Runner.xcodeproj/xcshareddata/xcschemes/production.xcscheme")
        configurations = {node.get("buildConfiguration") for node in scheme.getroot()
                          if node.get("buildConfiguration")}
        self.assertEqual(configurations, {"Debug-production", "Release-production", "Profile-production"})
        for config in configurations:
            self.assertEqual(project.count(f'name = "{config}";'), 3)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = com.ugk.smartfit;", project)

    def test_ios_configuration_references_preserve_target_ownership(self):
        project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        config_pattern = re.compile(
            r"(?ms)^\t\t(?P<id>[A-F0-9]{24}) /\* "
            r"(?P<name>(?:Debug|Release|Profile)(?:-production)?) \*/ = \{\n"
            r"\t\t\tisa = XCBuildConfiguration;\n(?P<body>.*?)^\t\t\};"
        )
        definitions = {match["id"]: match.groupdict()
                       for match in config_pattern.finditer(project)}
        self.assertEqual(len(definitions), 18)
        list_pattern = re.compile(
            r"(?ms)^\t\t(?P<id>[A-F0-9]{24}) /\* [^\r\n]* \*/ = \{\n"
            r"\t\t\tisa = XCConfigurationList;\n"
            r"\t\t\tbuildConfigurations = \(\n(?P<refs>.*?)^\t\t\t\);"
        )
        # The pre-existing Project, Runner and RunnerTests ownership is fixed.
        original_owners = {
            "97C146E91CF9000F007C117D": {
                "97C147031CF9000F007C117D", "97C147041CF9000F007C117D", "249021D3217E4FDB00AE95B9"},
            "97C147051CF9000F007C117D": {
                "97C147061CF9000F007C117D", "97C147071CF9000F007C117D", "249021D4217E4FDB00AE95B9"},
            "331C8087294A63A400263BE5": {
                "331C8088294A63A400263BE5", "331C8089294A63A400263BE5", "331C808A294A63A400263BE5"},
        }
        lists = list(list_pattern.finditer(project))
        self.assertEqual({item["id"] for item in lists}, set(original_owners))
        all_production_refs = []
        for item in lists:
            with self.subTest(configuration_list=item["id"]):
                refs = re.findall(r"\b([A-F0-9]{24}) /\*", item["refs"])
                self.assertEqual(len(refs), 6)
                self.assertEqual(len(set(refs)), 6)
                originals = {ref for ref in refs
                             if not definitions[ref]["name"].endswith("-production")}
                self.assertEqual(originals, original_owners[item["id"]])
                production = {definitions[ref]["name"]: ref for ref in refs
                              if definitions[ref]["name"].endswith("-production")}
                self.assertEqual(set(production), {
                    "Debug-production", "Release-production", "Profile-production"})
                for ref in originals:
                    original = definitions[ref]
                    production_ref = production[original["name"] + "-production"]
                    clone = definitions[production_ref]
                    self.assertEqual(
                        clone["body"].replace(
                            f'name = "{clone["name"]}";', f'name = {original["name"]};'),
                        original["body"],
                    )
                    all_production_refs.append(production_ref)
        self.assertEqual(len(set(all_production_refs)), 9)
        for ref in all_production_refs:
            # Exactly one definition and one reference in the owning list.
            self.assertEqual(len(re.findall(r"\b" + ref + r"\b", project)), 2)

    def test_build_helper_never_injects_ai_or_download_credentials(self):
        script = (ROOT / "tools/release/build_play_bundle.ps1").read_text(encoding="utf-8")
        self.assertNotIn("--dart-define=SMARTFIT_AI_TOKEN=", script)
        self.assertNotIn("--dart-define=SMARTFIT_AI_BASE_URL=", script)
        self.assertNotIn("--dart-define-from-file=", script)
        self.assertIn("--enforce-lockfile", script)
        self.assertIn("--release --flavor production --no-pub", script)


if __name__ == "__main__":
    unittest.main()
