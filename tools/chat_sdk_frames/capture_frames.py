"""Run the real SF chat migration capture against the frozen 22-frame inputs.

No pub get, package override, SDK checkout, baseline rewrite, or App source edit
is performed. Obtain an exclusive Flutter window before running this launcher.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
SDK_PIN = "a13e3b674359c93c941f7f59d1edf09a6d609487"
SDK_PACKAGES = {"ugk_coach", "ugk_coach_ui", "ugk_trainer", "ugk_trainer_runtime", "ugk_coach_chat"}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root).decode().strip()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")


def source_inputs(root):
    paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=root).decode().split("\0")
    paths = [path for path in paths if path and
             (path.startswith(("lib/", "test/", "assets/", "android/", "tools/chat_sdk_frames/")) or
              path in {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}) and
             (root / path).is_file() and "__pycache__" not in Path(path).parts]
    rows = {name: sha((root / name).read_bytes()) for name in sorted(paths)}
    return {"sha256": sha(json.dumps(rows, sort_keys=True, separators=(",", ":")).encode()), "files": rows}


def package_sources(checkout, flutter):
    config_file = checkout / ".dart_tool/package_config.json"
    rows = []
    for package in read(config_file)["packages"]:
        name = package["name"]
        if name not in SDK_PACKAGES | {"flutter", "flutter_test"}:
            continue
        uri = package["rootUri"]
        path = (Path(unquote(urlparse(uri).path).lstrip("/")) if uri.startswith("file:///")
                else (config_file.parent / uri).resolve())
        head = git(path, "rev-parse", "HEAD")
        status = git(path, "status", "--porcelain")
        if name in SDK_PACKAGES:
            assert head == SDK_PIN and not status, f"SDK source is not clean pinned main: {name}"
            assert "pub-cache" in str(path).lower(), f"Use resolved pin, not an SDK working branch: {path}"
        else:
            assert path.resolve() == (flutter.parent.parent / "packages" / name).resolve()
            assert head.startswith("84fc5cbb22"), f"Mixed Flutter framework: {path}"
        rows.append({"name": name, "rootUri": uri, "head": head, "workingTreeStatus": status})
    assert {row["name"] for row in rows} == SDK_PACKAGES | {"flutter", "flutter_test"}
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkout", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--receipts", type=Path, required=True)
    parser.add_argument("--flutter", type=Path, required=True)
    parser.add_argument("--pub-cache", type=Path)
    parser.add_argument("--expected-source", required=True)
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    assert Path(git(checkout, "rev-parse", "--show-toplevel")).resolve() == checkout
    head = git(checkout, "rev-parse", "HEAD")
    assert head == args.expected_source, "Capture only the agreed frozen source."
    flutter = args.flutter.resolve(strict=True)
    baseline = args.baseline.resolve(strict=True)
    output, receipts = args.output.resolve(), args.receipts.resolve()
    assert not output.exists() and not receipts.exists(), "Preserve existing capture output and receipts."
    assert not output.is_relative_to(baseline) and not baseline.is_relative_to(output)
    frozen = read(HERE / "frozen-inputs.json")
    baseline_rows = {}
    for filename, identity in frozen["inputs"].items():
        raw = (HERE / "inputs" / filename).read_bytes()
        assert len(raw) == identity["bytes"] and sha(raw) == identity["sha256"]
        assert (baseline / filename).read_bytes() == raw
        png = baseline / filename.replace(".json", ".png")
        baseline_rows[png.name] = sha(png.read_bytes())
    assert len(baseline_rows) == 22
    baseline_binding = read(baseline.parent / "baseline-source-bindings.json")
    for frame in baseline_binding["frames"]:
        assert baseline_rows[f"{frame['frame']}.png"] == frame["png"]["sha256"]
    media = read(HERE / "media-inputs.json")
    assert sha((checkout / "assets/posehub/images-index.json").read_bytes()) == media["sourceImageIndex"]["sha256"]
    for row in media["images"]:
        target = checkout / row["asset"]
        assert target.is_file(), f"Have the host provision the real image before capturing: {target}"
        raw = target.read_bytes()
        assert len(raw) == row["bytes"] and sha(raw) == row["sha256"]
    assert sha((checkout / "assets/fonts/NotoSansSC.ttf").read_bytes()) == frozen["notoSansSc"]["sha256"]
    packages = package_sources(checkout, flutter)
    inputs = source_inputs(checkout)
    source_status = git(checkout, "status", "--porcelain")
    driver = checkout / "tools/chat_sdk_frames/capture_test.dart"
    assert driver.read_bytes() == (HERE / "capture_test.dart").read_bytes()
    output.mkdir(parents=True)
    receipts.mkdir(parents=True)
    env = dict(os.environ, PUB_HOSTED_URL="https://pub.dev", CHAT_CAPTURE_OUTPUT=str(output),
               CHAT_CAPTURE_BASELINE=str(baseline), CHAT_CAPTURE_INPUTS=str(HERE / "inputs"))
    if args.pub_cache:
        env["PUB_CACHE"] = str(args.pub_cache.resolve(strict=True))
    command = [str(flutter), "test", "--no-pub", "--flavor", "internal", "--concurrency=1", "-r", "expanded",
               "--dart-define=SMARTFIT_ALPHA_CARDS=true", "--dart-define=SMARTFIT_POSEHUB_PACK=true",
               "--dart-define=UGK_INTERNAL_MEDIA_PREVIEW=true", "tools/chat_sdk_frames/capture_test.dart"]
    configuration = {"source": head, "recordedUtc": datetime.now(timezone.utc).isoformat(),
                     "sourceWorkingTreeStatus": source_status,
                     "sourceIsCleanCommit": not source_status,
                     "sourceDescription": head + (" + WIP (compiled input hashes recorded)" if source_status else ""),
                     "capturedBytesCommittedSource": None if source_status else head,
                     "compiledInputSha256": inputs["sha256"],
                     "sdkPin": SDK_PIN, "packages": packages, "command": command,
                     "driverSha256": sha(driver.read_bytes()), "inputSetSha256": frozen["inputsSha256"],
                     "baselinePngs": baseline_rows,
                     "baselineBindingsSha256": sha((baseline.parent / "baseline-source-bindings.json").read_bytes()),
                     "actualProfileAndHost": "SF createSmartfitChat.profile + bindings.actions; SF ChatHomePage -> SDK CoachChatPage",
                     "onlyControllerTestOverride": "read-only suggestions getter; canonical snapshot restoration via normal admission",
                     "comparison": "Flutter GoldenFileComparator.compareLists default zero threshold; no comparator override",
                     "isPhoneOrPerformanceEvidence": False}
    write_json(receipts / "configuration.json", configuration)
    flags = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}
    with (receipts / "flutter-version.txt").open("x", encoding="utf-8", newline="\n") as stream:
        version_result = subprocess.run([str(flutter), "--version"], cwd=checkout, env=env, stdout=stream, stderr=subprocess.STDOUT, **flags)
    assert version_result.returncode == 0
    version = (receipts / "flutter-version.txt").read_text(encoding="utf-8")
    assert all(value in version for value in ("Flutter 3.44.7", "Dart 3.12.2", "84fc5cbb22", "69c8c61792"))
    with (receipts / "capture.log").open("x", encoding="utf-8", newline="\n") as stream:
        result = subprocess.run(command, cwd=checkout, env=env, stdout=stream, stderr=subprocess.STDOUT, **flags)
    unchanged = git(checkout, "rev-parse", "HEAD") == head and source_inputs(checkout) == inputs
    same_packages = package_sources(checkout, flutter) == packages
    for filename, digest in baseline_rows.items():
        assert sha((baseline / filename).read_bytes()) == digest, "Frozen baseline was changed."
    write_json(receipts / "run.json", {"configuration": configuration, "compiledInputs": inputs,
                                      "exitCode": result.returncode, "headAndCompiledInputsUnchanged": unchanged,
                                      "resolvedPackageSourcesUnchanged": same_packages,
                                      "sealedBaselinePngsUnchanged": True,
                                      "captureLogSha256": sha((receipts / "capture.log").read_bytes())})
    assert unchanged and same_packages, "Source or pin changed during capture."
    print(json.dumps({"source": head, "exitCode": result.returncode, "output": str(output),
                      "driverSha256": configuration["driverSha256"]}))
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
