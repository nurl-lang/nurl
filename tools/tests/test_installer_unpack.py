#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The installer must not destroy a working install to make room for one.

`tools/get-nurl.sh` used to delete the toolchain's paths and then extract
the archive over the hole. Every failure from that point on — a truncated
archive, a full disk, a killed terminal — left a prefix with no compiler
in it, repairable only by a successful re-run. Now it unpacks into a
staging directory inside the prefix, checks the result, and only then
swaps: the destructive window is a handful of renames on one filesystem.

These controls serve a release over `file://` so the real download,
checksum and unpack path runs; nothing here reaches the network.

  python3 tools/tests/test_installer_unpack.py
"""
import hashlib
import os
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INSTALLER = os.path.join(ROOT, "tools", "get-nurl.sh")
VERSION = "v9.9.9"


def target_triple():
    """The same triple get-nurl.sh computes for this host."""
    machine = os.uname().machine
    cpu = {"x86_64": "x86_64", "amd64": "x86_64",
           "aarch64": "arm64", "arm64": "arm64"}.get(machine)
    system = os.uname().sysname
    if system == "Linux" and cpu:
        return "linux-%s-glibc" % cpu
    if system == "FreeBSD" and cpu == "x86_64":
        return "freebsd-x86_64"
    return None


class InstallerUnpack(unittest.TestCase):
    def setUp(self):
        self.triple = target_triple()
        if self.triple is None:
            self.skipTest("get-nurl.sh publishes no archive for this host")
        if shutil.which("curl") is None and shutil.which("wget") is None:
            self.skipTest("no curl or wget to fetch even a file:// URL")
        self.tmp = tempfile.mkdtemp(prefix="installer-unpack-")
        self.serve = os.path.join(self.tmp, "serve")
        self.prefix = os.path.join(self.tmp, "prefix")
        os.makedirs(self.serve)
        self.archive = "nurl-%s-%s.tar.gz" % (VERSION, self.triple)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    # ── fixtures ───────────────────────────────────────────────────────
    def publish(self, entries, truncate=False):
        """Write a release archive (and its checksum) into the served dir.

        `entries` maps archive-relative paths to contents; the archive's
        top-level `nurl/` directory is what --strip-components=1 removes.
        """
        staging = os.path.join(self.tmp, "stage-src", "nurl")
        shutil.rmtree(os.path.join(self.tmp, "stage-src"), ignore_errors=True)
        for rel, content in entries.items():
            path = os.path.join(staging, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                fh.write(content)
            if rel.startswith("bin/"):
                os.chmod(path, 0o755)
        path = os.path.join(self.serve, self.archive)
        with tarfile.open(path, "w:gz") as tar:
            tar.add(staging, arcname="nurl")
        if truncate:
            # A download that verified and then stopped part-way through
            # being unpacked: the bytes on disk are a valid prefix of a
            # gzip stream, so tar starts and then fails.
            with open(path, "rb") as fh:
                data = fh.read()
            with open(path, "wb") as fh:
                fh.write(data[: max(64, len(data) // 2)])
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        with open(path + ".sha256", "w") as fh:
            fh.write("%s  %s\n" % (digest, self.archive))

    def good_release(self):
        return {
            "bin/nurl": "#!/bin/sh\necho new-nurl\n",
            "bin/nurlc": "#!/bin/sh\necho new-nurlc\n",
            "build/nurlc": "new compiler\n",
            "stdlib/core/string.nu": "new stdlib\n",
            "nurl.sh": "new driver\n",
        }

    def prior_install(self):
        """A prefix holding a previous toolchain plus user state."""
        for rel, content in {
            "bin/nurl": "#!/bin/sh\necho old-nurl\n",
            "bin/nurlc": "#!/bin/sh\necho old-nurlc\n",
            "bin/mytool": "#!/bin/sh\necho installed-by-nurlpkg\n",
            "build/nurlc": "old compiler\n",
            "build/gone-upstream": "removed in the new release\n",
            "stdlib/core/string.nu": "old stdlib\n",
            "nurl.sh": "old driver\n",
            "credentials": "publish-token\n",
            "models/big.gguf": "tens of gigabytes, pretend\n",
        }.items():
            path = os.path.join(self.prefix, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as fh:
                fh.write(content)
            if rel.startswith("bin/"):
                os.chmod(path, 0o755)

    def install(self):
        env = dict(os.environ)
        env["NURL_INSTALL_BASE"] = "file://" + self.serve
        env["NURL_HOME"] = self.prefix
        # No signature is published for a locally served archive; without
        # this the minisign leg fails closed, which is its own control.
        env["NURL_INSTALL_INSECURE"] = "1"
        return subprocess.run(
            ["bash", INSTALLER, "--version", VERSION, "--prefix", self.prefix],
            capture_output=True, env=env, timeout=180)

    def read(self, rel):
        with open(os.path.join(self.prefix, rel)) as fh:
            return fh.read()

    def assertNoStagingLeft(self):
        leftovers = [n for n in os.listdir(self.prefix) if n.startswith(".stage.")]
        self.assertEqual(leftovers, [], "a staging directory was left behind")

    # ── controls ───────────────────────────────────────────────────────
    def test_fresh_install(self):
        self.publish(self.good_release())
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr.decode("utf-8", "replace")[-2000:])
        self.assertEqual(self.read("build/nurlc"), "new compiler\n")
        self.assertTrue(os.access(os.path.join(self.prefix, "bin/nurl"), os.X_OK))
        self.assertNoStagingLeft()

    def test_upgrade_replaces_toolchain_and_keeps_user_state(self):
        self.prior_install()
        self.publish(self.good_release())
        r = self.install()
        self.assertEqual(r.returncode, 0, r.stderr.decode("utf-8", "replace")[-2000:])
        self.assertEqual(self.read("build/nurlc"), "new compiler\n")
        self.assertEqual(self.read("stdlib/core/string.nu"), "new stdlib\n")
        # A file the new release dropped must not linger: build/ is
        # replaced wholesale, not merged.
        self.assertFalse(os.path.exists(os.path.join(self.prefix, "build/gone-upstream")))
        # …but user state in the same prefix survives.
        self.assertEqual(self.read("credentials"), "publish-token\n")
        self.assertEqual(self.read("models/big.gguf"), "tens of gigabytes, pretend\n")
        self.assertEqual(self.read("bin/mytool"), "#!/bin/sh\necho installed-by-nurlpkg\n")
        self.assertNoStagingLeft()

    def test_failed_unpack_leaves_prior_install_intact(self):
        """The case the staging directory exists for."""
        self.prior_install()
        self.publish(self.good_release(), truncate=True)
        r = self.install()
        self.assertNotEqual(r.returncode, 0, "a truncated archive must not install")
        self.assertEqual(self.read("build/nurlc"), "old compiler\n")
        self.assertEqual(self.read("stdlib/core/string.nu"), "old stdlib\n")
        self.assertEqual(self.read("nurl.sh"), "old driver\n")
        self.assertTrue(os.access(os.path.join(self.prefix, "bin/nurlc"), os.X_OK))
        self.assertEqual(self.read("credentials"), "publish-token\n")
        self.assertNoStagingLeft()

    def test_incomplete_archive_leaves_prior_install_intact(self):
        """An archive that unpacks but ships no `bin/nurl`."""
        self.prior_install()
        release = self.good_release()
        del release["bin/nurl"]
        self.publish(release)
        r = self.install()
        self.assertNotEqual(r.returncode, 0, "an archive with no bin/nurl must not install")
        self.assertEqual(self.read("build/nurlc"), "old compiler\n")
        self.assertEqual(self.read("bin/nurl"), "#!/bin/sh\necho old-nurl\n")
        self.assertNoStagingLeft()

    def test_checksum_mismatch_never_reaches_the_prefix(self):
        """Fail-closed before unpacking — the existing check, pinned here
        against the staged path so a future edit cannot reorder them."""
        self.prior_install()
        self.publish(self.good_release())
        with open(os.path.join(self.serve, self.archive + ".sha256"), "w") as fh:
            fh.write("%s  %s\n" % ("0" * 64, self.archive))
        r = self.install()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(b"checksum mismatch", r.stderr)
        self.assertEqual(self.read("build/nurlc"), "old compiler\n")
        self.assertNoStagingLeft()

    def test_refuses_a_prefix_that_is_not_an_install(self):
        """The pre-existing guard: a non-empty directory that is not ours."""
        os.makedirs(os.path.join(self.prefix, "someone-elses"))
        with open(os.path.join(self.prefix, "someone-elses", "data"), "w") as fh:
            fh.write("not a NURL install\n")
        self.publish(self.good_release())
        r = self.install()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn(b"refusing to overwrite", r.stderr)
        self.assertEqual(self.read("someone-elses/data"), "not a NURL install\n")
        self.assertNoStagingLeft()


if __name__ == "__main__":
    unittest.main(verbosity=2)
