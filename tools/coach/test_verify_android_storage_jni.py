"""Exercise binary definition checks without depending on a local release APK."""

import hashlib
import importlib.util
import struct
import sys
import unittest
import zlib
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "verify_android_storage_jni", Path(__file__).with_name("verify_android_storage_jni.py"))
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)
Dex, DexClass, InvalidDex, find_member = (
    MODULE.Dex, MODULE.DexClass, MODULE.InvalidDex, MODULE.find_member)


def seal(data):
    struct.pack_into("<I", data, 32, len(data))
    data[12:32] = hashlib.sha1(data[32:]).digest()
    struct.pack_into("<I", data, 8, zlib.adler32(data[12:]) & 0xFFFFFFFF)
    return bytes(data)


def small_dex(*, defined):
    """A DEX table fixture with a method ID that may have no definition."""
    data = bytearray(192)
    data[:8] = b"dex\n039\0"
    struct.pack_into("<II", data, 36, 112, 0x12345678)
    struct.pack_into("<II", data, 56, 4, 112)  # string IDs
    struct.pack_into("<II", data, 64, 3, 128)  # type IDs
    struct.pack_into("<II", data, 72, 1, 140)  # proto IDs
    struct.pack_into("<II", data, 88, 1, 152)  # method IDs
    struct.pack_into("<II", data, 96, 1, 160)  # class definitions
    struct.pack_into("<III", data, 128, 0, 1, 2)
    struct.pack_into("<III", data, 140, 2, 2, 0)  # ()V
    struct.pack_into("<HHI", data, 152, 0, 0, 3)
    struct.pack_into("<IIIIIIII", data, 160, 0, 1, 1, 0, 0xFFFFFFFF, 0, 192, 0)
    # virtual native public probe(), or no definitions (only a method ID).
    data.extend(b"\0\0\0\1\0\x81\x02\0" if defined else b"\0\0\0\0")
    for i, value in enumerate(("LExample;", "Ljava/lang/Object;", "V", "probe")):
        struct.pack_into("<I", data, 112 + 4 * i, len(data))
        data.extend(bytes([len(value)]) + value.encode("ascii") + b"\0")
    struct.pack_into("<II", data, 104, len(data) - 192, 192)
    return seal(data)


class DexCheckTest(unittest.TestCase):
    def test_reference_alone_cannot_satisfy_a_jni_member_lookup(self):
        for defined in (False, True):
            dex = Dex(small_dex(defined=defined))
            self.assertEqual(dex.methods, [("LExample;", "probe", "()V")])
            result = find_member(dex.classes, "LExample;", "probe", "()V", False, "methods")
            self.assertEqual(result is not None, defined)
            self.assertIsNone(find_member(dex.classes, "LExample;", "probe", "()V", True, "methods"))

    def test_invalid_header_checksum_and_table_offsets_are_rejected(self):
        with self.assertRaises(InvalidDex):
            Dex(b"dex\n039\0")
        data = bytearray(small_dex(defined=True))
        data[-2] ^= 1
        with self.assertRaisesRegex(InvalidDex, "invalid_dex_checksum"):
            Dex(bytes(data))
        struct.pack_into("<I", data, 60, len(data) + 4)
        with self.assertRaisesRegex(InvalidDex, "invalid_dex_offset"):
            Dex(seal(data))

    def test_inherited_static_lookup_works_but_constructors_do_not_inherit(self):
        classes = {
            "LChild;": DexClass("LParent;"),
            "LParent;": DexClass(None, methods={
                ("getCOROUTINE_SUSPENDED", "()Ljava/lang/Object;"): 0x9,
                ("<init>", "()V"): 0x1,
            }),
        }
        self.assertEqual(find_member(classes, "LChild;", "getCOROUTINE_SUSPENDED",
                                     "()Ljava/lang/Object;", True, "methods"), "LParent;")
        self.assertIsNone(find_member(classes, "LChild;", "<init>", "()V", False, "methods"))


if __name__ == "__main__":
    unittest.main()
