#!/usr/bin/env python3
"""Convert the 695 original clips to the approved AAC-LC audition settings.

Original assets/packs media and metadata are read-only. Outputs have a separate,
versioned asset root. A completed manifest is also the resumable checksum ledger:
existing media are reused only when their saved source/output hashes still match.
No normalisation, silence trimming, duration trimming or pitch changes are made.
"""

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import wave
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_VERSION = 1
VERSION = "v1"
ENCODING = {"format": "m4a", "codec": "aac", "profile": "LC",
            "audio_object_type": 2, "target_bit_rate_bps": 32000,
            "sample_rate_hz": 22050, "channels": 1, "rate_control": "CBR",
            "afterburner": True, "gapless": "iTunSMPB and ISO",
            "pcm_policy": "complete source decode; no trimming or normalisation"}
ENCODER_OPTIONS = ["-S", "-p", "2", "-b", "32000", "-m", "0", "-a", "1",
                   "-G", "2", "--moov-before-mdat"]
INVENTORY_FORMAT = "path\\tbytes\\tsha256\\n, sorted by path, UTF-8"


def run(arguments):
    result = subprocess.run([str(a) for a in arguments], check=True,
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace")
    return result.stdout


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    return [{"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size,
             "sha256": sha(p)}
            for p in sorted(root.glob("assets/packs/*/voice/zh/*.m4a"))]


def inventory_hash(items):
    canonical = "".join(f"{i['path']}\t{i['bytes']}\t{i['sha256']}\n" for i in items)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def atomic_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                         encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def output_relative(source_path):
    parts = Path(source_path).parts
    if len(parts) != 6 or parts[:2] != ("assets", "packs") or parts[3:5] != ("voice", "zh"):
        raise ValueError(f"Unexpected original voice path: {source_path}")
    return Path(parts[2], "zh", parts[5])


def probe(ffprobe, path):
    data = json.loads(run([ffprobe, "-v", "error", "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,profile,channels,sample_rate,duration,bit_rate:"
        "format=duration,size:packet=size", "-of", "json", path]))
    if len(data.get("streams", [])) != 1:
        raise ValueError(f"Expected one audio stream: {path}")
    stream = data["streams"][0]
    size = path.stat().st_size
    payload = sum(int(packet["size"]) for packet in data["packets"])
    return {"codec": stream["codec_name"], "profile": stream["profile"],
            "channels": int(stream["channels"]),
            "sample_rate_hz": int(stream["sample_rate"]),
            "duration_s": float(stream.get("duration", data["format"]["duration"])),
            "stream_bit_rate_bps": int(stream.get("bit_rate", 0)),
            "bytes": size, "audio_packet_bytes": payload,
            "container_bytes": size - payload, "sha256": sha(path)}


def assert_output(info, path):
    expected = {"codec": "aac", "profile": "LC", "channels": 1,
                "sample_rate_hz": 22050}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError(f"Unexpected output codec settings: {path}: {info}")


def decode(ffmpeg, source, output, rate=None):
    # Deliberately identical to the chosen audition, including complete AAC PCM.
    command = [ffmpeg, "-v", "error", "-xerror", "-nostdin", "-n", "-i", source,
               "-map", "0:a:0", "-vn", "-c:a", "pcm_s16le"]
    if rate:
        command += ["-ar", str(rate)]
    run(command + [output])
    with wave.open(str(output), "rb") as pcm:
        if pcm.getnchannels() != 1:
            raise ValueError(f"Decoded source must already be mono: {source}")
        return {"decoded_frames": pcm.getnframes(), "decoded_rate_hz": pcm.getframerate(),
                "decoded_duration_s": pcm.getnframes() / pcm.getframerate()}


def payload_sha(ffmpeg, path):
    value = run([ffmpeg, "-v", "error", "-xerror", "-nostdin", "-i", path,
                 "-map", "0:a:0", "-c:a", "copy", "-f", "hash", "-hash", "sha256", "-"])
    algorithm, digest = value.strip().split("=", 1)
    if algorithm != "SHA256" or len(digest) != 64:
        raise ValueError(f"Unexpected payload hash output: {path}")
    return digest


def runtime_manifest(report):
    """Only playback fields belong in the APK; audits stay outside asset roots."""
    return {"schema_version": SCHEMA_VERSION, "version": VERSION,
            "format": "m4a", "profile": "LC", "target_bit_rate_bps": 32000,
            "sample_rate_hz": 22050, "channels": 1,
            "clips": [{"pack": clip["pack"], "line": clip["line"], "lang": "zh",
                       "asset": clip["output"]["path"],
                       "bytes": clip["output"]["bytes"],
                       "sha256": clip["output"]["sha256"],
                       "decoded_ms": round(clip["output"]["decoded_duration_s"] * 1000),
                       "duration_ms": round(clip["output"]["duration_s"] * 1000),
                       "source": {"asset": clip["source"]["path"],
                                  "sha256": clip["source"]["sha256"]}}
                      for clip in report["clips"]]}


def validate_ledger(manifest, before, root, output):
    if (manifest.get("schema_version") != SCHEMA_VERSION or
            manifest.get("version") != VERSION or manifest.get("encoding") != ENCODING):
        raise ValueError("Existing manifest belongs to a different conversion; refusing to overwrite")
    if manifest.get("source_inventory", {}).get("before") != before:
        raise ValueError("Original voice inventory changed since conversion; refusing to resume")
    if manifest.get("output_root") != output.relative_to(root).as_posix():
        raise ValueError("Existing manifest output root does not match")
    by_source = {entry["source"]["path"]: entry for entry in manifest.get("clips", [])}
    if len(by_source) != len(manifest.get("clips", [])):
        raise ValueError("Duplicate source entries in existing conversion manifest")
    allowed_sources = {item["path"]: item for item in before}
    for source, entry in by_source.items():
        if source not in allowed_sources or entry["source"]["sha256"] != allowed_sources[source]["sha256"]:
            raise ValueError(f"Existing conversion source mismatch: {source}")
        wanted = (output / output_relative(source)).relative_to(root).as_posix()
        if entry["output"]["path"] != wanted:
            raise ValueError(f"Existing conversion output path mismatch: {source}")
    # Never silently adopt an unrelated file or overwrite an unrecorded conversion.
    allowed = {"manifest.json", "manifest.json.tmp"}
    allowed.update(str(output_relative(source)).replace("\\", "/") for source in by_source)
    unexpected = [p.relative_to(output).as_posix() for p in output.rglob("*")
                  if p.is_file() and p.relative_to(output).as_posix() not in allowed]
    if unexpected:
        raise ValueError(f"Unrecorded output files found; refusing to overwrite: {unexpected[:5]}")
    return by_source


def convert_one(args, root, output, temp_root, source_item, existing):
    source = root / source_item["path"]
    target = output / output_relative(source_item["path"])
    if existing:
        if not target.is_file() or sha(target) != existing["output"]["sha256"]:
            raise ValueError(f"Existing output missing or changed; refusing to overwrite: {target}")
        info = probe(args.ffprobe, target)
        assert_output(info, target)
        with tempfile.TemporaryDirectory(prefix="verify-", dir=temp_root) as temp:
            decoded = decode(args.ffmpeg, target, Path(temp) / "verify.wav")
        if decoded["decoded_frames"] != existing["output"]["decoded_frames"]:
            raise ValueError(f"Existing output decode changed: {target}")
        return existing, True
    if target.exists():
        raise ValueError(f"Unrecorded output already exists; refusing to overwrite: {target}")
    with tempfile.TemporaryDirectory(prefix="encode-", dir=temp_root) as temp:
        temp = Path(temp)
        source_info = probe(args.ffprobe, source)
        source_decoded = decode(args.ffmpeg, source, temp / "source.wav", 22050)
        encoded = temp / "encoded.m4a"
        run([args.fdkaac, *ENCODER_OPTIONS, "-o", encoded, temp / "source.wav"])
        info = probe(args.ffprobe, encoded)
        assert_output(info, encoded)
        info.update(decode(args.ffmpeg, encoded, temp / "verified.wav"))
        # gapless metadata describes the input PCM exactly; decoder output may
        # include at most one final AAC frame of padding (1024 at 22.05 kHz).
        if abs(info["duration_s"] - source_decoded["decoded_duration_s"]) > 1 / 22050:
            raise ValueError(f"Encoded gapless duration differs from source PCM: {source}")
        drift = info["decoded_duration_s"] - source_decoded["decoded_duration_s"]
        if drift < -1 / 22050 or drift > 1024 / 22050 + 1 / 22050:
            raise ValueError(f"Unexpected decoded duration drift ({drift}): {source}")
        info["audio_payload_sha256"] = payload_sha(args.ffmpeg, encoded)
        info["path"] = target.relative_to(root).as_posix()
        source_info.update(source_decoded)
        source_info["path"] = source_item["path"]
        parts = output_relative(source_item["path"]).parts
        entry = {"pack": parts[0], "language": "zh", "line": Path(parts[2]).stem,
                 "source": source_info, "output": info,
                 "decoded_duration_drift_s": drift, "decode_verified": True}
        target.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation prevents another process or user file being replaced.
        with target.open("xb") as handle:
            handle.write(encoded.read_bytes())
    return entry, False


def audition_check(args, root, entries):
    if not args.audition_manifest:
        return {"status": "not_requested"}
    audition_path = args.audition_manifest.resolve()
    audition = json.loads(audition_path.read_text(encoding="utf-8"))
    by_source = {entry["source"]["path"]: entry for entry in entries}
    checked = []
    for clip in audition["clips"]:
        expected = clip["variants"]["lc32"]
        sample = audition_path.parent / expected["file"]
        if sha(sample) != expected["sha256"]:
            raise ValueError(f"Approved audition sample changed: {sample}")
        output = by_source[clip["source"]]["output"]
        sample_payload = payload_sha(args.ffmpeg, sample)
        if sample_payload != output["audio_payload_sha256"]:
            raise ValueError(f"Converted AAC payload differs from approved audition: {clip['source']}")
        checked.append({"source": clip["source"], "sample_sha256": expected["sha256"],
                        "audio_payload_sha256": sample_payload, "payload_equal": True})
    if len(checked) != 10:
        raise ValueError("Expected exactly ten approved audition sample comparisons")
    return {"status": "passed", "count": len(checked), "clips": checked}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--fdkaac", type=Path, required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--workers", type=int, default=4, choices=range(1, 9))
    parser.add_argument("--audition-manifest", type=Path)
    parser.add_argument("--report", type=Path,
                        help="Detailed resumable audit report, outside application assets")
    args = parser.parse_args()
    root = args.root.resolve()
    output = (args.output or root / "assets/voice_lc32/v1").resolve()
    if output != root / "assets/voice_lc32/v1":
        parser.error("Output must be the separate assets/voice_lc32/v1 directory")
    if not args.fdkaac.is_file():
        parser.error("fdkaac executable does not exist")
    before = inventory(root)
    if len(before) != 695:
        raise ValueError(f"Expected exactly 695 original clips, found {len(before)}")
    manifest_path = output / "manifest.json"
    report_path = (args.report or root / "docs/reports/voice-lc32-2026-10-22.json").resolve()
    if not report_path.is_relative_to(root) or report_path.is_relative_to(root / "assets"):
        parser.error("Detailed audit report must be within the checkout and outside assets")
    if output.exists() and not report_path.is_file():
        raise ValueError("Output exists without conversion audit ledger; refusing to overwrite")
    if report_path.exists():
        report = json.loads(report_path.read_text(encoding="utf-8"))
        existing = validate_ledger(report, before, root, output)
        if report["tools"]["fdkaac_sha256"] != sha(args.fdkaac):
            raise ValueError("Encoder changed since conversion; refusing to mix encoders")
    else:
        output.mkdir(parents=True, exist_ok=False)
        report = {"schema_version": SCHEMA_VERSION, "version": VERSION,
                  "created_utc": datetime.now(timezone.utc).isoformat(),
                  "status": "converting", "encoding": ENCODING,
                  "output_root": output.relative_to(root).as_posix(),
                  "source_inventory": {"count": len(before),
                      "canonical_format": INVENTORY_FORMAT,
                      "before_sha256": inventory_hash(before), "before": before},
                  "tools": {"ffmpeg": run([args.ffmpeg, "-version"]).splitlines()[0],
                            "ffprobe": run([args.ffprobe, "-version"]).splitlines()[0],
                            "fdkaac_sha256": sha(args.fdkaac),
                            "fdkaac_upstream_commit": "cdfd8a555c31ffa7d0c2e303e84bb197ba518ed8",
                            "fdk_aac_version": "2.0.3", "encoder_options": ENCODER_OPTIONS},
                  "clips": []}
        existing = {}
        report_path.parent.mkdir(parents=True, exist_ok=True)
        atomic_json(report_path, report)
    temp_root = root / ".buildlog/voice-tools"
    temp_root.mkdir(parents=True, exist_ok=True)
    completed = dict(existing)
    reused = 0
    try:
        errors = []
        processed = 0
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(convert_one, args, root, output, temp_root,
                        item, existing.get(item["path"])) for item in before]
            for future in as_completed(futures):
                try:
                    entry, was_reused = future.result()
                except Exception as error:
                    errors.append(str(error))
                    continue
                processed += 1
                completed[entry["source"]["path"]] = entry
                reused += was_reused
                report["clips"] = [completed[key] for key in sorted(completed)]
                # Checkpoint each completed conversion before accepting another.
                atomic_json(report_path, report)
                if processed % 50 == 0 or processed == len(before):
                    print(json.dumps({"completed": len(completed), "total": len(before),
                                      "reused_verified": reused}), flush=True)
        if errors:
            raise RuntimeError(f"{len(errors)} clips failed; successful outputs checkpointed: {errors[:5]}")
        report["audition_comparison"] = audition_check(args, root, report["clips"])
    finally:
        after = inventory(root)
        if before != after:
            raise RuntimeError("ORIGINAL VOICE INVENTORY CHANGED")
    report["source_inventory"].update(after_sha256=inventory_hash(after), unchanged=True)
    report["status"] = "complete"
    report["validation"] = {"all_outputs_decode_verified": True,
                            "all_outputs_aac_lc_22050_mono": True,
                            "verified_count": len(report["clips"])}
    report["totals"] = {"count": len(report["clips"]),
                         "source_bytes": sum(c["source"]["bytes"] for c in report["clips"]),
                         "output_bytes": sum(c["output"]["bytes"] for c in report["clips"]),
                         "output_audio_packet_bytes": sum(c["output"]["audio_packet_bytes"] for c in report["clips"]),
                         "source_declared_duration_s": sum(c["source"]["duration_s"] for c in report["clips"]),
                         "output_declared_duration_s": sum(c["output"]["duration_s"] for c in report["clips"]),
                         "max_decoded_padding_s": max(c["decoded_duration_drift_s"] for c in report["clips"])}
    report["totals"]["saved_bytes"] = report["totals"]["source_bytes"] - report["totals"]["output_bytes"]
    report["totals"]["saving_pct"] = 100 * report["totals"]["saved_bytes"] / report["totals"]["source_bytes"]
    atomic_json(report_path, report)
    atomic_json(manifest_path, runtime_manifest(report))
    print(json.dumps({"manifest": str(manifest_path), "report": str(report_path),
                      "totals": report["totals"],
                      "integrity": {key: report["source_inventory"][key]
                                    for key in ("count", "before_sha256", "after_sha256", "unchanged")},
                      "reused_verified": reused,
                      "audition": report["audition_comparison"]["status"]}), flush=True)


if __name__ == "__main__":
    main()
