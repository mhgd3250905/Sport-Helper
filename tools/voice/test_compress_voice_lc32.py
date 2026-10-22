"""Safety checks for resuming the approved voice conversion."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "compress_voice_lc32", Path(__file__).with_name("compress_voice_lc32.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ConversionSafetyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "assets/voice_lc32/v1"
        self.output.mkdir(parents=True)
        self.source = {"path": "assets/packs/_common/voice/zh/n.1.m4a",
                       "bytes": 4306, "sha256": "original"}
        self.entry = {"pack": "_common", "line": "n.1",
                      "source": {**self.source},
                      "output": {"path": "assets/voice_lc32/v1/_common/zh/n.1.m4a",
                                 "bytes": 4183, "sha256": "encoded",
                                 "decoded_duration_s": 0.417959, "duration_s": 0.394739}}
        self.report = {"schema_version": MODULE.SCHEMA_VERSION,
                       "version": MODULE.VERSION, "encoding": MODULE.ENCODING,
                       "output_root": "assets/voice_lc32/v1",
                       "source_inventory": {"before": [self.source]},
                       "clips": [self.entry]}

    def test_resume_rejects_changed_original_and_foreign_output(self):
        self.assertEqual(
            MODULE.validate_ledger(self.report, [self.source], self.root, self.output),
            {self.source["path"]: self.entry})
        with self.assertRaisesRegex(ValueError, "inventory changed"):
            MODULE.validate_ledger(self.report, [{**self.source, "sha256": "changed"}],
                                   self.root, self.output)
        (self.output / "unowned.m4a").write_bytes(b"user file")
        with self.assertRaisesRegex(ValueError, "Unrecorded output"):
            MODULE.validate_ledger(self.report, [self.source], self.root, self.output)
        self.assertEqual((self.output / "unowned.m4a").read_bytes(), b"user file")

    def test_resume_rejects_changed_output_path_and_duplicate_sources(self):
        self.entry["output"]["path"] = "assets/packs/_common/voice/zh/n.1.m4a"
        with self.assertRaisesRegex(ValueError, "output path mismatch"):
            MODULE.validate_ledger(self.report, [self.source], self.root, self.output)
        self.entry["output"]["path"] = "assets/voice_lc32/v1/_common/zh/n.1.m4a"
        self.report["clips"].append(self.entry)
        with self.assertRaisesRegex(ValueError, "Duplicate source"):
            MODULE.validate_ledger(self.report, [self.source], self.root, self.output)

    def test_runtime_manifest_omits_large_audit_fields_and_uses_decoded_length(self):
        result = MODULE.runtime_manifest(self.report)
        self.assertNotIn("source_inventory", result)
        self.assertNotIn("tools", result)
        clip = result["clips"][0]
        self.assertEqual(clip["decoded_ms"], 418)
        self.assertEqual(clip["duration_ms"], 395)
        self.assertEqual(clip["asset"], self.entry["output"]["path"])
        self.assertEqual(clip["sha256"], "encoded")
        self.assertEqual(clip["source"], {"asset": self.source["path"], "sha256": "original"})
        self.assertEqual(MODULE.output_relative(self.source["path"]).as_posix(),
                         "_common/zh/n.1.m4a")
        with self.assertRaisesRegex(ValueError, "Unexpected original"):
            MODULE.output_relative("assets/voice_lc32/v1/_common/zh/n.1.m4a")

    def test_output_validation_rejects_he_stereo_and_wrong_sample_rate(self):
        expected = {"codec": "aac", "profile": "LC", "channels": 1,
                    "sample_rate_hz": 22050}
        MODULE.assert_output(expected, "clip.m4a")
        for change in ({"profile": "HE-AAC"}, {"channels": 2}, {"sample_rate_hz": 44100}):
            with self.assertRaisesRegex(ValueError, "Unexpected output"):
                MODULE.assert_output({**expected, **change}, "clip.m4a")


if __name__ == "__main__":
    unittest.main()
