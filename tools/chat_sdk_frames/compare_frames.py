"""Exact full-RGBA comparison for the immutable 22 SF chat key frames."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames-root", type=Path, required=True)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--receipts", type=Path, required=True)
    parser.add_argument("--output-prefix", type=Path, required=True)
    args = parser.parse_args()
    root = args.frames_root.resolve(strict=True)
    baseline = read(root / "baseline-source-bindings.json")
    run = read(args.receipts / "run.json")
    rows = []
    waiting_boundaries = []
    observed_routes = []
    for frame in baseline["frames"]:
        name = frame["frame"]
        base_path, new_path = root / "base" / f"{name}.png", args.new / f"{name}.png"
        assert sha(base_path) == frame["png"]["sha256"]
        row = {"frame": name, "baselineSha256": sha(base_path),
               "inputSha256": frame["input"]["sha256"], "width": 390, "height": 844}
        if not new_path.exists():
            rows.append({**row, "captured": False, "differentPixels": None, "passed": False})
            continue
        a = np.asarray(Image.open(base_path).convert("RGBA"), dtype=np.int16)
        b = np.asarray(Image.open(new_path).convert("RGBA"), dtype=np.int16)
        assert a.shape == b.shape == (844, 390, 4)
        delta = np.abs(a - b)
        changed = np.any(delta != 0, axis=2)
        count = int(np.count_nonzero(changed))
        y, x = np.nonzero(changed)
        metadata = read(new_path.with_suffix(".json"))
        assert metadata["sourceFixtureSha256"] == frame["input"]["sha256"]
        assert metadata["pngSha256"] == sha(new_path)
        if name.endswith("waiting-250ms"):
            waiting_boundaries.append(metadata["bubbleRepaintBoundaryCount"])
            assert metadata["bubbleRepaintBoundaryCount"] == 4
        if metadata["trainingRoute"] is not None:
            observed_routes.append({"frame": name, **metadata["trainingRoute"],
                                    "sdkSourceTransitionHoldActive": metadata["sdkSourceTransitionHoldActive"]})
        rows.append({**row, "captured": True, "differentPixels": count,
                     "totalPixels": int(changed.size), "maxChannelDelta": int(delta.max()),
                     "meanChannelDelta": float(delta.mean()),
                     "bbox": [int(x.min()), int(y.min()), int(x.max()) + 1, int(y.max()) + 1] if count else None,
                     "newSha256": sha(new_path), "passed": count == 0,
                     "pngBytesIdentical": sha(base_path) == sha(new_path)})
    assert len(rows) == 22
    summary = {"framesRequired": 22, "framesCaptured": sum(row["captured"] for row in rows),
               "zeroPixelFrames": sum(row["passed"] for row in rows),
               "nonzeroFrames": sum(row["captured"] and not row["passed"] for row in rows),
               "missingFrames": [row["frame"] for row in rows if not row["captured"]],
               "totalDifferentPixels": sum(row["differentPixels"] or 0 for row in rows),
               "strict22FrameZeroGatePassed": all(row["passed"] for row in rows) and run["exitCode"] == 0,
               "captureExitCode": run["exitCode"],
               "waitingBubbleRepaintBoundaryCounts": waiting_boundaries,
               "actualSfSdkTrainingRouteFramesObserved": len(observed_routes),
               "baselineSource": baseline["baselineSourceCommit"],
               "newSource": run["configuration"].get("sourceDescription", run["configuration"]["source"]),
               "capturedBytesCommittedSource": run["configuration"].get("capturedBytesCommittedSource"),
               "sdkPin": run["configuration"]["sdkPin"],
               "noCropMaskOrTolerance": True,
               "harkAcceptance": "pending; not inferred from pixel equality",
               "isPhoneOrPerformanceEvidence": False}
    bindings = {"schema": "smartfit-real-sdk-chat-frame-comparison@1", "summary": summary,
                "baselineBindingsSha256": sha(root / "baseline-source-bindings.json"),
                "newRunReceiptSha256": sha(args.receipts / "run.json"),
                "newConfiguration": run["configuration"],
                "headAndCompiledInputsUnchanged": run["headAndCompiledInputsUnchanged"],
                "resolvedPackageSourcesUnchanged": run["resolvedPackageSourcesUnchanged"],
                "sealedBaselinePngsUnchanged": run["sealedBaselinePngsUnchanged"],
                "actualTrainingRouteObservations": observed_routes,
                "frames": rows}
    args.output_prefix.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output_prefix.with_suffix(".json"), bindings)
    lines = ["# SF actual SDK chat key-frame comparison", "",
             f"Base `{summary['baselineSource']}`; actual migrated SF `{summary['newSource']}`; SDK `{summary['sdkPin']}`.", "",
             f"**{summary['zeroPixelFrames']}/22 frames have zero RGBA pixel differences; {summary['totalDifferentPixels']} changed pixels. Strict zero gate: {summary['strict22FrameZeroGatePassed']}.**", "",
             "390×844, DPR1, top/bottom inset24. Frozen v7 images/JSON, actual SF factory profile/host actions, SF ChatHomePage → SDK CoachChatPage. No crop, mask, placeholder or tolerance. Widget captures are not device/performance acceptance.", "",
             "| Frame | Captured | Different pixels | Max channel delta | Bounding box | PNG bytes identical |",
             "| --- | --- | ---: | ---: | --- | --- |"]
    for row in rows:
        lines.append(f"| {row['frame']} | {row['captured']} | {row['differentPixels']} | {row.get('maxChannelDelta')} | {row.get('bbox')} | {row.get('pngBytesIdentical')} |")
    with args.output_prefix.with_suffix(".md").open("x", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(lines) + "\n")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
