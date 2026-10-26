#!/usr/bin/env python3
"""Verify and copy an immutable, content-addressed PoseHub image payload.

Only cover/thumbnail files declared by the explicitly hashed catalog are read.
Existing outputs are accepted only when identical; neither source files nor
conflicting outputs are overwritten. A new catalog can use a new staging index.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

INDEX_FORMAT = "smartfit-posehub-bundled-images@1"
ASSET_PREFIX = "assets/posehub/images/"
MAX_IMAGE_BYTES = 20_000_000
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


class ImagePreparationError(ValueError):
    """Invalid catalog/source, budget overflow or immutable-output conflict."""


def _relative_image_path(value: object) -> str:
    if not isinstance(value, str) or not value.endswith(".webp"):
        raise ImagePreparationError("Image path must be a relative .webp path")
    if any(c in value for c in "\\:%?#\x00") or any(
        ord(c) < 32 for c in value
    ) or any(part in ("", ".", "..") for part in value.split("/")):
        raise ImagePreparationError(f"Unsafe image path: {value!r}")
    return value


def _asset_prefix(value: str) -> str:
    if not value.startswith(ASSET_PREFIX) or not value.endswith("/"):
        raise ImagePreparationError(f"Asset prefix must stay within {ASSET_PREFIX}")
    _relative_image_path(f"{value}prefix-check.webp")
    return value


def _hash_file(path: Path) -> tuple[int, str]:
    size = 0
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(128 * 1024), b""):
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def _verify_file(path: Path, spec: dict) -> None:
    if not path.is_file() or _hash_file(path) != (spec["bytes"], spec["sha256"]):
        raise ImagePreparationError(f"Image size/SHA256 mismatch: {path}")


def _publish(target: Path, write) -> None:
    """Publish an already verified temporary inode without replacing any file."""
    with tempfile.NamedTemporaryFile(
        prefix=".posehub-image-", dir=target.parent, delete=False
    ) as stream:
        temporary = Path(stream.name)
        try:
            write(stream)
            stream.flush()
        except BaseException:
            stream.close()
            temporary.unlink()
            raise
    try:
        os.link(temporary, target)  # Fails atomically if target already exists.
    finally:
        temporary.unlink()


def _copy_verified(source: Path, target: Path, spec: dict) -> None:
    def write(stream):
        size = 0
        digest = hashlib.sha256()
        with source.open("rb") as original:
            for chunk in iter(lambda: original.read(128 * 1024), b""):
                size += len(chunk)
                digest.update(chunk)
                stream.write(chunk)
        if (size, digest.hexdigest()) != (spec["bytes"], spec["sha256"]):
            raise ImagePreparationError(f"Source changed during copying: {source}")

    _publish(target, write)


def prepare_images(
    *, source_pack: Path, catalog: Path, catalog_sha256: str,
    output: Path, index_output: Path, asset_prefix: str = ASSET_PREFIX,
) -> dict:
    if not SHA256.fullmatch(catalog_sha256):
        raise ImagePreparationError("Catalog SHA256 must be 64 lowercase hex digits")
    asset_prefix = _asset_prefix(asset_prefix)
    source_pack = source_pack.resolve(strict=True)
    catalog = catalog.resolve(strict=True)
    if not source_pack.is_dir():
        raise ImagePreparationError("Source pack is not a directory")
    if output.is_symlink() or index_output.is_symlink():
        raise ImagePreparationError("Output paths must not be symbolic links")
    output = output.resolve()
    index_output = index_output.resolve()
    if output.is_relative_to(source_pack) or index_output.is_relative_to(source_pack):
        raise ImagePreparationError("Outputs must not modify the source pack")
    if index_output == catalog or index_output.parent == output:
        raise ImagePreparationError("Keep the index separate from source and image files")
    raw = catalog.read_bytes()
    if hashlib.sha256(raw).hexdigest() != catalog_sha256:
        raise ImagePreparationError("Catalog SHA256 mismatch")
    decoded = json.loads(raw)
    if decoded.get("format") != "pose-hub-app-test-catalog@1" or not isinstance(
        decoded.get("actions"), list
    ) or not decoded["actions"]:
        raise ImagePreparationError("Invalid PoseHub catalog")

    files: dict[str, dict] = {}
    unique: dict[str, dict] = {}
    for action in decoded["actions"]:
        if not isinstance(action, dict):
            raise ImagePreparationError("Catalog action must be an object")
        for role in ("cover", "thumbnail"):
            spec = action.get("files", {}).get(role)
            if not isinstance(spec, dict):
                raise ImagePreparationError(f"Missing {role} descriptor")
            relative = _relative_image_path(spec.get("path"))
            size, digest = spec.get("bytes"), spec.get("sha256")
            if type(size) is not int or size <= 0 or not isinstance(digest, str) or not SHA256.fullmatch(digest):
                raise ImagePreparationError(f"Invalid image integrity descriptor: {relative}")
            entry = {"asset": f"{asset_prefix}{digest}.webp", "bytes": size, "sha256": digest}
            if relative in files and files[relative] != entry:
                raise ImagePreparationError(f"Conflicting source image path: {relative}")
            files[relative] = entry
            if digest in unique and unique[digest]["bytes"] != size:
                raise ImagePreparationError(f"Conflicting SHA256 sizes: {digest}")
            unique.setdefault(digest, {**entry, "path": relative})
    unique_bytes = sum(spec["bytes"] for spec in unique.values())
    if unique_bytes > MAX_IMAGE_BYTES:
        raise ImagePreparationError(
            f"Image payload requires {unique_bytes:,} unique bytes; "
            f"budget is {MAX_IMAGE_BYTES:,}. No output was written."
        )
    index = {
        "format": INDEX_FORMAT,
        "catalogSha256": catalog_sha256,
        "uniqueFiles": len(unique),
        "uniqueBytes": unique_bytes,
        "referencedBytes": sum(spec["bytes"] for spec in files.values()),
        "files": dict(sorted(files.items())),
    }
    index_bytes = (json.dumps(index, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    if index_output.exists() and index_output.read_bytes() != index_bytes:
        raise ImagePreparationError(f"Conflicting immutable index; use a new index-output: {index_output}")
    if output.exists():
        expected = {f"{digest}.webp" for digest in unique}
        if not output.is_dir() or any(
            entry.name not in expected or not entry.is_file()
            for entry in output.iterdir()
        ):
            raise ImagePreparationError("Image output contains unrelated files; use a new staging directory")

    # Verify every declared source, including duplicate-content paths, before
    # creating any destination. resolve() prevents symlink escapes as well.
    sources: dict[str, Path] = {}
    for relative, spec in files.items():
        path = (source_pack / relative).resolve(strict=True)
        if not path.is_relative_to(source_pack):
            raise ImagePreparationError(f"Image escaped the source pack: {relative}")
        _verify_file(path, spec)
        sources[relative] = path
    for digest, spec in unique.items():
        target = output / f"{digest}.webp"
        if target.is_symlink():
            raise ImagePreparationError(f"Symbolic-link output conflict: {target}")
        if target.exists():
            _verify_file(target, spec)

    output.mkdir(parents=True, exist_ok=True)
    index_output.parent.mkdir(parents=True, exist_ok=True)
    for digest, spec in unique.items():
        target = output / f"{digest}.webp"
        if not target.exists():
            _copy_verified(sources[spec["path"]], target, spec)
    if not index_output.exists():
        _publish(index_output, lambda stream: stream.write(index_bytes))
    return {
        "sourcePack": str(source_pack), "catalog": str(catalog),
        "catalogSha256": catalog_sha256, "imageReferences": len(files),
        "uniqueFiles": len(unique), "uniqueBytes": unique_bytes,
        "budgetBytes": MAX_IMAGE_BYTES, "index": str(index_output),
        "indexSha256": hashlib.sha256(index_bytes).hexdigest(),
        "payload": str(output), "assetPrefix": asset_prefix,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-pack", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--catalog-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--index-output", type=Path, required=True)
    parser.add_argument("--asset-prefix", default=ASSET_PREFIX,
                        help="APK image directory, optionally scoped by catalog SHA256")
    args = parser.parse_args()
    try:
        result = prepare_images(**vars(args))
    except (ImagePreparationError, OSError, json.JSONDecodeError) as error:
        parser.exit(1, f"Image preparation failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
