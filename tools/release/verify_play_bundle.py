"""Inspect the actual AAB: identity, permissions, native alignment and secrets.

Only diagnostic labels and file names are emitted; matched secret values are
never printed. This complements, rather than replaces, review of build inputs.
"""
import argparse
import hashlib
import json
import re
import struct
import subprocess
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
AI_HOSTS = (b"api.uuugk.win", b"ugk-ai-proxy.294851575.workers.dev")
SECRET_PATTERNS = {
    "provider_secret": re.compile(rb"\bsk-[A-Za-z0-9_-]{32,}\b"),
    "google_api_key": re.compile(rb"AIza[A-Za-z0-9_-]{35}"),
    "private_key_block": re.compile(
        rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{80,}"
    ),
}


def elf_load_alignments(data):
    if data[:4] != b"\x7fELF" or data[4] != 2:
        return None
    endian = "<" if data[5] == 1 else ">"
    offset = struct.unpack_from(endian + "Q", data, 32)[0]
    size, count = struct.unpack_from(endian + "HH", data, 54)
    alignments = []
    for index in range(count):
        header = offset + index * size
        if struct.unpack_from(endian + "I", data, header)[0] == 1:
            alignments.append(struct.unpack_from(endian + "Q", data, header + 48)[0])
    return alignments


def inspect(bundle, java, bundletool, expected_build):
    command = [java, "-jar", bundletool, "dump", "manifest", f"--bundle={bundle}", "--module=base"]
    manifest = ET.fromstring(subprocess.run(command, capture_output=True, check=True).stdout)
    app = manifest.find("application")
    sdk = manifest.find("uses-sdk")
    report = {
        "bundle": str(bundle),
        "bytes": bundle.stat().st_size,
        "sha256": hashlib.file_digest(bundle.open("rb"), "sha256").hexdigest(),
        "applicationId": manifest.get("package"),
        "versionName": manifest.get(ANDROID + "versionName"),
        "versionCode": int(manifest.get(ANDROID + "versionCode")),
        "minSdk": int(sdk.get(ANDROID + "minSdkVersion")),
        "targetSdk": int(sdk.get(ANDROID + "targetSdkVersion")),
        "debuggable": app.get(ANDROID + "debuggable", "false") == "true",
        "allowBackup": app.get(ANDROID + "allowBackup", "true") == "true",
        "permissions": sorted(node.get(ANDROID + "name") for node in manifest.findall("uses-permission")),
        "secretFindings": [],
        "aiHostStrings": [],
        "native64BitLibraries": [],
        "issues": [],
        "scope": "Static AAB inspection plus explicit no-AI build inputs; not a network capture or Play review.",
    }
    allowed_permissions = {
        "android.permission.INTERNET", "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.WAKE_LOCK", "com.ugk.smartfit.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
    }
    if (report["applicationId"], report["versionName"], report["versionCode"]) != (
        "com.ugk.smartfit", "1.0.0", expected_build
    ):
        report["issues"].append("release_identity_mismatch")
    if report["debuggable"] or report["allowBackup"] or report["targetSdk"] < 36:
        report["issues"].append("release_manifest_contract_failed")
    if set(report["permissions"]) - allowed_permissions:
        report["issues"].append("unexpected_permissions")
    with zipfile.ZipFile(bundle) as archive:
        for name in archive.namelist():
            if name.endswith("/"):
                continue
            lower = name.lower()
            if lower.endswith((".jks", ".keystore", ".p12", ".pfx", "/key.properties", "/signing.properties")):
                report["secretFindings"].append({"file": name, "kind": "forbidden_secret_container"})
            data = archive.read(name)
            for kind, pattern in SECRET_PATTERNS.items():
                if pattern.search(data):
                    report["secretFindings"].append({"file": name, "kind": kind})
            for host in AI_HOSTS:
                if host in data:
                    report["aiHostStrings"].append({"file": name, "host": host.decode("ascii")})
            if lower.endswith(".so"):
                alignments = elf_load_alignments(data)
                if alignments is not None:
                    report["native64BitLibraries"].append({"file": name, "loadAlignments": alignments})
                    if not alignments or min(alignments) < 16384:
                        report["issues"].append("native_library_not_16kb_aligned:" + name)
    if report["secretFindings"]:
        report["issues"].append("potential_secret_in_bundle")
    report["passed"] = not report["issues"]
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--java", required=True)
    parser.add_argument("--bundletool", required=True)
    parser.add_argument("--build", type=int, default=23)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    result = inspect(args.bundle.resolve(), args.java, args.bundletool, args.build)
    args.report.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, ensure_ascii=False))
    raise SystemExit(0 if result["passed"] else 1)
