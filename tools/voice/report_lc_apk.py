#!/usr/bin/env python3
"""Compare arm64 release APK occupancy and verify the LC-only voice bundle.

The baseline uses the same ZIP occupancy categories but is never checked against
the new voice manifest. Candidate media, all 695 LC clips, the manifest itself,
and the unchanged common chimes are checked against the application sources.
"""

import argparse
import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/media"))
from report_apk_size import PREFIX, verify_candidate  # noqa: E402
from report_release_apks import category as previous_category  # noqa: E402

FLUTTER_PREFIX = "assets/flutter_assets/"
LC_ROOT = "assets/voice_lc32/v1"
LC_PREFIX = FLUTTER_PREFIX + LC_ROOT + "/"
ALL_LC_PREFIX = FLUTTER_PREFIX + "assets/voice_lc32/"
MANIFEST_PATH = LC_ROOT + "/manifest.json"
LEGACY_PREFIX = PREFIX + "packs/"
CHIME_ROOT = "assets/packs/_common/chime"
GROUP_NAMES = ("flutterEngine", "compiledDartApp", "trainingVoice",
               "trainingMedia", "fonts", "androidCode", "otherFiles",
               "debugKernelAndSnapshots", "graphicsValidation")


def sha(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def category(name):
    if name.startswith(LC_PREFIX) and name.endswith(".m4a"):
        return "trainingVoice"
    # Reject both data and instructions snapshots in a release artifact.
    if "snapshot_instr" in name:
        return "debugKernelAndSnapshots"
    if "vklayer" in name.lower():
        return "graphicsValidation"
    return previous_category(name)


def is_legacy_voice(name):
    return name.startswith(LEGACY_PREFIX) and "/voice/" in name


def measure_apk(path):
    """Use the exact compressed ZIP + header/signing/padding occupancy basis."""
    size = path.stat().st_size
    if not size:
        raise ValueError(f"Empty APK: {path}")
    groups = {name: {"files": 0, "zipBytes": 0, "uncompressedBytes": 0}
              for name in GROUP_NAMES}
    with zipfile.ZipFile(path) as apk:
        raw_entries = apk.infolist()
        names = [entry.filename for entry in raw_entries]
        if len(names) != len(set(names)):
            raise ValueError(f"Duplicate ZIP entries in APK: {path}")
        entries = [entry for entry in raw_entries if not entry.is_dir()]
        for entry in entries:
            group = groups[category(entry.filename)]
            group["files"] += 1
            group["zipBytes"] += entry.compress_size
            group["uncompressedBytes"] += entry.file_size
        native = [entry.filename.split("/") for entry in entries
                  if entry.filename.startswith("lib/")]
        if any(len(parts) != 3 or not parts[1] or not parts[2]
               for parts in native):
            raise ValueError(f"Unexpected native library layout: {path}")
        abis = sorted({parts[1] for parts in native})
        if abis != ["arm64-v8a"]:
            raise ValueError(f"Expected only arm64-v8a in {path.name}: {abis}")
        required = {"lib/arm64-v8a/libapp.so", "lib/arm64-v8a/libflutter.so"}
        if not required <= set(names):
            raise ValueError(f"Release APK needs arm64 AOT app and Flutter engine: {path}")
        if (groups["compiledDartApp"]["files"] != 1 or
                groups["flutterEngine"]["files"] != 1):
            raise ValueError(f"Unexpected AOT app or Flutter engine inventory: {path}")
        if (groups["debugKernelAndSnapshots"]["files"] or
                groups["graphicsValidation"]["files"]):
            raise ValueError(f"Release APK contains debug kernel/snapshots/VkLayer: {path}")
        headers = size - sum(entry.compress_size for entry in entries)
        if headers < 0:
            raise ValueError(f"Invalid ZIP occupancy accounting: {path}")
        groups["zipHeadersSigningPadding"] = {
            "files": 0, "zipBytes": headers, "uncompressedBytes": None}
        return {
            "file": path.name, "bytes": size, "sha256": sha(path), "abis": abis,
            "groups": {
                name: {**value, "percent": round(value["zipBytes"] / size * 100, 2)}
                for name, value in sorted(groups.items(), key=lambda pair: -pair[1]["zipBytes"])},
            "topFiles": [
                {"path": entry.filename, "zipBytes": entry.compress_size,
                 "uncompressedBytes": entry.file_size}
                for entry in sorted(entries, key=lambda entry: -entry.compress_size)[:12]],
            "voiceLayout": {
                "legacyFiles": sum(is_legacy_voice(entry.filename) for entry in entries),
                "lc32Files": sum(entry.filename.startswith(LC_PREFIX)
                                 and entry.filename.endswith(".m4a") for entry in entries)},
            "releaseArm64StructureVerified": True,
        }


def expected_voices(app_root):
    manifest_path = app_root / MANIFEST_PATH
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1 or manifest.get("version") != "v1":
        raise ValueError("LC voice manifest has an unsupported schema/version")
    expected_encoding = {"format": "m4a", "profile": "LC", "target_bit_rate_bps": 32000,
                         "sample_rate_hz": 22050, "channels": 1}
    if any(manifest.get(key) != value for key, value in expected_encoding.items()):
        raise ValueError("LC manifest has unexpected approved codec settings")
    clips = manifest.get("clips", [])
    if len(clips) != 695:
        raise ValueError(f"Expected 695 manifest clips, found {len(clips)}")
    expected = {}
    sources = set()
    for clip in clips:
        source = clip["source"]
        path = clip["asset"]
        wanted = f"{LC_ROOT}/{clip['pack']}/zh/{clip['line']}.m4a"
        source_wanted = f"assets/packs/{clip['pack']}/voice/zh/{clip['line']}.m4a"
        if (clip.get("lang") != "zh" or path != wanted or
                source["asset"] != source_wanted or
                len(PurePosixPath(path).parts) != 6 or
                any(part in (".", "..") for part in path.split("/")) or
                "\\" in path):
            raise ValueError(f"Unexpected LC manifest clip path: {path}")
        if path in expected or source["asset"] in sources:
            raise ValueError(f"Duplicate LC manifest clip: {path}")
        if (not isinstance(clip.get("bytes"), int) or clip["bytes"] <= 0 or
                re.fullmatch(r"[0-9a-f]{64}", str(clip.get("sha256"))) is None or
                re.fullmatch(r"[0-9a-f]{64}", str(source.get("sha256"))) is None or
                not isinstance(clip.get("decoded_ms"), int) or clip["decoded_ms"] <= 0 or
                not isinstance(clip.get("duration_ms"), int) or clip["duration_ms"] <= 0):
            raise ValueError(f"LC clip is missing verified size/hash/duration evidence: {path}")
        local = app_root / path
        if local.stat().st_size != clip["bytes"] or sha(local) != clip["sha256"]:
            raise ValueError(f"LC source asset changed after conversion: {path}")
        expected[path] = clip
        sources.add(source["asset"])
    actual_local = {path.relative_to(app_root).as_posix()
                    for path in (app_root / LC_ROOT).rglob("*") if path.is_file()}
    if actual_local != expected.keys() | {MANIFEST_PATH}:
        raise ValueError("Local LC directory contains missing or unrecorded files")
    return manifest_path, expected


def verify_lc_candidate(path, app_root):
    # Keep the existing independently sealed 413-file / 32-video media contract.
    media = verify_candidate(path, app_root)
    manifest_path, voices = expected_voices(app_root)
    expected = {FLUTTER_PREFIX + key: value for key, value in voices.items()}
    with zipfile.ZipFile(path) as apk:
        entries = {entry.filename: entry for entry in apk.infolist() if not entry.is_dir()}
        actual = {name for name in entries if name.startswith(ALL_LC_PREFIX)}
        if actual != expected.keys() | {FLUTTER_PREFIX + MANIFEST_PATH}:
            raise ValueError("APK LC inventory differs from the 695 clips plus manifest")
        if any(is_legacy_voice(name) for name in entries):
            raise ValueError("APK still bundles original packs/*/voice assets")
        for name, item in expected.items():
            if (entries[name].file_size != item["bytes"] or
                    hashlib.sha256(apk.read(name)).hexdigest() != item["sha256"]):
                raise ValueError(f"APK LC voice size/hash mismatch: {name}")
        if apk.read(FLUTTER_PREFIX + MANIFEST_PATH) != manifest_path.read_bytes():
            raise ValueError("APK LC manifest differs from verified application manifest")
        chimes = {FLUTTER_PREFIX + source.relative_to(app_root).as_posix(): source
                  for source in (app_root / CHIME_ROOT).glob("*.m4a")}
        if len(chimes) != 5:
            raise ValueError(f"Expected unchanged five common chimes, found {len(chimes)}")
        actual_chimes = {name for name in entries
                         if name.startswith(FLUTTER_PREFIX + CHIME_ROOT + "/")}
        if actual_chimes != chimes.keys():
            raise ValueError("APK common chime inventory changed")
        for name, source in chimes.items():
            if (entries[name].file_size != source.stat().st_size or
                    hashlib.sha256(apk.read(name)).hexdigest() != sha(source)):
                raise ValueError(f"APK common chime changed: {name}")
    return {"clipCount": len(expected), "voiceBytes": sum(v["bytes"] for v in expected.values()),
            "manifestSha256": sha(manifest_path), "legacyVoiceFiles": 0,
            "chimeCount": len(chimes), "manifestAndAllVoiceHashesVerified": True,
            "unchangedChimeHashesVerified": True, "trainingMedia": media["trainingMedia"],
            "trainingMediaInventoryAndHashesVerified": True}


def build_report(apk, baseline, app_root):
    before = measure_apk(baseline)
    # Baseline is classified from its own old voice layout; the new manifest is
    # deliberately used only for the candidate. Training media stayed unchanged.
    verify_candidate(baseline, app_root)
    before["trainingMediaInventoryAndHashesVerified"] = True
    before["voiceManifestVerification"] = "not_applied_to_baseline"
    after = measure_apk(apk)
    after["voiceValidation"] = verify_lc_candidate(apk, app_root)
    groups = sorted(before["groups"].keys() | after["groups"].keys())
    delta = {name: before["groups"][name]["zipBytes"] - after["groups"][name]["zipBytes"]
             for name in groups}
    saved = before["bytes"] - after["bytes"]
    if sum(delta.values()) != saved:
        raise ValueError("APK group differences do not reconcile with actual file-size difference")
    return {
        "unit": "bytes; MB = 1,000,000 bytes; occupancy = ZIP compressed bytes plus headers/signing/padding",
        "buildMode": "release, arm64-v8a split APK (same ABI)",
        "before": before, "after": after, "apkBytesSaved": saved,
        "apkSavingPercent": round(saved / before["bytes"] * 100, 4),
        "zipBytesSavedByGroup": delta,
        "voiceZipBytesSaved": delta["trainingVoice"],
        "occupancyReconcilesExactly": True,
        "platformPlaybackAcceptance": "not_established_by_apk_static_validation",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--app-root", type=Path, default=ROOT)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    app = args.app_root.resolve()
    apk, baseline = args.apk.resolve(), args.baseline.resolve()
    report = args.report.resolve()
    if apk == baseline:
        parser.error("--apk and --baseline must be different files")
    if report in (apk, baseline) or report.is_relative_to(app / "assets"):
        parser.error("--report must not overwrite an APK or application assets")
    result = build_report(apk, baseline, app)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8", newline="\n")
    for label in ("before", "after"):
        info = result[label]
        print(f"{label}: {info['bytes']:,} B ({info['bytes'] / 1_000_000:.2f} MB), SHA256 {info['sha256']}")
    print(f"saved: {result['apkBytesSaved']:,} B ({result['apkSavingPercent']:.2f}%)")
    print(f"Verified 695 AAC-LC clips, 5 unchanged chimes, minimal training media; report: {report}")


if __name__ == "__main__":
    main()
