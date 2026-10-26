import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from prepare_posehub_images import ImagePreparationError, prepare_images


class ImagePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="posehub-images-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.output = self.root / "payload"
        self.index = self.root / "images-index.json"
        self.catalog = self.source / "catalog.json"
        self.data = {"format": "pose-hub-app-test-catalog@1", "actions": []}
        for name in ("one", "two"):
            files = {}
            for role in ("cover", "thumbnail"):
                relative = f"media/{name}/{role}.webp"
                payload = b"shared-cover" if role == "cover" else name.encode()
                target = self.source / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
                files[role] = {"path": relative, "bytes": len(payload),
                               "sha256": hashlib.sha256(payload).hexdigest()}
            self.data["actions"].append({"id": name, "files": files})

    def write_catalog(self):
        self.catalog.write_text(json.dumps(self.data), encoding="utf-8")
        return hashlib.sha256(self.catalog.read_bytes()).hexdigest()

    def prepare(self, **overrides):
        args = dict(source_pack=self.source, catalog=self.catalog,
                    catalog_sha256=self.write_catalog(), output=self.output,
                    index_output=self.index)
        args.update(overrides)
        return prepare_images(**args)

    def test_deduplicates_verified_content_and_reruns_without_changing_source(self):
        catalog_sha = self.write_catalog()
        before = {p.relative_to(self.source): (p.read_bytes(), p.stat().st_mtime_ns)
                  for p in self.source.rglob("*") if p.is_file()}
        result = prepare_images(source_pack=self.source, catalog=self.catalog,
                                catalog_sha256=catalog_sha, output=self.output,
                                index_output=self.index)
        self.assertEqual(result["imageReferences"], 4)
        self.assertEqual(result["uniqueFiles"], 3)
        self.assertEqual(result["uniqueBytes"], len(b"shared-cover") + 6)
        index = json.loads(self.index.read_text(encoding="utf-8"))
        for relative, spec in index["files"].items():
            output = self.output / f"{spec['sha256']}.webp"
            self.assertEqual(output.read_bytes(), (self.source / relative).read_bytes())
            self.assertEqual(spec["asset"], f"assets/posehub/images/{output.name}")
        index_before = self.index.read_bytes()
        # Do not rewrite the source catalog during the idempotent generation.
        prepare_images(source_pack=self.source, catalog=self.catalog,
                       catalog_sha256=result["catalogSha256"], output=self.output,
                       index_output=self.index)
        self.assertEqual(self.index.read_bytes(), index_before)
        after = {p.relative_to(self.source): (p.read_bytes(), p.stat().st_mtime_ns)
                 for p in self.source.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_rejects_bad_catalog_or_source_hash_before_writing_outputs(self):
        with self.assertRaisesRegex(ImagePreparationError, "Catalog SHA256"):
            self.prepare(catalog_sha256="0" * 64)
        image = self.source / self.data["actions"][0]["files"]["cover"]["path"]
        image.write_bytes(b"changed outside the tool")
        with self.assertRaisesRegex(ImagePreparationError, "size/SHA256 mismatch"):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.assertFalse(self.index.exists())

    def test_rejects_escaped_paths_and_source_overlap(self):
        descriptor = self.data["actions"][0]["files"]["cover"]
        original = descriptor["path"]
        for invalid in ("../outside.webp", "/outside.webp", "media\\outside.webp",
                        "media/%2e%2e/outside.webp", "C:/outside.webp"):
            with self.subTest(path=invalid):
                descriptor["path"] = invalid
                with self.assertRaises(ImagePreparationError):
                    self.prepare()
                self.assertFalse(self.output.exists())
        descriptor["path"] = original
        with self.assertRaisesRegex(ImagePreparationError, "source pack"):
            self.prepare(output=self.source / "generated")

    def test_existing_media_and_index_conflicts_are_never_overwritten(self):
        self.prepare()
        target = next(self.output.glob("*.webp"))
        target.write_bytes(b"existing conflicting output")
        index_before = self.index.read_bytes()
        with self.assertRaises(ImagePreparationError):
            self.prepare()
        self.assertEqual(target.read_bytes(), b"existing conflicting output")
        self.assertEqual(self.index.read_bytes(), index_before)
        self.index.write_bytes(b"existing conflicting index")
        with self.assertRaisesRegex(ImagePreparationError, "immutable index"):
            self.prepare()
        self.assertEqual(self.index.read_bytes(), b"existing conflicting index")

    def test_budget_error_reports_unique_bytes_without_creating_payload(self):
        self.data["actions"][0]["files"]["thumbnail"]["bytes"] = 20_000_001
        with self.assertRaisesRegex(ImagePreparationError, "20,000,000"):
            self.prepare()
        self.assertFalse(self.output.exists())
        self.assertFalse(self.index.exists())


    def test_versioned_asset_prefix_is_supported_but_cannot_escape_image_root(self):
        catalog_sha = self.write_catalog()
        prefix = f"assets/posehub/images/{catalog_sha}/"
        self.prepare(asset_prefix=prefix)
        index = json.loads(self.index.read_text(encoding="utf-8"))
        for spec in index["files"].values():
            self.assertEqual(spec["asset"], f"{prefix}{spec['sha256']}.webp")
        for invalid in ("assets/other/", "assets/posehub/images/../outside/"):
            with self.assertRaises(ImagePreparationError):
                self.prepare(asset_prefix=invalid)


if __name__ == "__main__":
    unittest.main()
