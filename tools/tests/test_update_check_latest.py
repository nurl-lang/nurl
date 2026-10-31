#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""`nurl upgrade` must find the latest release when the GitHub API refuses it.

stdlib/ext/update_check.nu (behind `nurl upgrade` and the once-a-day
notice) asked only api.github.com, which allows 60 unauthenticated requests
an hour per IP and answers 403 past that. Shared IPs (CI runners, cloud
sandboxes, NAT) hit it, and `nurl upgrade` then said "could not reach the
release index (offline?)". The tag now comes from github.com's
releases/latest redirect (`httpc_redirect_location`); the API is asked once,
as the fallback (Agora #218).

A `curl` earlier on PATH stands in for GitHub; nothing reaches the network.
Needs the built toolchain (./build.sh).

  python3 tools/tests/test_update_check_latest.py
"""
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REDIRECT = "https://github.com/nurl-lang/nurl/releases/latest"
API = "https://api.github.com/repos/nurl-lang/nurl/releases/latest"
TAG = "v9.9.9"

PROGRAM = textwrap.dedent("""\
    $ `stdlib/core/io.nu`
    $ `stdlib/ext/update_check.nu`

    @ main → i {
        ?? ( update_check_latest ) {
            T v → { ( nurl_println ( string_data v ) ) }
            F → { ( nurl_println `none` ) }
        }
        ^ 0
    }
    """)

# The stand-in curl. `FAKE_REDIRECT`: "tag" (a 302 to …/releases/tag/TAG),
# "page" (a redirect that names no tag) or "none" (no redirect). `FAKE_API`:
# "403" (rate limited) or "json".
FAKE_CURL = textwrap.dedent("""\
    #!/usr/bin/env python3
    import os, sys
    args = sys.argv[1:]
    url = args[args.index("--") + 1] if "--" in args else ""
    out = args[args.index("-o") + 1] if "-o" in args else None
    fmt = args[args.index("-w") + 1] if "-w" in args else ""
    with open(os.environ["FAKE_CURL_LOG"], "a") as log:
        log.write(url + "\\n")
    def answer(body, code, location):
        if out:
            with open(out, "w") as fh:
                fh.write(body)
        sys.stdout.write(fmt.replace("%%{http_code}", code).replace("%%{redirect_url}", location))
        sys.exit(0)
    if url == %(redirect)r:
        mode = os.environ["FAKE_REDIRECT"]
        if mode == "tag":
            answer("", "302", "https://github.com/nurl-lang/nurl/releases/tag/%(tag)s")
        if mode == "page":
            answer("", "302", "https://github.com/login?return_to=releases")
        answer("<html></html>", "200", "")
    if url == %(api)r:
        if os.environ["FAKE_API"] == "json":
            answer('{"tag_name": "%(tag)s", "name": "x"}', "200", "")
        answer('{"message": "API rate limit exceeded"}', "403", "")
    sys.stderr.write("fake curl: unexpected request " + url + "\\n")
    sys.exit(7)
    """) % {"redirect": REDIRECT, "api": API, "tag": TAG}


class UpdateCheckLatest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.exists(os.path.join(ROOT, "build", "nurlc")):
            raise unittest.SkipTest("no built toolchain (run ./build.sh)")
        cls.tmp = tempfile.mkdtemp(prefix="update-check-")
        src = os.path.join(cls.tmp, "latest.nu")
        with open(src, "w") as fh:
            fh.write(PROGRAM)
        cls.exe = os.path.join(cls.tmp, "latest")
        r = subprocess.run([os.path.join(ROOT, "nurl.sh"), src, cls.exe], cwd=ROOT,
                           capture_output=True, text=True, timeout=600)
        if r.returncode != 0:
            raise AssertionError("compiling the probe failed:\n" + r.stdout + r.stderr)
        cls.bin = os.path.join(cls.tmp, "bin")
        os.makedirs(cls.bin)
        fake = os.path.join(cls.bin, "curl")
        with open(fake, "w") as fh:
            fh.write(FAKE_CURL)
        os.chmod(fake, 0o755)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def latest(self, redirect, api):
        log = os.path.join(self.tmp, "curl-%s-%s.log" % (redirect, api))
        env = dict(os.environ)
        env.update({"PATH": self.bin + os.pathsep + env.get("PATH", ""),
                    "FAKE_CURL_LOG": log, "FAKE_REDIRECT": redirect, "FAKE_API": api})
        r = subprocess.run([self.exe], env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        asked = []
        if os.path.exists(log):
            with open(log) as fh:
                asked = fh.read().split()
        return r.stdout.strip(), asked

    def test_api_refused_redirect_names_the_tag(self):
        # The case that broke: the API answers 403; the redirect resolves.
        got, asked = self.latest("tag", "403")
        self.assertEqual(got, TAG)
        self.assertEqual(asked, [REDIRECT])

    def test_redirect_without_a_tag_falls_back_to_the_api(self):
        got, asked = self.latest("page", "json")
        self.assertEqual(got, TAG)
        self.assertEqual(asked, [REDIRECT, API])

    def test_no_redirect_falls_back_to_the_api(self):
        got, asked = self.latest("none", "json")
        self.assertEqual(got, TAG)
        self.assertEqual(asked, [REDIRECT, API])

    def test_both_refused_asks_the_api_once(self):
        got, asked = self.latest("none", "403")
        self.assertEqual(got, "none")
        self.assertEqual(asked, [REDIRECT, API])


if __name__ == "__main__":
    unittest.main()
