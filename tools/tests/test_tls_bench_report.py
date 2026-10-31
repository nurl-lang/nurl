#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for bench/tls_bench/gen_tls_results.py's CPU families.

The tls-bench runner pool hands out AMD Zen 3, AMD Zen 5 and Intel Ice
Lake machines, and NURL's ratio to aws-lc flips with the family: one
report overwritten by whichever runner a run got could not close a perf
task honestly (Agora #112). Each run is now recorded as its family's
latest, the family decided by the CPU's vendor and flags. These tests
hold that: two families give two reports and an index that sets them side
by side, a re-run replaces only its own family, and a run that cannot say
which CPU and which NURL kernels produced it is refused.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GEN = os.path.join(ROOT, "bench", "tls_bench", "gen_tls_results.py")

ZEN3_FLAGS = "aes pclmulqdq avx avx2 bmi2 adx sha_ni vaes vpclmulqdq"
ZEN5_FLAGS = ZEN3_FLAGS + " gfni avx512f avx512vl avx512bw avx512ifma avx512vbmi"
ICELAKE_FLAGS = ZEN5_FLAGS
CASCADE_FLAGS = "aes pclmulqdq avx avx2 bmi2 adx avx512f avx512vl avx512bw"


def raw(vendor, flags, model, now, aes_nurl_ns, tiers=True, probes=True):
    """A raw run as run_tls.sh writes it, cut down to what the report reads."""
    lines = [
        f"ENV\tnow\t{now}",
        "ENV\tmode\tfull",
        f"ENV\tcpu\t{model}",
        f"ENV\tcommit\t{'a' * 40}",
        "ENV\tsecs\ths=15 lat=5 ka=10 client=6 prim_runs=3",
    ]
    if vendor is not None:
        lines.append(f"ENV\tcpu_vendor\t{vendor}")
    if flags is not None:
        lines.append(f"ENV\tcpu_flags\t{flags}")
    if probes:
        ifma = "1" if "avx512ifma" in (flags or "") else "0"
        for p, v in (("v3", "1"), ("aes", "1"), ("vaes", "1"), ("vaes512", ifma), ("sha", "1"), ("adx", "1"), ("ifma", ifma)):
            lines.append(f"PROBE\t{p}\t{v}")
    if tiers:
        lines.append(f"TIER\tAES-128-GCM seal 16 KB\t{'vaes512' if 'avx512f' in (flags or '') else 'vaes'}")
        lines.append("TIER\tRSA-2048 PSS sign\tadx")
    for _ in range(3):
        lines.append(f"P\tNURL\tAES-128-GCM seal 16 KB\t{aes_nurl_ns}")
        lines.append("P\tRUST\tAES-128-GCM seal 16 KB\t4000")
        lines.append("P\tNURL\tRSA-2048 PSS sign\t890000")
        lines.append("P\tRUST\tRSA-2048 PSS sign\t660000")
    lines.append("M\thandshake\trsa:x25519:0\tNURL\tok=13500 elapsed_ns=15000000000 srv_cpu_ns=14900000000 srv_cores=1")
    lines.append("M\thandshake\trsa:x25519:0\tRUST\tok=17280 elapsed_ns=15000000000 srv_cpu_ns=14950000000 srv_cores=1")
    return "\n".join(lines) + "\n"


def run_gen(args, stdin=""):
    return subprocess.run([sys.executable, GEN, *args], input=stdin, capture_output=True, text=True)


class TlsBenchFamilies(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="tlsbench-")
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def family(self, text):
        p = run_gen(["--family"], text)
        self.assertEqual(p.returncode, 0, p.stderr)
        return p.stdout.strip()

    def test_family_comes_from_vendor_and_flags_not_the_model(self):
        self.assertEqual(self.family(raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "t", 2220)),
                         "amd-avx2-vaes-sha-adx")
        self.assertEqual(self.family(raw("AuthenticAMD", ZEN5_FLAGS, "AMD EPYC 9V45", "t", 2220)),
                         "amd-avx512ifma-vaes-sha-adx")
        self.assertEqual(self.family(raw("GenuineIntel", ICELAKE_FLAGS, "Xeon 8370C", "t", 2220)),
                         "intel-avx512ifma-vaes-sha-adx")
        self.assertEqual(self.family(raw("GenuineIntel", CASCADE_FLAGS, "Xeon @ 2.80GHz", "t", 2220)),
                         "intel-avx512-adx")
        # The model string does not enter it: a renamed SKU is the same family.
        self.assertEqual(self.family(raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7B13", "t", 2220)),
                         "amd-avx2-vaes-sha-adx")

    def test_two_families_two_reports_and_an_index(self):
        for text in (raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "2026-10-29T11:50:10Z", 2220),
                     raw("AuthenticAMD", ZEN5_FLAGS, "AMD EPYC 9V45", "2026-10-30T09:00:00Z", 4800)):
            p = run_gen(["--store", self.dir], text)
            self.assertEqual(p.returncode, 0, p.stderr)
        runs = sorted(os.listdir(os.path.join(self.dir, "runs")))
        self.assertEqual(runs, ["amd-avx2-vaes-sha-adx.tsv", "amd-avx512ifma-vaes-sha-adx.tsv"])
        for fam in ("amd-avx2-vaes-sha-adx", "amd-avx512ifma-vaes-sha-adx"):
            with open(os.path.join(self.dir, f"TLS_RESULTS.{fam}.md"), encoding="utf-8") as f:
                rep = f.read()
            self.assertIn(f"CPU family `{fam}`", rep)
            self.assertIn("| NURL CPU probes |", rep)
        with open(os.path.join(self.dir, "TLS_RESULTS.md"), encoding="utf-8") as f:
            idx = f.read()
        self.assertIn("`amd-avx2-vaes-sha-adx`", idx)
        self.assertIn("`amd-avx512ifma-vaes-sha-adx`", idx)
        self.assertIn("2026-10-29T11:50:10Z", idx)
        self.assertIn("2026-10-30T09:00:00Z", idx)
        # AES-GCM leads on one family (4000/2220 = 180 %) and trails on the
        # other (4000/4800 = 83 %): the index must say so.
        aes = [ln for ln in idx.splitlines() if "AES-128-GCM seal 16 KB — µs/op" in ln]
        self.assertEqual(len(aes), 1, idx)
        self.assertIn("180 %", aes[0])
        self.assertIn("83 %", aes[0])
        self.assertIn("**differs**", aes[0])
        rsa = [ln for ln in idx.splitlines() if "RSA-2048 PSS sign — µs/op" in ln]
        self.assertEqual(len(rsa), 1, idx)
        self.assertNotIn("differs", rsa[0])

    def test_a_rerun_replaces_only_its_own_family(self):
        run_gen(["--store", self.dir], raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "2026-10-29T00:00:00Z", 2220))
        run_gen(["--store", self.dir], raw("AuthenticAMD", ZEN5_FLAGS, "AMD EPYC 9V45", "2026-10-30T00:00:00Z", 4800))
        p = run_gen(["--store", self.dir], raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "2026-10-31T00:00:00Z", 2000))
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(os.path.join(self.dir, "TLS_RESULTS.md"), encoding="utf-8") as f:
            idx = f.read()
        self.assertIn("2026-10-31T00:00:00Z", idx)
        self.assertNotIn("2026-10-29T00:00:00Z", idx)
        self.assertIn("2026-10-30T00:00:00Z", idx)
        # --render rebuilds the same reports from runs/ alone.
        with open(os.path.join(self.dir, "TLS_RESULTS.md"), encoding="utf-8") as f:
            before = f.read()
        os.remove(os.path.join(self.dir, "TLS_RESULTS.md"))
        p = run_gen(["--render", self.dir])
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(os.path.join(self.dir, "TLS_RESULTS.md"), encoding="utf-8") as f:
            self.assertEqual(f.read(), before)

    def test_a_run_without_flags_is_refused(self):
        p = run_gen(["--store", self.dir], raw("AuthenticAMD", None, "AMD EPYC 7763", "t", 2220))
        self.assertEqual(p.returncode, 1)
        self.assertIn("cpu_flags", p.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.dir, "runs")))
        p = run_gen([], raw(None, ZEN3_FLAGS, "AMD EPYC 7763", "t", 2220))
        self.assertEqual(p.returncode, 1)
        self.assertIn("cpu_vendor", p.stderr)

    def test_a_run_without_nurl_kernels_is_refused(self):
        p = run_gen([], raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "t", 2220, tiers=False))
        self.assertEqual(p.returncode, 1)
        self.assertIn("TIER AES-128-GCM seal 16 KB", p.stderr)
        p = run_gen([], raw("AuthenticAMD", ZEN3_FLAGS, "AMD EPYC 7763", "t", 2220, probes=False))
        self.assertEqual(p.returncode, 1)
        self.assertIn("PROBE ifma", p.stderr)


if __name__ == "__main__":
    unittest.main()
