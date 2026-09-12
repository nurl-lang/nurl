#!/usr/bin/env python3
"""Differential protobuf tests. Requires the official `protobuf` Python package.

Run: python3 tools/tests/test_protobuf.py
NURL_SAN=1 instruments the same adapter; no tests are omitted under sanitizers.
"""
import os
from pathlib import Path
import random
import re
import struct
import subprocess
import tempfile
import unittest

from google.protobuf import descriptor_pb2, descriptor_pool, message_factory

ROOT = Path(__file__).resolve().parents[2]


def message_class():
    file = descriptor_pb2.FileDescriptorProto(name="oracle.proto", syntax="proto2")
    message = file.message_type.add(name="All")
    types = [1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 15, 16, 17, 18]
    for number, kind in enumerate(types, 1):
        message.field.add(name=f"f{number}", number=number, type=kind, label=1)
    packed = message.field.add(name="packed", number=16, type=5, label=3)
    packed.options.packed = True
    message.field.add(name="child", number=17, type=11, type_name=".All", label=1)
    enum = file.enum_type.add(name="Flavor")
    for name, value in (("ZERO", 0), ("ONE", 1), ("NEGATIVE", -1),
                        ("MINIMUM", -2**31), ("MAXIMUM", 2**31 - 1)):
        enum.value.add(name=name, number=value)
    message.field.add(name="flavor", number=18, type=14, type_name=".Flavor", label=1)
    pool = descriptor_pool.DescriptorPool()
    pool.Add(file)
    return message_factory.GetMessageClass(pool.FindMessageTypeByName("All"))


All = message_class()


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def framed(data):
    """Independent strict wire grammar, with iterative group matching."""
    pos = 0
    groups = []

    def integer():
        nonlocal pos
        start = pos
        while pos < len(data) and pos - start < 10:
            byte = data[pos]
            pos += 1
            if pos - start == 10 and byte > 1:
                raise ValueError
            if byte < 128:
                return sum((data[k] & 127) * 128 ** (k - start)
                           for k in range(start, pos))
        raise ValueError

    try:
        while pos < len(data):
            tag = integer()
            field, wire = divmod(tag, 8)
            if not 1 <= field < 2**29 or wire > 5:
                return False
            if wire == 0:
                integer()
            elif wire in (1, 5):
                pos += 8 if wire == 1 else 4
            elif wire == 2:
                size = integer()
                if size >= 2**31:
                    return False
                pos += size
            elif wire == 3:
                groups.append(field)
                if len(groups) > 100:
                    return False
            elif wire == 4:
                if not groups or groups.pop() != field:
                    return False
            if pos > len(data):
                return False
        return not groups
    except ValueError:
        return False


class ProtobufTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="nurl-protobuf-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.path = Path(cls.temp.name)
        cls.exe = cls.path / "driver"
        cls.env = {**os.environ, "NURL_CACHE_DIR": str(cls.path / "cache"),
                   "ASAN_OPTIONS": "detect_leaks=1:halt_on_error=1",
                   "LSAN_OPTIONS": "use_stacks=0", "UBSAN_OPTIONS": "halt_on_error=1"}
        run = subprocess.run([str(ROOT / "nurl.sh"),
                              str(ROOT / "tools/tests/fixtures/protobuf_driver.nu"),
                              str(cls.exe)], cwd=ROOT, env=cls.env, capture_output=True,
                             text=True, timeout=120)
        if run.returncode or "warning:" in run.stderr:
            raise AssertionError(run.stdout + run.stderr)

    def adapter(self, mode, cases):
        run = subprocess.run([str(self.exe)],
                             input="".join(f"{mode} {case.hex()}\n" for case in cases),
                             capture_output=True, text=True, env=self.env, timeout=60)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, "")
        lines = run.stdout.splitlines()
        self.assertEqual(len(lines), len(cases))
        return lines

    def equivalent(self, cases):
        for source, line in zip(cases, self.adapter("t", cases)):
            self.assertTrue(line.startswith("ok "), (source.hex(), line))
            actual = All.FromString(bytes.fromhex(line[3:]))
            expected = All.FromString(source)
            self.assertEqual(actual.SerializeToString(deterministic=True),
                             expected.SerializeToString(deterministic=True), source.hex())

    def test_compiler_control_flow(self):
        compiler = ROOT / "build/nurlc"
        for name in ("protobuf", "return_paths", "try_statement_effect", "inout_forward"):
            run = subprocess.run([str(compiler), "--strict-borrowck", "--check",
                                  str(ROOT / f"compiler/tests/{name}.nu")],
                                 cwd=ROOT, env=self.env, capture_output=True,
                                 text=True, timeout=60)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(run.stderr, "", name)
        # A live path's consumption must still be diagnosed, including a
        # back-edge and conditional consumes through direct/generic calls.
        for name in ("borrow_loop_carried_free", "borrow_strict_maybe_double_free",
                     "borrow_strict_generic_maybe_double_free"):
            run = subprocess.run([str(compiler), "--strict-borrowck", "--check",
                                  str(ROOT / f"compiler/tests/{name}.nu")],
                                 cwd=ROOT, env=self.env, capture_output=True,
                                 text=True, timeout=60)
            self.assertEqual(run.returncode, 1, (name, run.stderr))
            self.assertIn("error:", run.stderr)

        # Publishing forward inout positions must retain call-site validation.
        for binding, parameter, diagnostic in (
                (": i n 3", "i", "mutable"),
                (": ~ i n 3", "f", "must match")):
            source = self.path / "forward_invalid.nu"
            source.write_text(f"@ main → i {{ {binding} ( bump n ) ^ 0 }}\n"
                              f"@ bump inout {parameter} n → v {{ ^ }}\n")
            run = subprocess.run([str(compiler), "--check", str(source)],
                                 cwd=ROOT, env=self.env, capture_output=True,
                                 text=True, timeout=60)
            self.assertEqual(run.returncode, 1, run.stderr)
            self.assertIn(diagnostic, run.stderr)

    def test_documented_examples(self):
        blocks = re.findall(r"```nurl\n(.*?)```", (ROOT / "docs/stdlib/protobuf.md").read_text(), re.S)
        self.assertEqual(len(blocks), 2)
        source = self.path / "examples.nu"
        source.write_text("\n".join(blocks) + r'''
@ main → i {
    : ( Vec u ) bytes ( vec_new [u] )
    ( proto_write_uint64 bytes 1 # u64 42 )
    : ~ i status 0
    ?? ( read_id bytes ) { T id → { ? != id # u64 42 { = status 1 } {} } F _ → { = status 2 } }
    ( vec_free [u] bytes )
    ?? ( encode_samples ) {
        T packed → {
            : String hex ( bytes_to_hex packed )
            ? == ( nurl_str_eq ( string_data hex ) `0a0301ac02` ) 0 { = status 3 } {}
            ( string_free hex )
            ( vec_free [u] packed )
        }
        F _ → { = status 4 }
    }
    ^ status
}
''')
        exe = self.path / "examples"
        build = subprocess.run([str(ROOT / "nurl.sh"), str(source), str(exe)],
                               cwd=ROOT, env=self.env, capture_output=True, text=True, timeout=120)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        self.assertNotIn("warning:", build.stderr)
        run = subprocess.run([str(exe)], env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stderr, "")

    def test_official_all_scalar_types(self):
        rng = random.Random(730201)
        cases = [b""]

        def message(depth):
            m = All()
            m.f1 = struct.unpack("<d", rng.randbytes(8))[0]
            m.f2 = struct.unpack("<f", rng.randbytes(4))[0]
            for field in (3, 13, 15):
                setattr(m, f"f{field}", rng.randrange(-2**63, 2**63))
            for field in (4, 6):
                setattr(m, f"f{field}", rng.getrandbits(64))
            for field in (5, 12, 14):
                setattr(m, f"f{field}", rng.randrange(-2**31, 2**31))
            for field in (7, 11):
                setattr(m, f"f{field}", rng.getrandbits(32))
            m.f8 = bool(rng.getrandbits(1))
            m.f9 = "NUL\0ää\U0001f600" * rng.randrange(10)
            m.f10 = rng.randbytes(rng.randrange(128))
            m.flavor = rng.choice([0, 1, -1, -2**31, 2**31 - 1])
            m.packed.extend(rng.randrange(-2**31, 2**31) for _ in range(rng.randrange(20)))
            if depth:
                m.child.CopyFrom(message(depth - 1))
            return m

        for _ in range(600):
            cases.append(message(rng.randrange(4)).SerializeToString(deterministic=True))
        self.equivalent(cases)

    def test_merge_packed_unknown_fields(self):
        rng = random.Random(9241)
        cases = []
        for _ in range(300):
            parts = []
            for k in range(4):
                m = All(f5=k, f9=str(k))
                m.child.f4 = k
                m.child.packed.append(k)
                m.packed.extend([k, -k])
                parts.append(m.SerializeToString())
                # An expanded occurrence interleaved with packed ones.
                parts.append(varint(16 << 3) + varint(k))
                # Unknown maximum-number fixed64 and nested groups.
                parts.append(varint(((2**29 - 1) << 3) | 1) + rng.randbytes(8))
                parts.append(varint((100 << 3) | 3) + b"\x08\x96\x01" + varint((100 << 3) | 4))
            rng.shuffle(parts)
            cases.append(b"".join(parts))
        self.equivalent(cases)

    def test_framing_mutations_and_truncations(self):
        rng = random.Random(440188)
        corpus = [b"", b"\x0b" * 100 + b"\x0c" * 100,
                  b"\x0b" * 101 + b"\x0c" * 101,
                  b"\x0a\x01\x80"]  # LEN contents remain opaque.
        for _ in range(200):
            m = All(f3=rng.randrange(-2**63, 2**63), f10=rng.randbytes(40))
            data = m.SerializeToString()
            corpus.extend(data[:k] for k in range(len(data) + 1))
            for _ in range(8):
                changed = bytearray(data)
                changed[rng.randrange(len(changed))] = rng.randrange(256)
                corpus.append(bytes(changed))
        corpus.extend(rng.randbytes(rng.randrange(65)) for _ in range(20000))
        for data, line in zip(corpus, self.adapter("v", corpus)):
            self.assertEqual(line.startswith("ok "), framed(data), (data.hex(), line))

    def test_utf8_and_packed_boundaries(self):
        bad_text = [b"\x80", b"\xc0\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80",
                    b"\xe2\x82", b"\xf0\x80\x80\x80", b"\0\xff"]
        cases = [b"\x4a" + varint(len(s)) + s for s in bad_text]
        cases += [varint((16 << 3) | 2) + b"\x01\x80", b"\x8a\x01\x01\x80"]
        for line in self.adapter("t", cases):
            self.assertTrue(line.startswith("err "), line)
        good_text = [b"", b"\0", "\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000\U0010ffff".encode()]
        self.equivalent([b"\x4a" + varint(len(s)) + s for s in good_text])


if __name__ == "__main__":
    unittest.main(verbosity=2)
