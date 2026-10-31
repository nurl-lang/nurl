#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""The installer must find "latest" when the GitHub API refuses it.

`tools/get-nurl.sh` resolved the latest release tag only through
api.github.com, which allows 60 unauthenticated requests an hour per IP and
answers 403 past that. CI runners, cloud sandboxes and NAT gateways share
their IP, so an install there died (Agora #216), after three retries that
only spent more of the quota. The tag now comes from github.com's
releases/latest redirect (its Location names the tag), and the API is asked
once, as the fallback.

A `curl` earlier on PATH answers the two GitHub endpoints and hands every
other request to the real curl; the release itself is served over `file://`
(NURL_INSTALL_BASE), so nothing here reaches the network.

  python3 tools/tests/test_installer_latest.py
"""
import hashlib
import os
import shutil
import subprocess
import tarfile
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INSTALLER = os.path.join(ROOT, "tools", "get-nurl.sh")
VERSION = "v9.9.9"
REDIRECT = "https://github.com/nurl-lang/nurl/releases/latest"
API = "https://api.github.com/repos/nurl-lang/nurl/releases/latest"

# What the stand-in curl answers. `redirect`: "tag" (a 302 naming VERSION)
# or "none" (no release: 404). `api`: "403" (rate limited) or "json".
FAKE_CURL = textwrap.dedent("""\
    #!/usr/bin/env python3
    import os, sys
    args = sys.argv[1:]
    url = next((a for a in args if "://" in a), "")
    with open(os.environ["FAKE_CURL_LOG"], "a") as log:
        log.write(url + "\\n")
    if url == %(redirect)r:
        if os.environ["FAKE_REDIRECT"] == "tag" and "-fsSI" in args:
            sys.stdout.write("HTTP/2 302\\r\\nlocation: "
                             "https://github.com/nurl-lang/nurl/releases/tag/%(version)s\\r\\n\\r\\n")
            sys.exit(0)
        sys.stderr.write("curl: (22) The requested URL returned error: 404\\n")
        sys.exit(22)
    if url == %(api)r:
        if os.environ["FAKE_API"] == "json":
            sys.stdout.write('{\\n  "url": "x",\\n  "tag_name": "%(version)s",\\n  "name": "x"\\n}\\n')
            sys.exit(0)
        sys.stderr.write("curl: (22) The requested URL returned error: 403\\n")
        sys.exit(22)
    os.execv(os.environ["REAL_CURL"], ["curl"] + args)
    """) % {"redirect": REDIRECT, "api": API, "version": VERSION}


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


class InstallerLatest(unittest.TestCase):
    def setUp(self):
        self.triple = target_triple()
        if self.triple is None:
            self.skipTest("get-nurl.sh publishes no archive for this host")
        self.real_curl = shutil.which("curl")
        if self.real_curl is None:
            self.skipTest("no curl to fetch a file:// URL")
        self.tmp = tempfile.mkdtemp(prefix="installer-latest-")
        self.serve = os.path.join(self.tmp, "serve")
        self.bin = os.path.join(self.tmp, "bin")
        self.log = os.path.join(self.tmp, "curl.log")
        os.makedirs(self.serve)
        os.makedirs(self.bin)
        fake = os.path.join(self.bin, "curl")
        with open(fake, "w") as fh:
            fh.write(FAKE_CURL)
        os.chmod(fake, 0o755)
        self.publish()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def publish(self):
        """A release VERSION with just enough in it to install."""
        src = os.path.join(self.tmp, "src", "nurl")
        os.makedirs(os.path.join(src, "bin"))
        nurl = os.path.join(src, "bin", "nurl")
        with open(nurl, "w") as fh:
            fh.write("#!/bin/sh\necho %s\n" % VERSION)
        os.chmod(nurl, 0o755)
        archive = os.path.join(self.serve, "nurl-%s-%s.tar.gz" % (VERSION, self.triple))
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(src, arcname="nurl")
        with open(archive, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
        with open(archive + ".sha256", "w") as fh:
            fh.write("%s  %s\n" % (digest, os.path.basename(archive)))

    def install(self, redirect, api, *args):
        env = dict(os.environ)
        env.update({
            "PATH": self.bin + os.pathsep + env.get("PATH", ""),
            "REAL_CURL": self.real_curl,
            "FAKE_CURL_LOG": self.log,
            "FAKE_REDIRECT": redirect,
            "FAKE_API": api,
            "NURL_HOME": os.path.join(self.tmp, "prefix"),
            "NURL_INSTALL_BASE": "file://" + self.serve,
            "NURL_NO_MODIFY_PATH": "1",
        })
        env.pop("NURL_VERSION", None)
        r = subprocess.run(["sh", INSTALLER] + list(args), env=env,
                           stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, timeout=120)
        asked = []
        if os.path.exists(self.log):
            with open(self.log) as fh:
                asked = fh.read().split()
        return r, asked

    def installed(self):
        nurl = os.path.join(self.tmp, "prefix", "bin", "nurl")
        return subprocess.run([nurl], capture_output=True, text=True).stdout.strip()

    def test_api_refused_redirect_names_the_tag(self):
        # The case that broke: the API answers 403. The redirect alone
        # resolves the tag and the API is never asked.
        r, asked = self.install("tag", "403")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.installed(), VERSION)
        self.assertIn(REDIRECT, asked)
        self.assertNotIn(API, asked)

    def test_no_redirect_falls_back_to_the_api(self):
        r, asked = self.install("none", "json")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.installed(), VERSION)
        self.assertEqual(asked.count(API), 1)

    def test_both_refused_fails_once_with_a_cure(self):
        # Nothing names a tag: the install stops, says how to pin one, and
        # asks the rate-limited API once rather than burning more quota.
        r, asked = self.install("none", "403")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("--version vX.Y.Z", r.stderr)
        self.assertIn("403", r.stderr)
        self.assertEqual(asked.count(API), 1)
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "prefix", "bin", "nurl")))

    def test_pinned_version_asks_neither(self):
        r, asked = self.install("none", "403", "--version", VERSION)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.installed(), VERSION)
        self.assertNotIn(REDIRECT, asked)
        self.assertNotIn(API, asked)


if __name__ == "__main__":
    unittest.main()
