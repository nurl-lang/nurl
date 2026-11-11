#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for tools/check_pr_reverts.py (Agora #652).

Each case builds a small repository: a `main` with a few commits shaped like
this one's (a compiler file, a test and its golden, a changelog fragment, an
open-hole note), and a change made from it. The checker must refuse the
stale squash that github#1746 was — a commit whose parent is main's tip and
whose tree is the old base plus the author's files — also when the author
edited a file main changed; and a hole note deleted by a change that never
names its task. It must accept a rebased change, a change that is merely
behind main, a fix that restores one golden, the fix that closes a hole and
deletes its note, a release fold, a rename, and a revert that says it is one.
"""
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOL = os.path.join(ROOT, "tools", "check_pr_reverts.py")

ENV = dict(os.environ,
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid",
           GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
ENV.pop("GITHUB_ACTIONS", None)


class Repo:
    def __init__(self, path):
        self.path = path
        self.git("init", "-q", "-b", "main")
        self.git("config", "core.autocrlf", "false")

    def git(self, *args):
        r = subprocess.run(["git", "-C", self.path] + list(args), env=ENV,
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise AssertionError("git %s: %s" % (" ".join(args), r.stderr))
        return r.stdout.strip()

    def write(self, files):
        for name, text in files.items():
            full = os.path.join(self.path, name)
            if text is None:
                os.remove(full)
                continue
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)

    def commit(self, subject, files, body=""):
        self.write(files)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", subject + ("\n\n" + body if body else ""))
        return self.git("rev-parse", "HEAD")

    def check(self, body=None, window=None):
        args = [sys.executable, TOOL, "--repo", self.path, "--base", "main", "--head", "HEAD"]
        if window is not None:
            args += ["--window", str(window)]
        if body is not None:
            bf = os.path.join(self.path, ".git", "pr-body.txt")
            with open(bf, "w", encoding="utf-8") as f:
                f.write(body)
            args += ["--body-file", bf]
        r = subprocess.run(args, env=ENV, capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr


COMPILER = "".join("line %d of the compiler\n" % i for i in range(40))
MEMORY = "".join("line %d of the memory model\n" % i for i in range(20))


class Controls(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.r = r = Repo(self.tmp.name)
        r.commit("the tree (#1)", {
            "compiler/nurlc.nu": COMPILER,
            "docs/MEMORY.md": MEMORY,
            "formal/A2.lean": "theorem one : True := trivial\n",
            "compiler/tests/outputs/old_golden.txt": "refused: a borrow outlives its owner\n",
            "CHANGELOG.md": "# Changelog\n\n## [Unreleased]\n",
        })
        # The author starts here …
        r.git("branch", "work")
        # … and main moves: a compiler fix with its test, golden, fragment
        # and docs (the shape of github#1741), then a docs-only hole note.
        self.fix = r.commit("A result is kept when a destructor panics (Agora #612) (#2)", {
            "compiler/nurlc.nu": COMPILER.replace("line 7 of", "line 7, fixed, of"),
            "docs/MEMORY.md": MEMORY + "a result outlives a panicking destructor\n",
            "compiler/tests/panic_in_drop.nu": "@ main → i { ^ 0 }\n",
            "compiler/tests/outputs/panic_in_drop.txt": "0\n",
            "compiler/tests/outputs/old_golden.txt": "refused: the result is read after its owner\n",
            "changes/unreleased/t612-result-kept.md": "### Fixed\n\n- **A result is kept** (Agora #612).\n",
        })
        self.note = r.commit("holes/open: t545, an owned slice moved on (Agora #545) (#3)", {
            "tools/fuzz/holes/open/t545.md": "**agora #545: an owned slice moved on.** It faults.\n",
        })
        r.git("checkout", "-q", "work")

    def tearDown(self):
        self.tmp.cleanup()

    def author(self, files=None, subject="formal: one more step (Agora #609)", body=""):
        return self.r.commit(subject, files or {
            "formal/A2.lean": "theorem one : True := trivial\ntheorem two : True := trivial\n"},
            body)

    def stale_squash(self):
        # github#1746's two commands, on a branch never rebased onto main.
        self.r.git("reset", "-q", "--soft", "main")
        self.r.git("commit", "-q", "-m", "formal: one more step (Agora #609)")

    # ---- refused -------------------------------------------------------

    def test_stale_squash_is_refused_and_names_what_it_undoes(self):
        self.author()
        self.stale_squash()
        code, out = self.r.check()
        self.assertEqual(code, 1, out)
        self.assertIn("undoes 2 commits", out)
        self.assertIn(self.fix[:8], out)
        self.assertIn(self.note[:8], out)
        self.assertIn("compiler/tests/panic_in_drop.nu", out)       # deleted again
        self.assertIn("compiler/nurlc.nu", out)                      # back at an older version
        self.assertIn("git rebase origin/main", out)
        self.assertIn("reverts: %s, %s" % (self.fix[:8], self.note[:8]), out)

    def test_stale_squash_by_an_author_who_edited_the_same_file(self):
        # The compiler file is the author's own version, so it matches no
        # version of main; the fix's test, golden and fragment still go.
        self.author({"compiler/nurlc.nu": COMPILER.replace("line 30 of", "line 30, mine, of")})
        self.stale_squash()
        code, out = self.r.check()
        self.assertEqual(code, 1, out)
        self.assertIn(self.fix[:8], out)
        self.assertNotIn("back at an older version: compiler/nurlc.nu", out)

    def test_a_hole_note_deleted_by_a_change_that_never_names_its_task(self):
        self.r.git("rebase", "-q", "main")
        self.author({"tools/fuzz/holes/open/t545.md": None})
        code, out = self.r.check()
        self.assertEqual(code, 1, out)
        self.assertIn(self.note[:8], out)
        self.assertIn("names\n                 its task in the pull request title or body (#545)", out)

    def test_a_revert_that_does_not_say_so(self):
        self.r.git("rebase", "-q", "main")
        self.r.git("revert", "--no-edit", self.fix)
        self.r.git("commit", "-q", "--amend", "-m", "tidy the result path")
        code, out = self.r.check()
        self.assertEqual(code, 1, out)
        self.assertIn("undoes 1 commit ", out)

    # ---- accepted ------------------------------------------------------

    def test_behind_main_is_not_stale(self):
        self.author()
        self.assertEqual(self.r.check()[0], 0)

    def test_rebased_change(self):
        self.author()
        self.r.git("rebase", "-q", "main")
        self.assertEqual(self.r.check()[0], 0)

    def test_squash_onto_the_merge_base(self):
        self.author()
        self.author({"formal/A3.lean": "theorem three : True := trivial\n"})
        self.r.git("rebase", "-q", "main")
        self.r.git("reset", "-q", "--soft", self.r.git("merge-base", "HEAD", "main"))
        self.r.git("commit", "-q", "-m", "formal: two steps")
        self.assertEqual(self.r.check()[0], 0)

    def test_a_fix_that_restores_one_golden_keeps_the_rest_of_the_commit(self):
        self.r.git("rebase", "-q", "main")
        self.author({
            "compiler/tests/outputs/old_golden.txt": "refused: a borrow outlives its owner\n",
            "compiler/nurlc.nu": COMPILER.replace("line 7 of", "line 7, fixed twice, of")})
        code, out = self.r.check()
        self.assertEqual(code, 0, out)

    def test_the_fix_that_closes_a_hole_deletes_its_note(self):
        self.r.git("rebase", "-q", "main")
        self.author({"tools/fuzz/holes/open/t545.md": None,
                     "compiler/nurlc.nu": COMPILER.replace("line 9 of", "line 9, sound, of")},
                    subject="An owned slice moved on is dropped once (Agora #545)")
        code, out = self.r.check()
        self.assertEqual(code, 0, out)

    def test_the_task_named_in_the_pull_request_body_counts(self):
        self.r.git("rebase", "-q", "main")
        self.author({"tools/fuzz/holes/open/t545.md": None}, subject="slices")
        self.assertEqual(self.r.check(body="github#545 is another thing")[0], 1)
        self.assertEqual(self.r.check(body="Closes Agora #545.")[0], 0)

    def test_a_release_fold_deletes_the_fragments(self):
        self.r.git("rebase", "-q", "main")
        self.author({"changes/unreleased/t612-result-kept.md": None,
                     "CHANGELOG.md": "# Changelog\n\n## [Unreleased]\n\n## [0.91.0]\n\n"
                                     "### Fixed\n\n- **A result is kept** (Agora #612).\n"},
                    subject="Release v0.91.0")
        code, out = self.r.check()
        self.assertEqual(code, 0, out)

    def test_a_fragment_deleted_outside_a_fold_is_evidence(self):
        self.author()
        self.stale_squash()
        _, out = self.r.check()
        self.assertIn("changes/unreleased/t612-result-kept.md", out)

    def test_a_renamed_file_is_kept(self):
        self.r.git("rebase", "-q", "main")
        self.r.git("mv", "tools/fuzz/holes/open/t545.md", "tools/fuzz/holes/open/t546.md")
        self.r.git("commit", "-q", "-m", "the note's task number")
        code, out = self.r.check()
        self.assertEqual(code, 0, out)

    def test_a_revert_that_says_so(self):
        self.r.git("rebase", "-q", "main")
        self.r.git("revert", "--no-edit", self.fix)          # "This reverts commit <sha>."
        code, out = self.r.check()
        self.assertEqual(code, 0, out)
        self.assertIn("reverts %s, as the change says" % self.fix[:8], out)

    def test_reverts_line_in_the_pull_request_body(self):
        self.author()
        self.stale_squash()
        both = "## Why\n\nreverts: %s, #3\n" % self.fix[:10]
        self.assertEqual(self.r.check(body=both)[0], 0)
        self.assertEqual(self.r.check(body="Reverts nurl-lang/nurl#2\nReverts nurl-lang/nurl#3")[0], 0)
        # One of two named: the other is still undone.
        code, out = self.r.check(body="reverts: #2")
        self.assertEqual(code, 1, out)
        self.assertIn("undoes 1 commit ", out)
        # A sentence about reverting is not the line.
        self.assertEqual(self.r.check(body="this nearly reverts #2 and #3")[0], 1)

    def test_outside_the_window_is_not_seen(self):
        # The limit, stated: a tree older than the window is not recognised
        # by the commits beyond it (the ones inside it still are).
        self.r.git("rebase", "-q", "main")
        self.r.git("revert", "--no-edit", self.fix)
        self.r.git("commit", "-q", "--amend", "-m", "tidy the result path")
        self.assertEqual(self.r.check(window=1)[0], 0)
        self.assertEqual(self.r.check(window=2)[0], 1)

    def test_a_shallow_clone_cannot_tell(self):
        # Without main's history the stale squash's tree has nothing to be
        # compared with: the answer is "cannot tell", never "ok". At depth 1
        # the head's own parent is cut off; at depth 2 the window is.
        self.author()
        self.stale_squash()
        for depth, why in ((1, "merge-base"), (2, "only 2 of main's commits")):
            with tempfile.TemporaryDirectory() as d:
                subprocess.run(["git", "clone", "-q", "--depth=%d" % depth, "--no-single-branch",
                                "file://" + self.r.path, d], env=ENV, check=True)
                subprocess.run(["git", "-C", d, "checkout", "-q", "work"], env=ENV, check=True)
                r = subprocess.run([sys.executable, TOOL, "--repo", d, "--base", "origin/main",
                                    "--head", "HEAD"], env=ENV, capture_output=True, text=True)
                self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
                self.assertIn("cannot tell", r.stderr)
                self.assertIn(why, r.stderr)


if __name__ == "__main__":
    unittest.main()
