#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for tools/check_release_artifacts.sh.

The gate exists because the publish job attaches whatever the build jobs
produced, through a glob: a failed Windows leg used to publish a release
with no .zip, and the one-line PowerShell installer then 404s for that
version. Each test here is one way a release can be incomplete.
"""
import hashlib
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GATE = os.path.join(ROOT, "tools", "check_release_artifacts.sh")
TAG = "v9.9.9"

REQUIRED = [
    f"nurl-{TAG}-linux-x86_64-glibc.tar.gz",
    f"nurl-{TAG}-linux-arm64-glibc.tar.gz",
    f"nurl-{TAG}-windows-x86_64.zip",
]
BEST_EFFORT = [f"nurl-{TAG}-freebsd-x86_64.tar.gz"]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


class ReleaseArtifactGate(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="relartifacts-")
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    # ── helpers ──────────────────────────────────────────────────
    def write_archive(self, name, body=b"archive-bytes", checksum=True,
                      crlf=False, sign=False, wrong_sum=False):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as f:
            f.write(body)
        if checksum:
            digest = "0" * 64 if wrong_sum else sha256(path)
            line = f"{digest}  {name}"
            eol = "\r\n" if crlf else "\n"
            with open(path + ".sha256", "w", newline="") as f:
                f.write(line + eol)
        if sign:
            with open(path + ".minisig", "w") as f:
                f.write("untrusted comment: fake\nRWQf\n")
        return path

    def populate(self, names=None, **kw):
        for name in (names if names is not None else REQUIRED + BEST_EFFORT):
            self.write_archive(name, **kw)

    def run_gate(self, *extra):
        return subprocess.run([GATE, self.dir, TAG, *extra],
                              capture_output=True, text=True)

    # ── controls ─────────────────────────────────────────────────
    def test_complete_set_passes(self):
        self.populate()
        r = self.run_gate()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("release artifacts: OK", r.stdout)

    def test_missing_required_target_fails_and_names_it(self):
        self.populate(names=[n for n in REQUIRED if "windows" not in n] + BEST_EFFORT)
        r = self.run_gate()
        self.assertEqual(r.returncode, 1)
        self.assertIn("windows-x86_64.zip", r.stderr)
        self.assertIn("required archive missing", r.stderr)

    def test_missing_best_effort_target_only_warns(self):
        self.populate(names=REQUIRED)
        r = self.run_gate()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("best-effort archive missing", r.stderr)

    def test_archive_without_checksum_fails(self):
        self.populate(names=REQUIRED[1:] + BEST_EFFORT)
        self.write_archive(REQUIRED[0], checksum=False)
        r = self.run_gate()
        self.assertEqual(r.returncode, 1)
        self.assertIn("no checksum published", r.stderr)

    def test_checksum_mismatch_fails(self):
        self.populate(names=REQUIRED[1:] + BEST_EFFORT)
        self.write_archive(REQUIRED[0], wrong_sum=True)
        r = self.run_gate()
        self.assertEqual(r.returncode, 1)
        self.assertIn("checksum mismatch", r.stderr)

    def test_windows_style_crlf_checksum_is_accepted(self):
        # The Windows leg writes its .sha256 with PowerShell's Out-File,
        # i.e. CRLF. The installers read the first field; so does the gate.
        self.populate(names=REQUIRED[:2] + BEST_EFFORT)
        self.write_archive(REQUIRED[2], crlf=True)
        r = self.run_gate()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_empty_archive_fails(self):
        self.populate(names=REQUIRED[1:] + BEST_EFFORT)
        self.write_archive(REQUIRED[0], body=b"")
        r = self.run_gate()
        self.assertEqual(r.returncode, 1)
        self.assertIn("archive is empty", r.stderr)

    def test_signed_release_requires_every_signature(self):
        self.populate(sign=True)
        r = self.run_gate("--signed")
        self.assertEqual(r.returncode, 0, r.stderr)
        os.unlink(os.path.join(self.dir, REQUIRED[0] + ".minisig"))
        r = self.run_gate("--signed")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no signature published", r.stderr)

    def test_unsigned_release_does_not_demand_signatures(self):
        self.populate()
        r = self.run_gate()
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_unknown_target_name_fails(self):
        self.populate()
        self.write_archive(f"nurl-{TAG}-linux-x86_64-musl.tar.gz")
        r = self.run_gate()
        self.assertEqual(r.returncode, 1)
        self.assertIn("unexpected archive", r.stderr)

    def test_missing_directory_is_an_environment_error(self):
        r = subprocess.run([GATE, os.path.join(self.dir, "nope"), TAG],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
