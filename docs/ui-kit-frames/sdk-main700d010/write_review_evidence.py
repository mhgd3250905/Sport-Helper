"""Summarize unmasked capture differences; preserve all source PNGs and receipts."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, data):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2, ensure_ascii=False)
        stream.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    checkout = args.checkout.resolve(strict=True)
    diff = read(root / "pixel-diff.json")
    runs = {variant: read(root / f"{variant}-receipts/run.json") for variant in ("base", "new")}
    manifests = {variant: {theme: read(root / variant / theme / "capture-manifest.json")
                          for theme in ("light", "dark")} for variant in ("base", "new")}
    for variant, run in runs.items():
        assert run["exitCode"] == 0
        for theme, manifest in manifests[variant].items():
            assert len(manifest["frames"]) == 65
            assert manifest["source"] == run["configuration"]["source"]
            assert manifest["publicInputsSha256"] == run["configuration"]["publicInputsSha256"]
            assert manifest["bubbleRepaintBoundaryCounts"] == [4]

    strip_rect = lambda rows: [{key: value for key, value in row.items() if key != "rect"} for row in rows]
    rect_maximum = 0.0
    semantic_meaning_differences = []
    strict_semantic_differences = []
    for frame in diff["frames"]:
        runtime = frame["runtimeComparison"]
        before, after = runtime["base"], runtime["new"]
        if (strip_rect(before["imageSemantics"]) != strip_rect(after["imageSemantics"])
                or before["focusClearSemantics"] != after["focusClearSemantics"]):
            semantic_meaning_differences.append(frame["frame"])
        assert len(before["imageSemantics"]) == len(after["imageSemantics"])
        for a, b in zip(before["imageSemantics"], after["imageSemantics"]):
            rect_maximum = max(rect_maximum, *(abs(x - y) for x, y in zip(a["rect"], b["rect"])))
        if not runtime["imageSemanticsEqual"] or not runtime["focusClearSemanticsEqual"]:
            strict_semantic_differences.append(frame["frame"])

    assert not semantic_meaning_differences
    historical_frames = [frame for manifest in manifests["base"].values() for frame in manifest["frames"]
                         if "historicalOriginalFrameByteIdentical" in frame]
    assert len(historical_frames) == 58 and all(frame["historicalOriginalFrameByteIdentical"] for frame in historical_frames)
    historical_names = {frame["frame"] for frame in historical_frames}
    historical_new = [frame for frame in diff["frames"] if frame["frame"] in historical_names]
    assert len(historical_new) == 58 and all(frame["differentPixels"] == 0 for frame in historical_new)

    package_config = checkout / ".dart_tool/package_config.json"
    packages = []
    for package in read(package_config)["packages"]:
        if package["name"] not in {"ugk_coach", "ugk_coach_ui", "ugk_trainer"}:
            continue
        uri = package["rootUri"]
        package_root = (Path(unquote(urlparse(uri).path).lstrip("/")) if uri.startswith("file:///")
                        else (package_config.parent / uri).resolve())
        resolved = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=package_root).decode().strip()
        assert resolved == "700d0100f1cb42ef122e774a6ee0076d1916b5e5"
        packages.append({"name": package["name"], "rootUri": uri, "resolvedHead": resolved})
    assert len(packages) == 3

    changed = [frame for frame in diff["frames"] if frame["differentPixels"]]
    review = root / "review"
    review.mkdir(exist_ok=False)
    crop_box = (100, 220, 205, 320)
    scale = 6
    font = ImageFont.load_default(size=18)
    panel_paths = []
    for frame in changed:
        old_image = Image.open(root / "base" / frame["frame"]).convert("RGBA")
        new_image = Image.open(root / "new" / frame["frame"]).convert("RGBA")
        a = np.asarray(old_image)
        b = np.asarray(new_image)
        mask = np.any(a != b, axis=2)
        diagnostic = np.zeros_like(a)
        diagnostic[:, :, 3] = 255
        diagnostic[mask, :3] = (255, 0, 0)
        diff_image = Image.fromarray(diagnostic)
        crops = [image.crop(crop_box).resize((630, 600), Image.Resampling.NEAREST)
                 for image in (old_image, new_image, diff_image)]
        canvas = Image.new("RGB", (1890, 668), "#eeeeee")
        draw = ImageDraw.Draw(canvas)
        draw.text((10, 8), f"{frame['frame']} | {frame['differentPixels']} pixels | max delta {frame['maxChannelDelta']}", fill="black", font=font)
        for index, (label, image) in enumerate(zip(("BASE 13c0bb4", "SDK700 de0bd432", "EXACT CHANGED PIXELS (RED)"), crops)):
            draw.text((index * 630 + 10, 36), label, fill="black", font=font)
            canvas.paste(image.convert("RGB"), (index * 630, 68))
        name = frame["frame"].replace("/", "--")
        with (review / name).open("xb") as stream:
            canvas.save(stream, format="PNG")
        panel_paths.append({"frame": frame["frame"], "review": f"review/{name}", "sha256": sha(review / name),
                            "sourceCropPhysicalPixels": list(crop_box), "nearestNeighborScale": scale,
                            "sourcePngsUnmodified": True, "differenceMask": "exact per-pixel RGBA inequality; no threshold"})

    all_evidence = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and not any(part in {"image-cache", "failed-base-handle-lifecycle"} for part in path.relative_to(root).parts):
            all_evidence[path.relative_to(root).as_posix()] = {"bytes": path.stat().st_size, "sha256": sha(path)}
    binding = {
        "schema": "smartfit-ui-kit-slots-source-bindings@3",
        "recordedUtc": datetime.now(timezone.utc).isoformat(),
        "source": {variant: {key: run["configuration"][key] for key in
                             ("source", "publicInputsSha256", "driverSha256", "adapterSha256")}
                   for variant, run in runs.items()},
        "sdkResolvedPackages": packages,
        "capture": {"themes": ["light", "dark"], "framesPerTheme": 65, "pairs": 130,
                    "logicalSize": {"width": 412, "height": 915}, "dpr": 2.625,
                    "driverSha256": manifests["base"]["light"]["driverSha256"],
                    "inputsSha256": manifests["base"]["light"]["inputsSha256"],
                    "originalDriverSha256": "81f80b15fbfc34526aca03c18e835c0234553f064c9a46ab4543c5f65ac6f154",
                    "originalInputsSha256": manifests["base"]["light"]["originalCaptureInputSha256"],
                    "planAndOriginalFramesUnchanged": True,
                    "original58BaselineHistoricalPngByteIdentical": True,
                    "original58NewVsBaselinePixelIdentical": True,
                    "baseAndNewCaptureTests": {"base": {"passed": 2, "exitCode": 0}, "new": {"passed": 2, "exitCode": 0}},
                    "headAndCompiledInputsUnchangedDuringBothRuns": True,
                    "bubbleRuntimeRepaintBoundaryCounts": {"base": [4], "new": [4]},
                    "fonts": manifests["base"]["light"]["fonts"],
                    "samples": manifests["base"]["light"]["capturePlan"]},
        "pixelDiffSummary": diff["summary"],
        "semanticExplanation": {"strictDifferentFrames": len(strict_semantic_differences),
                                "strictDifferentFrameNames": strict_semantic_differences,
                                "allLabelsImageFlagsAndFocusTapSemanticsEqual": True,
                                "maximumAbsoluteLocalRectDifferenceLogicalPixels": rect_maximum,
                                "rawRectDifferencesPreserved": True,
                                "toleranceAppliedToRawComparison": False},
        "legacyFixture": manifests["base"]["light"]["legacyAlpha"],
        "diagnosticPanels": panel_paths,
        "renderingDifferenceInference": {
            "status": "reported; no production adjustment made",
            "base": "Shared ClipOval outside Stack and per-image Transform.scale",
            "new": "SDK builder path removes shared ClipOval; production host ClipOval is inside per-image Transform.scale",
            "pixelObservation": "All 13 nonzero frames lie within the silhouette; only intermediate reveal/crossfade samples differ",
            "causalStatus": "source-supported inference, not a new compensated-render experiment",
            "sourceLocations": {"base": "13c0bb4:lib/ui/chat/coach_task_bubble.dart:662",
                                "sdk": "700d010:packages/ugk_coach_ui/lib/src/task_bubble.dart:721",
                                "host": "de0bd432:lib/ui/chat/coach_ui_adapter.dart:52"}},
        "failedAttempt": {"path": "failed-base-handle-lifecycle",
                          "cause": "Capture test SemanticsHandle was disposed in addTearDown after framework verification",
                          "resolution": "Dispose in test-body try/finally; no application source or pixels altered",
                          "isFormalEvidence": False},
        "harkAcceptance": "pending; pixel zero gate currently not met",
        "isPhoneScreenshot": False,
        "isPerformanceMeasurement": False,
        "artifactIntegrity": all_evidence,
    }
    write_json(root / "source-bindings.json", binding)
    lines = ["# SDK700 剪影帧差异说明", "",
             "基准 `13c0bb4` 与正式源码 `de0bd432`，同一 driver/input、412×915、DPR 2.625。两边各 130 帧；两边 capture tests 均 2/2 通过。", "",
             "**117/130 帧像素完全相同；13 帧共 299 个不同像素，单帧最多 81，最大通道差 59/255。严格零像素门禁未通过，也未满足全部抗锯齿候选规则。**", "",
             "原 58 帧在新 baseline 与历史 baseline 逐字节相同，SDK700 对这 58 帧的不同像素数也全部为 0。新增标签进入/退出边界帧全部为 0；差异只出现在新增的剪影首揭示和交叉淡入中间点。未修改生产 renderer 或任何动效数值。", "",
             "| 帧 | 不同像素 | 最大通道差 | 物理像素 bbox（右/下不含） |", "| --- | ---: | ---: | --- |"]
    for frame in changed:
        lines.append(f"| {frame['frame']} | {frame['differentPixels']} | {frame['maxChannelDelta']} | {frame['bbox']} |")
    lines.extend(["", "源码对照显示旧实现为 `ClipOval(Stack(Transform.scale(SfAlphaAsset)))`，新 SDK builder 路径移除公共 ClipOval，宿主返回的 ClipOval 位于每图 Transform 内。裁切相对于缩放的位置改变，与中间态剪影边缘的差异吻合；这是源码支持的原因推断，尚未通过改代码做补偿实验。按要求先报告，交 SDK/Hark 裁决。", "",
                  "实际 bubble 子树 RepaintBoundary 两边均为 **4**；legacy 裁切 CustomPaint 数量每帧一致，1025ms 为两张原图的两个 painter。动作 label/image 标志和标签清除按钮 button/tap 全部相同。严格语义矩形比较有 26 帧不同，仅为局部矩形的浮点运算尾数，最大绝对差 **1.4210854715202004e-14 逻辑像素**；原始值仍保留在 pixel-diff.json，未取整或以容差掩盖。", "",
                  "legacy 输入来自 manifest 可追溯的 +31 APK 两张原 alphaThumbnail，原始完整 index/bounds 与图片 SHA 均已断言，没有造图或改边界。", "",
                  "`review/` 为非验收替代图的诊断放大板：原图物理 ROI [100,220,205,320]，nearest-neighbor 放大 6 倍，左右为原 baseline/SDK 像素，红色面板仅显示精确 RGBA 不同像素。完整原图仍在 base/new，未改写。", "",
                  "完整每帧表见 pixel-diff.md；原始统计、语义矩形、SHA 与源码绑定见 pixel-diff.json / source-bindings.json。手机、profile 性能与 Hark 验收均不由这组测试建立。", ""])
    with (root / "review-notes.md").open("x", encoding="utf-8", newline="\n") as stream:
        stream.write("\n".join(lines))
    print(json.dumps({"pairs": 130, "differentFrames": len(changed), "totalDifferentPixels": diff["summary"]["totalDifferentPixels"],
                      "strictSemanticDifferentFrames": len(strict_semantic_differences), "maximumRectDifference": rect_maximum,
                      "sourceBindingsSha256": sha(root / "source-bindings.json"), "reviewPanels": len(panel_paths)}))


if __name__ == "__main__":
    main()
