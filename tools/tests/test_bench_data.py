#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for tools/bench_data.sh: the measured numbers go to the
bench-data branch, never to main (Agora #290).

Every benchmark and fuzz workflow publishes through it. These tests run it
against a throwaway bare repository standing in for origin and hold that
  - a first publish creates bench-data as an orphan branch holding the
    numbers and nothing else, and main does not move;
  - a publish onto an existing bench-data keeps the other reports there;
  - a publisher whose push is refused because another one pushed first
    replays onto the new tip instead of losing either run;
  - BENCH_DATA_RENDER runs inside the bench-data tree, so a report
    rendered from every recorded run (tls-bench's index) sees them all;
  - fetch writes bench-data's files into a checkout, and --if-missing
    leaves a local run's own file alone;
  - publishing numbers that are already there is a no-op.
"""
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "tools", "bench_data.sh")
BASH = shutil.which("bash") or "bash"


def git(cwd, *args, check=True):
    return subprocess.run(["git", *args], cwd=cwd, check=check, capture_output=True, text=True,
                          env={**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}).stdout


class BenchData(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.origin = os.path.join(self.tmp, "origin.git")
        git(self.tmp, "init", "-q", "--bare", "-b", "main", self.origin)
        seed = os.path.join(self.tmp, "seed")
        git(self.tmp, "clone", "-q", self.origin, seed)
        with open(os.path.join(seed, "code.txt"), "w") as f:
            f.write("code\n")
        git(seed, "add", ".")
        git(seed, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "code")
        git(seed, "push", "-q", "origin", "HEAD:main")
        self.main_tip = git(seed, "rev-parse", "HEAD").strip()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def clone(self, name):
        d = os.path.join(self.tmp, name)
        git(self.tmp, "clone", "-q", "--depth=1", "file://" + self.origin, d)
        os.makedirs(os.path.join(d, "tools"), exist_ok=True)
        shutil.copy(SCRIPT, os.path.join(d, "tools", "bench_data.sh"))
        return d

    def write(self, d, path, text):
        p = os.path.join(d, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)

    def run_script(self, d, *args, env=None, check=True):
        return subprocess.run([BASH, "tools/bench_data.sh", *args], cwd=d, capture_output=True, text=True,
                              check=check, env={**os.environ, **(env or {})})

    def data(self, path):
        return git(self.origin, "show", "bench-data:" + path)

    def test_publish_creates_then_extends_the_branch_and_main_stays(self):
        a = self.clone("a")
        self.write(a, "bench/HTTP_RESULTS.md", "http 1\n")
        self.run_script(a, "publish", "bench: http", "bench/HTTP_RESULTS.md")
        self.assertEqual(self.data("bench/HTTP_RESULTS.md"), "http 1\n")
        # An orphan of numbers only: main's code is not on it.
        self.assertEqual(git(self.origin, "ls-tree", "-r", "--name-only", "bench-data").split(),
                         ["bench/HTTP_RESULTS.md"])
        self.assertEqual(git(self.origin, "rev-list", "--count", "bench-data").strip(), "1")
        b = self.clone("b")
        self.write(b, "bench/PQ_RESULTS.md", "pq 1\n")
        self.run_script(b, "publish", "bench: pq", "bench/PQ_RESULTS.md")
        self.assertEqual(self.data("bench/HTTP_RESULTS.md"), "http 1\n")
        self.assertEqual(self.data("bench/PQ_RESULTS.md"), "pq 1\n")
        self.assertEqual(git(self.origin, "rev-parse", "main").strip(), self.main_tip)

    def test_a_refused_push_replays_onto_the_new_tip(self):
        a, b = self.clone("a"), self.clone("b")
        self.write(a, "bench/HTTP_RESULTS.md", "http 1\n")
        self.run_script(a, "publish", "bench: http", "bench/HTTP_RESULTS.md")
        # b's view of bench-data is now stale; its first push must be
        # refused and replayed. A pre-push hook in b pushes c's numbers
        # first, once, the way a concurrent workflow would.
        c = self.clone("c")
        self.write(c, "bench/PQ_RESULTS.md", "pq 1\n")
        hook = os.path.join(b, ".git", "hooks", "pre-push")
        with open(hook, "w") as f:
            f.write("#!/bin/sh\n"
                    "m=\"$(git rev-parse --git-common-dir)/raced\"\n"
                    "[ -e \"$m\" ] && exit 0\n"
                    "touch \"$m\"\n"
                    "unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX\n"
                    "cd '%s' && bash tools/bench_data.sh publish 'bench: pq' bench/PQ_RESULTS.md >/dev/null\n" % c)
        os.chmod(hook, 0o755)
        self.write(b, "bench/http_torture/TORTURE_RESULTS.md", "torture 1\n")
        r = self.run_script(b, "publish", "bench: torture", "bench/http_torture/TORTURE_RESULTS.md")
        self.assertIn("replaying onto the new tip", r.stdout)
        for path, text in (("bench/HTTP_RESULTS.md", "http 1\n"), ("bench/PQ_RESULTS.md", "pq 1\n"),
                           ("bench/http_torture/TORTURE_RESULTS.md", "torture 1\n")):
            self.assertEqual(self.data(path), text)

    def test_render_runs_inside_the_data_tree(self):
        a = self.clone("a")
        self.write(a, "bench/tls_bench/runs/zen3.tsv", "z3\n")
        render = "cat bench/tls_bench/runs/*.tsv > bench/tls_bench/TLS_RESULTS.md"
        self.run_script(a, "publish", "tls zen3", "bench/tls_bench/runs/zen3.tsv", env={"BENCH_DATA_RENDER": render})
        b = self.clone("b")
        self.write(b, "bench/tls_bench/runs/zen5.tsv", "z5\n")
        self.run_script(b, "publish", "tls zen5", "bench/tls_bench/runs/zen5.tsv", env={"BENCH_DATA_RENDER": render})
        # b never had zen3's run; the index it rendered on bench-data has both.
        self.assertEqual(self.data("bench/tls_bench/TLS_RESULTS.md"), "z3\nz5\n")

    def test_fetch_and_no_op(self):
        a = self.clone("a")
        self.write(a, "bench/results/latest.json", "{\"n\": 1}\n")
        self.write(a, "bench/tls_bench/runs/zen3.tsv", "z3\n")
        self.run_script(a, "publish", "bench", "bench/results/latest.json", "bench/tls_bench/runs")
        r = self.run_script(a, "publish", "bench", "bench/results/latest.json")
        self.assertIn("nothing to publish", r.stdout)
        self.assertEqual(git(self.origin, "rev-list", "--count", "bench-data").strip(), "1")
        b = self.clone("b")
        self.run_script(b, "fetch", "bench/results/latest.json", "bench/tls_bench/runs")
        with open(os.path.join(b, "bench/results/latest.json")) as f:
            self.assertEqual(f.read(), "{\"n\": 1}\n")
        self.assertTrue(os.path.exists(os.path.join(b, "bench/tls_bench/runs/zen3.tsv")))
        self.write(b, "bench/results/latest.json", "local\n")
        self.run_script(b, "fetch", "--if-missing", "bench/results/latest.json")
        with open(os.path.join(b, "bench/results/latest.json")) as f:
            self.assertEqual(f.read(), "local\n")
        r = self.run_script(b, "fetch", "bench/NOPE.md", check=False)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("is not on bench-data", r.stderr)

    def test_url(self):
        a = self.clone("a")
        self.assertEqual(self.run_script(a, "url", "bench/RESULTS.md").stdout.strip(),
                         "https://github.com/nurl-lang/nurl/blob/bench-data/bench/RESULTS.md")


if __name__ == "__main__":
    unittest.main(verbosity=1)
