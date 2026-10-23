#!/usr/bin/env python3
"""Reject APKs whose R8 output breaks SharedPreferences' fixed JNI lookups.

Contract: shared_preferences_android 2.5.0 (Pigeon 29.0.10), package:jni 1.1.0.
The Kotlin requirements match the six upstream 2.5.2 consumer keep rules:
https://github.com/flutter/packages/blob/shared_preferences_android-v2.5.2/
packages/shared_preferences/shared_preferences_android/android/consumer-rules.pro

Uses only the Python standard library. Reads DEX definitions, not merely string
or method references: a reference to a removed/renamed class must not pass.
This verifies binary compatibility; it does not claim device execution passed.
"""

import argparse
import hashlib
import json
import re
import struct
import sys
import zipfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path


PACKAGE = "Lio/flutter/plugins/sharedpreferences/"
CONTINUATION = "Lkotlin/coroutines/Continuation;"
OPTIONS = PACKAGE + "SharedPreferencesPigeonOptions;"
OBJECT = "Ljava/lang/Object;"
STRING = "Ljava/lang/String;"
LIST = "Ljava/util/List;"
KOTLIN_CLASSES = (
    "Lkotlin/Unit;", "Lkotlin/Result;", "Lkotlin/Result$Failure;",
    CONTINUATION,
    "Lkotlin/coroutines/intrinsics/CoroutineSingletons;",
    "Lkotlin/coroutines/intrinsics/IntrinsicsKt;",
)


class InvalidDex(ValueError):
    """Malformed or unsupported DEX. Messages are fixed diagnostic codes."""


@dataclass
class DexClass:
    parent: str | None
    methods: dict[tuple[str, str], int] = field(default_factory=dict)
    fields: dict[tuple[str, str], int] = field(default_factory=dict)


class Dex:
    def __init__(self, data: bytes):
        self.data = data
        if (len(data) < 112 or not re.fullmatch(rb"dex\n0(?:3[5-9]|40)\0", data[:8])
                or self.u32(32) != len(data) or self.u32(36) != 112
                or self.u32(40) != 0x12345678):
            raise InvalidDex("invalid_dex_header")
        if (hashlib.sha1(data[32:]).digest() != data[12:32]
                or zlib.adler32(data[12:]) & 0xFFFFFFFF != self.u32(8)):
            raise InvalidDex("invalid_dex_checksum")
        self.strings = [self.string(self.u32(off)) for off in self.table(56, 4)]
        self.types = [self.index(self.strings, self.u32(off))
                      for off in self.table(64, 4)]
        self.protos = []
        for off in self.table(72, 12):
            result = self.index(self.types, self.u32(off + 4))
            args = self.u32(off + 8)
            params = ""
            if args:
                size = self.u32(args)
                self.bounds(args + 4, size * 2)
                params = "".join(self.index(self.types, self.u16(args + 4 + i * 2))
                                 for i in range(size))
            self.protos.append(f"({params}){result}")
        self.fields = []
        for off in self.table(80, 8):
            self.fields.append((self.index(self.types, self.u16(off)),
                                self.index(self.strings, self.u32(off + 4)),
                                self.index(self.types, self.u16(off + 2))))
        self.methods = []
        for off in self.table(88, 8):
            self.methods.append((self.index(self.types, self.u16(off)),
                                 self.index(self.strings, self.u32(off + 4)),
                                 self.index(self.protos, self.u16(off + 2))))
        self.classes = {}
        for off in self.table(96, 32):
            name = self.index(self.types, self.u32(off))
            parent_idx = self.u32(off + 8)
            parent = None if parent_idx == 0xFFFFFFFF else self.index(self.types, parent_idx)
            if name in self.classes:
                raise InvalidDex("duplicate_dex_class")
            cls = self.classes[name] = DexClass(parent)
            pos = self.u32(off + 24)
            if not pos:
                continue
            counts = []
            for _ in range(4):
                value, pos = self.uleb(pos)
                counts.append(value)
            for section, count in enumerate(counts):
                members = self.fields if section < 2 else self.methods
                if count > len(members):
                    raise InvalidDex("invalid_dex_member_count")
                idx = 0
                for _ in range(count):
                    diff, pos = self.uleb(pos)
                    idx += diff
                    flags, pos = self.uleb(pos)
                    owner, member, descriptor = self.index(members, idx)
                    if owner != name:
                        raise InvalidDex("invalid_dex_member_owner")
                    if section >= 2:
                        code, pos = self.uleb(pos)
                        if code:
                            self.bounds(code, 16)
                    target = cls.fields if section < 2 else cls.methods
                    if (member, descriptor) in target:
                        raise InvalidDex("duplicate_dex_member")
                    target[member, descriptor] = flags

    @staticmethod
    def index(items, idx):
        if idx < 0 or idx >= len(items):
            raise InvalidDex("invalid_dex_index")
        return items[idx]

    def bounds(self, offset, size):
        if offset < 0 or size < 0 or offset + size > len(self.data):
            raise InvalidDex("invalid_dex_offset")

    def u32(self, offset):
        self.bounds(offset, 4)
        return struct.unpack_from("<I", self.data, offset)[0]

    def u16(self, offset):
        self.bounds(offset, 2)
        return struct.unpack_from("<H", self.data, offset)[0]

    def table(self, header_offset, width):
        size, offset = self.u32(header_offset), self.u32(header_offset + 4)
        if size and offset < 112:
            raise InvalidDex("invalid_dex_table")
        self.bounds(offset, size * width)
        return range(offset, offset + size * width, width)

    def uleb(self, pos):
        value = 0
        for shift in range(0, 35, 7):
            self.bounds(pos, 1)
            byte = self.data[pos]
            pos += 1
            if shift == 28 and byte > 15:
                raise InvalidDex("invalid_dex_uleb128")
            value |= (byte & 127) << shift
            if not byte & 128:
                return value, pos
        raise InvalidDex("invalid_dex_uleb128")

    def string(self, pos):
        _, pos = self.uleb(pos)  # UTF-16 length; compared identifiers are ASCII.
        end = self.data.find(b"\0", pos)
        if end < 0:
            raise InvalidDex("invalid_dex_string")
        return self.data[pos:end].decode("utf-8", errors="replace")


def required_methods():
    methods = []
    for name, params in (
        ("SharedPreferencesApiRegistrar", {
            "remove": STRING, "setBool": STRING + "Z", "setString": STRING * 2,
            "setInt": STRING + "J", "setDouble": STRING + "D",
            "setEncodedStringList": STRING * 2,
            "setDeprecatedStringList": STRING + LIST,
            "clear": STRING + LIST, "getAll": STRING + LIST,
        }),
        ("SharedPreferencesAsyncApiRegistrar", {
            "setBool": STRING + "Z", "setString": STRING * 2,
            "setInt": STRING + "J", "setDouble": STRING + "D",
            "setEncodedStringList": STRING * 2,
            "setDeprecatedStringList": STRING + LIST,
            "getString": STRING, "getInt": STRING, "getBool": STRING,
            "getDouble": STRING, "getPlatformEncodedStringList": STRING,
            "getStringList": STRING, "clear": LIST, "getAll": LIST,
            "getKeys": LIST,
        }),
    ):
        owner = PACKAGE + name + ";"
        api = PACKAGE + name.removesuffix("Registrar") + ";"
        methods.extend([
            (owner, "<init>", "()V", False),
            (owner, "register", f"({api}{STRING}){owner}", False),
            (owner, "getInstance", f"({STRING}){owner}", False),
        ])
        for method, arguments in params.items():
            if name == "SharedPreferencesAsyncApiRegistrar":
                arguments += OPTIONS
            methods.append((owner, method, f"({arguments}{CONTINUATION}){OBJECT}", False))
    methods.extend([
        (CONTINUATION, "resumeWith", f"({OBJECT})V", False),
        ("Lkotlin/Result$Failure;", "<init>", "(Ljava/lang/Throwable;)V", False),
        ("Lkotlin/coroutines/intrinsics/IntrinsicsKt;", "getCOROUTINE_SUSPENDED",
         f"(){OBJECT}", True),
    ])
    return methods


def find_member(classes, owner, name, descriptor, static, kind):
    """JNI lookups can resolve inherited members; constructors cannot inherit."""
    seen = set()
    while owner in classes and owner not in seen:
        seen.add(owner)
        cls = classes[owner]
        flags = getattr(cls, kind).get((name, descriptor))
        if flags is not None and bool(flags & 0x8) == static:
            return owner
        if name == "<init>":
            break
        owner = cls.parent
    return None


def verify_apk(path):
    report = {
        "schema": 1, "check": "android_storage_jni", "passed": False,
        "contract": {"sharedPreferencesAndroid": "2.5.0", "jni": "1.1.0"},
        "apk": {"name": path.name, "bytes": path.stat().st_size},
    }
    with path.open("rb") as handle:
        report["apk"]["sha256"] = hashlib.file_digest(handle, "sha256").hexdigest()
    classes = {}
    with zipfile.ZipFile(path) as apk:
        names = [name for name in apk.namelist()
                 if re.fullmatch(r"classes(?:[2-9]|[1-9][0-9]+)?\.dex", name)]
        if not names or len(names) != len(set(names)):
            raise InvalidDex("invalid_apk_dex_entries")
        for name in sorted(names):
            parsed = Dex(apk.read(name))
            if classes.keys() & parsed.classes.keys():
                raise InvalidDex("duplicate_apk_dex_class")
            classes.update(parsed.classes)
    report["dexFiles"] = sorted(names)
    required_classes = (*KOTLIN_CLASSES, PACKAGE + "SharedPreferencesApiRegistrar;",
                        PACKAGE + "SharedPreferencesAsyncApiRegistrar;")
    report["classes"] = [dict(descriptor=name, present=name in classes)
                         for name in required_classes]
    report["methods"] = []
    for owner, name, descriptor, static in required_methods():
        declared_in = find_member(classes, owner, name, descriptor, static, "methods")
        check = dict(owner=owner, name=name, descriptor=descriptor,
                     static=static, present=declared_in is not None)
        if declared_in:
            check["declaredIn"] = declared_in
        elif owner in classes:
            check["observedDescriptors"] = sorted(
                actual for member, actual in classes[owner].methods if member == name)
        report["methods"].append(check)
    report["fields"] = []
    for owner, name, descriptor, static in (
        ("Lkotlin/Unit;", "INSTANCE", "Lkotlin/Unit;", True),
        ("Lkotlin/Result;", "value", OBJECT, False),
        ("Lkotlin/Result$Failure;", "exception", "Ljava/lang/Throwable;", False),
    ):
        declared_in = find_member(classes, owner, name, descriptor, static, "fields")
        report["fields"].append(dict(owner=owner, name=name, descriptor=descriptor,
                                     static=static, present=declared_in is not None,
                                     **({"declaredIn": declared_in} if declared_in else {})))
    report["failedChecks"] = [
        {"kind": kind, **check} for kind in ("classes", "methods", "fields")
        for check in report[kind] if not check["present"]
    ]
    report["passed"] = not report["failedChecks"]
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(argv)
    if args.report and args.report.resolve() == args.apk.resolve():
        parser.error("--report must not overwrite the APK")
    try:
        report = verify_apk(args.apk)
    except (InvalidDex, OSError, zipfile.BadZipFile, RuntimeError) as error:
        report = {
            "schema": 1, "check": "android_storage_jni", "passed": False,
            "apk": {"name": args.apk.name},
            "error": str(error) if isinstance(error, InvalidDex) else type(error).__name__,
        }
    output = json.dumps(report, indent=2) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output, encoding="utf-8", newline="\n")
    print(json.dumps({
        "check": report["check"], "apk": report["apk"]["name"],
        "passed": report["passed"],
        "failedChecks": len(report.get("failedChecks", [])),
        **({"error": report["error"]} if "error" in report else {}),
    }))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
