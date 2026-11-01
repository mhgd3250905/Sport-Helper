"""Verify and copy the SDK's sealed SF v7 baseline without executing Flutter.

The SDK checkout and original baseline are read-only. A new output directory is
required; existing evidence is never replaced. Git objects, not the SDK working
branch, supply the pinned reference tools.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

from PIL import Image

SDK_PIN = "b025ee88bd1a6d69564ce96a473302739c981c3b"
SF_SOURCE = "3eb2a9e88ef4d28e02f4cf306c1716d61baa7f10"
BASELINE_SDK = "700d0100f1cb42ef122e774a6ee0076d1916b5e5"
STATES = (
    "empty", "waiting-250ms", "plan-collapsed", "plan-expand-280ms",
    "plan-expanded", "recommendations", "focused-saved-plan",
    "training-enter-150ms", "training-enter-300ms", "training-exit-140ms",
    "training-return",
)
REFERENCE_FILES = (
    "docs/coach-chat-module-design/capture-environment.md",
    "tool/chat_capture_sf_baseline.ps1", "tool/chat_capture_sf_baseline.dart.txt",
    "tool/chat_capture_candidate.ps1", "tool/chat_capture_candidate.dart.txt",
)
HERE = Path(__file__).resolve().parent


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def identity(raw):
    return {"bytes": len(raw), "sha256": digest(raw)}


def git(repository, *args):
    return subprocess.check_output(["git", *args], cwd=repository)


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def same_or_new(path, raw):
    if path.exists():
        assert path.read_bytes() == raw, f"Preserve differing existing fixture: {path}"
    else:
        write_new(path, raw)


def write_json(path, data):
    write_new(path, (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode())


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-repository", type=Path, required=True)
    parser.add_argument("--sf-repository", type=Path, required=True)
    parser.add_argument("--sealed-baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    sdk_repository = args.sdk_repository.resolve(strict=True)
    sf_repository = args.sf_repository.resolve(strict=True)
    baseline = args.sealed_baseline.resolve(strict=True)
    source = baseline / "sf-source"
    output = args.output.resolve()
    assert not output.exists(), "Use a new evidence root."
    environment = read(baseline / "environment.json")
    assert environment["sourceCommit"] == SF_SOURCE
    assert environment["viewport"] == {
        "bottomInset": 24, "topInset": 24, "devicePixelRatio": 1,
        "width": 390, "height": 844,
    }
    assert environment["clock"] == "2026-10-30T12:00:00"
    sdk_status = git(sdk_repository, "status", "--porcelain")
    baseline_status = {p.relative_to(baseline).as_posix(): identity(p.read_bytes())
                       for p in baseline.iterdir() if p.is_file()}

    # Windows git archive applied CRLF to some text. Verify every source file
    # against its Git blob, accepting only that recorded newline conversion.
    paths = ["lib", "test", "assets",
             "ios/Runner/Assets.xcassets/AppIconB.appiconset/Icon-App-60x60@3x.png",
             "pubspec.yaml", "pubspec.lock", "analysis_options.yaml", ".metadata"]
    entries = git(sf_repository, "ls-tree", "-r", "-z", SF_SOURCE, "--", *paths)
    source_rows = {}
    crlf_only = []
    for item in entries.split(b"\0"):
        if not item:
            continue
        descriptor, name_bytes = item.split(b"\t", 1)
        mode, kind, blob = descriptor.split()
        assert kind == b"blob" and mode in (b"100644", b"100755")
        name = name_bytes.decode()
        raw = (source / name).read_bytes()
        actual = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
        if actual != blob.decode():
            normalized = raw.replace(b"\r\n", b"\n")
            normalized_blob = hashlib.sha1(b"blob " + str(len(normalized)).encode() + b"\0" + normalized).hexdigest()
            assert normalized_blob == blob.decode(), f"Frozen SF source content differs from 3eb2a9e: {name}"
            crlf_only.append(name)
        source_rows[name] = {"gitBlob": blob.decode(), "snapshotGitBlob": actual,
                             "transformation": "CRLF only" if name in crlf_only else "byte-identical",
                             **identity(raw)}
    assert source_rows
    raw_references = {name: git(sdk_repository, "show", f"{SDK_PIN}:{name}")
                      for name in REFERENCE_FILES}
    injected = (source / "test/sdk_chat_baseline_capture_test.dart").read_bytes()
    dart = Path(environment["flutterCommand"]).with_name("dart.bat")
    formatted = []
    for raw in (injected, raw_references["tool/chat_capture_sf_baseline.dart.txt"]):
        result = subprocess.run([str(dart), "format", "--output=show", "--show=none",
                                 "--summary=none", "--language-version=3.12"],
                                input=raw, capture_output=True)
        assert result.returncode == 0, result.stderr
        formatted.append("".join(line + "\n" for line in result.stdout.decode().splitlines() if line.strip()).encode())
    assert formatted[0] == formatted[1], "Pinned baseline template has a non-formatting change."

    index_path = source / "assets/posehub/images-index.json"
    image_index = read(index_path)
    media_rows = []
    for key, row in image_index["files"].items():
        raw = (source / row["asset"]).read_bytes()
        assert len(raw) == row["bytes"] and digest(raw) == row["sha256"], key
        media_rows.append({"catalogMediaKey": key, **row})
    assert len(media_rows) == image_index["uniqueFiles"] == 438

    package_config = read(source / ".dart_tool/package_config.json")
    dependency_rows = []
    for package in package_config["packages"]:
        if package["name"] not in {"flutter", "flutter_test", "ugk_coach", "ugk_coach_ui", "ugk_trainer"}:
            continue
        uri = package["rootUri"]
        assert uri.startswith("file:///")
        root = Path(unquote(urlparse(uri).path).lstrip("/"))
        resolved = git(root, "rev-parse", "HEAD").decode().strip()
        if package["name"].startswith("ugk_"):
            assert resolved == BASELINE_SDK
        else:
            assert resolved.startswith("84fc5cbb22")
        dependency_rows.append({"name": package["name"], "rootUri": uri, "resolvedHead": resolved})
    version_bytes = (baseline / "flutter-version.txt").read_bytes()
    version = version_bytes.decode("utf-8-sig")
    assert all(value in version for value in ("Flutter 3.44.7", "Dart 3.12.2", "84fc5cbb22", "69c8c61792"))
    log = (baseline / "render.log").read_text(encoding="utf-8-sig")
    assert "+2: All tests passed!" in log

    frame_rows = []
    for theme in ("light", "dark"):
        for state in STATES:
            name = f"{theme}-{state}"
            metadata = read(baseline / f"{name}.json")
            assert metadata["name"] == state and metadata["theme"] == theme
            assert metadata["clock"] == environment["clock"]
            with Image.open(baseline / f"{name}.png") as image:
                assert image.size == (390, 844)
            frame_rows.append({"frame": name,
                               "png": identity((baseline / f"{name}.png").read_bytes()),
                               "input": identity((baseline / f"{name}.json").read_bytes()),
                               "captureDate": metadata["captureDate"],
                               "elapsedFromMountMs": metadata["elapsedFromMountMs"],
                               "actionIds": metadata.get("actionIds")})

    output.mkdir(parents=True)
    for row in frame_rows:
        for suffix in ("png", "json"):
            name = f"{row['frame']}.{suffix}"
            write_new(output / "base" / name, (baseline / name).read_bytes())
        same_or_new(HERE / "inputs" / f"{row['frame']}.json", (baseline / f"{row['frame']}.json").read_bytes())
    for name in ("environment.json", "flutter-version.txt", "render.log"):
        write_new(output / "baseline-receipts" / name, (baseline / name).read_bytes())
    write_new(output / "baseline-receipts/original-capture-test.dart", injected)
    for name, raw in raw_references.items():
        write_new(output / "baseline-receipts/sdk-pin" / name, raw)
        same_or_new(HERE / "reference" / name, raw)
    for relative in ("test/support.dart", "test/support/coach_v2_fixtures.dart"):
        raw = (source / relative).read_bytes()
        write_new(output / "baseline-receipts/sf-source" / relative, raw)
        # Commit reproducible LF copies of helper source; raw source evidence
        # above stays untouched. This does not alter any fixture value.
        same_or_new(HERE / relative.removeprefix("test/"), raw.replace(b"\r\n", b"\n"))
    write_new(output / "baseline-receipts/source-package-config.json",
              (source / ".dart_tool/package_config.json").read_bytes())
    write_json(output / "baseline-receipts/source-files.json", source_rows)
    write_json(output / "baseline-receipts/media-files.json", media_rows)

    needed_media = [row for row in media_rows if any(
        f"/{action}/" in row["catalogMediaKey"] for action in ("s-butterfly", "s-frog", "s-kneel-hipflex"))]
    assert len(needed_media) == 6
    for row in needed_media:
        fixture = f"media/{Path(row['asset']).name}"
        same_or_new(HERE / fixture, (source / row["asset"]).read_bytes())
        row["fixture"] = fixture
    same_or_new(HERE / "media-inputs.json", (json.dumps({
        "schema": "smartfit-chat-capture-media@1",
        "sourceCommit": SF_SOURCE,
        "sourceImageIndex": identity(index_path.read_bytes()),
        "catalogSha256": image_index["catalogSha256"], "images": needed_media,
    }, ensure_ascii=False, indent=2) + "\n").encode())

    font_bytes = (source / "assets/fonts/NotoSansSC.ttf").read_bytes()
    inputs = {f"{row['frame']}.json": row["input"] for row in frame_rows}
    receipt = {
        "schema": "smartfit-sdk-chat-frozen-baseline@1",
        "recordedUtc": datetime.now(timezone.utc).isoformat(),
        "baselineSourceCommit": SF_SOURCE, "sdkReferencePin": SDK_PIN,
        "baselineRuntimeSdk": BASELINE_SDK,
        "originalDirectory": str(baseline),
        "newSfRepository": str(sf_repository),
        "meaning": "Independent hash checkpoint of the SDK's existing sealed v7 SF baseline, not a new SF migration capture",
        "historicalHashSignatureClaimed": False,
        "allArchivedSfGitBlobsMatch3eb2a9e": not crlf_only,
        "allArchivedSfSourceMatches3eb2a9eExceptRecordedCrlf": True,
        "archivedSfFilesVerified": len(source_rows),
        "archivedSfFilesByteIdentical": len(source_rows) - len(crlf_only),
        "archivedSfCrlfOnlyFiles": crlf_only,
        "originalBaselineHarnessMatchesPinnedSdkTemplateAfterDartFormattingAndEmptyLineRemoval": True,
        "harnessCanonicalFormattingSha256": digest(formatted[0]),
        "harnessCanonicalizationOnlyUsedForProvenanceCheckNotCapture": True,
        "originalBaselineHarness": identity(injected),
        "all438BundledImagesMatchOriginalIndex": True,
        "notoSansSc": identity(font_bytes),
        "environment": environment, "baselineDependencies": dependency_rows,
        "baselineCaptureTestsPassed": 2, "frames": frame_rows,
        "inputsSha256": digest(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode()),
        "inputs": inputs,
        "sdkReferences": {name: identity(raw) for name, raw in raw_references.items()},
        "sourceAndSealedBaselineUnmodified": True,
        "isPhoneOrPerformanceEvidence": False,
        "newSfMigrationAcceptance": "not run",
    }
    write_json(output / "baseline-source-bindings.json", receipt)
    same_or_new(HERE / "frozen-inputs.json", (json.dumps({
        key: receipt[key] for key in ("schema", "baselineSourceCommit", "sdkReferencePin",
                                     "baselineRuntimeSdk", "notoSansSc", "inputsSha256", "inputs")
    }, indent=2) + "\n").encode())
    assert git(sdk_repository, "status", "--porcelain") == sdk_status
    assert baseline_status == {p.relative_to(baseline).as_posix(): identity(p.read_bytes())
                               for p in baseline.iterdir() if p.is_file()}
    print(json.dumps({"frames": len(frame_rows), "verifiedSfGitFiles": len(source_rows),
                      "verifiedMediaFiles": len(media_rows), "fixtureMediaBytes": sum(row["bytes"] for row in needed_media),
                      "baselineBindingsSha256": digest((output / "baseline-source-bindings.json").read_bytes()),
                      "inputsSha256": receipt["inputsSha256"]}))


if __name__ == "__main__":
    main()
